class_name ToonFX
extends RefCounted

## Polvo, humo y fuego DIBUJADOS (cómic) para las partículas, en lugar de manchas difuminadas.
## Texturas de tools/make_toon_fx.py en res://assets/textures/toon/fx/:
##  - puff.png: 4 nubes entintadas (rejilla 2×2), para polvo y humo.
##  - flame.png: 4 lenguas de fuego entintadas (rejilla 2×2), gris/blanco para que la partícula las tiña.
##  - ring.png: anillo de onda entintado (polvo al aterrizar, onda de fuego).
## Uso: ToonFX.puff_material(mat) / ToonFX.flame_material(mat) en el material (billboard de partículas,
## mezcla alfa) y ToonFX.vary(p) en el emisor, para que cada partícula salga con uno de los cuatro dibujos.
##
## Aspecto 2D: un dibujo no se "difumina"; con pop_ramp() y pop_curve() la partícula sale opaca y desaparece
## encogiéndose (como en una animación dibujada). Además sale más barato: menos píxeles semitransparentes
## al final de la vida, que es cuando las nubes son más grandes.

const PUFF_PATH := "res://assets/textures/toon/fx/puff.png"
const FLAME_PATH := "res://assets/textures/toon/fx/flame.png"
const RING_PATH := "res://assets/textures/toon/fx/ring.png"
const FRAMES := 2                 ## rejilla 2×2

static var _cache: Dictionary = {}

static func _tex(path: String) -> Texture2D:
	if not _cache.has(path):
		_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _cache[path]

## La textura de nubes, o null si no está (se queda la mancha suave de siempre).
static func puff_texture() -> Texture2D:
	return _tex(PUFF_PATH)

static func flame_texture() -> Texture2D:
	return _tex(FLAME_PATH)

static func ring_texture() -> Texture2D:
	return _tex(RING_PATH)

## Pone las nubes dibujadas en un material de partículas. Devuelve si lo hizo.
static func puff_material(mat: BaseMaterial3D) -> bool:
	return _sheet_material(mat, puff_texture())

## Pone las lenguas de fuego dibujadas en un material de partículas. Devuelve si lo hizo.
static func flame_material(mat: BaseMaterial3D) -> bool:
	return _sheet_material(mat, flame_texture())

static func _sheet_material(mat: BaseMaterial3D, tex: Texture2D) -> bool:
	if tex == null:
		return false
	mat.albedo_texture = tex
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX      # la tinta no existe en mezcla aditiva
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.particles_anim_h_frames = FRAMES
	mat.particles_anim_v_frames = FRAMES
	mat.particles_anim_loop = false
	return true

## Material plano para el anillo entintado (PlaneMesh/QuadMesh, sin billboard). null si falta la textura.
static func ring_material() -> StandardMaterial3D:
	var tex := ring_texture()
	if tex == null:
		return null
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = tex
	m.disable_receive_shadows = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

## ── Armas y ataques dibujados (tools/make_weapon_sprites.py) ──
## guitarra.png / brazo.png: 8 fotogramas de giro en fila; maza.png: 2 (quieta, con rayas de velocidad);
## magia.png: 2 fotogramas × 3 filas (MAGIC_*); grieta.png: grietas vistas desde arriba.
const FX_DIR := "res://assets/textures/toon/fx/"
const SPIN_FRAMES := 8
const MAGIC_ARCANE := 0           ## magos goblin
const MAGIC_CRIMSON := 1          ## jefe
const MAGIC_GREEN := 2            ## necromante

## Sprite3D con una hoja dibujada: sin luz, recorte alfa (sin mezcla: barato y sin problemas de orden).
## `billboard` = mira siempre a la cámara; si no, es un recorte plano (para girarlo en su plano).
static func sheet_sprite(file: String, hframes: int, vframes: int, pixel: float, billboard := true) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = _tex(FX_DIR + file)
	s.hframes = hframes
	s.vframes = vframes
	s.pixel_size = pixel
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED if billboard else BaseMaterial3D.BILLBOARD_DISABLED
	s.shaded = false
	s.double_sided = true
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return s

## Arma dibujada para llevar en la mano: dos recortes planos cruzados a lo largo del eje largo del dibujo
## (+Y del nodo = arriba del dibujo), así no desaparece cuando la mano lo pone de canto a la cámara.
static func cutout_cross(file: String, hframes: int, vframes: int, pixel: float, frame: int = 0) -> Node3D:
	var root := Node3D.new()
	for k in 2:
		var s := sheet_sprite(file, hframes, vframes, pixel, false)
		s.frame = frame
		s.rotation.y = k * PI * 0.5
		root.add_child(s)
	return root

## Fotograma de una rueda de giro (guitarra, brazo) para el ángulo `angle` (rad, cualquier signo).
static func spin_frame(angle: float) -> int:
	return int(floor(fposmod(angle, TAU) / TAU * SPIN_FRAMES)) % SPIN_FRAMES

## Proyectil mágico dibujado (billboard), `row` = MAGIC_*. ~`size` m de diámetro.
static func magic_sprite(row: int, size: float = 0.7) -> Sprite3D:
	var s := sheet_sprite("magia.png", 2, 3, size / 128.0)
	s.frame = row * 2
	return s

## Fila de magia.png que mejor casa con un color (azul/violeta = arcano, rojo = carmesí, verde = necro).
static func magic_row_for(c: Color) -> int:
	if c.g > c.r and c.g > c.b:
		return MAGIC_GREEN
	if c.r > c.b:
		return MAGIC_CRIMSON
	return MAGIC_ARCANE

## Anillo de onda entintado a ras de suelo que se abre hasta `radius` y se apaga.
static func ring_burst(parent: Node, pos: Vector3, radius: float, color: Color, duration: float = 0.4) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var m := ring_material()
	if m == null:
		return
	m.albedo_color = Color(color.r, color.g, color.b, 1.0)
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.0, 2.0)
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = pos + Vector3(0, 0.06, 0)
	mi.scale = Vector3.ONE * radius * 0.25
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * radius, duration).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(mi, "transparency", 1.0, duration * 0.45).set_delay(duration * 0.55)
	tw.chain().tween_callback(mi.queue_free)

## Estallido dibujado: estrella de impacto entintada (impact.png) teñida que entra grande y se encoge.
static func impact_pop(parent: Node, pos: Vector3, color: Color, size: float = 1.0) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var tex := _tex(FX_DIR + "impact.png")
	if tex == null:
		return
	var s := Sprite3D.new()
	s.texture = tex
	s.hframes = 2
	s.vframes = 2
	s.frame = randi() % 4
	s.pixel_size = 0.0062
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.modulate = color.lerp(Color.WHITE, 0.25)
	parent.add_child(s)
	s.global_position = pos
	s.scale = Vector3.ONE * size * 0.4
	var tw := s.create_tween()
	tw.tween_property(s, "scale", Vector3.ONE * size * 1.2, 0.07).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(s, "scale", Vector3.ZERO, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN).set_delay(0.05)
	tw.tween_callback(s.queue_free)

## Nubecitas dibujadas que salen disparadas (puff.png), del color dado. Se borran solas.
static func puff_burst(parent: Node, pos: Vector3, color: Color, amount: int = 8, speed: float = 3.0, size: float = 0.5) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var p := CPUParticles3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	p.mesh = quad
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	if not puff_material(m):
		return
	p.material_override = m
	vary(p)
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = maxi(3, int(round(float(amount) * Quality.particle_factor())))
	p.lifetime = 0.45
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 80.0
	p.gravity = Vector3(0, -2.0, 0)
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.scale_amount_curve = pop_curve(0.6, 1.0)
	p.color_ramp = pop_ramp([color.lerp(Color.WHITE, 0.3), color])
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.get_tree().create_timer(p.lifetime + 0.3).timeout.connect(p.queue_free)

## Columna de llamas DIBUJADAS que sube del suelo (flame.png, mezcla normal: la tinta se ve). Se borra sola.
static func flame_column(parent: Node, pos: Vector3, radius: float, color: Color) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var p := CPUParticles3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.8, 0.8)
	p.mesh = quad
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	if not flame_material(m):
		return
	p.material_override = m
	vary(p)
	p.one_shot = true
	p.explosiveness = 0.85
	p.amount = maxi(10, int(round(34.0 * Quality.particle_factor())))
	p.lifetime = 0.7
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius * 0.55
	p.direction = Vector3.UP
	p.spread = 12.0
	p.gravity = Vector3(0, 2.0, 0)
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 8.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.2
	p.scale_amount_curve = pop_curve(0.5, 1.0, 0.25)
	p.color_ramp = pop_ramp([color.lerp(Color.WHITE, 0.55), color, color.darkened(0.35)])
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.get_tree().create_timer(1.2).timeout.connect(p.queue_free)

## Nubecitas dibujadas que suben despacio por una zona (burbujeo antes de una erupción). Emite en bucle:
## añadirlo como hijo de la zona (se va con ella).
static func puff_rise(radius: float, color: Color) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.45, 0.45)
	p.mesh = quad
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	puff_material(m)
	p.material_override = m
	vary(p)
	p.amount = maxi(4, int(round(12.0 * Quality.particle_factor())))
	p.lifetime = 0.9
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE_SURFACE
	p.emission_sphere_radius = radius * 0.75
	p.direction = Vector3.UP
	p.spread = 15.0
	p.gravity = Vector3(0, 1.2, 0)
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.4
	p.scale_amount_curve = pop_curve(0.3, 1.0)
	p.color_ramp = pop_ramp([color.lerp(Color.WHITE, 0.4), color])
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p

## Cada partícula del emisor usa uno de los cuatro dibujos (sin animar).
static func vary(p: CPUParticles3D) -> void:
	p.anim_speed_min = 0.0
	p.anim_speed_max = 0.0
	p.anim_offset_min = 0.0
	p.anim_offset_max = 1.0

## Rampa "dibujada": colores dados, opaca casi toda la vida; solo se corta al final (la forma ya es pequeña
## por pop_curve). `colors` = colores en orden; `alpha` = opacidad (1 = tinta sólida).
static func pop_ramp(colors: Array, alpha: float = 1.0) -> Gradient:
	var g := Gradient.new()
	var cols := PackedColorArray()
	var offs := PackedFloat32Array()
	var n := colors.size()
	for i in n:
		var c: Color = colors[i]
		cols.append(Color(c.r, c.g, c.b, alpha))
		offs.append(0.92 * float(i) / float(maxi(n - 1, 1)))
	var last: Color = colors[n - 1]
	cols.append(Color(last.r, last.g, last.b, 0.0))
	offs.append(1.0)
	g.colors = cols
	g.offsets = offs
	return g

## Curva de escala "dibujada": aparece de golpe (`start`), crece hasta `peak` y se encoge hasta desaparecer.
static func pop_curve(start: float, peak: float, peak_at: float = 0.35) -> Curve:
	var cv := Curve.new()
	cv.max_value = maxf(1.0, maxf(start, peak))
	cv.add_point(Vector2(0.0, start))
	cv.add_point(Vector2(peak_at, peak))
	cv.add_point(Vector2(lerpf(peak_at, 1.0, 0.55), peak * 0.85))
	cv.add_point(Vector2(1.0, 0.0))
	return cv
