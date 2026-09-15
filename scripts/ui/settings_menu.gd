extends CanvasLayer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 120 # Put it above pause menu
	_build_ui()

func _build_ui() -> void:
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.85)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_child(center)
	
	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.14, 0.22)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.15, 0.62, 0.92)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	
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
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.15, 0.70, 1.0))
	vbox.add_child(title)
	
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 15)
	vbox.add_child(spacer)
	
	_add_slider(vbox, "Volumen Maestro", SettingsManager.master_vol, _on_master_changed)
	_add_slider(vbox, "Efectos (SFX)", SettingsManager.sfx_vol, _on_sfx_changed)
	_add_slider(vbox, "Música", SettingsManager.music_vol, _on_music_changed)
	
	var spacer2 = Control.new()
	spacer2.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(spacer2)
	
	var close_btn = Button.new()
	close_btn.text = "Guardar y Volver"
	close_btn.custom_minimum_size = Vector2(0, 45)
	close_btn.pressed.connect(func(): queue_free())
	vbox.add_child(close_btn)

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
