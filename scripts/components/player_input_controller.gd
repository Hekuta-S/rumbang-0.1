extends Node

signal attack_pressed
signal alt_attack_pressed
signal alt_attack_released
signal skill_pressed
signal dodge_pressed
signal parry_pressed
signal weapon_cycle(delta: int)
signal weapon_select(slot: int)
signal reload_pressed
signal toggle_mouse_capture
signal spawn_debug_enemy

var _last_joy_buttons: Dictionary = {}

## Armas que en pantalla táctil se apuntan manteniendo el botón de disparo y se disparan al soltarlo.
const AIM_ON_HOLD := [
	WeaponData.WeaponType.SPORE_BAZOOKA,
	WeaponData.WeaponType.DUSTS,
	WeaponData.WeaponType.TRI_SHOTGUN,
]

func joy_just_pressed(btn: int) -> bool:
	var pressed = Input.is_joy_button_pressed(0, btn)
	var was_pressed = _last_joy_buttons.get(btn, false)
	_last_joy_buttons[btn] = pressed
	return pressed and not was_pressed

func _ready() -> void:
	set_process_unhandled_input(true)

## Clic izquierdo real. Con la interfaz táctil, los toques (joystick, cámara) emulan clic izquierdo:
## ahí solo cuenta el botón de ataque.
func _mouse_attack() -> bool:
	return Input.is_action_pressed("attack") and not VirtualInput.touch_ui_active

func _physics_process(_delta: float) -> void:
	if Input.is_action_just_pressed("switch_weapon") or joy_just_pressed(JOY_BUTTON_RIGHT_SHOULDER) or VirtualInput.just_pressed_cycle_next:
		emit_signal("weapon_cycle", 1)
		
	if joy_just_pressed(JOY_BUTTON_LEFT_SHOULDER) or VirtualInput.just_pressed_cycle_prev:
		emit_signal("weapon_cycle", -1)

	if Input.is_action_just_pressed("activate_skill") or joy_just_pressed(JOY_BUTTON_Y) or VirtualInput.just_pressed_skill:
		emit_signal("skill_pressed")

	var shift_pressed = Input.is_physical_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_SHIFT)
	var was_shift = _last_joy_buttons.get("SHIFT", false)
	_last_joy_buttons["SHIFT"] = shift_pressed
	var dodge_action = (InputMap.has_action("dodge") and Input.is_action_just_pressed("dodge")) or (InputMap.has_action("dodge_roll") and Input.is_action_just_pressed("dodge_roll"))
	if dodge_action or (shift_pressed and not was_shift) or joy_just_pressed(JOY_BUTTON_B) or VirtualInput.just_pressed_dodge:
		emit_signal("dodge_pressed")

	# Parry: F o clic del stick izquierdo
	var f_pressed = Input.is_physical_key_pressed(KEY_F)
	var was_f = _last_joy_buttons.get("F", false)
	_last_joy_buttons["F"] = f_pressed
	if (f_pressed and not was_f) or joy_just_pressed(JOY_BUTTON_LEFT_STICK) or VirtualInput.just_pressed_parry:
		emit_signal("parry_pressed")

	if Input.is_key_pressed(KEY_T):
		emit_signal("spawn_debug_enemy")

	var lt = Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT)
	var rt = Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT)
	
	if Input.is_action_just_pressed("alt_attack") or (lt > 0.5 and not _last_joy_buttons.get("LT", false)) or VirtualInput.is_alt_attack:
		emit_signal("alt_attack_pressed")
	if Input.is_action_just_released("alt_attack") or (lt <= 0.5 and _last_joy_buttons.get("LT", false)) or (not VirtualInput.is_alt_attack and _last_joy_buttons.get("VALT", false)):
		emit_signal("alt_attack_released")
	_last_joy_buttons["LT"] = (lt > 0.5)
	_last_joy_buttons["VALT"] = VirtualInput.is_alt_attack
	
	# Click izquierdo (acción "attack"):
	#  - Mazmorra: cada pulsación es UN golpe (solo el flanco de bajada); el combo lo encadena el búfer.
	#  - Supervivencia: mantener pulsado repite el ataque; el cooldown del arma marca el ritmo.
	#  - Mazmorra con lanzallamas: mantener pulsado = chorro continuo.
	if GameData.game_mode == "dungeon":
		var weapon: int = get_parent().current_weapon()
		# Táctil: la bazuca, los polvos y la escopeta se apuntan con el botón de disparo; al soltarlo sale el tiro
		VirtualInput.attack_aims = VirtualInput.touch_ui_active and AIM_ON_HOLD.has(weapon)
		if VirtualInput.attack_aims:
			if _last_joy_buttons.get("VAIM", false) and not VirtualInput.is_attacking:
				emit_signal("attack_pressed")
			_last_joy_buttons["VAIM"] = VirtualInput.is_attacking
			# El gatillo del mando y el ratón siguen disparando al pulsar
			var other_down: bool = rt > 0.5 or _mouse_attack()
			if other_down and not _last_joy_buttons.get("ATTACK", false):
				emit_signal("attack_pressed")
			_last_joy_buttons["ATTACK"] = other_down
		else:
			_last_joy_buttons["VAIM"] = false
			var attack_down: bool = rt > 0.5 or VirtualInput.is_attacking or _mouse_attack()
			var hold_weapon: bool = weapon == WeaponData.WeaponType.FLAME_THROWER
			if attack_down and (hold_weapon or not _last_joy_buttons.get("ATTACK", false)):
				emit_signal("attack_pressed")
			_last_joy_buttons["ATTACK"] = attack_down
	elif (rt > 0.5 and not _last_joy_buttons.get("RT", false)) or VirtualInput.is_attacking or _mouse_attack():
		emit_signal("attack_pressed")
	_last_joy_buttons["RT"] = (rt > 0.5)
	
	if joy_just_pressed(JOY_BUTTON_X) or VirtualInput.just_pressed_reload:
		emit_signal("reload_pressed")

func _unhandled_input(event: InputEvent) -> void:
	# En la mazmorra la rueda es el zoom de la cámara (CameraController)
	if event is InputEventMouseButton and GameData.game_mode != "dungeon":
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

## --- APLICACIÓN DEL PATRÓN ADAPTER (Client) ---
## El táctil tiene prioridad; teclado y mando se suman. Cada fuente se adapta a MovementSource.
var _touch_source: MovementSource = TouchMovementAdapter.new()
var _direct_sources: Array[MovementSource] = [KeyboardMovementAdapter.new(), GamepadMovementAdapter.new()]

func get_movement_vector() -> Vector2:
	var touch: Vector2 = _touch_source.get_movement_vector()
	if touch != Vector2.ZERO:
		return touch

	var total := Vector2.ZERO
	for source in _direct_sources:
		total += source.get_movement_vector()
	return total.limit_length(1.0)
