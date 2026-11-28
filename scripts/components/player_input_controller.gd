extends Node

signal attack_pressed
signal alt_attack_pressed
signal alt_attack_released
signal charge_started     ## clic izquierdo mantenido (armas con ataque cargado, mazmorra)
signal charge_released
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

## Mazmorra: mantener esquivar más de esto (s) es correr; soltarlo antes, rodar.
const SPRINT_HOLD := 0.25
## ¿Se mantiene esquivar lo bastante para correr? Lo lee PlayerMovementController.
var sprint_held := false
var _dodge_held := false
var _dodge_hold_t := 0.0

## Botón de esquivar en la mazmorra: rueda al soltar un toque, corre mientras se mantiene.
func _update_dodge_hold(delta: float, down: bool) -> void:
	if down:
		if not _dodge_held:
			_dodge_hold_t = 0.0
		_dodge_hold_t += delta
		sprint_held = _dodge_hold_t >= SPRINT_HOLD
	elif _dodge_held:
		if _dodge_hold_t < SPRINT_HOLD:
			emit_signal("dodge_pressed")
		sprint_held = false
	_dodge_held = down

## Mazmorra, armas con ataque cargado (PlayerCombatController.has_melee_charge): el golpe sale al SOLTAR un toque;
## mantenido más de CHARGE_HOLD s empieza a cargar (charge_started) y al soltar sale el cargado (charge_released).
const CHARGE_HOLD := 0.22
var _atk_held := false
var _atk_hold_t := 0.0
var _atk_charge_sent := false

func _update_attack_hold(delta: float, down: bool) -> void:
	if down:
		if not _atk_held:
			_atk_hold_t = 0.0
			_atk_charge_sent = false
		_atk_hold_t += delta
		if not _atk_charge_sent and _atk_hold_t >= CHARGE_HOLD:
			_atk_charge_sent = true
			emit_signal("charge_started")
	elif _atk_held:
		if _atk_charge_sent:
			emit_signal("charge_released")
		else:
			emit_signal("attack_pressed")
	_atk_held = down

## El arma cambió a una sin carga con el clic mantenido: se cierra la carga que hubiera.
func _end_attack_hold() -> void:
	if _atk_held and _atk_charge_sent:
		emit_signal("charge_released")
	_atk_held = false
	_atk_charge_sent = false

## Clic izquierdo real. Con la interfaz táctil, los toques (joystick, cámara) emulan clic izquierdo:
## ahí solo cuenta el botón de ataque.
func _mouse_attack() -> bool:
	return Input.is_action_pressed("attack") and not VirtualInput.touch_ui_active

func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("switch_weapon") or joy_just_pressed(JOY_BUTTON_Y) or VirtualInput.just_pressed_cycle_next:
		emit_signal("weapon_cycle", 1)
		
	# L1 del mando fija objetivo (TargetLockController); el arma anterior queda solo para el botón táctil
	if VirtualInput.just_pressed_cycle_prev:
		emit_signal("weapon_cycle", -1)

	if Input.is_action_just_pressed("activate_skill") or joy_just_pressed(JOY_BUTTON_RIGHT_SHOULDER) or VirtualInput.just_pressed_skill:
		emit_signal("skill_pressed")

	var shift_pressed = Input.is_physical_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_SHIFT)
	var was_shift = _last_joy_buttons.get("SHIFT", false)
	_last_joy_buttons["SHIFT"] = shift_pressed
	var dodge_action = (InputMap.has_action("dodge") and Input.is_action_just_pressed("dodge")) or (InputMap.has_action("dodge_roll") and Input.is_action_just_pressed("dodge_roll"))
	if GameData.game_mode == "dungeon":
		# Como Dark Souls: el botón de esquivar (Shift, B del mando, botón táctil) rueda al SOLTARLO si fue un
		# toque; mantenido más de SPRINT_HOLD s es correr, y al soltarlo no rueda. Espacio (dodge_roll) sigue
		# rodando al pulsar.
		_update_dodge_hold(delta, shift_pressed or Input.is_joy_button_pressed(0, JOY_BUTTON_B) or VirtualInput.is_dodge_held)
		if dodge_action:
			emit_signal("dodge_pressed")
	else:
		_dodge_held = false
		sprint_held = false
		if dodge_action or (shift_pressed and not was_shift) or VirtualInput.just_pressed_dodge:
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
	#  - Mazmorra con lanzallamas o fusil: mantener pulsado = chorro continuo / fuego automático.
	if GameData.game_mode == "dungeon":
		var weapon: int = get_parent().current_weapon()
		# Táctil: la bazuca, los polvos y la escopeta se apuntan con el botón de disparo; al soltarlo sale el tiro
		VirtualInput.attack_aims = VirtualInput.touch_ui_active and AIM_ON_HOLD.has(weapon)
		if VirtualInput.attack_aims:
			_end_attack_hold()
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
			var hold_weapon: bool = weapon == WeaponData.WeaponType.FLAME_THROWER or weapon == WeaponData.WeaponType.RIFLE
			var cc = get_parent().get("combat_controller")
			if not hold_weapon and cc and cc.has_melee_charge():
				_update_attack_hold(delta, attack_down)
			else:
				_end_attack_hold()
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

	if event.is_action_pressed("ui_cancel") and not event is InputEventJoypadButton:   # B = esquivar; Start lo gestiona PauseMenu
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
