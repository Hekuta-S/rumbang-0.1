extends Node

signal attack_pressed
signal alt_attack_pressed
signal skill_pressed
signal weapon_cycle(delta: int)
signal weapon_select(slot: int)
signal reload_pressed
signal toggle_mouse_capture
signal spawn_debug_enemy

var _last_joy_buttons: Dictionary = {}

func joy_just_pressed(btn: int) -> bool:
	var pressed = Input.is_joy_button_pressed(0, btn)
	var was_pressed = _last_joy_buttons.get(btn, false)
	_last_joy_buttons[btn] = pressed
	return pressed and not was_pressed

func _ready() -> void:
	set_process_unhandled_input(true)

func _physics_process(_delta: float) -> void:
	if Input.is_action_just_pressed("switch_weapon") or joy_just_pressed(JOY_BUTTON_RIGHT_SHOULDER):
		emit_signal("weapon_cycle", 1)
		
	if joy_just_pressed(JOY_BUTTON_LEFT_SHOULDER):
		emit_signal("weapon_cycle", -1)

	if Input.is_action_just_pressed("activate_skill") or joy_just_pressed(JOY_BUTTON_Y):
		emit_signal("skill_pressed")

	if Input.is_key_pressed(KEY_T):
		emit_signal("spawn_debug_enemy")

	var lt = Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT)
	var rt = Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT)
	
	if Input.is_action_just_pressed("alt_attack") or (lt > 0.5 and not _last_joy_buttons.get("LT", false)):
		emit_signal("alt_attack_pressed")
	_last_joy_buttons["LT"] = (lt > 0.5)
	
	if (rt > 0.5 and not _last_joy_buttons.get("RT", false)):
		emit_signal("attack_pressed")
	_last_joy_buttons["RT"] = (rt > 0.5)
	
	if joy_just_pressed(JOY_BUTTON_X):
		emit_signal("reload_pressed")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			emit_signal("weapon_cycle", 1)
			get_viewport().set_input_as_handled()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			emit_signal("weapon_cycle", -1)
			get_viewport().set_input_as_handled()

	elif event is InputEventKey and event.pressed:
		if event.keycode >= KEY_1 and event.keycode <= KEY_4:
			emit_signal("weapon_select", event.keycode - KEY_1)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_R:
			emit_signal("reload_pressed")
			get_viewport().set_input_as_handled()

	if event.is_action_pressed("ui_cancel") or joy_just_pressed(JOY_BUTTON_START):
		emit_signal("toggle_mouse_capture")
		get_viewport().set_input_as_handled()

func get_movement_vector() -> Vector2:
	var x := 0.0
	var y := 0.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_key_pressed(KEY_W): y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_key_pressed(KEY_S): y += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_key_pressed(KEY_A): x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_key_pressed(KEY_D): x += 1.0
	
	var joy_x = Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
	var joy_y = Input.get_joy_axis(0, JOY_AXIS_LEFT_Y)
	if abs(joy_x) > 0.2: x += joy_x
	if abs(joy_y) > 0.2: y += joy_y
	
	return Vector2(x, y).limit_length(1.0)
