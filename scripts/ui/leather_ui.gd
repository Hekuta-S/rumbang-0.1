class_name LeatherUI
extends RefCounted

## Piezas de interfaz "mochila cartoon 2D": cuero marrón con grano, borde de tinta, sombra dura, costuras claras y
## remaches de latón (el mismo lenguaje que la bolsa del HUD de supervivencia, tools/make_ui_icons.py). Todo opaco.
## Misma forma que StoneUI para poder cambiar una por otra:
##   Sheet       : panel de cuero cosido (el contenido se añade como hijos)
##   SocketPlate : placa de cuero con huecos redondos (equipo y mochila)
##   Socket      : un hueco: bolsillo oscuro con aro de latón y la pieza dentro
##   Rail        : cinta de cuero cosida para los títulos
##   style_button / item_card

const TEXT := Color(0.98, 0.92, 0.78)
const TEXT_DIM := Color(0.86, 0.72, 0.52)
const AMBER := Color(1.0, 0.78, 0.30)
const INK := Color(0.10, 0.055, 0.03)
const LEATHER := Color(0.48, 0.29, 0.165)
const LEATHER_DARK := Color(0.30, 0.17, 0.09)
const LEATHER_FLAP := Color(0.38, 0.22, 0.12)
const POCKET := Color(0.19, 0.11, 0.06)
const STITCH := Color(0.88, 0.72, 0.49)
const BRASS := Color(0.80, 0.63, 0.24)
const BRASS_LIGHT := Color(0.98, 0.88, 0.55)
const BRASS_DARK := Color(0.50, 0.37, 0.12)
const BACKDROP := Color(0.13, 0.075, 0.04)
const TILE := 128

static var _grain: ImageTexture

## Motas y arañazos de cuero (alfa suave: se pinta sobre un fondo ya opaco, sin costuras).
static func grain_texture() -> ImageTexture:
	if _grain != null:
		return _grain
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.07
	n.fractal_octaves = 3
	n.seed = 7
	var img: Image = n.get_seamless_image(TILE, TILE)
	var out := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
	for y in TILE:
		for x in TILE:
			var v := img.get_pixel(x, y).r
			var dark := clampf((0.45 - v) * 1.1, 0.0, 0.4)
			var light := clampf((v - 0.62) * 0.9, 0.0, 0.25)
			out.set_pixel(x, y, Color(0.16, 0.08, 0.03, dark) if dark > light else Color(0.85, 0.6, 0.38, light))
	var rnd := RandomNumberGenerator.new()
	rnd.seed = 3
	for i in 70:
		var px := rnd.randi_range(0, TILE - 1)
		var py := rnd.randi_range(0, TILE - 1)
		out.set_pixel(px, py, Color(0.12, 0.06, 0.02, 0.55))
		out.set_pixel((px + 1) % TILE, py, Color(0.12, 0.06, 0.02, 0.4))
	_grain = ImageTexture.create_from_image(out)
	return _grain

static func _flat(bg: Color, border: Color, bw: int, radius: int, shadow: bool = true) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.anti_aliasing = true
	if shadow:
		s.shadow_color = Color(INK, 0.85)             # sombra dura de tinta (cómic)
		s.shadow_size = 1
		s.shadow_offset = Vector2(3, 4)
	return s

## Costura discontinua recta de `a` a `b`.
static func stitch_line(ci: CanvasItem, a: Vector2, b: Vector2, dash: float = 7.0, gap: float = 5.0, color: Color = STITCH, w: float = 1.6) -> void:
	var len := a.distance_to(b)
	if len < 1.0:
		return
	var dir := (b - a) / len
	var t := 0.0
	while t < len:
		ci.draw_line(a + dir * t, a + dir * minf(t + dash, len), color, w)
		t += dash + gap

## Rectángulo cosido: costura por dentro del borde (las esquinas se dejan libres para el redondeo).
static func stitch_rect(ci: CanvasItem, r: Rect2, corner: float = 10.0, color: Color = STITCH) -> void:
	stitch_line(ci, r.position + Vector2(corner, 0), Vector2(r.end.x - corner, r.position.y), 7.0, 5.0, color)
	stitch_line(ci, Vector2(r.position.x + corner, r.end.y), r.end - Vector2(corner, 0), 7.0, 5.0, color)
	stitch_line(ci, r.position + Vector2(0, corner), Vector2(r.position.x, r.end.y - corner), 7.0, 5.0, color)
	stitch_line(ci, Vector2(r.end.x, r.position.y + corner), r.end - Vector2(0, corner), 7.0, 5.0, color)

## Remache de latón.
static func rivet(ci: CanvasItem, c: Vector2, r: float = 3.5) -> void:
	ci.draw_circle(c, r + 1.5, INK)
	ci.draw_circle(c, r, BRASS)
	ci.draw_circle(c + Vector2(-r * 0.25, -r * 0.3), r * 0.4, BRASS_LIGHT)

## Cuero opaco con borde de tinta, grano y costura. El CanvasItem necesita texture_repeat activado.
static func draw_leather(ci: CanvasItem, rect: Rect2, base: Color = LEATHER, radius: float = 14.0, stitches: bool = true) -> void:
	ci.draw_style_box(_flat(base, INK, 4, int(radius)), rect)
	var inner := rect.grow(-5.0)
	ci.draw_texture_rect(grain_texture(), inner, true, Color(1, 1, 1, 0.5))
	ci.draw_style_box(_flat(Color(0, 0, 0, 0), Color(INK.r, INK.g, INK.b, 0.28), 3, int(maxf(radius - 4.0, 3.0)), false), rect.grow(-4.0))
	if stitches:
		stitch_rect(ci, rect.grow(-11.0), maxf(radius - 3.0, 4.0))

# ───────────────────────────── tarjeta de información ─────────────────────────────

static func _label(t: String, size: int, color: Color, do_wrap: bool = true) -> Label:
	var l := Label.new()
	l.text = t
	if do_wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## Tarjeta de una pieza (como StoneUI.item_card pero de cuero).
static func item_card(it: Dictionary, delta: Dictionary = {}, old: Dictionary = {}, width: float = 300.0) -> Control:
	var p := Sheet.new(16.0)
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
	v.add_child(_label("%s · %s" % [kind, EquipmentDB.rarity_name(it)], 10, col.lightened(0.15)))
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
				flow.add_child(_label(EquipmentDB.format_stat(String(k), val) + "   ", 10, Color(0.6, 0.95, 0.5) if val > 0.0 else Color(1.0, 0.5, 0.45), false))
	var el := EquipmentDB.element_of(it)
	for line in EquipmentDB.trait_lines(it):
		var c := EquipmentDB.trait_color(line, col)
		if el != "" and (line.begins_with("Elemento") or line.begins_with("Armadura de")):
			c = EquipmentDB.ELEMENTS[el]["color"]
		v.add_child(_label(line, 10, c))
	if EquipmentDB.SETS.has(String(it.get("set", ""))):
		v.add_child(_label("Set " + String(EquipmentDB.SETS[it["set"]]["name"]), 10, TEXT_DIM))
	if not old.is_empty() and EquipmentDB.trait_lines(old) != EquipmentDB.trait_lines(it):
		var ot := EquipmentDB.trait_lines(old)
		v.add_child(_label("Ahora llevas: " + (" | ".join(ot) if not ot.is_empty() else "sin efectos"), 9, TEXT_DIM))
	return p

## Botón de cuero: cuerpo marrón, borde de tinta, sombra dura; en hover el borde se vuelve latón.
static func style_button(b: Button, font_size: int = 11) -> void:
	var mk := func(bg: Color, border: Color, shadow: bool = true) -> StyleBoxFlat:
		var s := _flat(bg, border, 3, 8, shadow)
		s.content_margin_left = 12
		s.content_margin_right = 12
		s.content_margin_top = 5
		s.content_margin_bottom = 5
		return s
	b.add_theme_color_override("font_outline_color", INK)
	b.add_theme_constant_override("outline_size", 5)
	b.add_theme_stylebox_override("normal", mk.call(LEATHER_FLAP, INK))
	b.add_theme_stylebox_override("hover", mk.call(LEATHER, BRASS_LIGHT))
	b.add_theme_stylebox_override("pressed", mk.call(LEATHER_DARK, BRASS_LIGHT))
	b.add_theme_stylebox_override("focus", mk.call(Color(0, 0, 0, 0), AMBER, false))
	b.add_theme_stylebox_override("disabled", mk.call(Color(0.25, 0.17, 0.11), Color(0.17, 0.11, 0.07)))
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(0.5, 0.42, 0.34))
	b.add_theme_font_size_override("font_size", font_size)

# ───────────────────────────── piezas ─────────────────────────────

## Panel de cuero cosido. Los hijos se colocan dentro con `pad` píxeles de margen.
class Sheet extends PanelContainer:
	var base := LeatherUI.LEATHER

	func _init(pad: float = 20.0, p_base: Color = LeatherUI.LEATHER) -> void:
		base = p_base
		texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		var e := StyleBoxEmpty.new()
		e.set_content_margin_all(pad)
		add_theme_stylebox_override("panel", e)

	func _draw() -> void:
		LeatherUI.draw_leather(self, Rect2(Vector2.ZERO, size - Vector2(3, 4)), base, 14.0)

## Título: cinta de cuero oscuro cosida, con remaches a los lados y el texto crema.
class Rail extends Control:
	var text := ""
	var font_size := 14
	var _label: Label

	func _init(p_text: String, p_font_size: int = 14, min_w: float = 0.0) -> void:
		text = p_text
		font_size = p_font_size
		texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		custom_minimum_size = Vector2(min_w, font_size + 22.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_label = Label.new()
		_label.text = p_text
		_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_label.add_theme_font_size_override("font_size", font_size)
		_label.add_theme_color_override("font_color", LeatherUI.TEXT)
		_label.add_theme_color_override("font_outline_color", LeatherUI.INK)
		_label.add_theme_constant_override("outline_size", 7)
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_label)

	func set_text(t: String) -> void:
		text = t
		_label.text = t

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size - Vector2(3, 4))
		LeatherUI.draw_leather(self, r, LeatherUI.LEATHER_FLAP, 8.0, false)
		LeatherUI.stitch_line(self, Vector2(18, 7), Vector2(r.size.x - 18, 7), 6.0, 4.0)
		LeatherUI.stitch_line(self, Vector2(18, r.size.y - 7), Vector2(r.size.x - 18, r.size.y - 7), 6.0, 4.0)
		LeatherUI.rivet(self, Vector2(10, r.size.y * 0.5), 2.8)
		LeatherUI.rivet(self, Vector2(r.size.x - 10, r.size.y * 0.5), 2.8)

## Un hueco redondo: bolsillo oscuro de cuero con la pieza dentro (resplandor del color de su rareza) y aro de latón.
class Socket extends StoneUI.Socket:
	func _build_card() -> Control:
		return card_builder.call() if card_builder.is_valid() else LeatherUI.item_card(item)

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0 - 2.0
		var inner := r * 0.80
		draw_circle(c + Vector2(2.5, 3.5), r, Color(LeatherUI.INK, 0.85))          # sombra dura
		draw_circle(c, r, LeatherUI.INK)
		draw_circle(c, r - 2.0, LeatherUI.BRASS)
		draw_arc(c, r - 3.5, PI * 0.9, PI * 1.6, 20, LeatherUI.BRASS_LIGHT, 2.0, true)
		draw_arc(c, r - 3.5, -PI * 0.1, PI * 0.55, 20, LeatherUI.BRASS_DARK, 2.0, true)
		draw_circle(c, inner + 1.5, LeatherUI.INK)
		draw_circle(c, inner, LeatherUI.POCKET)
		if filled:
			for i in 4:
				draw_arc(c, inner - 2.0 - i * (inner * 0.07), 0.0, TAU, 48, color.darkened(0.15 * i), maxf(2.0, inner * 0.07), true)
		if tex:
			draw_texture_rect(tex, Rect2(c - Vector2(inner, inner) * 0.95, Vector2(inner, inner) * 1.9), false, Color(1, 1, 1, 1.0 if filled else 0.4))
		if selected:
			draw_arc(c, r + 1.5, 0.0, TAU, 56, LeatherUI.AMBER, 3.2, true)
		elif has_focus() or is_hovered():
			draw_arc(c, r + 1.5, 0.0, TAU, 56, LeatherUI.BRASS_LIGHT, 2.4, true)

## Placa de cuero con una cuadrícula de huecos redondos unidos por remaches.
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
			var s := LeatherUI.Socket.new(diameter)
			s.position = Vector2(pad + (i % cols) * (diameter + gap), pad + (i / cols) * (diameter + gap))
			s.pressed.connect(func():
				if not s.take_long_press():
					socket_pressed.emit(i))
			add_child(s)
			sockets.append(s)

	func _draw() -> void:
		LeatherUI.draw_leather(self, Rect2(Vector2.ZERO, size - Vector2(3, 4)), Color(0.56, 0.35, 0.2), minf(14.0, pad * 0.9), pad >= 14.0)
		for i in cols * rows:
			if i % cols == cols - 1:
				continue
			var s: Control = sockets[i]
			LeatherUI.rivet(self, s.position + Vector2(diameter + gap * 0.5, diameter * 0.5), minf(gap * 0.2, 3.5))
