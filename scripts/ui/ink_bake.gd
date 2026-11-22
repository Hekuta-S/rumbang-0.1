class_name InkBake
extends RefCounted

## Hornea el contorno de tinta (ink_outline.gdshader) de una imagen UNA vez, al tamaño al que se ve en
## pantalla, y la devuelve como textura normal. Así el HUD no ejecuta el shader de tinta en cada frame:
## ese shader lee la textura 14 veces por píxel, y en la tira de armas (imagen de 2172 px) más 5 iconos de
## 648 px era la parte cara del HUD en el móvil (~3 ms en un Mali-G57, 2026-11-17).
## También puede recortar en círculo (clip_radius, en UV) para no usar clip_children, que en Godot dibuja
## cada hueco en un búfer aparte (un pase de render más por hueco).
##
## La textura resultante tiene el alfa premultiplicado (lo que deja un SubViewport transparente): dibujarla
## con material(), y con modulate de alfa 1 (o Color(a, a, a, a)).
##     InkBake.request(tex, Vector2i(160, 160), {"ink_px": 14.0}, func(t): icon.texture = t)
## Sin render (headless) la llamada devuelve null y el que pide sigue con el shader.

const INK_OUTLINE := preload("res://scripts/ui/ink_outline.gdshader")
## Tope de texturas horneadas guardadas (iconos de armas × activo/inactivo + la tira).
const CACHE_MAX := 64

static var _cache: Dictionary = {}       ## clave -> ImageTexture
static var _pending: Dictionary = {}     ## clave -> Array[Callable]
static var _premult: CanvasItemMaterial

## Material para dibujar lo horneado (alfa premultiplicado). Compartido: no rompe el agrupado de dibujos.
static func material() -> CanvasItemMaterial:
	if _premult == null:
		_premult = CanvasItemMaterial.new()
		_premult.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	return _premult

static func cached(tex: Texture2D, px: Vector2i, params: Dictionary) -> Texture2D:
	return _cache.get(_key(tex, px, params))

## Pide `tex` con tinta a `px` píxeles (nunca más grande que la original). `params`: ink_px, shadow_px,
## ink_color (en píxeles de la textura ORIGINAL, como en el shader) y clip_radius. `cb(textura o null)`.
static func request(tex: Texture2D, px: Vector2i, params: Dictionary, cb: Callable) -> void:
	if tex == null:
		cb.call(null)
		return
	var key := _key(tex, px, params)
	if _cache.has(key):
		cb.call(_cache[key])
		return
	if _pending.has(key):
		(_pending[key] as Array).append(cb)
		return
	_pending[key] = [cb]
	_bake(key, tex, px, params)

static func _key(tex: Texture2D, px: Vector2i, params: Dictionary) -> String:
	return "%d|%d|%d|%s" % [tex.get_instance_id(), px.x, px.y, str(params)]

static func _bake(key: String, tex: Texture2D, px: Vector2i, params: Dictionary) -> void:
	var out: Texture2D = null
	var tree := Engine.get_main_loop() as SceneTree
	var src := tex.get_image() if tree != null and DisplayServer.get_name() != "headless" else null
	if src != null and not src.is_empty():
		src = src.duplicate()
		if src.is_compressed():
			src.decompress()
		if src.has_mipmaps():
			src.clear_mipmaps()
		# Reducir en CPU (Lanczos) antes de hornear: sin esto, leer una imagen 5-7 veces mayor sin mipmaps
		# deja dientes. Los grosores del shader van en píxeles de la textura, así que se escalan igual.
		var f := minf(1.0, minf(float(px.x) / src.get_width(), float(px.y) / src.get_height()))
		var w := maxi(1, roundi(src.get_width() * f))
		var h := maxi(1, roundi(src.get_height() * f))
		if f < 1.0:
			src.resize(w, h, Image.INTERPOLATE_LANCZOS)
		var vp := SubViewport.new()
		vp.size = Vector2i(w, h)
		vp.transparent_bg = true
		vp.disable_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		var tr := TextureRect.new()
		tr.texture = ImageTexture.create_from_image(src)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.size = Vector2(w, h)
		var m := ShaderMaterial.new()
		m.shader = INK_OUTLINE
		m.set_shader_parameter("ink_px", float(params.get("ink_px", 3.0)) * f)
		m.set_shader_parameter("shadow_px", (params.get("shadow_px", Vector2(3.0, 4.0)) as Vector2) * f)
		if params.has("ink_color"):
			m.set_shader_parameter("ink_color", params["ink_color"])
		if params.has("clip_radius"):
			m.set_shader_parameter("clip_radius", float(params["clip_radius"]))
			m.set_shader_parameter("clip_soft", 1.0 / float(w))   # borde suave de ~1 píxel
		tr.material = m
		vp.add_child(tr)
		tree.root.add_child(vp)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		vp.queue_free()
		if img != null and not img.is_empty():
			out = ImageTexture.create_from_image(img)
			if _cache.size() >= CACHE_MAX:
				_cache.erase(_cache.keys()[0])
			_cache[key] = out
	var cbs: Array = _pending.get(key, [])
	_pending.erase(key)
	for cb in cbs:
		if (cb as Callable).is_valid():
			(cb as Callable).call(out)
