## main_menu.gd — Main Menu Scene Script
extends Control

const C_BG        := Color(0.055, 0.072, 0.11)
const C_ACCENT     := Color(0.15, 0.62, 0.92)
const C_TITLE      := Color(0.15, 0.70, 1.00)
const C_TEXT       := Color(0.88, 0.90, 0.94)
const C_TEXT_DIM   := Color(0.45, 0.52, 0.62)
const C_BTN_BG     := Color(0.10, 0.14, 0.22)
const C_BTN_BORDER := Color(0.18, 0.26, 0.40)
const C_BTN_HOVER  := Color(0.12, 0.20, 0.34)
const C_BTN_PRESS  := Color(0.08, 0.42, 0.68)

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_ui()

func _build_ui() -> void:
	# ── Background ──────────────────────────────────────────────────────────
	var bg := ColorRect.new()
	bg.set_anchors_preset(PRESET_FULL_RECT)
	bg.color = C_BG
	add_child(bg)

	# Subtle top accent bar
	var accent_bar := ColorRect.new()
	accent_bar.set_anchors_preset(PRESET_TOP_WIDE)
	accent_bar.custom_minimum_size = Vector2(0, 3)
	accent_bar.color = C_ACCENT
	add_child(accent_bar)

	# ── Center layout ────────────────────────────────────────────────────────
	var center := CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(380, 0)
	vbox.add_theme_constant_override("separation", 14)
	center.add_child(vbox)

	# Title
	var lbl_title := Label.new()
	lbl_title.text = "SOUL KNIGHT 3D"
	lbl_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_title.add_theme_font_size_override("font_size", 50)
	lbl_title.add_theme_color_override("font_color", C_TITLE)
	vbox.add_child(lbl_title)

	var lbl_sub := Label.new()
	lbl_sub.text = "Third Person Roguelike"
	lbl_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_sub.add_theme_font_size_override("font_size", 15)
	lbl_sub.add_theme_color_override("font_color", C_TEXT_DIM)
	vbox.add_child(lbl_sub)

	# Separator
	var sep := HSeparator.new()
	sep.custom_minimum_size = Vector2(0, 1)
	var sep_style := StyleBoxFlat.new()
	sep_style.bg_color = Color(C_ACCENT, 0.3)
	sep.add_theme_stylebox_override("separator", sep_style)
	vbox.add_child(sep)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 28)
	vbox.add_child(spacer)

	# ── Buttons ───────────────────────────────────────────────────────────────
	var btn_play := _make_button("  JUGAR", C_ACCENT)
	btn_play.pressed.connect(_on_play)
	vbox.add_child(btn_play)

	var btn_opts := _make_button("  OPCIONES", C_BTN_BORDER)
	btn_opts.disabled = true
	btn_opts.modulate.a = 0.45
	vbox.add_child(btn_opts)

	var btn_quit := _make_button("  SALIR", C_BTN_BORDER)
	btn_quit.pressed.connect(_on_quit)
	vbox.add_child(btn_quit)

	var btn_test := _make_button("  MAPA DE PRUEBA (RIVA)", C_BTN_BORDER)
	btn_test.pressed.connect(_on_test_map)
	vbox.add_child(btn_test)

	# ── Version label (bottom-right) ─────────────────────────────────────────
	var lbl_ver := Label.new()
	lbl_ver.text = "v0.1 - Alpha"
	lbl_ver.set_anchors_preset(PRESET_BOTTOM_RIGHT)
	lbl_ver.offset_left  = -120
	lbl_ver.offset_top   = -36
	lbl_ver.offset_right = -16
	lbl_ver.offset_bottom = -12
	lbl_ver.add_theme_font_size_override("font_size", 12)
	lbl_ver.add_theme_color_override("font_color", C_TEXT_DIM)
	add_child(lbl_ver)

func _make_button(txt: String, border_col: Color) -> Button:
	var btn := Button.new()
	btn.text = txt
	btn.custom_minimum_size = Vector2(320, 54)
	btn.add_theme_font_size_override("font_size", 17)
	btn.add_theme_color_override("font_color", C_TEXT)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)
	btn.add_theme_color_override("font_disabled_color", C_TEXT_DIM)

	btn.add_theme_stylebox_override("normal",  _btn_style(C_BTN_BG,    border_col,       5))
	btn.add_theme_stylebox_override("hover",   _btn_style(C_BTN_HOVER, C_ACCENT,         5))
	btn.add_theme_stylebox_override("pressed", _btn_style(C_BTN_PRESS, C_ACCENT,         5))
	btn.add_theme_stylebox_override("disabled",_btn_style(C_BTN_BG,    C_BTN_BORDER,     5))
	btn.add_theme_stylebox_override("focus",   _btn_style(C_BTN_BG,    C_ACCENT,         5))
	return btn

func _btn_style(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_border_width_all(2)
	s.border_color = border
	s.set_corner_radius_all(radius)
	s.content_margin_left   = 16
	s.content_margin_right  = 16
	s.content_margin_top    = 10
	s.content_margin_bottom = 10
	return s

func _on_play() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/character_select.tscn")

func _on_quit() -> void:
	get_tree().quit()

func _on_test_map() -> void:
	get_tree().change_scene_to_file("res://scenes/world.tscn")
