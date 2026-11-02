class_name RemotePlayer
extends CharacterBody3D

## Representación de otro jugador de la red. No se mueve por física: su dueño manda el estado (posición,
## giro, velocidad, arma) y aquí se interpola. Se ve con el MISMO controlador de animación y las mismas
## armas en la mano que el jugador local (PlayerAnimationController + PlayerWeaponVisuals): su dueño avisa de
## cada acción (golpes, rodar, disparos) y aquí se reproducen igual. Para la IA enemiga y los proyectiles se
## comporta como un jugador: está en el grupo "net_players" y tiene take_damage(), que reenvía el golpe a su
## dueño (que es quien lleva su vida real).

signal weapon_attacked(weapon_type: int)    ## el controlador de animación espera esta señal del jugador

var peer_id := 0
var char_index := 0
var net_char_id := ""                 ## lo lee PlayerAnimationController (_char_id)
var net_on_floor := true              ## ídem (no se puede sobrescribir is_on_floor)
var weapon := -1
var hp := 1.0
var max_hp := 1.0
var move_speed := 7.0
var mesh: Node3D                      ## como Player.mesh: el modelo cuelga de aquí
var weapon_visuals: Node
var weapon_models: Dictionary = {}
var animation_controller: PlayerAnimationController

var _target_pos := Vector3.ZERO
var _target_yaw := 0.0
var _label: Label3D
var _got_state := false

func _ready() -> void:
	add_to_group("net_players")
	collision_layer = 2
	collision_mask = 0
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.7
	col.shape = cap
	col.position.y = 0.9
	add_child(col)
	mesh = Node3D.new()
	mesh.name = "KnightMesh"
	add_child(mesh)

	var ch: Dictionary = GameData.CHARACTERS[clampi(char_index, 0, GameData.CHARACTERS.size() - 1)]
	net_char_id = str(ch["id"])
	move_speed = float(ch.get("stats", {}).get("move_speed", 7.0)) * GameData.DUNGEON_MOVE_SPEED_MULT

	# Mismo esqueleto, animaciones y armas en la mano que el jugador local
	weapon_visuals = load("res://scripts/entities/player_weapon_visuals.gd").new()
	add_child(weapon_visuals)
	weapon_models = weapon_visuals.weapon_models
	animation_controller = PlayerAnimationController.new()
	animation_controller.name = "PlayerAnimationController"
	add_child(animation_controller)
	if animation_controller.model:
		weapon_visuals.attach_spear_to_hand(animation_controller.model)
		weapon_visuals.attach_axe_to_hand(animation_controller.model)

	_label = Label3D.new()
	_label.text = Net.name_of(peer_id)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = true
	_label.pixel_size = 0.0011
	_label.font_size = 28
	_label.outline_size = 8
	_label.position = Vector3(0, 2.25, 0)
	add_child(_label)

func current_weapon() -> int:
	return weapon

## Muestra solo el arma en la mano del arma equipada (como Player.update_weapon_visuals).
func update_weapon_visuals() -> void:
	if animation_controller:
		animation_controller.set_held_weapon(weapon)
	for wt in weapon_models:
		var m: Node3D = weapon_models[wt]
		if m != null and is_instance_valid(m):
			m.visible = m.has_meta("in_hand") and wt == weapon

# ───────────────────────────── Estado de la red ─────────────────────────────

## Estado recibido de su dueño: [pos, yaw, vel, en_suelo, arma, hp, max_hp, caído, disparando].
func apply_state(s: Array) -> void:
	_target_pos = s[0]
	_target_yaw = s[1]
	velocity = s[2]
	net_on_floor = s[3]
	var new_weapon: int = s[4]
	hp = s[5]
	max_hp = s[6]
	var down: bool = s[7]
	set_meta("downed", down)
	visible = not down
	if bool(s[8]) and animation_controller:
		# Arma de fuego continua (lanzallamas): mantiene la pose de disparo mientras el dueño dispara
		animation_controller.held_fire_until = Time.get_ticks_msec() / 1000.0 + 0.3
	if new_weapon != weapon:
		weapon = new_weapon
		update_weapon_visuals()
	if not _got_state:
		_got_state = true
		global_position = _target_pos
		mesh.rotation.y = _target_yaw

## Acción de cuerpo entero de su dueño (golpe, rodar, lanzamiento...).
func play_action(anim_name: String, from_time: float, speed: float) -> void:
	if animation_controller:
		animation_controller._fire_action(anim_name, from_time, speed)
		animation_controller._suppress_hit_window = true

func play_held_shot(speed: float) -> void:
	if animation_controller:
		animation_controller.play_held_shot(speed)

func _physics_process(delta: float) -> void:
	if not _got_state:
		return
	global_position = global_position.lerp(_target_pos, 1.0 - exp(-16.0 * delta))
	mesh.rotation.y = lerp_angle(mesh.rotation.y, _target_yaw, 1.0 - exp(-14.0 * delta))

# ───────────────────────────── Como un jugador ─────────────────────────────

func is_dead() -> bool:
	return bool(get_meta("downed", false))

## Los enemigos y proyectiles lo tratan como a un jugador: el golpe se reenvía a su dueño.
func take_damage(amount: float, direction: Vector3 = Vector3.ZERO) -> void:
	if not Net.is_host() or is_dead():
		return
	var world := get_tree().current_scene.get_node_or_null("NetWorld")
	if world:
		world.damage_player(peer_id, amount, direction)
