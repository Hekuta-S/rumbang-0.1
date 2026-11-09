class_name Minimap
extends Control

## Minimapa de la mazmorra (arriba a la izquierda). Compacto: sigue al jugador en una ventana de unos
## 80 m. Expandido (M): muestra toda la zona explorada. Niebla de exploración: solo se dibujan las
## celdas que algún jugador ha pisado de cerca. Marca jugadores, cofres, portal y altar (los enemigos no aparecen).
## El mapa se pinta en una textura de 1 píxel por celda (se actualiza solo al descubrir celdas nuevas).

const COMPACT := 200.0                ## lado del panel compacto (px)
const MAX_EXPANDED := 600.0           ## lado máximo del panel expandido
const WINDOW_CELLS := 36.0            ## celdas visibles en el modo compacto
const REVEAL_R := 7                   ## radio de descubrimiento (celdas)
const TOGGLE_KEY := KEY_M            ## (C es el bloqueo de objetivo; Tab, el menú de pausa)
const MARGIN := 22.0
const INSET := 6.0
const EXPAND_SPEED := 9.0

const FLOOR_COL := Color(0.56, 0.5, 0.66, 0.95)
const CORRIDOR_COL := Color(0.42, 0.4, 0.52, 0.95)
const ALTAR_COL := Color(1.0, 0.25, 0.25)
const CHEST_COL := Color(1.0, 0.8, 0.25)
const PORTAL_COL := Color(0.85, 0.35, 1.0)
const ME_COL := Color(0.25, 0.95, 1.0)
const MATE_COL := Color(0.4, 1.0, 0.5)

var _view: Control
var _map: DungeonMap
var _map_id := -1
var _find_t := 0.0
var _reveal_t := 0.0
var _img: Image
var _tex: ImageTexture
var _origin := Vector2i.ZERO          ## celda de la esquina (0,0) de la imagen
var _dim := Vector2i.ONE
var _seen := {}
var _expanded := false
var _t := 0.0                         ## 0 compacto … 1 expandido
var _font: Font

func _ready() -> void:
	_font = ThemeDB.fallback_font
	visible = GameData.game_mode == "dungeon"
	mouse_filter = Control.MOUSE_FILTER_STOP if Quality.is_mobile() else Control.MOUSE_FILTER_IGNORE
	_view = Control.new()
	_view.name = "View"
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.clip_contents = true
	_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_view.draw.connect(_draw_view)
	add_child(_view)
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	_layout()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		toggle()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		toggle()

func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == TOGGLE_KEY:
		toggle()
		get_viewport().set_input_as_handled()

func toggle() -> void:
	_expanded = not _expanded

func is_expanded() -> bool:
	return _expanded

func _expanded_side() -> float:
	return minf(MAX_EXPANDED, get_viewport_rect().size.y - MARGIN * 2.0 - 24.0)

func _layout() -> void:
	var side := lerpf(COMPACT, _expanded_side(), _ease(_t))
	var top := MARGIN + (44.0 + 66.0 if Quality.is_mobile() else 0.0)
	offset_left = MARGIN
	offset_top = top
	offset_right = MARGIN + side
	offset_bottom = top + side
	_view.position = Vector2(INSET, INSET)
	_view.size = Vector2(side - INSET * 2.0, side - INSET * 2.0)

static func _ease(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)

func _process(delta: float) -> void:
	if not visible:
		return
	var target := 1.0 if _expanded else 0.0
	if not is_equal_approx(_t, target):
		_t = move_toward(_t, target, delta * EXPAND_SPEED * 0.5)
		_layout()
	_find_t -= delta
	if not is_instance_valid(_map) and _find_t <= 0.0:
		_find_t = 0.5
		_map = get_tree().root.find_child("ProceduralMap", true, false) as DungeonMap
	if not is_instance_valid(_map) or _map._cells.is_empty():
		return
	# Mapa nuevo (otro nivel): nueva textura y niebla
	var id := _map.used_seed * 31 + _map._cells.size()
	if id != _map_id:
		_map_id = id
		_rebuild()
	_reveal_t -= delta
	if _reveal_t <= 0.0:
		_reveal_t = 0.12
		_reveal()
	queue_redraw()
	_view.queue_redraw()

func _rebuild() -> void:
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-(1 << 30), -(1 << 30))
	for c in _map._cells:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	_origin = lo - Vector2i.ONE
	_dim = hi - lo + Vector2i(3, 3)
	_img = Image.create(_dim.x, _dim.y, false, Image.FORMAT_RGBA8)
	_tex = ImageTexture.create_from_image(_img)
	_seen.clear()

func _reveal() -> void:
	var changed := false
	for p in NetPlayers.all():
		if not NetPlayers.is_alive(p):
			continue
		var c0 := _map.world_to_cell((p as Node3D).global_position)
		for dx in range(-REVEAL_R, REVEAL_R + 1):
			for dz in range(-REVEAL_R, REVEAL_R + 1):
				if dx * dx + dz * dz > REVEAL_R * REVEAL_R:
					continue
				var c := c0 + Vector2i(dx, dz)
				if _seen.has(c) or not _map._cells.has(c):
					continue
				_seen[c] = true
				var px := c - _origin
				_img.set_pixel(px.x, px.y, FLOOR_COL if _map._cells[c] == DungeonMap.FLOOR else CORRIDOR_COL)
				changed = true
	if changed:
		_tex.update(_img)

func is_seen_world(p: Vector3) -> bool:
	return _seen.has(_map.world_to_cell(p))

## Píxel de la textura (con decimales) de una posición del mundo.
func _px(p: Vector3) -> Vector2:
	return Vector2(p.x / DungeonMap.CELL - _origin.x + 0.5, p.z / DungeonMap.CELL - _origin.y + 0.5)

func _view_params() -> Dictionary:
	var vs := _view.size
	if _t > 0.5:
		# Toda la imagen, centrada y con la misma escala en los dos ejes
		var s := minf(vs.x / _dim.x, vs.y / _dim.y)
		var off := (vs - Vector2(_dim) * s) * 0.5
		return {"scale": s, "offset": off}
	var local := get_tree().get_first_node_in_group("player") as Node3D
	var centre := _px(local.global_position) if local != null else Vector2(_dim) * 0.5
	var sc := vs.x / WINDOW_CELLS
	return {"scale": sc, "offset": vs * 0.5 - centre * sc}

func _draw() -> void:
	HudDraw.panel(self, Rect2(Vector2.ZERO, size))

func _draw_view() -> void:
	if _tex == null or not is_instance_valid(_map):
		return
	var prm := _view_params()
	var s: float = prm["scale"]
	var off: Vector2 = prm["offset"]
	_view.draw_texture_rect(_tex, Rect2(off, Vector2(_dim) * s), false)
	var dot := clampf(s * 0.9, 2.5, 5.0)
	# Cofres y portal (solo si ya se ha descubierto su celda)
	for ch in get_tree().get_nodes_in_group("treasure_chests"):
		var cp := ch as TreasureChest
		if cp != null and is_seen_world(cp.global_position):
			_diamond(off + _px(cp.global_position) * s, dot * 1.6, Color(0.5, 0.45, 0.35) if cp.is_open else CHEST_COL)
	var enc := get_tree().root.find_child("DungeonEncounter", true, false) as DungeonEncounter
	if enc != null and is_instance_valid(enc.portal) and is_seen_world(enc.portal.global_position):
		var pp := off + _px(enc.portal.global_position) * s
		_view.draw_arc(pp, dot * 1.8, 0.0, TAU, 14, PORTAL_COL, 2.0, true)
		_view.draw_circle(pp, dot * 0.8, PORTAL_COL)
	for i in _map.rooms.size():
		if _map.rooms[i]["type"] == "end" and is_seen_world(_map.room_center(i)):
			var ep := off + _px(_map.room_center(i)) * s
			_view.draw_line(ep + Vector2(-1, -1) * dot * 1.3, ep + Vector2(1, 1) * dot * 1.3, ALTAR_COL, 2.0, true)
			_view.draw_line(ep + Vector2(1, -1) * dot * 1.3, ep + Vector2(-1, 1) * dot * 1.3, ALTAR_COL, 2.0, true)
	# Jugadores (el local en cian y con flecha de dirección)
	var local := get_tree().get_first_node_in_group("player")
	for p in NetPlayers.all():
		var pn := p as Node3D
		if pn == null:
			continue
		var pp2 := off + _px(pn.global_position) * s
		if pn == local:
			# Hacia donde mira el modelo (KnightMesh gira hacia el movimiento); el cuerpo no rota
			var body := pn.get("mesh") as Node3D
			var f := -(body.global_transform.basis.z if body != null else pn.global_transform.basis.z)
			var dir := Vector2(f.x, f.z).normalized() if Vector2(f.x, f.z).length() > 0.01 else Vector2.UP
			var side := Vector2(-dir.y, dir.x)
			var r := dot * 1.9
			_view.draw_colored_polygon(PackedVector2Array([pp2 + dir * r * 1.3, pp2 - dir * r * 0.8 + side * r * 0.8, pp2 - dir * r * 0.3, pp2 - dir * r * 0.8 - side * r * 0.8]), ME_COL)
		else:
			_view.draw_circle(pp2, dot * 1.1, MATE_COL)
	var hint := "M · CERRAR" if _expanded else "M"
	HudDraw.text(_view, _font, Vector2(_view.size.x - (70.0 if _expanded else 18.0), _view.size.y - 6.0), hint, 10, Color(1, 1, 1, 0.55))

func _diamond(c: Vector2, r: float, col: Color) -> void:
	_view.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), col)
