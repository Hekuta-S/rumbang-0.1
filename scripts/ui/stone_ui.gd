class_name StoneUI
extends RefCounted

## Piezas de interfaz "dark fantasy de piedra y hierro", dibujadas con código a imitación del HUD de armas
## (marco de hierro biselado y remachado, placa de piedra con vetas, huecos redondos con anillo de metal y
## muescas, adornos en punta). No usa la imagen del HUD: todo es procedural, así que escala a cualquier tamaño.
##   StonePanel  : panel con marco de hierro sobre piedra oscura (el contenido se añade como hijos)
##   SocketPlate : placa de piedra clara con huecos redondos unidos por rombos (equipo y mochila)
##   Socket      : un hueco (botón redondo) con la pieza dentro y el anillo de metal por encima
##   Rail        : cartela alargada con puntas para los títulos
##   style_button: botón de hierro

const AMBER := Color(0.98, 0.64, 0.22)
const TEXT := Color(0.93, 0.90, 0.86)
const TEXT_DIM := Color(0.62, 0.58, 0.54)
const IRON := Color(0.34, 0.33, 0.32)
const IRON_LIGHT := Color(0.66, 0.64, 0.60)
const IRON_DARK := Color(0.12, 0.11, 0.11)
const OUTLINE := Color(0.03, 0.025, 0.025)
const STONE_DARK := Color(0.27, 0.235, 0.225)     ## tinte de la piedra de los paneles (oscuro)
const STONE_PLATE := Color(0.95, 0.80, 0.68)    ## tinte de la placa de huecos (piedra clara y cálida)
const TILE := 160.0

const HOVER_DELAY := 0.12      ## segundos de ratón encima antes de mostrar la tarjeta
const LONG_PRESS := 0.4        ## segundos de dedo quieto para mostrarla en táctil

static var _tex: ImageTexture
static var _card_layer: CanvasLayer
static var _card: Control
static var _card_owner: Control

## Textura de piedra con vetas, sin costuras (se genera una vez).
static func stone_texture() -> ImageTexture:
	if _tex != null:
		return _tex
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.045
	n.fractal_octaves = 4
	n.seed = 11
	var img: Image = n.get_seamless_image(int(TILE), int(TILE))
	var out := Image.create(int(TILE), int(TILE), false, Image.FORMAT_RGBA8)
	var dark := Color(0.26, 0.23, 0.22)
	var light := Color(0.62, 0.55, 0.50)
	for y in int(TILE):
		for x in int(TILE):
			var v := img.get_pixel(x, y).r
			out.set_pixel(x, y, dark.lerp(light, clampf(v * 1.15, 0.0, 1.0)))
	_tex = ImageTexture.create_from_image(out)
	return _tex

## Octógono con las esquinas cortadas (la silueta de las placas del HUD).
static func chamfer_points(r: Rect2, c: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(r.position.x + c, r.position.y), Vector2(r.end.x - c, r.position.y),
		Vector2(r.end.x, r.position.y + c), Vector2(r.end.x, r.end.y - c),
		Vector2(r.end.x - c, r.end.y), Vector2(r.position.x + c, r.end.y),
		Vector2(r.position.x, r.end.y - c), Vector2(r.position.x, r.position.y + c)])

static func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var p := pts.duplicate()
	p.append(pts[0])
	return p

## Placa de piedra con marco de hierro (tres bandas), brillo arriba a la izquierda y remaches en las esquinas.
static func draw_plate(ci: CanvasItem, rect: Rect2, tint: Color, chamfer: float = 14.0) -> void:
	var pts := chamfer_points(rect, chamfer)
	var uvs := PackedVector2Array()
	for p in pts:
		uvs.append(p / TILE)
	ci.draw_colored_polygon(pts, tint, uvs, stone_texture())
	# sombra interior (da relieve a la piedra)
	ci.draw_polyline(_closed(chamfer_points(rect.grow(-9.0), maxf(chamfer - 9.0, 3.0))), Color(0, 0, 0, 0.35), 5.0, true)
	var bands := [[1.5, OUTLINE, 3.0], [5.0, IRON, 4.0], [8.5, IRON_DARK, 2.0]]
	for b in bands:
		var inset: float = b[0]
		ci.draw_polyline(_closed(chamfer_points(rect.grow(-inset), maxf(chamfer - inset, 3.0))), b[1], b[2], true)
	# brillo de la banda de hierro (borde superior e izquierdo) y sombra (inferior y derecho)
	var hi := rect.grow(-5.0)
	ci.draw_line(Vector2(hi.position.x + chamfer, hi.position.y - 1.0), Vector2(hi.end.x - chamfer, hi.position.y - 1.0), Color(IRON_LIGHT, 0.8), 1.5)
	ci.draw_line(Vector2(hi.position.x - 1.0, hi.position.y + chamfer), Vector2(hi.position.x - 1.0, hi.end.y - chamfer), Color(IRON_LIGHT, 0.55), 1.5)
	ci.draw_line(Vector2(hi.position.x + chamfer, hi.end.y + 1.0), Vector2(hi.end.x - chamfer, hi.end.y + 1.0), Color(0, 0, 0, 0.7), 1.5)
	# remaches
	for corner in [rect.position + Vector2(chamfer * 0.55 + 4.0, chamfer * 0.55 + 4.0), Vector2(rect.end.x - chamfer * 0.55 - 4.0, rect.position.y + chamfer * 0.55 + 4.0),
			Vector2(rect.position.x + chamfer * 0.55 + 4.0, rect.end.y - chamfer * 0.55 - 4.0), rect.end - Vector2(chamfer * 0.55 + 4.0, chamfer * 0.55 + 4.0)]:
		ci.draw_circle(corner, 3.0, IRON_LIGHT)
		ci.draw_circle(corner, 1.4, OUTLINE)

## Disco de piedra (con la textura de vetas) centrado en `c`. El CanvasItem necesita texture_repeat activado.
static func draw_stone_disc(ci: CanvasItem, c: Vector2, r: float, tint: Color, segments: int = 48) -> void:
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	for i in segments:
		var p := c + Vector2.from_angle(TAU * i / segments) * r
		pts.append(p)
		uvs.append(p / TILE)
	ci.draw_colored_polygon(pts, tint, uvs, stone_texture())

## Anillo de hierro entre los radios `inner` y `outer` (el de los huecos del inventario): banda metálica,
## brillo arriba-izquierda, sombra abajo-derecha, filos negros y `notches` muescas. `a` = opacidad global.
static func draw_iron_ring(ci: CanvasItem, c: Vector2, inner: float, outer: float, a: float = 1.0, notches: int = 4) -> void:
	var band := outer - inner
	ci.draw_arc(c, inner + band * 0.5, 0.0, TAU, 56, Color(IRON, a), band, true)
	ci.draw_arc(c, inner + band * 0.78, PI * 0.85, PI * 1.65, 24, Color(IRON_LIGHT, 0.85 * a), maxf(1.5, band * 0.22), true)
	ci.draw_arc(c, inner + band * 0.3, -PI * 0.15, PI * 0.65, 24, Color(0, 0, 0, 0.45 * a), maxf(1.5, band * 0.22), true)
	ci.draw_arc(c, outer - 0.8, 0.0, TAU, 56, Color(OUTLINE, a), 1.6, true)
	ci.draw_arc(c, inner, 0.0, TAU, 56, Color(OUTLINE, a), 1.6, true)
	for k in notches:
		var dir := Vector2.RIGHT.rotated(k * TAU / notches)
		ci.draw_line(c + dir * (inner + band * 0.15), c + dir * (outer - band * 0.1), Color(IRON_LIGHT, a), maxf(1.5, band * 0.18))

## Rombo de hierro (el adorno que une los huecos).
static func draw_diamond(ci: CanvasItem, c: Vector2, r: float) -> void:
	var d := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 1.5, 0), c + Vector2(0, r), c + Vector2(-r * 1.5, 0)])
	ci.draw_colored_polygon(d, IRON)
	ci.draw_polyline(_closed(d), OUTLINE, 1.5, true)
	ci.draw_circle(c, r * 0.28, IRON_LIGHT)

# ───────────────────────────── tarjeta de información ─────────────────────────────

static func _label(t: String, size: int, color: Color, wrap: bool = true) -> Label:
	var l := Label.new()
	l.text = t
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## Tarjeta de una pieza: nombre, rareza, stats, elemento, modificador, efecto y set. `delta` (cambio de stats frente a
## lo equipado) y `old` (la pieza que sustituiría) añaden la comparación, como en la mochila.
static func item_card(it: Dictionary, delta: Dictionary = {}, old: Dictionary = {}, width: float = 300.0) -> Control:
	var p := StonePanel.new(16.0)
	p.custom_minimum_size = Vector2(width, 0)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.theme = RumbangStyle.get_theme()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	var col := EquipmentDB.rarity_color(it)
	v.add_child(_label(String(it.get("name", "")), 14, col))
	var kind := String(EquipmentDB.KIND_NAMES.get(String(it.get("slot", "")), ""))
	v.add_child(_label("%s · %s" % [kind, EquipmentDB.rarity_name(it)], 10, Color(col, 0.75)))
	if delta.is_empty():
		var st := EquipmentDB.describe_stats(it.get("stats", {}))
		if not st.is_empty():
			v.add_child(_label("\n".join(st), 11, TEXT))
	else:
		var flow := HFlowContainer.new()
		flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(flow)
		for k in delta:
			var val := float(delta[k])
			if not is_zero_approx(val):
				flow.add_child(_label(EquipmentDB.format_stat(String(k), val) + "   ", 10, Color(0.55, 0.9, 0.5) if val > 0.0 else Color(0.92, 0.4, 0.4), false))
	var el := EquipmentDB.element_of(it)
	for line in EquipmentDB.trait_lines(it):
		var c := col
		if el != "" and (line.begins_with("Elemento") or line.begins_with("Armadura de")):
			c = EquipmentDB.ELEMENTS[el]["color"]
		v.add_child(_label(line, 10, c))
	if EquipmentDB.SETS.has(String(it.get("set", ""))):
		v.add_child(_label("Set " + String(EquipmentDB.SETS[it["set"]]["name"]), 10, TEXT_DIM))
	if not old.is_empty() and EquipmentDB.trait_lines(old) != EquipmentDB.trait_lines(it):
		var ot := EquipmentDB.trait_lines(old)
		v.add_child(_label("Ahora llevas: " + (" | ".join(ot) if not ot.is_empty() else "sin efectos"), 9, TEXT_DIM))
	return p

## Muestra `card` junto a `anchor` (a su derecha o izquierda, sin salirse de la pantalla), sobre toda la interfaz.
static func show_card(anchor: Control, card: Control) -> void:
	hide_card()
	if anchor == null or not anchor.is_inside_tree():
		card.queue_free()
		return
	var tree := anchor.get_tree()
	_card_layer = CanvasLayer.new()
	_card_layer.layer = 120
	_card_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	tree.root.add_child(_card_layer)
	_card = card
	_card_owner = anchor
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.modulate.a = 0.0               # se coloca en el siguiente fotograma, cuando ya conoce su tamaño
	_card_layer.add_child(card)
	_place_card.call_deferred(anchor, card)

static func _place_card(anchor: Control, card: Control) -> void:
	if card != _card or not is_instance_valid(card) or not is_instance_valid(anchor) or not anchor.is_inside_tree():
		return
	card.reset_size()
	var sz := card.get_combined_minimum_size()
	card.size = sz
	var vp := anchor.get_tree().root.get_visible_rect().size
	var r := anchor.get_global_rect()
	var pos := Vector2(r.end.x + 12.0, r.position.y)
	if pos.x + sz.x > vp.x - 8.0:
		pos.x = r.position.x - sz.x - 12.0
	if pos.x < 8.0:                      # no cabe a los lados: debajo o encima
		pos.x = clampf(r.position.x, 8.0, maxf(8.0, vp.x - sz.x - 8.0))
		pos.y = r.end.y + 10.0
		if pos.y + sz.y > vp.y - 8.0:
			pos.y = r.position.y - sz.y - 10.0
	pos.y = clampf(pos.y, 8.0, maxf(8.0, vp.y - sz.y - 8.0))
	card.position = pos
	card.modulate.a = 1.0

## Oculta la tarjeta. Con `owner_ctrl`, solo si la mostró ese hueco (un hueco que se va no cierra la de otro).
static func hide_card(owner_ctrl: Control = null) -> void:
	if owner_ctrl != null and owner_ctrl != _card_owner:
		return
	if is_instance_valid(_card_layer):
		_card_layer.queue_free()
	_card_layer = null
	_card = null
	_card_owner = null

static func card_visible() -> bool:
	return is_instance_valid(_card) and _card.is_inside_tree()

## Botón de hierro: fondo oscuro, borde metálico; en hover el borde se vuelve ámbar.
static func style_button(b: Button, font_size: int = 11) -> void:
	var mk := func(bg: Color, border: Color) -> StyleBoxFlat:
		var s := StyleBoxFlat.new()
		s.bg_color = bg
		s.set_border_width_all(2)
		s.border_color = border
		s.set_corner_radius_all(2)
		s.content_margin_left = 12
		s.content_margin_right = 12
		s.content_margin_top = 5
		s.content_margin_bottom = 5
		s.shadow_color = Color(0, 0, 0, 0.5)
		s.shadow_size = 2
		return s
	b.add_theme_stylebox_override("normal", mk.call(Color(0.12, 0.105, 0.10), Color(0.42, 0.40, 0.38)))
	b.add_theme_stylebox_override("hover", mk.call(Color(0.20, 0.15, 0.11), AMBER))
	b.add_theme_stylebox_override("pressed", mk.call(Color(0.28, 0.14, 0.08), AMBER))
	b.add_theme_stylebox_override("focus", mk.call(Color(0, 0, 0, 0), AMBER))
	b.add_theme_stylebox_override("disabled", mk.call(Color(0.09, 0.085, 0.085), Color(0.22, 0.21, 0.2)))
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(0.4, 0.38, 0.36))
	b.add_theme_font_size_override("font_size", font_size)

# ───────────────────────────── piezas ─────────────────────────────

## Panel de piedra oscura con marco de hierro. Los hijos se colocan dentro con `pad` píxeles de margen.
class StonePanel extends PanelContainer:
	func _init(pad: float = 20.0) -> void:
		texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		var e := StyleBoxEmpty.new()
		e.set_content_margin_all(pad)
		add_theme_stylebox_override("panel", e)

	func _draw() -> void:
		StoneUI.draw_plate(self, Rect2(Vector2.ZERO, size), StoneUI.STONE_DARK, 16.0)

## Título: cartela de hierro con puntas a los lados y el texto en ámbar.
class Rail extends Control:
	var text := ""
	var font_size := 14
	var _label: Label

	func _init(p_text: String, p_font_size: int = 14, min_w: float = 0.0) -> void:
		text = p_text
		font_size = p_font_size
		custom_minimum_size = Vector2(min_w, font_size + 22.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_label = Label.new()
		_label.text = p_text
		_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_label.add_theme_font_size_override("font_size", font_size)
		_label.add_theme_color_override("font_color", StoneUI.AMBER)
		_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		_label.add_theme_constant_override("outline_size", 5)
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_label)

	func set_text(t: String) -> void:
		text = t
		_label.text = t

	func _draw() -> void:
		var h := size.y
		var tip := h * 0.7
		var pts := PackedVector2Array([Vector2(0, h / 2.0), Vector2(tip, 1), Vector2(size.x - tip, 1),
			Vector2(size.x, h / 2.0), Vector2(size.x - tip, h - 1), Vector2(tip, h - 1)])
		draw_colored_polygon(pts, Color(0.07, 0.06, 0.06))
		draw_polyline(StoneUI._closed(pts), StoneUI.OUTLINE, 3.0, true)
		var inner := PackedVector2Array([Vector2(7, h / 2.0), Vector2(tip + 1, 4.5), Vector2(size.x - tip - 1, 4.5),
			Vector2(size.x - 7, h / 2.0), Vector2(size.x - tip - 1, h - 4.5), Vector2(tip + 1, h - 4.5)])
		draw_polyline(StoneUI._closed(inner), StoneUI.IRON, 3.0, true)
		draw_line(Vector2(tip + 2, 3.5), Vector2(size.x - tip - 2, 3.5), Color(StoneUI.IRON_LIGHT, 0.6), 1.0)
		# adornos de las puntas
		draw_circle(Vector2(h * 0.5, h / 2.0), 2.5, StoneUI.IRON_LIGHT)
		draw_circle(Vector2(size.x - h * 0.5, h / 2.0), 2.5, StoneUI.IRON_LIGHT)

## Un hueco redondo: la pieza dentro (símbolo o icono) con un resplandor del color de su rareza y,
## por encima, el anillo de metal con muescas. Es un botón (se elige con clic o con el foco).
class Socket extends Button:
	var color := Color(0.3, 0.2, 0.42)
	var filled := false
	var selected := false
	var tex: Texture2D
	var item: Dictionary = {}
	## Cómo se construye la tarjeta de información de este hueco (por defecto StoneUI.item_card(item)).
	var card_builder: Callable = Callable()
	var long_press_fired := false     ## una pulsación larga acaba de mostrar la tarjeta: el clic de soltar no cuenta
	var _glyph: Label
	var _touch := false
	var _hold_id := 0

	func _init(diameter: float) -> void:
		custom_minimum_size = Vector2(diameter, diameter)
		size = Vector2(diameter, diameter)
		flat = true
		focus_mode = Control.FOCUS_ALL
		var clear := StyleBoxEmpty.new()
		for st in ["normal", "hover", "pressed", "focus", "disabled"]:
			add_theme_stylebox_override(st, clear)
		_glyph = Label.new()
		_glyph.set_anchors_preset(Control.PRESET_FULL_RECT)
		_glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_glyph.add_theme_font_size_override("font_size", int(diameter * 0.42))
		_glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_glyph)
		mouse_entered.connect(_on_hover)
		mouse_exited.connect(_on_leave)

	func show_item(it: Dictionary, glyph: String, p_tex: Texture2D = null) -> void:
		item = it
		filled = not it.is_empty()
		color = EquipmentDB.rarity_color(it) if filled else Color(0.3, 0.2, 0.42)
		tex = p_tex
		_glyph.text = "" if p_tex != null else glyph
		_glyph.modulate.a = 1.0 if filled else 0.28
		if not filled:
			StoneUI.hide_card(self)
		queue_redraw()

	func set_selected(on: bool) -> void:
		selected = on
		queue_redraw()

	## true una sola vez tras una pulsación larga: quien reacciona al clic debe ignorarlo (ver SocketPlate).
	func take_long_press() -> bool:
		var v := long_press_fired
		long_press_fired = false
		return v

	func _build_card() -> Control:
		return card_builder.call() if card_builder.is_valid() else StoneUI.item_card(item)

	## Ratón encima: la tarjeta sale casi al instante (un poco de retardo para no parpadear al cruzar huecos).
	func _on_hover() -> void:
		if not filled:
			return
		_hold_id += 1
		var id := _hold_id
		await get_tree().create_timer(StoneUI.HOVER_DELAY, true).timeout
		if id == _hold_id and not _touch and filled and is_inside_tree():
			StoneUI.show_card(self, _build_card())

	func _on_leave() -> void:
		_hold_id += 1
		StoneUI.hide_card(self)

	## Táctil: mantener el dedo LONG_PRESS segundos (sin moverlo) muestra la tarjeta; al soltar se oculta.
	func _gui_input(event: InputEvent) -> void:
		if event is InputEventScreenTouch:
			if event.pressed:
				_touch = true
				long_press_fired = false
				_hold_id += 1
				var id := _hold_id
				await get_tree().create_timer(StoneUI.LONG_PRESS, true).timeout
				if id == _hold_id and _touch and filled and is_inside_tree():
					long_press_fired = true
					StoneUI.show_card(self, _build_card())
			else:
				_touch = false
				_hold_id += 1
				StoneUI.hide_card(self)
		elif event is InputEventScreenDrag and (event as InputEventScreenDrag).relative.length() > 12.0:
			_hold_id += 1      # arrastrar cancela la pulsación larga

	func _exit_tree() -> void:
		StoneUI.hide_card(self)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_FOCUS_ENTER or what == NOTIFICATION_FOCUS_EXIT or what == NOTIFICATION_MOUSE_ENTER or what == NOTIFICATION_MOUSE_EXIT:
			queue_redraw()

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0
		var inner := r * 0.78
		draw_circle(c, inner, Color(0.025, 0.04, 0.04))
		if filled:
			for i in 5:
				draw_arc(c, inner - 1.5 - i * (inner * 0.07), 0.0, TAU, 48, Color(color, 0.55 - i * 0.1), maxf(2.0, inner * 0.07), true)
		if tex:
			draw_texture_rect(tex, Rect2(c - Vector2(inner, inner) * 0.95, Vector2(inner, inner) * 1.9), false, Color(1, 1, 1, 1.0 if filled else 0.35))
		# anillo de hierro: banda, brillo arriba-izquierda, sombra abajo-derecha y filos negros
		var band := r - inner
		draw_arc(c, inner + band * 0.5, 0.0, TAU, 56, StoneUI.IRON, band, true)
		draw_arc(c, inner + band * 0.78, PI * 0.85, PI * 1.65, 24, Color(StoneUI.IRON_LIGHT, 0.85), maxf(1.5, band * 0.22), true)
		draw_arc(c, inner + band * 0.3, -PI * 0.15, PI * 0.65, 24, Color(0, 0, 0, 0.45), maxf(1.5, band * 0.22), true)
		draw_arc(c, r - 0.8, 0.0, TAU, 56, StoneUI.OUTLINE, 1.6, true)
		draw_arc(c, inner, 0.0, TAU, 56, StoneUI.OUTLINE, 1.6, true)
		# muescas en los cuatro puntos cardinales
		for k in 4:
			var dir := Vector2.RIGHT.rotated(k * PI / 2.0)
			draw_line(c + dir * (inner + band * 0.15), c + dir * (r - band * 0.1), StoneUI.IRON_LIGHT, maxf(1.5, band * 0.18))
		if selected:
			draw_arc(c, inner - 1.0, 0.0, TAU, 48, StoneUI.AMBER, 3.0, true)
		if has_focus() or is_hovered():
			draw_arc(c, r + 1.5, 0.0, TAU, 56, Color(StoneUI.AMBER, 0.85), 2.0, true)

## Placa de piedra clara con una cuadrícula de huecos redondos unidos por rombos de hierro (como la del HUD de armas).
class SocketPlate extends Control:
	signal socket_pressed(index: int)

	var sockets: Array = []
	var cols := 5
	var rows := 1
	var diameter := 64.0
	var gap := 14.0
	var pad := 18.0

	func _init(p_cols: int, p_rows: int = 1, p_diameter: float = 64.0, p_gap: float = 14.0, p_pad: float = 18.0) -> void:
		cols = p_cols
		rows = p_rows
		diameter = p_diameter
		gap = p_gap
		pad = p_pad
		texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		custom_minimum_size = Vector2(pad * 2.0 + cols * diameter + (cols - 1) * gap, pad * 2.0 + rows * diameter + (rows - 1) * gap)
		for i in cols * rows:
			var s := Socket.new(diameter)
			s.position = Vector2(pad + (i % cols) * (diameter + gap), pad + (i / cols) * (diameter + gap))
			s.pressed.connect(func():
				if not s.take_long_press():
					socket_pressed.emit(i))
			add_child(s)
			sockets.append(s)

	func _draw() -> void:
		StoneUI.draw_plate(self, Rect2(Vector2.ZERO, size), StoneUI.STONE_PLATE, minf(14.0, pad * 0.9))
		for i in cols * rows:
			if i % cols == cols - 1:
				continue
			var s: Control = sockets[i]
			StoneUI.draw_diamond(self, s.position + Vector2(diameter + gap * 0.5, diameter * 0.5), minf(gap * 0.32, 6.0))
