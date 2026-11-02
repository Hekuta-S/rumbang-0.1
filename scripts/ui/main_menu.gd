extends Control

const Style := preload("res://scripts/ui/rumbang_style.gd")

# Paleta compartida (ver RumbangStyle)
const C_BG         := Style.BG
const C_ACCENT     := Style.ACCENT
const C_TITLE      := Style.TITLE
const C_TITLE_GLOW := Style.GLOW
const C_TEXT       := Style.TEXT
const C_TEXT_DIM   := Style.TEXT_DIM
const C_BTN_BG     := Style.BTN_BG
const C_BTN_BORDER := Style.BTN_BORDER
const C_BTN_HOVER  := Style.BTN_HOVER
const C_BTN_PRESS  := Style.BTN_PRESS

const TITLE_FONT := Style.FONT
const GAME_TITLE := "RUMBANG"

var weapons = [
	{"id": "flame_thrower", "name": "Lanzallamas"},
	{"id": "radiation_zone", "name": "Zona de Radiación"},
	{"id": "serpent_projectile", "name": "Espíritus de Joel"},
	{"id": "spear_projectile", "name": "Espalanza"},
	{"id": "spinning_axe_projectile", "name": "Hacha Giratoria"},
	{"id": "spore_cloud", "name": "Bazuca de Esporas"}
]

var _bg_container: SubViewportContainer
var center_container: Control         ## columna izquierda (título y botones)
var _play_menu: PanelContainer         ## mini menú de JUGAR: mazmorra, supervivencia, multijugador
var _play_tween: Tween
var upgrades_panel: ColorRect
var lbl_gold: Label
var upgrades_container: VBoxContainer

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	theme = Style.get_theme()
	_build_ui()

func _build_ui() -> void:
	_build_background()

	var accent_bar := ColorRect.new()
	accent_bar.set_anchors_preset(PRESET_TOP_WIDE)
	accent_bar.custom_minimum_size = Vector2(0, 3)
	accent_bar.color = C_ACCENT
	add_child(accent_bar)

	# Degradado oscuro a la izquierda para que la columna del menú se lea sobre el paisaje
	var shade_grad := Gradient.new()
	shade_grad.set_color(0, Color(0.02, 0.01, 0.05, 0.85))
	shade_grad.set_color(1, Color(0.02, 0.01, 0.05, 0.0))
	var shade_tex := GradientTexture2D.new()
	shade_tex.gradient = shade_grad
	shade_tex.fill_from = Vector2(0.0, 0.5)
	shade_tex.fill_to = Vector2(1.0, 0.5)
	var shade := TextureRect.new()
	shade.texture = shade_tex
	shade.set_anchors_preset(PRESET_LEFT_WIDE)
	shade.offset_right = 720
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	# Columna del menú a la izquierda, centrada en vertical
	center_container = MarginContainer.new()
	center_container.set_anchors_preset(PRESET_LEFT_WIDE)
	center_container.offset_left = 80
	center_container.offset_right = 80 + MENU_W
	add_child(center_container)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(MENU_W, 0)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 14)
	center_container.add_child(vbox)

	var lbl_title := Label.new()
	lbl_title.text = GAME_TITLE
	lbl_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lbl_title.add_theme_font_override("font", TITLE_FONT)
	lbl_title.add_theme_font_size_override("font_size", 56)
	lbl_title.add_theme_color_override("font_color", C_TITLE)
	lbl_title.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.10))
	lbl_title.add_theme_constant_override("outline_size", 12)
	lbl_title.add_theme_color_override("font_shadow_color", Color(C_TITLE_GLOW, 0.75))
	lbl_title.add_theme_constant_override("shadow_offset_x", 0)
	lbl_title.add_theme_constant_override("shadow_offset_y", 6)
	lbl_title.add_theme_constant_override("shadow_outline_size", 14)
	vbox.add_child(lbl_title)
	# Latido suave: el resplandor arcano del título respira
	var pulse := create_tween().set_loops()
	pulse.tween_property(lbl_title, "theme_override_colors/font_shadow_color", Color(Style.NEON_MAGENTA, 0.35), 1.6).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(lbl_title, "theme_override_colors/font_shadow_color", Color(C_TITLE_GLOW, 0.85), 1.6).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(lbl_title, "theme_override_colors/font_shadow_color", Color(Style.NEON_CYAN, 0.45), 1.6).set_trans(Tween.TRANS_SINE)

	var lbl_sub := Label.new()
	lbl_sub.text = "Dark Fantasy Roguelike"
	lbl_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
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
	btn_play.pressed.connect(_toggle_play_menu)
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
	lbl_ver.offset_left  = -260
	lbl_ver.offset_top   = -36
	lbl_ver.offset_right = -16
	lbl_ver.offset_bottom = -12
	lbl_ver.add_theme_font_size_override("font_size", 12)
	lbl_ver.add_theme_color_override("font_color", C_TEXT_DIM)
	add_child(lbl_ver)
	
	_build_upgrades_panel()
	_build_play_menu()
	btn_play.grab_focus.call_deferred()

const MENU_W := 360.0

## Mini menú que se abre a la derecha de JUGAR con los tres modos de juego.
func _build_play_menu() -> void:
	_play_menu = PanelContainer.new()
	_play_menu.set_anchors_preset(PRESET_CENTER_LEFT)
	_play_menu.offset_left = 80 + MENU_W + 40
	_play_menu.grow_vertical = Control.GROW_DIRECTION_BOTH
	_play_menu.custom_minimum_size = Vector2(380, 0)
	add_child(_play_menu)
	NeonFrame.attach(_play_menu)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_play_menu.add_child(box)
	var title := Label.new()
	title.text = "MODO DE JUEGO"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Style.style_title(title, 20)
	box.add_child(title)
	var hint := Label.new()
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(330, 34)
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", C_TEXT_DIM)
	var modes := []
	# Un botón de mazmorra por mundo (WorldDefs)
	for id in WorldDefs.ORDER:
		var w: Dictionary = WorldDefs.get_def(id)
		modes.append(["  MAZMORRA: %s" % str(w["name"]).to_upper(), "%s Combate a mano, nivel a nivel." % w["subtitle"],
			_on_play_dungeon.bind(id)])
	modes += [
		["  SUPERVIVENCIA", "Hordas sin fin en campo abierto: aguanta todo lo que puedas.", _on_play],
		["  MULTIJUGADOR", "Mazmorra cooperativa en tu wifi u online, hasta 4 jugadores.", func(): get_tree().change_scene_to_file("res://scenes/ui/lobby_menu.tscn")],
	]
	for m in modes:
		var b := _make_button(m[0], C_ACCENT)
		b.custom_minimum_size = Vector2(330, 50)
		b.pressed.connect(m[2])
		var desc: String = m[1]
		b.mouse_entered.connect(func(): hint.text = desc)
		b.focus_entered.connect(func(): hint.text = desc)
		box.add_child(b)
	box.add_child(hint)
	var back := _make_button("  VOLVER", C_BTN_BORDER)
	back.custom_minimum_size = Vector2(330, 42)
	back.pressed.connect(_toggle_play_menu)
	box.add_child(back)
	hint.text = modes[0][1]
	_play_menu.visible = false

func _toggle_play_menu() -> void:
	if _play_tween:
		_play_tween.kill()
	var opening := not _play_menu.visible
	_play_menu.visible = true
	_play_tween = create_tween().set_parallel(true)
	if opening:
		_play_menu.modulate.a = 0.0
		_play_menu.position.x = 80 + MENU_W + 10
		_play_tween.tween_property(_play_menu, "modulate:a", 1.0, 0.2)
		_play_tween.tween_property(_play_menu, "position:x", 80 + MENU_W + 40, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		var first := _play_menu.find_children("*", "Button", true, false)
		if not first.is_empty():
			(first[0] as Button).grab_focus()
	else:
		_play_tween.tween_property(_play_menu, "modulate:a", 0.0, 0.15)
		_play_tween.chain().tween_callback(func(): _play_menu.visible = false)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _play_menu and _play_menu.visible:
		_toggle_play_menu()
		get_viewport().set_input_as_handled()

## Panorama 3D del mapa (SubViewport) + viñeta oscura para que el menú se lea.
func _build_background() -> void:
	var fallback := ColorRect.new()
	fallback.set_anchors_preset(PRESET_FULL_RECT)
	fallback.color = C_BG
	add_child(fallback)

	var is_mobile := Quality.is_mobile()
	_bg_container = SubViewportContainer.new()
	_bg_container.set_anchors_preset(PRESET_FULL_RECT)
	_bg_container.stretch = true
	_bg_container.stretch_shrink = 2 if is_mobile else 1   # menos resolución en móvil
	_bg_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg_container)

	var vp := SubViewport.new()
	vp.handle_input_locally = false
	vp.msaa_3d = Viewport.MSAA_DISABLED if is_mobile else Viewport.MSAA_2X
	_bg_container.add_child(vp)

	var bg3d := MenuBackground.new()
	vp.add_child(bg3d)
	bg3d.fade_requested.connect(_on_bg_fade)

	# Viñeta radial: centro claro, bordes oscuros
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0.15))
	grad.set_color(1, Color(0.02, 0.01, 0.05, 0.85))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.9)
	var vignette := TextureRect.new()
	vignette.texture = tex
	vignette.set_anchors_preset(PRESET_FULL_RECT)
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)

func _on_bg_fade(to_black: bool, duration: float) -> void:
	var tw := create_tween()
	tw.tween_property(_bg_container, "modulate", Color(0, 0, 0, 1) if to_black else Color.WHITE, duration)

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
	return Style.make_button(txt, border_col, Vector2(320, 54))

func _btn_style(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	return Style.button_style(bg, border, radius)

func _on_play() -> void:
	GameData.game_mode = "survival"
	SceneLoader.load_scene("res://scenes/ui/character_select.tscn")

func _on_play_dungeon(world: String = WorldDefs.DEFAULT) -> void:
	GameData.game_mode = "dungeon"
	GameData.world = world
	SceneLoader.load_scene("res://scenes/ui/character_select.tscn")

func _on_upgrades_menu() -> void:
	center_container.hide()
	_play_menu.hide()
	upgrades_panel.show()
	_refresh_upgrades()

func _on_quit() -> void:
	get_tree().quit()

func _on_options_menu() -> void:
	var SettingsMenu = load("res://scripts/ui/settings_menu.gd")
	var sm = SettingsMenu.new()
	add_child(sm)
