class_name EnemyBehavior
extends RefCounted

var enemy: CharacterBody3D

func _init(e: CharacterBody3D):
	enemy = e

func apply_config() -> void:
	pass

func get_model_paths() -> Dictionary:
	return { "idle": "", "walk": "", "tex": "" }

func get_knockback_resistance() -> float:
	return 1.0

func process_ai(delta: float, to_player: Vector3, dist: float, effective_speed: float) -> Vector3:
	return Vector3.ZERO


class RangedGoblinBehavior extends EnemyBehavior:
	func apply_config() -> void:
		enemy.max_hp = 30.0
		enemy.hp = 30.0
		enemy.speed = 3.0
		enemy.attack_range = 14.0
		enemy.damage = 2.0
		enemy.gold_reward = 6
		enemy.base_color = Color.WHITE
		enemy.scale = Vector3.ONE

	func get_model_paths() -> Dictionary:
		return {
			"idle": "res://assets/models/entities/enemigos/goblins/idle_magoblin.fbx",
			"walk": "res://assets/models/entities/enemigos/goblins/caminar_magoblin.fbx",
			"tex": "res://assets/textures/enemigos/textura_mago_goblin.png"
		}

	func process_ai(delta: float, to_player: Vector3, dist: float, effective_speed: float) -> Vector3:
		var next_vel = Vector3.ZERO
		if dist > 11.5:
			next_vel = to_player.normalized() * effective_speed
		elif dist < 8.0:
			next_vel = -to_player.normalized() * effective_speed

		if dist <= enemy.attack_range and enemy.attack_cooldown <= 0:
			enemy.attack_cooldown = 1.6
			var bullet = PoolManager.get_bullet()
			bullet.global_position = enemy.global_position + Vector3(0, 1.0, 0)
			bullet.setup(to_player, enemy.damage, 16.0, true, Color(1.0, 0.1, 0.3), enemy.get_rid())
		return next_vel


class SniperGoblinBehavior extends EnemyBehavior:
	func apply_config() -> void:
		enemy.max_hp = 45.0
		enemy.hp = 45.0
		enemy.speed = 3.5
		enemy.attack_range = 9.0
		enemy.damage = 6.0
		enemy.gold_reward = 20
		enemy.base_color = Color.WHITE
		enemy.scale = Vector3(1.1, 1.25, 1.1)

	func get_model_paths() -> Dictionary:
		return {
			"idle": "res://assets/models/entities/enemigos/goblins/idle_magoblin.fbx",
			"walk": "res://assets/models/entities/enemigos/goblins/caminar_magoblin.fbx",
			"tex": "res://assets/textures/enemigos/textura_mago_goblin.png"
		}

	func process_ai(delta: float, to_player: Vector3, dist: float, effective_speed: float) -> Vector3:
		var next_vel = Vector3.ZERO
		if dist > 8.5:
			next_vel = to_player.normalized() * effective_speed
		elif dist < 5.0:
			next_vel = -to_player.normalized() * effective_speed

		if dist <= enemy.attack_range and enemy.attack_cooldown <= 0:
			enemy.attack_cooldown = 2.0
			var bullet = PoolManager.get_bullet()
			bullet.global_position = enemy.global_position + Vector3(0, 1.0, 0)
			bullet.setup(to_player, enemy.damage, 34.0, true, Color(1.0, 0.1, 0.3), enemy.get_rid())
		return next_vel


class MeleeGoblinBehavior extends EnemyBehavior:
	func process_ai(delta: float, to_player: Vector3, dist: float, effective_speed: float) -> Vector3:
		var next_vel = Vector3.ZERO
		if dist > (enemy.attack_range - 0.2):
			next_vel = to_player.normalized() * effective_speed

		if dist <= enemy.attack_range:
			if enemy.attack_cooldown <= 0:
				enemy.attack_windup += delta
				if enemy.attack_windup >= 0.4:
					enemy.attack_cooldown = 2.0
					enemy.attack_windup = 0.0
					if enemy.player.has_method("take_damage"):
						enemy.player.take_damage(enemy.damage)
		else:
			enemy.attack_windup = 0.0
		return next_vel

class NormalGoblinBehavior extends MeleeGoblinBehavior:
	func apply_config() -> void:
		enemy.max_hp = 40.0
		enemy.hp = 40.0
		enemy.speed = 4.5
		enemy.attack_range = 1.0
		enemy.damage = 0.5
		enemy.gold_reward = 8
		enemy.base_color = Color.WHITE
		enemy.scale = Vector3.ONE

	func get_model_paths() -> Dictionary:
		return {
			"idle": "res://assets/models/entities/enemigos/goblins/idle_normal_goblin.fbx",
			"walk": "res://assets/models/entities/enemigos/goblins/caminar_normal_goblin.fbx",
			"tex": "res://assets/textures/enemigos/texture_normal_goblin.png"
		}

class HeavyBruteBehavior extends MeleeGoblinBehavior:
	func apply_config() -> void:
		enemy.max_hp = 90.0
		enemy.hp = 90.0
		enemy.speed = 2.0
		enemy.attack_range = 1.4
		enemy.damage = 0.5
		enemy.gold_reward = 15
		enemy.base_color = Color.WHITE
		enemy.scale = Vector3(1.5, 1.5, 1.5)

	func get_model_paths() -> Dictionary:
		return {
			"idle": "res://assets/models/entities/enemigos/goblins/idle_goblin_bruto.fbx",
			"walk": "res://assets/models/entities/enemigos/goblins/caminar_goblin_bruto.fbx",
			"tex": "res://assets/textures/enemigos/textura_goblin_bruto.png"
		}

	func get_knockback_resistance() -> float:
		return 0.3

class ZombieGoblinBehavior extends MeleeGoblinBehavior:
	func apply_config() -> void:
		enemy.max_hp = 25.0
		enemy.hp = 25.0
		enemy.speed = 1.5
		enemy.attack_range = 1.2
		enemy.damage = 1.0
		enemy.gold_reward = 3
		enemy.base_color = Color.WHITE
		enemy.scale = Vector3(0.9, 0.9, 0.9)

	func get_model_paths() -> Dictionary:
		return {
			"idle": "res://assets/models/entities/enemigos/goblins/goblin_idle_zombie.fbx",
			"walk": "res://assets/models/entities/enemigos/goblins/goblin_caminar_zombie.fbx",
			"tex": "res://assets/textures/enemigos/textura_zombie_goblin.png"
		}
