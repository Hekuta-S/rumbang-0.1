## character_select.gd — Character Selection Screen
extends Control

const C_BG          := Color(0.055, 0.072, 0.11)
const C_ACCENT       := Color(0.15, 0.62, 0.92)
const C_PANEL        := Color(0.08, 0.11, 0.18, 0.97)
const C_TEXT         := Color(0.88, 0.90, 0.94)
const C_TEXT_DIM     := Color(0.45, 0.52, 0.62)
const C_BTN_BG       := Color(0.10, 0.14, 0.22)
const C_BTN_BORDER   := Color(0.18, 0.26, 0.40)
const C_BTN_HOVER    := Color(0.12, 0.20, 0.34)
const C_BTN_PRESS    := Color(0.08, 0.42, 0.68)

var _current_index: int = 0

# UI references updated on card refresh
var _lbl_name:          Label
var _lbl_subtitle:      Label
var _lbl_lore:          Label
var _lbl_passive_name:  Label
var _lbl_passive_desc:  Label
var _lbl_stats:         Label
var _portrait_rect:     ColorRect
var _portrait_label:    Label
var _passive_dot:       ColorRect

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_current_index = GameData.selected_index
	_build_ui()
	_refresh_card()

func _build_ui() -> void:
	# ── Background ─────────────────────────────────────────────────────────
	var bg := ColorRect.new()
	bg.set_anchors_preset(PRESET_FULL_RECT)
	bg.color = C_BG
	add_child(bg)

	var accent_bar := ColorRect.new()
	accent_bar.set_anchors_preset(PRESET_TOP_WIDE)
	accent_bar.custom_minimum_size = Vector2(0, 3)
	accent_bar.color = C_ACCENT
	add_child(accent_bar)

	# ── Root margin container ──────────────────────────────────────────────
	var margin := MarginContainer.new()
	margin.set_anchors_preset(PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left",   60)
	margin.add_theme_constant_override("margin_right",  60)
	margin.add_theme_constant_override("margin_top",    40)
	margin.add_theme_constant_override("margin_bottom", 40)
	add_child(margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 24)
	margin.add_child(root_vbox)

	# ── Header ─────────────────────────────────────────────────────────────
	var lbl_title := Label.new()
	lbl_title.text = "SELECCIONAR PERSONAJE"
	lbl_title.add_theme_font_size_override("font_size", 28)
	lbl_title.add_theme_color_override("font_color", C_TEXT)
	root_vbox.add_child(lbl_title)

	var sep := HSeparator.new()
	var sep_style := StyleBoxFlat.new()
	sep_style.bg_color = Color(C_ACCENT, 0.3)
	sep.add_theme_stylebox_override("separator", sep_style)
	root_vbox.add_child(sep)

	# ── Card row: arrow ← | card | arrow → ────────────────────────────────
	var card_row := HBoxContainer.new()
	card_row.alignment = BoxContainer.ALIGNMENT_CENTER
	card_row.add_theme_constant_override("separation", 20)
	card_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(card_row)

	var btn_prev := _make_nav_button("◀")
	btn_prev.pressed.connect(_on_prev)
	card_row.add_child(btn_prev)

	# ── Character card panel ───────────────────────────────────────────────
	var card_panel := Panel.new()
	card_panel.custom_minimum_size = Vector2(620, 400)
	card_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = C_PANEL
	card_style.set_border_width_all(1)
	card_style.border_color = Color(C_ACCENT, 0.35)
	card_style.set_corner_radius_all(10)
	card_panel.add_theme_stylebox_override("panel", card_style)
	card_row.add_child(card_panel)

	var card_margin := MarginContainer.new()
	card_margin.set_anchors_preset(PRESET_FULL_RECT)
	card_margin.add_theme_constant_override("margin_left",   28)
	card_margin.add_theme_constant_override("margin_right",  28)
	card_margin.add_theme_constant_override("margin_top",    24)
	card_margin.add_theme_constant_override("margin_bottom", 24)
	card_panel.add_child(card_margin)

	var card_hbox := HBoxContainer.new()
	card_hbox.add_theme_constant_override("separation", 28)
	card_margin.add_child(card_hbox)

	# Left column: portrait + name
	var left_col := VBoxContainer.new()
	left_col.custom_minimum_size = Vector2(180, 0)
	left_col.add_theme_constant_override("separation", 12)
	card_hbox.add_child(left_col)

	# Portrait placeholder
	var portrait_bg := Panel.new()
	portrait_bg.custom_minimum_size = Vector2(180, 180)
	var port_style := StyleBoxFlat.new()
	port_style.bg_color = Color(0.1, 0.15, 0.22)
	port_style.set_border_width_all(2)
	port_style.border_color = Color(C_ACCENT, 0.5)
	port_style.set_corner_radius_all(8)
	portrait_bg.add_theme_stylebox_override("panel", port_style)
	left_col.add_child(portrait_bg)

	_portrait_rect = ColorRect.new()
	_portrait_rect.set_anchors_preset(PRESET_FULL_RECT)
	_portrait_rect.add_theme_constant_override("margin_all", 0)
	_portrait_rect.color = Color(0.2, 0.55, 1.0, 0.18)
	portrait_bg.add_child(_portrait_rect)

	_portrait_label = Label.new()
	_portrait_label.set_anchors_preset(PRESET_CENTER)
	_portrait_label.text = "M"
	_portrait_label.add_theme_font_size_override("font_size", 72)
	_portrait_label.add_theme_color_override("font_color", Color.WHITE)
	_portrait_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_portrait_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	portrait_bg.add_child(_portrait_label)

	_lbl_name = Label.new()
	_lbl_name.text = "Mikeura"
	_lbl_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_name.add_theme_font_size_override("font_size", 22)
	_lbl_name.add_theme_color_override("font_color", C_TEXT)
	left_col.add_child(_lbl_name)

	_lbl_subtitle = Label.new()
	_lbl_subtitle.text = "Guerrero del Escudo"
	_lbl_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_subtitle.add_theme_font_size_override("font_size", 13)
	_lbl_subtitle.add_theme_color_override("font_color", C_ACCENT)
	left_col.add_child(_lbl_subtitle)

	# Stats block
	var stats_spacer := Control.new()
	stats_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_col.add_child(stats_spacer)

	_lbl_stats = Label.new()
	_lbl_stats.add_theme_font_size_override("font_size", 13)
	_lbl_stats.add_theme_color_override("font_color", C_TEXT_DIM)
	left_col.add_child(_lbl_stats)

	# Right column: lore + passive
	var right_col := VBoxContainer.new()
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.add_theme_constant_override("separation", 14)
	card_hbox.add_child(right_col)

	_lbl_lore = Label.new()
	_lbl_lore.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_lore.add_theme_font_size_override("font_size", 14)
	_lbl_lore.add_theme_color_override("font_color", C_TEXT_DIM)
	right_col.add_child(_lbl_lore)

	var vsep := HSeparator.new()
	var vsep_style := StyleBoxFlat.new()
	vsep_style.bg_color = Color(C_ACCENT, 0.2)
	vsep.add_theme_stylebox_override("separator", vsep_style)
	right_col.add_child(vsep)

	# Passive section header
	var passive_header := HBoxContainer.new()
	passive_header.add_theme_constant_override("separation", 8)
	right_col.add_child(passive_header)

	_passive_dot = ColorRect.new()
	_passive_dot.custom_minimum_size = Vector2(10, 10)
	_passive_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	passive_header.add_child(_passive_dot)

	var lbl_passive_hdr := Label.new()
	lbl_passive_hdr.text = "PASIVA"
	lbl_passive_hdr.add_theme_font_size_override("font_size", 12)
	lbl_passive_hdr.add_theme_color_override("font_color", C_TEXT_DIM)
	passive_header.add_child(lbl_passive_hdr)

	_lbl_passive_name = Label.new()
	_lbl_passive_name.add_theme_font_size_override("font_size", 17)
	_lbl_passive_name.add_theme_color_override("font_color", C_TEXT)
	right_col.add_child(_lbl_passive_name)

	_lbl_passive_desc = Label.new()
	_lbl_passive_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_passive_desc.add_theme_font_size_override("font_size", 13)
	_lbl_passive_desc.add_theme_color_override("font_color", C_TEXT_DIM)
	right_col.add_child(_lbl_passive_desc)

	var expand_fill := Control.new()
	expand_fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_col.add_child(expand_fill)

	# Character counter label (e.g. "1 / 1")
	var lbl_counter := Label.new()
	lbl_counter.name = "CounterLabel"
	lbl_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl_counter.add_theme_font_size_override("font_size", 13)
	lbl_counter.add_theme_color_override("font_color", C_TEXT_DIM)
	right_col.add_child(lbl_counter)

	var btn_next := _make_nav_button("▶")
	btn_next.pressed.connect(_on_next)
	card_row.add_child(btn_next)

	# ── Bottom button row ──────────────────────────────────────────────────
	var bottom_row := HBoxContainer.new()
	bottom_row.add_theme_constant_override("separation", 16)
	root_vbox.add_child(bottom_row)

	var btn_back := _make_button("← ATRÁS", C_BTN_BORDER)
	btn_back.pressed.connect(_on_back)
	bottom_row.add_child(btn_back)

	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_row.add_child(fill)

	var btn_select := _make_button("SELECCIONAR  →", C_ACCENT)
	btn_select.pressed.connect(_on_select)
	bottom_row.add_child(btn_select)

# ── Card refresh ────────────────────────────────────────────────────────────
func _refresh_card() -> void:
	var chars: Array = GameData.CHARACTERS
	if chars.is_empty(): return
	var c: Dictionary = chars[_current_index]
	var stats: Dictionary = c.get("stats", {})

	_lbl_name.text         = c.get("name", "")
	_lbl_subtitle.text     = c.get("subtitle", "")
	_lbl_lore.text         = c.get("lore", "")
	_lbl_passive_name.text = c.get("passive_name", "")
	_lbl_passive_desc.text = c.get("passive_desc", "")

	var char_color: Color = c.get("color", C_ACCENT)
	_portrait_rect.color   = Color(char_color, 0.18)
	_portrait_label.text   = c.get("portrait_label", "?")
	_portrait_label.add_theme_color_override("font_color", char_color)
	_passive_dot.color     = c.get("passive_color", C_ACCENT)

	_lbl_stats.text = "HP:       %s\nEscudo:   %s\nEnergía:  %s\nVelocidad: %s" % [
		stats.get("max_hp",     "—"),
		stats.get("max_shield", "—"),
		stats.get("max_energy", "—"),
		stats.get("move_speed", "—"),
	]

	# Update counter
	var counter := find_child("CounterLabel") as Label
	if counter:
		counter.text = "%d / %d" % [_current_index + 1, chars.size()]

# ── Navigation ──────────────────────────────────────────────────────────────
func _on_prev() -> void:
	_current_index = (_current_index - 1 + GameData.CHARACTERS.size()) % GameData.CHARACTERS.size()
	_refresh_card()

func _on_next() -> void:
	_current_index = (_current_index + 1) % GameData.CHARACTERS.size()
	_refresh_card()

func _on_select() -> void:
	GameData.selected_index = _current_index
	SceneLoader.load_scene("res://scenes/core/main.tscn")
	#get_tree().change_scene_to_file("res://scenes/core/main.tscn")

func _on_back() -> void:
	SceneLoader.load_scene("res://scenes/ui/main_menu.tscn")
	#get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")

# ── Helpers ─────────────────────────────────────────────────────────────────
func _make_nav_button(txt: String) -> Button:
	var btn := Button.new()
	btn.text = txt
	btn.custom_minimum_size = Vector2(52, 52)
	btn.add_theme_font_size_override("font_size", 20)
	btn.add_theme_color_override("font_color", C_TEXT_DIM)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_stylebox_override("normal",  _btn_style(C_BTN_BG,   C_BTN_BORDER, 8))
	btn.add_theme_stylebox_override("hover",   _btn_style(C_BTN_HOVER, C_ACCENT,    8))
	btn.add_theme_stylebox_override("pressed", _btn_style(C_BTN_PRESS, C_ACCENT,    8))
	btn.add_theme_stylebox_override("focus",   _btn_style(C_BTN_BG,   C_ACCENT,     8))
	return btn

func _make_button(txt: String, border_col: Color) -> Button:
	var btn := Button.new()
	btn.text = txt
	btn.custom_minimum_size = Vector2(200, 50)
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", C_TEXT)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)
	btn.add_theme_stylebox_override("normal",  _btn_style(C_BTN_BG,    border_col, 6))
	btn.add_theme_stylebox_override("hover",   _btn_style(C_BTN_HOVER, C_ACCENT,   6))
	btn.add_theme_stylebox_override("pressed", _btn_style(C_BTN_PRESS, C_ACCENT,   6))
	btn.add_theme_stylebox_override("focus",   _btn_style(C_BTN_BG,    C_ACCENT,   6))
	return btn

func _btn_style(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_border_width_all(2)
	s.border_color = border
	s.set_corner_radius_all(radius)
	s.content_margin_left   = 14
	s.content_margin_right  = 14
	s.content_margin_top    = 10
	s.content_margin_bottom = 10
	return s
