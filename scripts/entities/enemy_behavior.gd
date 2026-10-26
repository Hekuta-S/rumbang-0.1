class_name EnemyBehavior
extends RefCounted

var enemy   # EnemyData

func _init(e):
	enemy = e

func apply_config() -> void:
	pass

func get_model_paths() -> Dictionary:
	return { "idle": "", "walk": "", "tex": "" }

func get_knockback_resistance() -> float:
	return 1.0

func process_ai(delta: float, to_player: Vector3, dist: float, effective_speed: float) -> Vector3:
	return Vector3.ZERO

## --- Disparos de los magos (poco frecuentes) ---
## Tiempo entre disparos de cada mago y separación mínima entre disparos de CUALQUIER mago.
## Además de hacerlos menos molestos, limita los proyectiles enemigos simultáneos (rendimiento).
const RANGED_COOLDOWN := 4.5
const SNIPER_COOLDOWN := 5.5
const MORTAR_COOLDOWN := 6.5
const GLOBAL_SHOT_GAP_MS := 400
static var _last_shot_ms: int = -10000

## true si ya pasó la separación global entre disparos (y la registra).
static func try_global_shot() -> bool:
	var now := Time.get_ticks_msec()
	if now - _last_shot_ms < GLOBAL_SHOT_GAP_MS:
		return false
	_last_shot_ms = now
	return true


class RangedGoblinBehavior extends EnemyBehavior:
	func apply_config() -> void:
		# Flyweight: estado intrínseco compartido por todos los enemigos de este tipo
		EnemyTypeFlyweightFactory.get_flyweight(EnemyData.EnemyType.GOBLIN_RANGED).apply_to(enemy)
		# No disparan nada más aparecer: primer disparo tras un retraso aleatorio
		enemy.attack_cooldown = randf_range(1.5, RANGED_COOLDOWN)

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

		if dist <= enemy.attack_range and enemy.attack_cooldown <= 0 and try_global_shot():
			enemy.attack_cooldown = RANGED_COOLDOWN
			var bullet = PoolManager.get_bullet()
			bullet.global_position = enemy.global_position + Vector3(0, 1.0, 0)
			var vfx_scene = preload("res://assets/vfx/distancia/magoblin_ataque_normal.tscn")
			bullet.setup(to_player, enemy.damage, 16.0, true, Color(0.46, 0.51, 1.0), enemy.get_rid(), vfx_scene)
		return next_vel


class SniperGoblinBehavior extends EnemyBehavior:
	func apply_config() -> void:
		# Flyweight: estado intrínseco compartido por todos los enemigos de este tipo
		EnemyTypeFlyweightFactory.get_flyweight(EnemyData.EnemyType.SNIPER_GOBLIN).apply_to(enemy)
		enemy.attack_cooldown = randf_range(2.0, SNIPER_COOLDOWN)

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

		if dist <= enemy.attack_range and enemy.attack_cooldown <= 0 and try_global_shot():
			enemy.attack_cooldown = SNIPER_COOLDOWN
			var bullet = PoolManager.get_bullet()
			bullet.global_position = enemy.global_position + Vector3(0, 1.0, 0)
			var vfx_scene = preload("res://assets/vfx/distancia/magoblin_ataque_normal.tscn")
			bullet.setup(to_player, enemy.damage, 34.0, true, Color(0.46, 0.51, 1.0), enemy.get_rid(), vfx_scene)
		return next_vel


## Mago de artillería: misma skin que el mago, ataca desde mucho más lejos con un proyectil en parábola
## que cae donde estaba el jugador al disparar (no lo persigue).
class MortarGoblinBehavior extends EnemyBehavior:
	func apply_config() -> void:
		# Flyweight: estado intrínseco compartido por todos los enemigos de este tipo
		EnemyTypeFlyweightFactory.get_flyweight(EnemyData.EnemyType.MORTAR_GOBLIN).apply_to(enemy)
		enemy.attack_cooldown = randf_range(2.5, MORTAR_COOLDOWN)

	func get_model_paths() -> Dictionary:
		return {
			"idle": "res://assets/models/entities/enemigos/goblins/idle_magoblin.fbx",
			"walk": "res://assets/models/entities/enemigos/goblins/caminar_magoblin.fbx",
			"tex": "res://assets/textures/enemigos/textura_mago_goblin.png"
		}

	func process_ai(delta: float, to_player: Vector3, dist: float, effective_speed: float) -> Vector3:
		var next_vel = Vector3.ZERO
		if dist > 24.0:
			next_vel = to_player.normalized() * effective_speed
		elif dist < 16.0:
			next_vel = -to_player.normalized() * effective_speed

		if dist <= enemy.attack_range and dist >= 10.0 and enemy.attack_cooldown <= 0 and try_global_shot():
			enemy.attack_cooldown = MORTAR_COOLDOWN
			var root = EnemyManager.scene_root()
			if root != null and enemy.player != null:
				var target: Vector3 = enemy.player.global_position
				target.y = EnemyManager.floor_y(target.x, target.z)
				var from: Vector3 = enemy.global_position + Vector3(0, 1.6, 0)
				MortarShell.launch(root, from, target, enemy.damage)
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
		# Flyweight: estado intrínseco compartido por todos los enemigos de este tipo
		EnemyTypeFlyweightFactory.get_flyweight(EnemyData.EnemyType.NORMAL_GOBLIN).apply_to(enemy)

	func get_model_paths() -> Dictionary:
		return {
			"idle": "res://assets/models/entities/enemigos/goblins/idle_normal_goblin.fbx",
			"walk": "res://assets/models/entities/enemigos/goblins/caminar_normal_goblin.fbx",
			"tex": "res://assets/textures/enemigos/texture_normal_goblin.png"
		}

class HeavyBruteBehavior extends MeleeGoblinBehavior:
	func apply_config() -> void:
		# Flyweight: estado intrínseco compartido por todos los enemigos de este tipo
		EnemyTypeFlyweightFactory.get_flyweight(EnemyData.EnemyType.HEAVY_BRUTE).apply_to(enemy)

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
		# Flyweight: estado intrínseco compartido por todos los enemigos de este tipo
		EnemyTypeFlyweightFactory.get_flyweight(EnemyData.EnemyType.ZOMBIE_GOBLIN).apply_to(enemy)

	func get_model_paths() -> Dictionary:
		return {
			"idle": "res://assets/models/entities/enemigos/goblins/goblin_idle_zombie.fbx",
			"walk": "res://assets/models/entities/enemigos/goblins/goblin_caminar_zombie.fbx",
			"tex": "res://assets/textures/enemigos/textura_zombie_goblin.png"
		}
