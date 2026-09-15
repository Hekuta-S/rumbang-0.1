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

var weapons = [
	{"id": "flame_axe", "name": "Hacha de Fuego"},
	{"id": "air_fists", "name": "Puños de Aire"},
	{"id": "dual_daggers", "name": "Dagas Gemelas"},
	{"id": "flame_thrower", "name": "Lanzallamas"},
	{"id": "radiation_zone", "name": "Zona de Radiación"},
	{"id": "serpent_projectile", "name": "Serpientes de Joel"},
	{"id": "spear_projectile", "name": "Espalanza"},
	{"id": "spinning_axe_projectile", "name": "Hacha Giratoria"},
	{"id": "spore_cloud", "name": "Bazuca de Esporas"}
]

var center_container: CenterContainer
var upgrades_panel: ColorRect
var lbl_gold: Label
var upgrades_container: VBoxContainer

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_ui()

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

	center_container = CenterContainer.new()
	center_container.set_anchors_preset(PRESET_FULL_RECT)
	add_child(center_container)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(380, 0)
	vbox.add_theme_constant_override("separation", 14)
	center_container.add_child(vbox)

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

	var sep := HSeparator.new()
	sep.custom_minimum_size = Vector2(0, 1)
	var sep_style := StyleBoxFlat.new()
	sep_style.bg_color = Color(C_ACCENT, 0.3)
	sep.add_theme_stylebox_override("separator", sep_style)
	vbox.add_child(sep)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 28)
	vbox.add_child(spacer)

	var btn_play := _make_button("  JUGAR", C_ACCENT)
	btn_play.pressed.connect(_on_play)
	vbox.add_child(btn_play)

	var btn_upgrades := _make_button("  MEJORAS", C_BTN_BORDER)
	btn_upgrades.pressed.connect(_on_upgrades_menu)
	vbox.add_child(btn_upgrades)
	
	var btn_opts := _make_button("  OPCIONES", C_BTN_BORDER)
	btn_opts.pressed.connect(_on_options_menu)
	vbox.add_child(btn_opts)

	var btn_quit := _make_button("  SALIR", C_BTN_BORDER)
	btn_quit.pressed.connect(_on_quit)
	vbox.add_child(btn_quit)

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
	
	_build_upgrades_panel()

func _build_upgrades_panel() -> void:
	upgrades_panel = ColorRect.new()
	upgrades_panel.set_anchors_preset(PRESET_FULL_RECT)
	upgrades_panel.color = Color(C_BG, 0.95)
	upgrades_panel.hide()
	add_child(upgrades_panel)
	
	var margin := MarginContainer.new()
	margin.set_anchors_preset(PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 60)
	margin.add_theme_constant_override("margin_right", 60)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 40)
	upgrades_panel.add_child(margin)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	margin.add_child(vbox)
	
	var header := HBoxContainer.new()
	vbox.add_child(header)
	
	var title := Label.new()
	title.text = "MEJORAS DE ARMAS"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", C_TITLE)
	header.add_child(title)
	
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	
	lbl_gold = Label.new()
	lbl_gold.add_theme_font_size_override("font_size", 24)
	lbl_gold.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	header.add_child(lbl_gold)
	
	var btn_back := _make_button("VOLVER", C_BTN_BORDER)
	btn_back.custom_minimum_size = Vector2(150, 40)
	btn_back.pressed.connect(func():
		upgrades_panel.hide()
		center_container.show()
	)
	header.add_child(btn_back)
	
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	
	upgrades_container = VBoxContainer.new()
	upgrades_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	upgrades_container.add_theme_constant_override("separation", 10)
	scroll.add_child(upgrades_container)

func _refresh_upgrades() -> void:
	lbl_gold.text = "Oro: " + str(SaveManager.get_total_gold())
	
	for child in upgrades_container.get_children():
		child.queue_free()
		
	for w in weapons:
		var panel = PanelContainer.new()
		var style = StyleBoxFlat.new()
		style.bg_color = C_BTN_BG
		style.border_width_bottom = 2
		style.border_color = C_BTN_BORDER
		style.content_margin_left = 15
		style.content_margin_right = 15
		style.content_margin_top = 10
		style.content_margin_bottom = 10
		panel.add_theme_stylebox_override("panel", style)
		upgrades_container.add_child(panel)
		
		var hbox = HBoxContainer.new()
		panel.add_child(hbox)
		
		var name_lbl = Label.new()
		name_lbl.text = w["name"]
		name_lbl.custom_minimum_size = Vector2(250, 0)
		name_lbl.add_theme_font_size_override("font_size", 18)
		hbox.add_child(name_lbl)
		
		var spacer = Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(spacer)
		
		var lvl = SaveManager.get_upgrade(w["id"])
		
		# Draw 5 blocks
		for i in range(5):
			var block = ColorRect.new()
			block.custom_minimum_size = Vector2(20, 20)
			block.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			if i < lvl:
				block.color = C_ACCENT
			else:
				block.color = C_BTN_BORDER
			hbox.add_child(block)
			
		var spacer2 = Control.new()
		spacer2.custom_minimum_size = Vector2(20, 0)
		hbox.add_child(spacer2)
			
		var cost = 500
		var btn_buy = _make_button("+" if lvl < 5 else "MAX", C_ACCENT if lvl < 5 else C_BTN_BORDER)
		btn_buy.custom_minimum_size = Vector2(100, 40)
		if lvl >= 5:
			btn_buy.disabled = true
		else:
			btn_buy.text = str(cost) + "G"
			btn_buy.pressed.connect(func():
				if SaveManager.buy_upgrade(w["id"], cost):
					_refresh_upgrades()
			)
		hbox.add_child(btn_buy)

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
	SceneLoader.load_scene("res://scenes/ui/character_select.tscn")

func _on_upgrades_menu() -> void:
	center_container.hide()
	upgrades_panel.show()
	_refresh_upgrades()

func _on_quit() -> void:
	get_tree().quit()

func _on_options_menu() -> void:
	var SettingsMenu = load("res://scripts/ui/settings_menu.gd")
	var sm = SettingsMenu.new()
	add_child(sm)
