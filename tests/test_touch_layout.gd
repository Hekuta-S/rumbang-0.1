extends Node

## Editor de controles táctiles: seleccionar, mover, escalar, ocultar y restablecer un botón.

func _ready() -> void:
	print("--- TEST: EDITOR DE CONTROLES TACTILES ---")
	SettingsManager.touch_custom = {}
	SettingsManager.touch_hidden = []
	var controls: Node = load("res://scripts/ui/mobile_controls.gd").new()
	add_child(controls)
	await get_tree().process_frame
	var vp := get_viewport().get_visible_rect().size
	var i: int = controls._key_index("dodge")
	var def_pos: Vector2 = controls._btn_center[i]
	var def_r: float = controls._btn_radius[i]

	SettingsManager.touch_edit_requested.emit()
	assert(controls._editing, "El editor se abre")
	controls._edit_panel.position = Vector2(-9999, -9999)  # fuera de la zona de prueba
	controls._on_press(0, Vector2.ZERO, false)  # no debe romper nada
	controls._edit_press(3, def_pos, true)
	assert(controls._edit_sel == "dodge", "Tocar selecciona el boton")
	var target := Vector2(vp.x * 0.3, vp.y * 0.4)
	controls._edit_drag(3, target)
	controls._edit_press(3, target, false)
	assert(controls._btn_center[i].distance_to(target) < 2.0, "Arrastrar mueve el boton")
	controls._on_edit_scale(1.5)
	assert(is_equal_approx(controls._btn_radius[i], def_r * 1.5), "El deslizador escala el boton")
	controls._on_edit_visible(false)
	assert(SettingsManager.touch_hidden.has("dodge"), "Visible=false lo oculta")

	# Persistencia: otra instancia lee la misma disposicion
	var c2: Node = load("res://scripts/ui/mobile_controls.gd").new()
	add_child(c2)
	await get_tree().process_frame
	assert(c2._btn_center[i].distance_to(target) < 2.0 and is_equal_approx(c2._btn_radius[i], def_r * 1.5), "La disposicion se conserva")
	c2.queue_free()

	controls._on_edit_reset_one()
	assert(controls._btn_center[i].distance_to(def_pos) < 0.5 and is_equal_approx(controls._btn_radius[i], def_r), "Restablecer boton")

	# Joystick
	controls._edit_press(4, controls._joy_rest, true)
	assert(controls._edit_sel == "joystick")
	controls._edit_drag(4, Vector2(vp.x * 0.2, vp.y * 0.5))
	controls._edit_press(4, Vector2.ZERO, false)
	assert(controls._joy_rest.distance_to(Vector2(vp.x * 0.2, vp.y * 0.5)) < 2.0, "El joystick se mueve")

	var finished := [false]
	SettingsManager.touch_edit_finished.connect(func(): finished[0] = true)
	controls.end_edit()
	assert(finished[0] and not controls._editing)
	SettingsManager.touch_custom = {}
	SettingsManager.touch_hidden = []
	SettingsManager.save_settings()
	print("ALL TOUCH LAYOUT CHECKS PASSED")
	get_tree().quit(0)
