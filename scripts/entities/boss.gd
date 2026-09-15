extends CharacterBody3D

signal boss_died(position, gold_val)
signal boss_hit

@export var max_hp: float = 600.0
var hp: float = 600.0
@export var speed: float = 4.0
@export var gold_reward: int = 150

var player: Node3D = null
var attack_cooldown: float = 0.0
var phase: int = 1

enum BossState { NORMAL, TELEGRAPH, CHARGING, RECOVERING }
var state: BossState = BossState.NORMAL
var state_timer: float = 0.0
var charge_dir: Vector3 = Vector3.FORWARD
var charge_speed: float = 18.0
var attack_pattern_step: int = 0
var ring_rotation_offset: float = 0.0
var charge_damage_dealt: bool = false

var bullet_scene = preload("res://scenes/objects/bullet.tscn")
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var omni_light: OmniLight3D = get_node_or_null("OmniLight3D")

func _ready() -> void:
	add_to_group("enemies")
	add_to_group("boss")
	max_hp = 600.0
	hp = max_hp
	player = get_tree().get_first_node_in_group("player")
	update_phase_visuals()

func _physics_process(delta: float) -> void:
	if not player or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
		return

	if mesh_instance:
		var rot_speed = 1.2 if phase == 1 else (2.0 if phase == 2 else 3.5)
		mesh_instance.rotation.y += delta * rot_speed

	if attack_cooldown > 0: attack_cooldown -= delta

	var to_player = player.global_position - global_position
	to_player.y = 0

	var current_vy = velocity.y
	if not is_on_floor():
		current_vy -= 30.0 * delta

	match state:
		BossState.NORMAL:
			if to_player.length_squared() > 0.01:
				look_at(Vector3(player.global_position.x, global_position.y, player.global_position.z), Vector3.UP)
			
			velocity = to_player.normalized() * speed
			velocity.y = current_vy
			move_and_slide()

			if attack_cooldown <= 0:
				select_next_attack(to_player)

		BossState.TELEGRAPH:
			state_timer -= delta
			velocity = Vector3.ZERO
			velocity.y = current_vy
			move_and_slide()

			if to_player.length_squared() > 0.01:
				charge_dir = to_player.normalized()
				look_at(Vector3(player.global_position.x, global_position.y, player.global_position.z), Vector3.UP)

			if state_timer <= 0:
				state = BossState.CHARGING
				state_timer = 0.7 if phase == 2 else 0.8
				charge_damage_dealt = false

		BossState.CHARGING:
			state_timer -= delta
			velocity = charge_dir * charge_speed
			velocity.y = current_vy
			move_and_slide()

			if not charge_damage_dealt:
				var dist = global_position.distance_to(player.global_position)
				if dist <= 2.2:
					if player.has_method("take_damage"):
						var charge_dmg = 8.0 if phase == 2 else 12.0
						player.take_damage(charge_dmg)
						charge_damage_dealt = true

			if state_timer <= 0:
				state = BossState.RECOVERING
				state_timer = 0.6 if phase == 2 else 0.4
				update_phase_visuals()

		BossState.RECOVERING:
			state_timer -= delta
			velocity = Vector3.ZERO
			velocity.y = current_vy
			move_and_slide()

			if state_timer <= 0:
				state = BossState.NORMAL
				attack_cooldown = 1.2 if phase == 2 else 0.8

func select_next_attack(to_player: Vector3) -> void:
	if phase == 1:
		fire_bullet_ring(12, 3.0, 14.0)
		attack_cooldown = 2.0
	else:
		attack_pattern_step += 1
		if attack_pattern_step % 2 == 1:
			var bullet_count = 16 if phase == 2 else 20
			var bullet_dmg = 4.0 if phase == 2 else 5.0
			var bullet_spd = 16.0 if phase == 2 else 18.0
			fire_bullet_ring(bullet_count, bullet_dmg, bullet_spd)
			attack_cooldown = 1.6 if phase == 2 else 1.0
		else:
			state = BossState.TELEGRAPH
			state_timer = 0.7 if phase == 2 else 0.45
			charge_speed = 18.0 if phase == 2 else 23.0
			if to_player.length_squared() > 0.01:
				charge_dir = to_player.normalized()
			
			if mesh_instance and mesh_instance.material_override:
				var mat = mesh_instance.material_override.duplicate() as StandardMaterial3D
				mat.albedo_color = Color(1.0, 0.4, 0.0)
				mesh_instance.material_override = mat

func fire_bullet_ring(count: int, dmg: float, bullet_spd: float) -> void:
	ring_rotation_offset += 0.15
	for i in range(count):
		var angle = ((float(i) / float(count)) * TAU) + ring_rotation_offset
		var dir = Vector3(cos(angle), 0, sin(angle))
		var bullet = PoolManager.get_bullet()
		bullet.global_position = global_position + Vector3(0, 1.5, 0)
		bullet.setup(dir, dmg, bullet_spd, true, Color(1.0, 0.1, 0.3), get_rid())

func take_damage(amount: float, _knockback_dir: Vector3 = Vector3.ZERO) -> void:
	hp -= amount
	emit_signal("boss_hit")

	var FloatingDamage = load("res://scripts/objects/floating_damage.gd")
	if FloatingDamage:
		var is_crit = amount >= 24.0 or randf() < 0.2
		var col = Color(1.0, 0.25, 0.1) if is_crit else Color(1.0, 0.85, 0.2)
		FloatingDamage.spawn(get_parent(), global_position + Vector3(0, 2.2, 0), amount, col, is_crit)

	if hp <= max_hp * 0.5 and phase == 1:
		phase = 2
		speed = 6.0
		$MeshInstance3D.material_override.albedo_color = Color(1.0, 0.1, 0.2)

	if hp <= 0:
		emit_signal("boss_died", global_position, gold_reward)
		queue_free()

func update_phase_visuals() -> void:
	if not mesh_instance or not mesh_instance.material_override:
		return

	var mat = mesh_instance.material_override.duplicate() as StandardMaterial3D
	match phase:
		1:
			mat.albedo_color = Color(0.66, 0.33, 0.97)
			if omni_light:
				omni_light.light_color = Color(0.66, 0.33, 0.97)
				omni_light.light_energy = 5.0
		2:
			mat.albedo_color = Color(0.9, 0.2, 0.5)
			if omni_light:
				omni_light.light_color = Color(0.9, 0.2, 0.5)
				omni_light.light_energy = 7.0
		3:
			mat.albedo_color = Color(1.0, 0.05, 0.1)
			if omni_light:
				omni_light.light_color = Color(1.0, 0.05, 0.1)
				omni_light.light_energy = 10.0

	mesh_instance.material_override = mat

