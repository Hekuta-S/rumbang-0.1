class_name BagPanel
extends PanelContainer

## "Bolsa" del HUD de supervivencia: a la derecha de la pantalla, un panel de cuero (estirado en 9 partes,
## tools/make_ui_icons.py) con los TOMOS (icono + nivel) y los OBJETOS recogidos (icono + copias).
## Los objetos aún no tienen dibujo: se muestra un medallón del color de su rareza con su inicial
## (ITEM_ICON_DIR queda listo para cuando existan: assets/ui/icons/items/<id>.png).
## Se pliega/despliega tocando la cabecera; en móvil empieza plegada (los botones táctiles van a la derecha).
## HUD.refresh_bag() la actualiza cuando cambian tomos u objetos (PlayerStatBlock.stats_recalculated).

const LEATHER := "res://assets/ui/hud/bolsa_cuero.png"
const BAG_ICON := "res://assets/ui/hud/bolsa_cerrada.png"
const ITEM_ICON_DIR := "res://assets/ui/icons/items/"
const FLAP := 104              ## = BAG_FLAP de tools/make_ui_icons.py (alto de la solapa)
const SIDE := 34               ## = BAG_SIDE
const CELL := 34               ## px de cada icono
const COLS := 4
const WIDTH := 196
## Color del medallón provisional por rareza de ItemDB (COMMON, UNCOMMON, RARE, LEGENDARY, MYTHIC).
const ITEM_RARITY_COLOR := [Color(0.72, 0.72, 0.75), Color(0.4, 0.85, 0.45), Color(0.35, 0.6, 1.0),
	Color(1.0, 0.65, 0.2), Color(0.8, 0.4, 1.0)]
const TEXT := Color(0.98, 0.92, 0.78)
const TEXT_DIM := Color(0.9, 0.78, 0.6)

var collapsed := false
var _content: VBoxContainer
var _tomes_grid: GridContainer
var _items_grid: GridContainer
var _items_title: Label
var _tomes_title: Label
var _header_btn: Button
var _flap_gap: Control
const FLAP_GAP := 46       ## espacio bajo la cabecera para no tapar el botón de la solapa
var _open_style: StyleBox
var _closed_style: StyleBox

func _ready() -> void:
	name = "BagPanel"
	mouse_filter = Control.MOUSE_FILTER_PASS
	_open_style = _leather_style()
	_closed_style = StyleBoxEmpty.new()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	add_child(vb)
	_header_btn = Button.new()
	_header_btn.flat = true
	_header_btn.focus_mode = Control.FOCUS_NONE
	_header_btn.text = "BOLSA"
	_header_btn.icon = load(BAG_ICON) if ResourceLoader.exists(BAG_ICON) else null
	_header_btn.expand_icon = false
	_header_btn.add_theme_constant_override("icon_max_width", 30)
	_header_btn.add_theme_font_size_override("font_size", 14)
	_header_btn.add_theme_color_override("font_color", TEXT)
	_header_btn.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.02))
	_header_btn.add_theme_constant_override("outline_size", 4)
	_header_btn.tooltip_text = "Tomos y objetos (toca para plegar)"
	_header_btn.pressed.connect(func(): set_collapsed(not collapsed))
	vb.add_child(_header_btn)
	# El contenido empieza bajo la solapa (su botón de latón queda a la vista)
	_flap_gap = Control.new()
	_flap_gap.custom_minimum_size = Vector2(0, FLAP_GAP)
	_flap_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(_flap_gap)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 6)
	vb.add_child(_content)
	_tomes_title = _title("TOMOS")
	_content.add_child(_tomes_title)
	_tomes_grid = _grid()
	_content.add_child(_tomes_grid)
	_items_title = _title("OBJETOS")
	_content.add_child(_items_title)
	_items_grid = _grid()
	_content.add_child(_items_grid)
	set_collapsed(Quality.is_mobile())
	minimum_size_changed.connect(func(): _relayout.call_deferred())

var _margin := 12.0

## Coloca la bolsa a la derecha, centrada en vertical. Los offsets se recalculan con su tamaño real cada vez
## que cambia el contenido (_relayout): un preset de anclaje deja offsets viejos y la estira a toda la altura.
func place_right(margin: float = 12.0) -> void:
	_margin = margin
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.5
	anchor_bottom = 0.5
	_relayout()

func _relayout() -> void:
	var s := get_combined_minimum_size()
	offset_right = -_margin
	offset_left = -_margin - s.x
	offset_top = -s.y * 0.5
	offset_bottom = s.y * 0.5
	size = s

func set_collapsed(v: bool) -> void:
	collapsed = v
	_content.visible = not v
	_flap_gap.visible = not v
	add_theme_stylebox_override("panel", _closed_style if v else _open_style)
	custom_minimum_size = Vector2(0, 0) if v else Vector2(WIDTH, 0)
	_header_btn.text = "" if v else "BOLSA"
	_relayout.call_deferred()

## Rellena la bolsa: tomos de TomeDB (icono + nivel) y objetos del inventario (icono + copias).
func refresh(inventory) -> void:
	for g in [_tomes_grid, _items_grid]:
		for c in g.get_children():
			g.remove_child(c)       # fuera ya: si no, cuentan para el tamaño hasta el próximo frame
			c.queue_free()
	var tomes: Dictionary = TomeDB.owned()
	for id in tomes:
		var def: Dictionary = TomeDB.TOMES.get(id, {})
		var tip := "%s · nivel %d\n%s" % [def.get("name", id), TomeDB.level(id), def.get("desc", "")]
		_tomes_grid.add_child(_cell(_load(TomeDB.icon_path(id)), str(TomeDB.level(id)), tip, Color(0.9, 0.8, 0.5), String(def.get("name", id))))
	_tomes_title.text = "TOMOS %d/%d" % [tomes.size(), TomeDB.SLOTS]
	var counts := {}
	var order: Array = []
	if inventory != null:
		for item_id in inventory.collected_items:
			if not counts.has(item_id):
				order.append(item_id)
			counts[item_id] = int(counts.get(item_id, 0)) + 1
	for item_id in order:
		var it: Dictionary = ItemDB.get_item(item_id)
		var r := clampi(int(it.get("rarity", 0)), 0, ITEM_RARITY_COLOR.size() - 1)
		var tip := "%s ×%d\n%s" % [it.get("name", item_id), counts[item_id], it.get("description", "")]
		var n: int = counts[item_id]
		_items_grid.add_child(_cell(_load(ITEM_ICON_DIR + String(item_id) + ".png"), "×%d" % n if n > 1 else "",
			tip, ITEM_RARITY_COLOR[r], String(it.get("name", item_id))))
	_items_title.text = "OBJETOS %d" % inventory.collected_items.size() if inventory != null else "OBJETOS"
	_tomes_title.visible = true
	_items_title.visible = true
	_relayout.call_deferred()

func tome_count() -> int:
	return _tomes_grid.get_child_count()

func item_count() -> int:
	return _items_grid.get_child_count()

# ── piezas ───────────────────────────────────────────────────────────────

func _leather_style() -> StyleBox:
	if not ResourceLoader.exists(LEATHER):
		var flat := StyleBoxFlat.new()
		flat.bg_color = Color(0.48, 0.29, 0.16)
		flat.set_content_margin_all(12)
		return flat
	var sb := StyleBoxTexture.new()
	sb.texture = load(LEATHER)
	sb.texture_margin_top = FLAP
	sb.texture_margin_left = SIDE
	sb.texture_margin_right = SIDE
	sb.texture_margin_bottom = SIDE
	sb.content_margin_top = 22
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_bottom = 26
	return sb

## Plegada: pastilla de cuero opaca tras el saquito (antes quedaba el icono suelto sobre el mapa).
func _sack_style() -> StyleBox:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.48, 0.29, 0.165)
	s.border_color = Color(0.1, 0.055, 0.03)
	s.set_border_width_all(3)
	s.set_corner_radius_all(12)
	s.anti_aliasing = true
	s.shadow_color = Color(0.1, 0.055, 0.03, 0.85)
	s.shadow_size = 1
	s.shadow_offset = Vector2(3, 4)
	s.set_content_margin_all(4)
	return s

func _title(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", TEXT_DIM)
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.02))
	l.add_theme_constant_override("outline_size", 3)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _grid() -> GridContainer:
	var g := GridContainer.new()
	g.columns = COLS
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 4)
	return g

func _load(path: String) -> Texture2D:
	return load(path) if path != "" and ResourceLoader.exists(path) else null

## Icono con su número (nivel o copias). Sin dibujo: medallón del color con la inicial del nombre.
func _cell(tex: Texture2D, badge: String, tip: String, color: Color, label: String) -> Control:
	var box := Control.new()
	box.custom_minimum_size = Vector2(CELL + 8, CELL + 4)     # hueco a la derecha para el número
	box.tooltip_text = tip
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	# Bolsillo opaco de cuero oscuro detrás del icono (los iconos tienen fondo transparente)
	var pocket := Panel.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.19, 0.11, 0.06)
	ps.border_color = Color(0.1, 0.055, 0.03)
	ps.set_border_width_all(2)
	ps.set_corner_radius_all(8)
	ps.anti_aliasing = true
	pocket.add_theme_stylebox_override("panel", ps)
	pocket.size = Vector2(CELL, CELL)
	pocket.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(pocket)
	if tex != null:
		var r := TextureRect.new()
		r.texture = tex
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		r.size = Vector2(CELL, CELL)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(r)
	else:
		var p := Panel.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = color.darkened(0.25)
		sb.border_color = Color(0.1, 0.06, 0.03)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(CELL / 2)
		p.add_theme_stylebox_override("panel", sb)
		p.size = Vector2(CELL, CELL)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var l := Label.new()
		l.text = label.substr(0, 1).to_upper()
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.size = Vector2(CELL, CELL)
		l.add_theme_font_size_override("font_size", 16)
		l.add_theme_color_override("font_color", Color(1, 1, 1))
		l.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.03))
		l.add_theme_constant_override("outline_size", 4)
		p.add_child(l)
		box.add_child(p)
	if badge != "":
		var b := Label.new()
		b.text = badge
		b.position = Vector2(CELL - 8, CELL - 14)
		b.add_theme_font_size_override("font_size", 11)
		b.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45))
		b.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.02))
		b.add_theme_constant_override("outline_size", 4)
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(b)
	return box
