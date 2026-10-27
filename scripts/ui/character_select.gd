## character_select.gd — Selección de personaje (cuadrícula + panel de detalle)
extends Control

const Style := preload("res://scripts/ui/rumbang_style.gd")

# Paleta compartida (ver RumbangStyle)
const C_BG          := Style.BG
const C_ACCENT      := Style.ACCENT
const C_PANEL       := Style.PANEL
const C_TEXT        := Style.TEXT
const C_TEXT_DIM    := Style.TEXT_DIM
const C_BTN_BG      := Style.BTN_BG
const C_BTN_BORDER  := Style.BTN_BORDER
const C_BTN_HOVER   := Style.BTN_HOVER
const C_BTN_PRESS   := Style.BTN_PRESS

const PIXEL_FONT := Style.FONT
const GRID_COLUMNS := 4
const CELL_SIZE := Vector2(118, 118)

var _selected_index: int = 0
var _cells: Array[Button] = []

# Referencias del panel de detalle
var _preview: CharacterPreview
var _preview_bg: PanelContainer
var _lbl_name: Label
var _lbl_subtitle: Label
var _lbl_passive_name: Label
var _lbl_passive_desc: Label
var _lbl_weapon_name: Label
var _lbl_weapon_kind: Label
var _lbl_stats: Label
var _btn_start: Button

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	theme = Style.get_theme()
	_selected_index = clampi(GameData.selected_index, 0, GameData.CHARACTERS.size() - 1)
	_build_ui()
	CharacterPreview.preload_all(String(GameData.CHARACTERS[_selected_index].get("id", "")))
	_refresh_detail()
	_refresh_cells()
	if _cells.size() > _selected_index:
		_cells[_selected_index].grab_focus()

func _exit_tree() -> void:
	CharacterPreview.clear_cache()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back()
		get_viewport().set_input_as_handled()

# ───────────────────────────── Construcción de la UI ─────────────────────────────

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(PRESET_FULL_RECT)
	bg.color = C_BG
	add_child(bg)

	var accent_bar := ColorRect.new()
	accent_bar.set_anchors_preset(PRESET_TOP_WIDE)
	accent_bar.custom_minimum_size = Vector2(0, 3)
	accent_bar.color = C_ACCENT
	add_child(accent_bar)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_bottom", 32)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 20)
	margin.add_child(root)

	# Cabecera
	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.text = "ELIGE TU PERSONAJE"
	title.add_theme_font_override("font", PIXEL_FONT)
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", C_ACCENT)
	header.add_child(title)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(fill)
	var btn_back := _make_button("← ATRÁS", C_BTN_BORDER)
	btn_back.custom_minimum_size = Vector2(160, 42)
	btn_back.pressed.connect(_on_back)
	header.add_child(btn_back)

	# Cuerpo: cuadrícula | detalle
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 28)
	root.add_child(body)

	body.add_child(_build_grid())
	body.add_child(_build_detail_panel())

func _build_grid() -> Control:
	var holder := VBoxContainer.new()
	holder.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN   # ancho fijo; el detalle ocupa el resto

	var grid := GridContainer.new()
	grid.columns = GRID_COLUMNS
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	holder.add_child(grid)

	for i in range(GameData.CHARACTERS.size()):
		var cell := _make_cell(i)
		grid.add_child(cell)
		_cells.append(cell)
	return holder

func _make_cell(index: int) -> Button:
	var c: Dictionary = GameData.CHARACTERS[index]
	var col: Color = c.get("color", C_ACCENT)

	var btn := Button.new()
	btn.custom_minimum_size = CELL_SIZE
	btn.focus_mode = Control.FOCUS_ALL
	btn.tooltip_text = "%s — %s" % [c.get("name", ""), c.get("subtitle", "")]
	btn.set_meta("color", col)
	btn.add_theme_stylebox_override("normal", _cell_style(Color(col, 0.10), Color(col, 0.45), 2))
	btn.add_theme_stylebox_override("hover", _cell_style(Color(col, 0.22), col, 2))
	btn.add_theme_stylebox_override("pressed", _cell_style(Color(col, 0.32), col, 3))
	btn.add_theme_stylebox_override("focus", _cell_style(Color(col, 0.18), C_TEXT, 3))

	var vb := VBoxContainer.new()
	vb.set_anchors_preset(PRESET_FULL_RECT)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 6)
	btn.add_child(vb)

	var initial := Label.new()
	initial.text = c.get("portrait_label", "?")
	initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initial.add_theme_font_override("font", PIXEL_FONT)
	initial.add_theme_font_size_override("font_size", 34)
	initial.add_theme_color_override("font_color", col)
	initial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(initial)

	var nm := Label.new()
	nm.text = c.get("name", "")
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.add_theme_font_size_override("font_size", 13)
	nm.add_theme_color_override("font_color", C_TEXT)
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(nm)

	btn.pressed.connect(_select.bind(index))
	btn.focus_entered.connect(_select.bind(index))
	btn.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.double_click and ev.button_index == MOUSE_BUTTON_LEFT:
			_select(index)
			_on_start()
	)
	return btn

func _build_detail_panel() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(430, 0)
	var ps := StyleBoxFlat.new()
	ps.bg_color = C_PANEL
	ps.set_border_width_all(2)
	ps.border_color = C_BTN_BORDER
	ps.set_corner_radius_all(6)
	ps.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", ps)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)

	# Zona de preview (paso 4: aquí irá el modelo 3D)
	_preview_bg = PanelContainer.new()
	_preview_bg.custom_minimum_size = Vector2(0, 250)
	_preview_bg.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(_preview_bg)
	_preview = CharacterPreview.new()
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.tooltip_text = "Arrastra para girar al personaje"
	_preview_bg.add_child(_preview)

	_lbl_name = Label.new()
	_lbl_name.add_theme_font_override("font", PIXEL_FONT)
	_lbl_name.add_theme_font_size_override("font_size", 24)
	_lbl_name.add_theme_color_override("font_color", C_TEXT)
	vb.add_child(_lbl_name)

	_lbl_subtitle = Label.new()
	_lbl_subtitle.add_theme_font_size_override("font_size", 14)
	_lbl_subtitle.add_theme_color_override("font_color", C_TEXT_DIM)
	vb.add_child(_lbl_subtitle)

	vb.add_child(_section_header("PASIVA"))
	_lbl_passive_name = Label.new()
	_lbl_passive_name.add_theme_font_size_override("font_size", 17)
	vb.add_child(_lbl_passive_name)
	_lbl_passive_desc = Label.new()
	_lbl_passive_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_passive_desc.custom_minimum_size = Vector2(0, 62)
	_lbl_passive_desc.add_theme_font_size_override("font_size", 13)
	_lbl_passive_desc.add_theme_color_override("font_color", C_TEXT_DIM)
	vb.add_child(_lbl_passive_desc)

	vb.add_child(_section_header("ARMA PRINCIPAL"))
	var wrow := HBoxContainer.new()
	wrow.add_theme_constant_override("separation", 12)
	vb.add_child(wrow)
	_lbl_weapon_name = Label.new()
	_lbl_weapon_name.add_theme_font_size_override("font_size", 17)
	_lbl_weapon_name.add_theme_color_override("font_color", C_ACCENT)
	wrow.add_child(_lbl_weapon_name)
	_lbl_weapon_kind = Label.new()
	_lbl_weapon_kind.add_theme_font_size_override("font_size", 13)
	_lbl_weapon_kind.add_theme_color_override("font_color", C_TEXT_DIM)
	wrow.add_child(_lbl_weapon_kind)

	_lbl_stats = Label.new()
	_lbl_stats.add_theme_font_size_override("font_size", 13)
	_lbl_stats.add_theme_color_override("font_color", C_TEXT_DIM)
	vb.add_child(_lbl_stats)

	_btn_start = _make_button("COMENZAR PARTIDA", C_ACCENT)
	_btn_start.custom_minimum_size = Vector2(0, 56)
	_btn_start.pressed.connect(_on_start)
	vb.add_child(_btn_start)
	return panel

func _section_header(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", PIXEL_FONT)
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", C_TEXT_DIM)
	return l

# ───────────────────────────── Estado ─────────────────────────────

func _select(index: int) -> void:
	if index == _selected_index and _lbl_name and _lbl_name.text != "":
		return
	_selected_index = index
	_refresh_detail()
	_refresh_cells()

func _refresh_cells() -> void:
	for i in range(_cells.size()):
		var col: Color = _cells[i].get_meta("color")
		var selected := i == _selected_index
		_cells[i].add_theme_stylebox_override("normal",
			_cell_style(Color(col, 0.30 if selected else 0.10), C_ACCENT if selected else Color(col, 0.45), 4 if selected else 2))

func _main_weapon_type(c: Dictionary) -> int:
	var list: Array = c.get("initial_weapons", [WeaponData.WeaponType.SPEAR_LANCE])
	return int(list[0]) if not list.is_empty() else WeaponData.WeaponType.SPEAR_LANCE

func _refresh_detail() -> void:
	var c: Dictionary = GameData.CHARACTERS[_selected_index]
	var col: Color = c.get("color", C_ACCENT)
	var stats: Dictionary = c.get("stats", {})

	_preview.show_character(String(c.get("id", "")), col)
	var pb := StyleBoxFlat.new()
	pb.bg_color = Color(col, 0.10)
	pb.set_border_width_all(2)
	pb.border_color = Color(col, 0.5)
	pb.set_corner_radius_all(6)
	_preview_bg.add_theme_stylebox_override("panel", pb)

	_lbl_name.text = String(c.get("name", "")).to_upper()
	_lbl_name.add_theme_color_override("font_color", col.lerp(Color.WHITE, 0.35))
	_lbl_subtitle.text = c.get("subtitle", "")

	_lbl_passive_name.text = c.get("passive_name", "Sin pasiva")
	_lbl_passive_name.add_theme_color_override("font_color", c.get("passive_color", C_TEXT))
	var pdesc: String = c.get("passive_desc", "")
	_lbl_passive_desc.text = pdesc if pdesc != "" else "Este héroe no tiene habilidad pasiva."

	var w := _main_weapon_type(c)
	_lbl_weapon_name.text = String(WeaponData.weapon_names.get(w, "Arma"))
	var kind: String = WeaponData.get_weapon_data(w).category
	_lbl_weapon_kind.text = {"melee": "Cuerpo a cuerpo", "ranged": "A distancia", "special": "Especial"}.get(kind, kind)

	_lbl_stats.text = "Vida %s    Escudo %s    Velocidad %s" % [
		_fmt(float(stats.get("max_hp", 0.0)) + GameData.BASE_HP_BONUS), _fmt(stats.get("max_shield")),
		_fmt(stats.get("move_speed"))]

func _fmt(v) -> String:
	return "—" if v == null else str(int(v)) if float(v) == floorf(float(v)) else str(v)

# ───────────────────────────── Acciones ─────────────────────────────

func _on_start() -> void:
	GameData.selected_index = _selected_index
	var scene := "res://scenes/core/main_dungeon.tscn" if GameData.game_mode == "dungeon" else "res://scenes/core/main_procedural.tscn"
	SceneLoader.load_scene(scene)

func _on_back() -> void:
	SceneLoader.load_scene("res://scenes/ui/main_menu.tscn")

# ───────────────────────────── Estilos ─────────────────────────────

func _make_button(txt: String, border_col: Color) -> Button:
	return Style.make_button(txt, border_col, Vector2(240, 50))

func _btn_style(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	return Style.button_style(bg, border, radius)

func _cell_style(bg: Color, border: Color, width: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_border_width_all(width)
	s.border_color = border
	s.set_corner_radius_all(6)
	return s
