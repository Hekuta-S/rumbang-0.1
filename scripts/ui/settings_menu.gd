extends CanvasLayer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 120 # Put it above pause menu
	_build_ui()

func _build_ui() -> void:
	var bg = ColorRect.new()
	bg.color = Color(0.02, 0.01, 0.05, 0.88)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_child(center)
	
	var panel = PanelContainer.new()
	panel.theme = RumbangStyle.get_theme()
	center.add_child(panel)
	NeonFrame.attach(panel)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 30)
	panel.add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(350, 0)
	vbox.add_theme_constant_override("separation", 15)
	margin.add_child(vbox)
	
	var title = Label.new()
	title.text = "CONFIGURACIÓN"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	RumbangStyle.style_title(title, 26)
	vbox.add_child(title)
	
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 15)
	vbox.add_child(spacer)
	
	_add_slider(vbox, "Volumen Maestro", SettingsManager.master_vol, _on_master_changed)
	_add_slider(vbox, "Efectos (SFX)", SettingsManager.sfx_vol, _on_sfx_changed)
	_add_slider(vbox, "Música", SettingsManager.music_vol, _on_music_changed)
	
	_add_quality_selector(vbox)
	if Quality.is_mobile():
		_add_fps_selector(vbox)
	_add_attack_marks_toggle(vbox)
	_add_submenu_button(vbox, "Sensibilidad", _fill_sensitivity)
	_add_submenu_button(vbox, "Controles táctiles", _fill_touch)

	var spacer2 = Control.new()
	spacer2.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(spacer2)
	
	var close_btn = Button.new()
	close_btn.text = "Guardar y Volver"
	close_btn.custom_minimum_size = Vector2(0, 45)
	close_btn.pressed.connect(func(): queue_free())
	vbox.add_child(close_btn)
	close_btn.grab_focus.call_deferred()

func _add_quality_selector(parent: Control) -> void:
	var hbox = HBoxContainer.new()
	parent.add_child(hbox)

	var lbl = Label.new()
	lbl.text = "Calidad gráfica"
	lbl.custom_minimum_size = Vector2(150, 0)
	hbox.add_child(lbl)

	var opt = OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for n in ["Bajo", "Medio", "Alto"]:
		opt.add_item(n)
	opt.selected = Quality.level()
	opt.item_selected.connect(_on_quality_changed)
	hbox.add_child(opt)

## Tope de FPS (solo móvil): Automático / 30 / 60. A 30 el móvil gasta menos batería y se calienta menos.
func _add_fps_selector(parent: Control) -> void:
	var hbox = HBoxContainer.new()
	parent.add_child(hbox)
	var lbl = Label.new()
	lbl.text = "Límite de FPS"
	lbl.custom_minimum_size = Vector2(150, 0)
	hbox.add_child(lbl)
	var opt = OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for n in ["Automático", "30 FPS (ahorra batería)", "60 FPS"]:
		opt.add_item(n)
	opt.selected = [0, 30, 60].find(SettingsManager.mobile_fps)
	opt.item_selected.connect(func(idx: int): Quality.set_mobile_fps([0, 30, 60][idx]))
	hbox.add_child(opt)

## Guarda el nivel y aplica en vivo lo que se puede (resolución 3D, sombras y brillo).
## Partículas, luces y tope de enemigos se notan en los efectos nuevos y la próxima partida.
func _on_quality_changed(idx: int) -> void:
	Quality.set_level(idx)
	var vp := get_viewport()
	if vp:
		vp.scaling_3d_scale = Quality.scale_3d()
	var scene := get_tree().current_scene
	if scene:
		var light := scene.get_node_or_null("DirectionalLight3D") as DirectionalLight3D
		if light and not Quality.is_mobile():
			light.shadow_enabled = Quality.shadows_enabled()
		var we := scene.get_node_or_null("WorldEnvironment") as WorldEnvironment
		if we and we.environment and not Quality.is_mobile():
			we.environment.glow_enabled = Quality.glow_enabled()

## Marcas en el suelo de los ataques enemigos; se aplica en el siguiente ataque.
func _add_attack_marks_toggle(parent: Control) -> void:
	var check = CheckButton.new()
	check.text = "Marcas de ataques enemigos"
	check.button_pressed = SettingsManager.show_attack_marks
	check.toggled.connect(func(on: bool):
		SettingsManager.show_attack_marks = on
		SettingsManager.save_settings())
	parent.add_child(check)

func _add_slider(parent: Control, label_text: String, start_val: float, callback: Callable) -> void:
	var hbox = HBoxContainer.new()
	parent.add_child(hbox)
	
	var lbl = Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(150, 0)
	hbox.add_child(lbl)
	
	var slider = HSlider.new()
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = start_val
	slider.value_changed.connect(callback)
	hbox.add_child(slider)

func _on_master_changed(v: float) -> void:
	SettingsManager.master_vol = v
	SettingsManager.set_bus_volume("Master", v)
	SettingsManager.save_settings()

func _on_sfx_changed(v: float) -> void:
	SettingsManager.sfx_vol = v
	SettingsManager.set_bus_volume("SFX", v)
	SettingsManager.save_settings()

func _on_music_changed(v: float) -> void:
	SettingsManager.music_vol = v
	SettingsManager.set_bus_volume("Music", v)
	SettingsManager.save_settings()

# ───────────────────────────── Submenús ─────────────────────────────

const TOUCH_NAMES := {
	"attack": "Ataque", "jump": "Salto", "dodge": "Rodar", "alt": "Ataque especial",
	"target": "Fijar objetivo", "skill": "Habilidad", "parry": "Parar",
	"reload": "Recargar", "weapon": "Cambiar arma",
}

func _add_submenu_button(parent: Control, text: String, fill: Callable) -> void:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 40)
	btn.pressed.connect(func(): _open_subpanel(text, fill))
	parent.add_child(btn)

## Panel secundario con desplazamiento (cabe en pantallas pequeñas); `fill` recibe su VBox.
func _open_subpanel(title_text: String, fill: Callable) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 121
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.9)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_child(center)

	var panel := PanelContainer.new()
	panel.theme = RumbangStyle.get_theme()
	center.add_child(panel)
	NeonFrame.attach(panel, RumbangStyle.NEON_MAGENTA)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	margin.add_child(outer)

	var title := Label.new()
	title.text = title_text.to_upper()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	RumbangStyle.style_title(title, 22)
	outer.add_child(title)

	var scroll := ScrollContainer.new()
	var max_h := get_viewport().get_visible_rect().size.y * 0.62
	scroll.custom_minimum_size = Vector2(380, minf(max_h, 420.0))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 12)
	scroll.add_child(inner)
	fill.call(inner)

	var back := Button.new()
	back.text = "Volver"
	back.custom_minimum_size = Vector2(0, 42)
	back.pressed.connect(func(): layer.queue_free())
	outer.add_child(back)
	back.grab_focus.call_deferred()

## Deslizador con rango libre y el valor al lado (p. ej. "×1.25").
func _add_range_slider(parent: Control, label_text: String, min_v: float, max_v: float, start_val: float, callback: Callable) -> void:
	var hbox := HBoxContainer.new()
	parent.add_child(hbox)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(150, 0)
	hbox.add_child(lbl)
	var slider := HSlider.new()
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = 0.05
	slider.value = start_val
	hbox.add_child(slider)
	var val_lbl := Label.new()
	val_lbl.custom_minimum_size = Vector2(52, 0)
	val_lbl.text = "×%.2f" % start_val
	hbox.add_child(val_lbl)
	slider.value_changed.connect(func(v: float):
		val_lbl.text = "×%.2f" % v
		callback.call(v))
	return

func _fill_sensitivity(box: VBoxContainer) -> void:
	_add_range_slider(box, "Ratón / mando", SettingsManager.SENS_MIN, SettingsManager.SENS_MAX,
		SettingsManager.look_sensitivity, func(v: float):
			SettingsManager.look_sensitivity = v
			SettingsManager.save_settings())
	_add_range_slider(box, "Arrastre táctil", SettingsManager.SENS_MIN, SettingsManager.SENS_MAX,
		SettingsManager.touch_look_sensitivity, func(v: float):
			SettingsManager.touch_look_sensitivity = v
			SettingsManager.save_settings())
	var reset := Button.new()
	reset.text = "Restablecer"
	reset.pressed.connect(func():
		SettingsManager.look_sensitivity = 1.0
		SettingsManager.touch_look_sensitivity = 1.0
		SettingsManager.save_settings()
		for c in box.get_children():
			c.queue_free()
		_fill_sensitivity.call_deferred(box))
	box.add_child(reset)

func _fill_touch(box: VBoxContainer) -> void:
	_add_range_slider(box, "Tamaño", SettingsManager.TOUCH_SCALE_MIN, SettingsManager.TOUCH_SCALE_MAX,
		SettingsManager.touch_scale, func(v: float):
			SettingsManager.touch_scale = v
			SettingsManager.save_settings()
			SettingsManager.touch_layout_changed.emit())
	_add_range_slider(box, "Opacidad", 0.2, 1.0, SettingsManager.touch_opacity, func(v: float):
		SettingsManager.touch_opacity = v
		SettingsManager.save_settings()
		SettingsManager.touch_layout_changed.emit())
	if get_tree().get_nodes_in_group("mobile_controls").is_empty():
		var note := Label.new()
		note.text = "La disposición se edita desde el menú de pausa durante la partida."
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(note)
	else:
		var edit := Button.new()
		edit.text = "Editar disposición (mover y escalar)"
		edit.custom_minimum_size = Vector2(0, 44)
		edit.pressed.connect(_start_touch_edit)
		box.add_child(edit)
	var hdr := Label.new()
	hdr.text = "Botones visibles"
	hdr.add_theme_color_override("font_color", RumbangStyle.NEON_CYAN)
	box.add_child(hdr)
	for key in TOUCH_NAMES:
		var check := CheckButton.new()
		check.text = TOUCH_NAMES[key]
		check.button_pressed = not SettingsManager.touch_hidden.has(key)
		check.toggled.connect(func(on: bool):
			if on:
				SettingsManager.touch_hidden.erase(key)
			elif not SettingsManager.touch_hidden.has(key):
				SettingsManager.touch_hidden.append(key)
			SettingsManager.save_settings()
			SettingsManager.touch_layout_changed.emit())
		box.add_child(check)
	var reset := Button.new()
	reset.text = "Restablecer"
	reset.pressed.connect(func():
		SettingsManager.touch_scale = 1.0
		SettingsManager.touch_opacity = 1.0
		SettingsManager.touch_hidden = []
		SettingsManager.touch_custom = {}
		SettingsManager.save_settings()
		SettingsManager.touch_layout_changed.emit()
		for c in box.get_children():
			c.queue_free()
		_fill_touch.call_deferred(box))
	box.add_child(reset)

## Oculta los ajustes mientras el editor de MobileControls está abierto y los devuelve al terminar.
func _start_touch_edit() -> void:
	_set_menu_visible(false)
	SettingsManager.touch_edit_finished.connect(_set_menu_visible.bind(true), CONNECT_ONE_SHOT)
	SettingsManager.touch_edit_requested.emit()

func _set_menu_visible(on: bool) -> void:
	visible = on
	for c in get_children():
		if c is CanvasLayer:
			c.visible = on
