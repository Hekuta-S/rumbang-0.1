class_name EnemyBehavior
extends RefCounted

var enemy: EnemyData   ## tipado: la IA lee sus campos cada tick (acceso directo, sin búsqueda por nombre)

func _init(e: EnemyData):
	enemy = e

func apply_config() -> void:
	pass

func get_model_paths() -> Dictionary:
	return { "idle": "", "walk": "", "tex": "" }

## Multiplica la velocidad del empujón (1 = normal; menos = más pesado)
func get_knockback_resistance() -> float:
	return 0.85

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

## --- Beta: comportamientos más complejos (todo por debajo de BETA_FROM s de partida se queda como antes) ---
const BURST_FROM := 90.0            ## el mago empieza a disparar en ráfagas de dos
const BURST_GAP := 0.3              ## s entre los dos disparos de la ráfaga
const STRAFE_SPEED := 0.55          ## × velocidad del mago al moverse de lado mientras dispara
const LUNGE_FROM := 60.0            ## los goblins embisten desde el minuto
const LUNGE_SHARE := 0.3            ## fracción de goblins que sabe embestir
const LUNGE_MIN := 4.5
const LUNGE_MAX := 9.5
const LUNGE_WINDUP := 0.55          ## s plantado y parpadeando antes de lanzarse (se puede esquivar o deslizar)
const LUNGE_TIME := 0.45
const LUNGE_SPEED_MULT := 3.6
const LUNGE_DAMAGE_MULT := 1.4
const LUNGE_COOLDOWN := Vector2(5.0, 8.0)
const SLAM_FROM := 120.0            ## el bruto empieza a golpear el suelo
const SLAM_RANGE := Vector2(3.5, 10.0)
const SLAM_RADIUS := 3.2
const SLAM_DELAY := 1.1
const SLAM_DAMAGE_MULT := 1.3
const SLAM_COOLDOWN := 8.0
const ENRAGE_HP := 0.35             ## el zombi se enfurece por debajo de esta fracción de vida
const ENRAGE_SPEED := 1.5

## Segundos de partida (el reloj de la partida de supervivencia).
static func elapsed() -> float:
	return GameState.get_instance().elapsed_time

## true si ya pasó la separación global entre disparos (y la registra).
static func try_global_shot() -> bool:
	var now := Time.get_ticks_msec()
	if now - _last_shot_ms < GLOBAL_SHOT_GAP_MS:
		return false
	_last_shot_ms = now
	return true


class RangedGoblinBehavior extends EnemyBehavior:
	func get_knockback_resistance() -> float:
		return 0.8

	func apply_config() -> void:
		# Flyweight: estado intrínseco compartido por todos los enemigos de este tipo
		EnemyTypeFlyweightFactory.get_flyweight(EnemyData.EnemyType.GOBLIN_RANGED).apply_to(enemy)
		# No disparan nada más aparecer: primer disparo tras un retraso aleatorio
		enemy.attack_cooldown = randf_range(1.5, RANGED_COOLDOWN)
		enemy.burst_left = 0

	func get_model_paths() -> Dictionary:
		return {
			"idle": "res://assets/models/entities/enemigos/goblins/idle_magoblin.fbx",
			"walk": "res://assets/models/entities/enemigos/goblins/caminar_magoblin.fbx",
			"tex": "res://assets/textures/enemigos/textura_mago_goblin.png"
		}

	func process_ai(delta: float, to_player: Vector3, dist: float, effective_speed: float) -> Vector3:
		var next_vel := Vector3.ZERO
		if dist > 11.5:
			next_vel = to_player.normalized() * effective_speed
		elif dist < 8.0:
			next_vel = -to_player.normalized() * effective_speed
		elif dist > 0.01:
			# A distancia de tiro: se mueve de lado (cambia de sentido en cada disparo) en vez de quedarse plantado
			var radial := to_player / dist
			next_vel = Vector3(-radial.z, 0.0, radial.x) * float(enemy.orbit_sign) * effective_speed * STRAFE_SPEED

		# Segundo disparo de la ráfaga (no cuenta para la separación global: ya la pasó el primero)
		var burst_shot: bool = enemy.burst_left > 0 and enemy.attack_cooldown <= 0
		if burst_shot or (dist <= enemy.attack_range and enemy.attack_cooldown <= 0 and try_global_shot()):
			if burst_shot:
				enemy.burst_left = 0
				enemy.attack_cooldown = RANGED_COOLDOWN
			elif elapsed() >= BURST_FROM:
				enemy.burst_left = 1
				enemy.attack_cooldown = BURST_GAP
			else:
				enemy.attack_cooldown = RANGED_COOLDOWN
			enemy.orbit_sign = -enemy.orbit_sign
			var bullet = PoolManager.get_bullet()
			bullet.global_position = enemy.global_position + Vector3(0, 1.0, 0)
			var vfx_scene = preload("res://assets/vfx/distancia/magoblin_ataque_normal.tscn")
			bullet.setup(to_player, enemy.damage, 16.0, true, Color(0.46, 0.51, 1.0), enemy.get_rid(), vfx_scene)
		return next_vel


class SniperGoblinBehavior extends EnemyBehavior:
	func get_knockback_resistance() -> float:
		return 0.75

	## Dirección de tiro adelantada: apunta a donde estará el jugador cuando llegue la bala (si se mueve en
	## línea recta; hasta el minuto y medio apunta directo, como antes).
	func lead_aim(to_player: Vector3, dist: float, bullet_speed: float) -> Vector3:
		if elapsed() < BURST_FROM or enemy.player == null:
			return to_player
		var v = enemy.player.get("velocity")
		if not (v is Vector3):
			return to_player
		var flat := Vector3(v.x, 0.0, v.z)
		return to_player + flat * (dist / bullet_speed) * 0.8

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
		var next_vel := Vector3.ZERO
		if dist > 8.5:
			next_vel = to_player.normalized() * effective_speed
		elif dist < 5.0:
			next_vel = -to_player.normalized() * effective_speed

		if dist <= enemy.attack_range and enemy.attack_cooldown <= 0 and try_global_shot():
			enemy.attack_cooldown = SNIPER_COOLDOWN
			var bullet = PoolManager.get_bullet()
			bullet.global_position = enemy.global_position + Vector3(0, 1.0, 0)
			var vfx_scene = preload("res://assets/vfx/distancia/magoblin_ataque_normal.tscn")
			bullet.setup(lead_aim(to_player, dist, 34.0), enemy.damage, 34.0, true, Color(0.46, 0.51, 1.0), enemy.get_rid(), vfx_scene)
		return next_vel


## Mago de artillería: misma skin que el mago, ataca desde mucho más lejos con un proyectil en parábola
## que cae donde estaba el jugador al disparar (no lo persigue).
class MortarGoblinBehavior extends EnemyBehavior:
	func get_knockback_resistance() -> float:
		return 0.6

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
		var next_vel := Vector3.ZERO
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


## Cuerpo a cuerpo con turnos de la mente colmena: dentro del anillo (attack_range + RING_GAP) solo se
## acerca a golpear quien tiene token (HiveMind.acquire_token); los demás rodean al jugador a esa
## distancia esperando su turno. Tras cada golpe el token se suelta para que rote.
class MeleeGoblinBehavior extends EnemyBehavior:
	const RING_GAP := 1.3            ## distancia extra sobre attack_range a la que esperan los que no tienen turno
	const RELEASE_GAP := 3.0         ## si el jugador se aleja tanto del anillo, el token se suelta
	const ORBIT_SPEED := 0.45        ## × velocidad, al rodear esperando turno

	func process_ai(delta: float, to_player: Vector3, dist: float, effective_speed: float) -> Vector3:
		var ring: float = enemy.attack_range + RING_GAP
		if enemy.has_token and dist > ring + RELEASE_GAP:
			HiveMind.release_token(enemy)
		if dist <= ring and not HiveMind.acquire_token(enemy):
			enemy.attack_windup = 0.0
			return _wait_in_ring(to_player, dist, ring, effective_speed)

		var next_vel := Vector3.ZERO
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
					# Turno cumplido: el token pasa a otro de la horda
					HiveMind.release_token(enemy, HiveMind.TOKEN_RETRY)
		else:
			enemy.attack_windup = 0.0
		return next_vel

	## Sin turno: rodea al jugador manteniéndose en el anillo (se aparta si está más cerca).
	func _wait_in_ring(to_player: Vector3, dist: float, ring: float, effective_speed: float) -> Vector3:
		if dist < 0.01:
			return Vector3.ZERO
		var radial := to_player / dist                      # hacia el jugador
		var tangent: Vector3 = Vector3(-radial.z, 0.0, radial.x) * float(enemy.orbit_sign)
		var radial_err := clampf((dist - ring) / RING_GAP, -1.0, 1.0)   # <0: demasiado cerca -> se aparta
		return (tangent * ORBIT_SPEED + radial * radial_err) * effective_speed

class NormalGoblinBehavior extends MeleeGoblinBehavior:
	func get_knockback_resistance() -> float:
		return 0.85

	func apply_config() -> void:
		# Flyweight: estado intrínseco compartido por todos los enemigos de este tipo
		EnemyTypeFlyweightFactory.get_flyweight(EnemyData.EnemyType.NORMAL_GOBLIN).apply_to(enemy)
		enemy.lunger = randf() < LUNGE_SHARE
		enemy.special_cd = randf_range(LUNGE_COOLDOWN.x, LUNGE_COOLDOWN.y)

	## Embestida: se planta y parpadea LUNGE_WINDUP s (aviso) y se lanza en línea recta; si te toca, hace
	## LUNGE_DAMAGE_MULT del daño. Falla si te apartas, te deslizas o esquivas. Solo algunos goblins, pasado el minuto.
	func process_ai(delta: float, to_player: Vector3, dist: float, effective_speed: float) -> Vector3:
		if enemy.special_state == 1:
			enemy.special_t -= delta
			enemy.vat_flash = 0.15                      # parpadeo blanco: aviso
			if enemy.special_t <= 0.0:
				enemy.special_state = 2
				enemy.special_t = LUNGE_TIME
				enemy.special_hit = false
				enemy.special_dir = to_player.normalized()
			return Vector3.ZERO
		if enemy.special_state == 2:
			enemy.special_t -= delta
			if not enemy.special_hit and dist <= enemy.attack_range + 0.4 and enemy.player.has_method("take_damage"):
				enemy.special_hit = true
				enemy.player.take_damage(enemy.damage * LUNGE_DAMAGE_MULT)
			if enemy.special_t <= 0.0 or enemy.special_hit:
				enemy.special_state = 0
				enemy.special_cd = randf_range(LUNGE_COOLDOWN.x, LUNGE_COOLDOWN.y)
			return enemy.special_dir * effective_speed * LUNGE_SPEED_MULT
		if enemy.lunger and enemy.special_cd <= 0.0 and dist >= LUNGE_MIN and dist <= LUNGE_MAX and elapsed() >= LUNGE_FROM:
			enemy.special_state = 1
			enemy.special_t = LUNGE_WINDUP
			return Vector3.ZERO
		return super.process_ai(delta, to_player, dist, effective_speed)

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
		enemy.special_cd = randf_range(2.0, SLAM_COOLDOWN)

	## Golpe al suelo: desde SLAM_RANGE, marca un círculo donde está el jugador y a SLAM_DELAY s revienta
	## (GroundBlast: avisa en el suelo; se esquiva saliendo del círculo). Además de su golpe de siempre.
	func process_ai(delta: float, to_player: Vector3, dist: float, effective_speed: float) -> Vector3:
		if enemy.special_cd <= 0.0 and dist >= SLAM_RANGE.x and dist <= SLAM_RANGE.y and elapsed() >= SLAM_FROM \
				and enemy.player != null:
			enemy.special_cd = SLAM_COOLDOWN
			var root = EnemyManager.scene_root()
			if root != null:
				var target: Vector3 = enemy.player.global_position
				target.y = EnemyManager.floor_y(target.x, target.z)
				GroundBlast.spawn(root, target, SLAM_RADIUS, SLAM_DELAY, enemy.damage * SLAM_DAMAGE_MULT, Color(1.0, 0.45, 0.2))
		return super.process_ai(delta, to_player, dist, effective_speed)

	func get_model_paths() -> Dictionary:
		return {
			"idle": "res://assets/models/entities/enemigos/goblins/idle_goblin_bruto.fbx",
			"walk": "res://assets/models/entities/enemigos/goblins/caminar_goblin_bruto.fbx",
			"tex": "res://assets/textures/enemigos/textura_goblin_bruto.png"
		}

	func get_knockback_resistance() -> float:
		return 0.2

class ZombieGoblinBehavior extends MeleeGoblinBehavior:
	func get_knockback_resistance() -> float:
		return 0.6

	func apply_config() -> void:
		# Flyweight: estado intrínseco compartido por todos los enemigos de este tipo
		EnemyTypeFlyweightFactory.get_flyweight(EnemyData.EnemyType.ZOMBIE_GOBLIN).apply_to(enemy)

	## Con menos de ENRAGE_HP de su vida el zombi se enfurece: ENRAGE_SPEED veces más rápido.
	func process_ai(delta: float, to_player: Vector3, dist: float, effective_speed: float) -> Vector3:
		var f := ENRAGE_SPEED if enemy.hp < enemy.max_hp * ENRAGE_HP and elapsed() >= LUNGE_FROM else 1.0
		return super.process_ai(delta, to_player, dist, effective_speed * f)

	func get_model_paths() -> Dictionary:
		return {
			"idle": "res://assets/models/entities/enemigos/goblins/goblin_idle_zombie.fbx",
			"walk": "res://assets/models/entities/enemigos/goblins/goblin_caminar_zombie.fbx",
			"tex": "res://assets/textures/enemigos/textura_zombie_goblin.png"
		}
