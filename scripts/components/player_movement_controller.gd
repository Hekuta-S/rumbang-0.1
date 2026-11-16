extends Node
class_name PlayerMovementController

var player: CharacterBody3D
var gravity: float = 22.0

var dust_particles: CPUParticles3D
var jump_particles: CPUParticles3D

const BASE_JUMP_VELOCITY := 8.5
## Pasada esta proporción de la velocidad base se considera "corriendo" (animación de carrera, pasos más rápidos).
const RUN_SPEED_RATIO := 1.2
var _jump_was_pressed: bool = false
## Dash de ataque: velocidad horizontal extra que se frena sola (DASH_DECEL m/s²).
const DASH_DECEL := 70.0
var _dash_decel: float = DASH_DECEL
var dash_velocity: Vector3 = Vector3.ZERO
## Hasta este instante (s) el modelo no gira hacia donde camina (p. ej. disparando el lanzallamas).
var face_lock_until: float = 0.0
## Velocidad de paso (× normal) mientras suena una animación de ataque
const ATTACK_MOVE_MULT := 0.12
const AIM_TURN_SPEED := 18.0   ## lo rápido que el cuerpo se gira hacia la mira
const FREE_TURN_SPEED := 14.0  ## supervivencia: lo rápido que el cuerpo se gira hacia donde camina
const SIDE_SPEED := 0.8        ## multiplicador de velocidad de lado
const BACK_SPEED := 0.68       ## y hacia atrás
## Mazmorra: de lado y hacia atrás solo se ANDA (nunca se corre): velocidad de paso y sin carrera del espadón/espada.
const SIDE_SPEED_DUNGEON := 0.5
const BACK_SPEED_DUNGEON := 0.45
## Espadón/espada/arco ya andan despacio (GAITS "walk"): de lado y atrás solo se frena un poco más. Con 0,5/0,45
## se iba a ~1 m/s, más lento que lo que piden sus clips de paso lateral y retroceso (los pies patinaban).
const SIDE_SPEED_GAIT := 0.8
const BACK_SPEED_GAIT := 0.7
## Para correr hay que ir hacia delante: mínimo de movimiento a lo largo de la mira (cos 60°).
const RUN_FORWARD_DOT := 0.5
## Corriendo, a partir de este coseno (≈45°, el joystick en diagonal) el cuerpo ya mira del todo hacia donde corre
## (ver handle_movement).
const RUN_FACE_FULL_DOT := 0.7
## Hasta este instante (s) se mueve a `slow_mult` de su velocidad (p. ej. lanzando polvos).
var slow_until: float = 0.0
var slow_mult: float = 1.0
var _air_jumps_used: int = 0

func _ready() -> void:
	player = get_parent() as CharacterBody3D
	_setup_particles()

var _step_distance_accum: float = 0.0
var _last_foot_side: float = 1.0

func _setup_particles() -> void:
	# Un frame después: la cámara del jugador ya existe.
	(func(): if is_instance_valid(player): FootDustVFX.prewarm(player)).call_deferred()

## Polvo de una pisada (FootDustVFX). `move_dir`: hacia dónde avanza; al correr el polvo sale hacia atrás.
func _spawn_footstep_puff(pos: Vector3, is_running: bool, move_dir: Vector3 = Vector3.ZERO) -> void:
	if not player or not player.is_inside_tree(): return
	FootDustVFX.step(player.get_parent(), pos, move_dir, is_running)

## Despegue del salto desde el suelo (o bocanada en el aire si `airborne`).
func _spawn_jump_burst(pos: Vector3, airborne: bool = false) -> void:
	if not player or not player.is_inside_tree(): return
	if airborne:
		FootDustVFX.air_jump(player.get_parent(), pos)
	else:
		FootDustVFX.takeoff(player.get_parent(), pos)

## ── Espadón: andar y correr ──
## Con el espadón se anda despacio. Tras GS_RUN_DELAY s moviéndose sin atacar, recibir daño ni rodar (note_combat
## reinicia la cuenta) se pasa a correr, más rápido que cualquier otra arma; el cambio de velocidad es progresivo.
const GS_WALK_MULT := 0.42           ## × velocidad base (4,8 m/s -> ~2 m/s)
const GS_RUN_MULT := 1.15            ## (-> ~5,5 m/s)
const GS_RUN_DELAY := 2.8            ## s moviéndose sin combate para empezar a correr
const GS_BLEND_RATE := 3.5           ## lo rápido que sube hacia la carrera (1/s); al bajar es inmediato
## La espada de una mano sigue la misma lógica, más ligera: anda algo más deprisa y arranca a correr antes.
## Por arma: walk/run = × velocidad base, delay = s sin combate para correr.
const GAITS := {
	WeaponData.WeaponType.GREATSWORD: {"walk": GS_WALK_MULT, "run": GS_RUN_MULT, "delay": GS_RUN_DELAY},
	WeaponData.WeaponType.SWORD: {"walk": 0.45, "run": 1.1, "delay": 2.2},
	WeaponData.WeaponType.KATANA: {"walk": 0.5, "run": 1.15, "delay": 1.8},
	# Arco: anda apuntando (clips del arco) y, tras un rato sin disparar, corre con la carrera del personaje
	WeaponData.WeaponType.BOW: {"walk": 0.4, "run": 1.0, "delay": 2.0},
}
var gs_calm := 0.0                   ## s moviéndose sin combate
var _gs_mult := GS_WALK_MULT
## Avance del clip de ataque en curso (root motion, lo pone PlayerAnimationController): se suma a la velocidad.
var root_motion_velocity := Vector3.ZERO

func _gs_active() -> bool:
	return GameData.game_mode == "dungeon" and player != null and GAITS.has(player.current_weapon())

## Andar/correr del arma en la mano (o el del espadón si no tiene).
func _gait() -> Dictionary:
	return GAITS.get(player.current_weapon() if player else -1, GAITS[WeaponData.WeaponType.GREATSWORD])

## Un golpe, un daño recibido, una parada o una rodada: el espadón (o la espada) vuelve a andar.
func note_combat() -> void:
	gs_calm = 0.0
	_gs_mult = float(_gait()["walk"])

## ¿Va corriendo con el espadón o la espada? (ha pasado el tiempo sin combate y ya va deprisa)
func gs_running() -> bool:
	if not _gs_active():
		return false
	var g := _gait()
	return gs_calm >= float(g["delay"]) and _gs_mult > (float(g["walk"]) + float(g["run"])) * 0.5

## `forward`: va hacia delante respecto a la mira; de lado o atrás vuelve a andar (la cuenta de calma se conserva).
func _update_gs_gait(delta: float, moving: bool, forward: bool = true) -> void:
	if not _gs_active():
		gs_calm = 0.0
		_gs_mult = GS_WALK_MULT
		return
	var g := _gait()
	var walk := float(g["walk"])
	var run := float(g["run"])
	if moving and player.is_on_floor():
		gs_calm += delta
	var target := run if (gs_calm >= float(g["delay"]) and moving and forward) else walk
	if target < _gs_mult:
		_gs_mult = target
	else:
		_gs_mult = move_toward(_gs_mult, target, GS_BLEND_RATE * delta * (run - walk))

## ¿Va corriendo (no andando) a esta velocidad? Con espadón/espada/arco lo decide su modo de carrera; con el
## resto, la velocidad frente al umbral del clip de andar.
func _runs_now(speed: float) -> bool:
	if _gs_active():
		return gs_running()
	return speed > PlayerAnimationController.WALK_TO_RUN

## Impulso horizontal (lunge de un ataque). Durante el dash el control se reduce.
func add_dash(v: Vector3, decel: float = DASH_DECEL) -> void:
	v.y = 0.0
	dash_velocity = v
	_dash_decel = decel
	_spawn_footstep_puff(player.global_position + Vector3(0, 0.05, 0), true, v)

const DODGE_COOLDOWN: float = 0.75
## La voltereta duraba 0,32 s y se veía acelerada; ahora más lenta pero recorre lo mismo (~2,3 m con
## roll_speed 18): el impulso se frena con su propia deceleración para acabar justo al terminar el giro.
const DODGE_DURATION: float = 0.5
const DODGE_IFRAMES: float = 0.32
const DODGE_BASE_DISTANCE: float = 2.3  # con roll_speed = 18 (DASH_DECEL clásico: 18²/(2·70))
var _dodge_timer: float = 0.0
var _dodge_cooldown_timer: float = 0.0
## Esquiva perfecta: un golpe que llega en los primeros PERFECT_WINDOW s de la voltereta (con i-frames).
const PERFECT_WINDOW: float = 0.25
const PERFECT_ENERGY: float = 25.0      ## energía que devuelve (paga la voltereta y algo más)
const PERFECT_TEXT_COLOR := Color(0.45, 0.85, 1.0)
var _perfect_used := false
## Aterrizaje: a partir de esta velocidad de caída (m/s) se nota (squash, polvo, cámara, golpe seco).
const LAND_MIN_SPEED := 6.0
const LAND_HEAVY_SPEED := 16.0
## Sonido de pasos: uno por pisada (los puffs de polvo van cada dos).
const STEP_VOLUME_WALK := -17.0
const STEP_VOLUME_RUN := -12.0
var _step_sfx_accum := 0.0

func is_dodging() -> bool:
	return _dodge_timer > 0.0

func perform_dodge() -> void:
	if _dodge_cooldown_timer > 0.0 or not player:
		return
	var anim = player.get("animation_controller")
	if anim and not anim.can_cancel_for_dodge():
		return
	var res = player.get("resources")
	if res and not res.spend_energy(PlayerResources.DODGE_COST):
		return
	_end_slide()
	_dodge_cooldown_timer = DODGE_COOLDOWN
	_dodge_timer = DODGE_DURATION
	_perfect_used = false
	note_combat()
	
	var inp: Vector2 = player.input_controller.get_movement_vector() if player.input_controller else Vector2.ZERO
	var dodge_dir := Vector3.ZERO
	if inp.length_squared() > 0.01 and player.spring_arm:
		var cam_basis: Basis = player.spring_arm.global_transform.basis
		dodge_dir = (-cam_basis.z * -inp.y + cam_basis.x * inp.x)
	elif player.mesh:
		dodge_dir = -player.mesh.global_transform.basis.z
	dodge_dir.y = 0.0
	if dodge_dir.length_squared() < 0.001:
		dodge_dir = Vector3.FORWARD
	dodge_dir = dodge_dir.normalized()

	if player.mesh:
		player.mesh.rotation.y = atan2(-dodge_dir.x, -dodge_dir.z)

	var roll_spd: float = float(player.get("roll_speed")) if player.get("roll_speed") else 18.0
	# Frenado uniforme durante toda la voltereta: v0 = 2d/T, decel = v0/T
	var dist: float = DODGE_BASE_DISTANCE * roll_spd / 18.0
	var v0: float = 2.0 * dist / DODGE_DURATION
	add_dash(dodge_dir * v0, v0 / DODGE_DURATION)

	if player.health_comp and player.health_comp.has_method("set_invincibility"):
		player.health_comp.set_invincibility(DODGE_IFRAMES)

	var parry = player.get("parry_controller")
	if parry:
		parry.cancel()
	if player.combat_controller:
		if player.combat_controller.spear_charge >= 0.0:
			player.combat_controller.spear_charge = -1.0
			player.combat_controller._stop_charge_shake()
			if player.weapon_visuals:
				player.weapon_visuals.set_spear_charge(0.0)
	if anim:
		anim.cancel_action()
		anim.play_roll(DODGE_DURATION)

	AudioManager.play("dodge", -6.0, randf_range(0.95, 1.05))
	if player.has_method("notify_equipment"):
		player.notify_equipment("dodge")
	# (Los fantasmas de la voltereta, HitFeedback.afterimages, quedan para la habilidad de una armadura.)

## Un golpe llegó durante la invulnerabilidad: si fue al principio de la voltereta, es una esquiva
## perfecta (una por voltereta). Devuelve true si lo fue.
func try_perfect_dodge() -> bool:
	if not is_dodging() or _perfect_used or DODGE_DURATION - _dodge_timer > PERFECT_WINDOW:
		return false
	_perfect_used = true
	var res = player.get("resources")
	if res:
		res.add_energy(PERFECT_ENERGY)
	HitFeedback.perfect_dodge(player)
	EquipmentPickup.toast(player, "¡ESQUIVA PERFECTA!", PERFECT_TEXT_COLOR)
	return true

## Aterrizaje tras una caída a `speed` m/s: el cuerpo se aplasta, polvo, la cámara baja y un golpe seco.
func _on_land(speed: float) -> void:
	var k := clampf((speed - LAND_MIN_SPEED) / (LAND_HEAVY_SPEED - LAND_MIN_SPEED), 0.0, 1.0)
	if player.mesh:
		HitFeedback.squash(player.mesh, 0.08 + 0.14 * k, 0.24)
	HitFeedback.kick(Vector3.DOWN, 0.2 + 0.45 * k)
	FootDustVFX.land(player.get_parent(), player.global_position + Vector3(0, 0.05, 0), k)
	AudioManager.play_at("step", player.global_position, -9.0 + 5.0 * k, 0.8 - 0.15 * k)
	if k > 0.5:
		AudioManager.play_at("impact_blunt", player.global_position, -14.0 + 6.0 * k, 0.55)

## ── Golpe de caída (mapa con mesetas) ──
## Bajar de un salto desde SLAM_MIN_DROP m o más por encima del suelo donde caes, con una caída de
## SLAM_MIN_FALL m desde lo más alto, revienta el suelo: daño en área (parte de la vida del enemigo, menos a
## élites) y empujón. Los saltos normales en llano (y el doble salto) no llegan.
const SLAM_MIN_DROP := 2.0
const SLAM_MIN_FALL := 3.0
const SLAM_COLOR := Color(1.0, 0.7, 0.3)
var _air_start_y: float = 0.0
var _air_peak_y: float = 0.0
var _was_airborne: bool = false
## Vuelo de una runa lanzadora: velocidad horizontal fija hasta aterrizar (el control solo la corrige un poco).
var _launch_vel: Vector3 = Vector3.ZERO
var _launch_air: bool = false
const LAUNCH_STEER := 0.15

## Radio, fracción de vida (normales) y daño mínimo del golpe tras caer `fall` m. Pura.
static func slam_params(fall: float) -> Dictionary:
	return {"radius": clampf(2.5 + 0.45 * fall, 3.5, 8.0), "frac": clampf(0.2 + 0.05 * fall, 0.3, 0.75),
		"min_damage": 8.0 + 4.0 * fall, "knockback": clampf(6.0 + 1.2 * fall, 8.0, 18.0)}

## Golpe de caída en `pos`. Devuelve cuántos enemigos alcanza.
func ground_slam(pos: Vector3, fall: float) -> int:
	var prm := slam_params(fall)
	var radius: float = prm["radius"]
	var mult: float = player.stat_block.damage_mult() if player and player.stat_block else 1.0
	var hits := 0
	HitFeedback.weapon_tag = -1
	for e in EnemyRegistry.all().duplicate():
		if not (e is EnemyData) or e.recycled:
			continue
		var to_e: Vector3 = e.global_position - pos
		if absf(to_e.y) > 2.5:
			continue
		to_e.y = 0.0
		var d := to_e.length()
		if d > radius:
			continue
		var frac: float = prm["frac"] * (0.35 if e.xp_reward >= XpCurve.XP_ELITE else 1.0)
		var dmg := maxf(float(prm["min_damage"]) * mult, e.max_hp * frac) * lerpf(1.0, 0.6, d / radius)
		var dir := to_e / d if d > 0.05 else Vector3.FORWARD
		e.take_damage(dmg, dir * float(prm["knockback"]))
		hits += 1
	if player and player.is_inside_tree():
		var scene := player.get_parent()
		NecroVFX.shockwave(scene, pos + Vector3(0, 0.1, 0), radius * 2.0, SLAM_COLOR)
		FootDustVFX.land(scene, pos + Vector3(0, 0.05, 0), 1.0)
		AudioManager.play_at("explosion", pos, -6.0, 0.7)
		HitFeedback.shake(0.25 + 0.03 * fall)
		if hits > 0:
			HitFeedback.slowmo(0.5, 0.12)
	return hits

## Runa lanzadora: sale despedido con `vel` (la vertical la gasta la gravedad; la horizontal se mantiene).
func launch(vel: Vector3) -> void:
	player.velocity.y = vel.y
	_launch_vel = Vector3(vel.x, 0.0, vel.z)
	_launch_air = false
	_spawn_jump_burst(player.global_position + Vector3(0, 0.05, 0))

func is_launched() -> bool:
	return _launch_vel != Vector3.ZERO

## ── Deslizamiento (solo supervivencia), estilo CoD/Apex ──
## Ctrl (o la cruceta abajo) corriendo, o en una cuesta abajo, lanza un deslizamiento: arranca con un
## empujón, la cuesta abajo lo acelera (cuesta arriba lo frena), el roce lo para en llano. Soltar la tecla o
## saltar lo corta (saltando conserva el impulso). A su paso aparta a los enemigos hacia los lados, más
## fuerte cuanto más rápido va. La animación (mikeura_slide) solo la tiene Mikeura por ahora.
const SLIDE_KEY := KEY_CTRL
const SLIDE_JOY := JOY_BUTTON_DPAD_DOWN
const SLIDE_MIN_SPEED := 6.0          ## m/s horizontales para empezar en llano
const SLIDE_DOWNHILL_START := 0.12    ## pendiente a favor (m por m) con la que empieza aunque vaya despacio
const SLIDE_BOOST := 1.3              ## × velocidad al empezar
const SLIDE_MIN_START := 9.0
const SLIDE_MAX_SPEED := 20.0
const SLIDE_FRICTION := 6.5           ## m/s² de frenado propio
const SLIDE_SLOPE_GAIN := 0.9         ## fracción de la gravedad a lo largo de la cuesta
const SLIDE_END_SPEED := 3.0
const SLIDE_MAX_TIME := 3.5
const SLIDE_STEER := 1.6              ## rad/s de giro hacia donde se empuja el stick
const SLIDE_COOLDOWN := 0.4
const SLIDE_AIR_GRACE := 0.18         ## s en el aire (un bache) antes de cortar el deslizamiento
const SLIDE_JUMP_DECEL := 9.0         ## frenado del impulso que conserva al saltar o caer de un borde
const SLIDE_PUSH_RADIUS := 1.7
const SLIDE_PUSH_MIN_SPEED := 3.5
const SLIDE_PUSH_GAIN := 1.15         ## fuerza del empujón por m/s de deslizamiento
const SLIDE_PUSH_MAX := 22.0
const SLIDE_PUSH_STAGGER := 0.45      ## s que el enemigo apartado queda frenado
## Beta: al empezar la partida el deslizamiento es más flojo (más corto, más lento, con espera y casi sin
## empujón) y llega a su fuerza completa a los SLIDE_NERF_RAMP_S s: se "desbloquea" jugando.
const SLIDE_NERF_START := 0.55        ## fracción de la fuerza de deslizamiento con la partida recién empezada
const SLIDE_NERF_RAMP_S := 180.0      ## s de partida hasta llegar al 100 %
const SLIDE_NERF_COOLDOWN := 1.6      ## s extra de espera entre deslizamientos al empezar (se va a 0)
## Para los tests: fuerza el reloj de la partida (<0 = el de GameState).
var slide_elapsed_override := -1.0
var _sliding := false
var _slide_vel := Vector3.ZERO
var _slide_t := 0.0
var _slide_air := 0.0
var _slide_cd := 0.0
var _slide_was_pressed := false
var _slide_pushed := {}               ## enemigos ya apartados en este deslizamiento
var _slide_dust_t := 0.0
## Para los tests: fuerza la tecla de deslizar como pulsada.
var slide_input_override := false
var _slide_power_now := 1.0           ## fuerza (slide_power) con la que empezó el deslizamiento en curso

func is_sliding() -> bool:
	return _sliding

func _slide_pressed() -> bool:
	return slide_input_override or VirtualInput.is_sliding or Input.is_physical_key_pressed(SLIDE_KEY) \
		or Input.is_joy_button_pressed(0, SLIDE_JOY)

## Pendiente del suelo bajo `pos` (m de subida por m, en x y z); cero sin mapa con relieve.
static func ground_gradient(pos: Vector3) -> Vector2:
	if not EnemyMotion.available():
		return Vector2.ZERO
	if pos.y - EnemyMotion.height_at(pos.x, pos.z) > 0.8:
		return Vector2.ZERO                      # sobre un puente (u otra cosa por encima del relieve)
	var hx := EnemyMotion.height_at(pos.x + 0.5, pos.z) - EnemyMotion.height_at(pos.x - 0.5, pos.z)
	var hz := EnemyMotion.height_at(pos.x, pos.z + 0.5) - EnemyMotion.height_at(pos.x, pos.z - 0.5)
	return Vector2(hx, hz)

## Aceleración horizontal (m/s²) que da la cuesta: a favor si se baja. Pura.
static func slope_accel(grad: Vector2, g: float) -> Vector3:
	var a := -grad / sqrt(1.0 + grad.length_squared()) * g * SLIDE_SLOPE_GAIN
	return Vector3(a.x, 0.0, a.y)

## Velocidad nueva tras `delta` s deslizando a `vel` con pendiente `grad`; `friction` multiplica el roce
## (barro de un tobogán: ProceduralMap.CHUTE_FRICTION). Pura (la usan los tests).
static func slide_step(vel: Vector3, grad: Vector2, g: float, delta: float, friction: float = 1.0) -> Vector3:
	var v := vel + slope_accel(grad, g) * delta
	var spd := v.length()
	if spd > 0.001:
		v = v / spd * clampf(spd - SLIDE_FRICTION * friction * delta, 0.0, SLIDE_MAX_SPEED)
	return v

## Mapa con toboganes (o null).
var _map_ref: Node = null
func _proc_map() -> Node:
	if _map_ref == null or not is_instance_valid(_map_ref):
		_map_ref = get_tree().get_first_node_in_group("procedural_map") if is_inside_tree() else null
	return _map_ref if _map_ref and _map_ref.has_method("chute_dir_at") else null

## Dirección de bajada del tobogán bajo el jugador (Vector2.ZERO si no está en uno, o va por encima).
func _chute_here() -> Vector2:
	var m := _proc_map()
	if m == null:
		return Vector2.ZERO
	var pos := player.global_position
	if pos.y - m.get_height_at(pos.x, pos.z) > 0.8:
		return Vector2.ZERO
	return m.chute_dir_at(pos.x, pos.z)

## Fuerza del deslizamiento a los `elapsed` s de partida: SLIDE_NERF_START → 1. Pura.
static func slide_power(elapsed: float) -> float:
	return lerpf(SLIDE_NERF_START, 1.0, clampf(elapsed / SLIDE_NERF_RAMP_S, 0.0, 1.0))

func _slide_strength() -> float:
	var t := slide_elapsed_override if slide_elapsed_override >= 0.0 else GameState.get_instance().elapsed_time
	return slide_power(t)

## Velocidad que basta para que un tobogán te lleve solo (cuesta abajo).
const CHUTE_AUTO_SPEED := 3.0

## ¿Puede empezar a deslizarse yendo a `vel` (horizontal) con pendiente `grad`? Pura.
static func can_start_slide(vel: Vector3, grad: Vector2) -> bool:
	var flat := Vector2(vel.x, vel.z)
	if flat.length() >= SLIDE_MIN_SPEED:
		return true
	if flat.length() < 1.0:
		return false
	return -grad.dot(flat.normalized()) >= SLIDE_DOWNHILL_START

## Fuerza del empujón a los enemigos a `speed` m/s (0 si va demasiado lento). Pura.
static func slide_push_force(speed: float) -> float:
	if speed < SLIDE_PUSH_MIN_SPEED:
		return 0.0
	return minf(speed * SLIDE_PUSH_GAIN, SLIDE_PUSH_MAX)

## Dirección y fuerza del empujón: sobre todo hacia el lado en que está el enemigo, algo hacia delante. Pura.
static func slide_push_vector(dir: Vector3, to_e: Vector3, force: float) -> Vector3:
	var side := Vector3(-dir.z, 0.0, dir.x)
	var s := signf(side.dot(to_e))
	if s == 0.0:
		s = 1.0
	return (side * s * 0.85 + dir * 0.4).normalized() * force

## Aterrizar con la tecla de deslizar pulsada (pulsada en el aire): entra deslizando, y parte de la
## velocidad de caída pasa al deslizamiento (como en Apex). Con caídas fuertes basta con estar quieto.
const SLIDE_LAND_FALL_GAIN := 0.4     ## m/s de deslizamiento por m/s de caída
const SLIDE_LAND_MIN_FALL := 6.0      ## caída mínima (m/s) para que cuente como aterrizaje
const SLIDE_LAND_STILL_FALL := 11.0   ## caída con la que se desliza aunque no se moviera en horizontal
var _slide_queued := false            ## Ctrl pulsado en el aire: deslizar al tocar suelo

## Velocidad de un deslizamiento que empieza al aterrizar yendo a `flat` m/s tras caer a `fall` m/s. Pura.
static func landing_slide_speed(flat: float, fall: float) -> float:
	return clampf(maxf(flat * SLIDE_BOOST, SLIDE_MIN_START) + maxf(fall, 0.0) * SLIDE_LAND_FALL_GAIN, 0.0, SLIDE_MAX_SPEED)

## ¿Aterrizando a `fall` m/s con velocidad horizontal `flat` se puede entrar deslizando? Pura.
static func can_landing_slide(flat: float, fall: float) -> bool:
	if fall < SLIDE_LAND_MIN_FALL:
		return false
	return flat >= 1.0 or fall >= SLIDE_LAND_STILL_FALL

func _try_start_slide(land_fall: float = -1.0) -> void:
	if GameData.game_mode != "survival" or _sliding or _slide_cd > 0.0 or not player.is_on_floor():
		return
	if is_dodging() or is_launched():
		return
	var flat := Vector3(player.velocity.x, 0.0, player.velocity.z)
	var grad := ground_gradient(player.global_position)
	var landing := land_fall >= 0.0
	if landing:
		if not can_landing_slide(flat.length(), land_fall):
			return
	elif not can_start_slide(flat, grad):
		return
	var dir: Vector3 = flat.normalized() if flat.length() >= 1.0 else (-player.mesh.global_transform.basis.z if player.mesh else Vector3.FORWARD)
	dir.y = 0.0
	dir = dir.normalized()
	var downhill := maxf(-grad.dot(Vector2(dir.x, dir.z)), 0.0)
	var power := _slide_strength()
	var spd := clampf(((landing_slide_speed(flat.length(), land_fall) if landing else maxf(flat.length() * SLIDE_BOOST, SLIDE_MIN_START)) + downhill * 6.0) * power, 0.0, SLIDE_MAX_SPEED * power)
	_slide_power_now = power
	_sliding = true
	_slide_vel = dir * spd
	_slide_t = 0.0
	_slide_air = 0.0
	_slide_pushed.clear()
	dash_velocity = Vector3.ZERO
	var anim = player.get("animation_controller")
	if anim and anim.has_method("play_slide"):
		anim.play_slide()
	HitFeedback.kick(Vector3.DOWN, 0.25)
	AudioManager.play_at("dodge", player.global_position, -5.0, 0.7)
	_spawn_footstep_puff(player.global_position + Vector3(0, 0.05, 0), true, _slide_vel)

## Termina el deslizamiento; `carry` conserva el impulso (salto o caída por un borde).
func _end_slide(carry: bool = false) -> void:
	if not _sliding:
		return
	_sliding = false
	_slide_cd = SLIDE_COOLDOWN + SLIDE_NERF_COOLDOWN * (1.0 - _slide_power_now) / (1.0 - SLIDE_NERF_START)
	if carry:
		add_dash(_slide_vel, SLIDE_JUMP_DECEL)
	_slide_vel = Vector3.ZERO
	var anim = player.get("animation_controller")
	if anim and anim.has_method("stop_slide"):
		anim.stop_slide()

func _update_slide(delta: float, wish: Vector3) -> void:
	_slide_t += delta
	if not player.is_on_floor():
		_slide_air += delta
		if _slide_air > SLIDE_AIR_GRACE:
			_end_slide(true)                    # se cayó por un borde: sigue con el impulso
			return
	else:
		_slide_air = 0.0
	var chute := _chute_here()
	_slide_vel = slide_step(_slide_vel, ground_gradient(player.global_position), gravity, delta, ProceduralMap.CHUTE_FRICTION if chute != Vector2.ZERO else 1.0)
	# Un poco de giro hacia donde se empuja el stick
	if wish.length_squared() > 0.01 and _slide_vel.length_squared() > 0.01:
		var cur := atan2(_slide_vel.x, _slide_vel.z)
		var want := atan2(wish.x, wish.z)
		var turn := clampf(wrapf(want - cur, -PI, PI), -SLIDE_STEER * delta, SLIDE_STEER * delta)
		_slide_vel = _slide_vel.rotated(Vector3.UP, turn)
	var spd := _slide_vel.length()
	# En un tobogán sigue aunque se suelte la tecla (y sin tope de tiempo)
	if spd < SLIDE_END_SPEED or (chute == Vector2.ZERO and (_slide_t > SLIDE_MAX_TIME * _slide_power_now or not _slide_pressed())):
		_end_slide()
		return
	player.velocity.x = _slide_vel.x
	player.velocity.z = _slide_vel.z
	if player.mesh:
		player.mesh.rotation.y = lerp_angle(player.mesh.rotation.y, atan2(-_slide_vel.x, -_slide_vel.z), 12.0 * delta)
	_slide_push(spd)
	_slide_dust_t -= delta
	if _slide_dust_t <= 0.0:
		_slide_dust_t = 0.07
		_spawn_footstep_puff(player.global_position + Vector3(0, 0.05, 0), true, _slide_vel)

## Aparta hacia los lados a los enemigos que hay delante (una vez a cada uno por deslizamiento).
func _slide_push(speed: float) -> void:
	var force := slide_push_force(speed) * _slide_power_now * _slide_power_now      # casi sin empujón al empezar
	if force <= 0.0:
		return
	var pos := player.global_position
	var dir := _slide_vel / speed
	for e in EnemyRegistry.all():
		if not (e is EnemyData) or e.recycled or _slide_pushed.has(e.get_instance_id()):
			continue
		var to_e: Vector3 = e.global_position - pos
		if absf(to_e.y) > 1.5:
			continue
		to_e.y = 0.0
		var d := to_e.length()
		if d > SLIDE_PUSH_RADIUS * (1.0 + (e.scale.x - 1.0) * 0.5) or (d > 0.3 and to_e.dot(dir) < -0.2 * d):
			continue
		_slide_pushed[e.get_instance_id()] = true
		e.knockback_velocity = slide_push_vector(dir, to_e, force) * e.knockback_resistance
		e.slow_multiplier = minf(e.slow_multiplier, 0.25)
		e.slow_timer = maxf(e.slow_timer, SLIDE_PUSH_STAGGER)
		e.is_alerted = true
		AudioManager.play_at("impact_blunt", e.global_position, -12.0, randf_range(0.9, 1.1))
		HitFeedback.shake(0.05)

## Saltar cuesta energía (solo mazmorra); sin ella no se despega del suelo.
func _can_pay_jump() -> bool:
	var res = player.get("resources")
	return res == null or res.spend_energy(PlayerResources.JUMP_COST)

func handle_movement(delta: float) -> void:
	if not player: return
	_dodge_timer = maxf(_dodge_timer - delta, 0.0)
	_dodge_cooldown_timer = maxf(_dodge_cooldown_timer - delta, 0.0)

	var inp: Vector2 = player.input_controller.get_movement_vector()
	var cam_basis: Basis = player.spring_arm.global_transform.basis
	var fwd := -cam_basis.z
	var right := cam_basis.x
	var wish := fwd * -inp.y + right * inp.x
	wish.y = 0.0
	
	var stat_move: float = player.stat_block.move_mult() if player.stat_block else 1.0
	var current_speed: float = player.move_speed * stat_move * (1.3 if player.is_berserk else 1.0) * (1.35 if player.dust_speed_boost_timer > 0 else 1.0)
	var parry = player.get("parry_controller")
	if parry and parry.is_active():
		current_speed *= PlayerParryController.MOVE_MULT     # en guardia se avanza despacio
	
	# Ya no hay botón de correr: la animación de carrera la decide PlayerAnimationController
	# cuando la velocidad supera cierto umbral (mejoras, objetos, berserk...).
	var is_running: bool = current_speed > player.move_speed * RUN_SPEED_RATIO
	if Time.get_ticks_msec() / 1000.0 < slow_until:
		current_speed *= slow_mult
	# Cargando el lanzamiento de la espalanza: se mueve más lento
	if player.combat_controller and player.combat_controller.spear_charge >= 0.0:
		current_speed *= 0.5
	# Durante un golpe el cuerpo está plantado: el clip mueve las piernas en su sitio, así que caminar
	# a velocidad normal lo haría patinar (flotar sobre el suelo). Solo avanza el impulso del propio golpe.
	var attacking: bool = GameData.game_mode == "dungeon" and player.animation_controller != null 		and player.animation_controller.is_attacking()
	if attacking:
		current_speed *= ATTACK_MOVE_MULT

	var moving = wish.length_squared() > 0.0001
	var aim_fwd := Vector3(fwd.x, 0.0, fwd.z).normalized()
	var forward: bool = moving and wish.normalized().dot(aim_fwd) > RUN_FORWARD_DOT
	_update_gs_gait(delta, moving, forward)
	if _gs_active():
		current_speed *= _gs_mult
	if moving and player.is_on_floor() and not _sliding:
		var dist_step = current_speed * delta
		_step_distance_accum += dist_step
		var step_interval = 0.9 if is_running else 1.4
		_step_sfx_accum += dist_step
		if _step_sfx_accum >= step_interval * 0.5:
			_step_sfx_accum = 0.0
			AudioManager.play_at("step", player.global_position, STEP_VOLUME_RUN if is_running else STEP_VOLUME_WALK,
				randf_range(0.9, 1.08) * (1.08 if is_running else 1.0))
		if _step_distance_accum >= step_interval:
			_step_distance_accum = 0.0
			_last_foot_side = -_last_foot_side
			var foot_offset = right * (_last_foot_side * 0.25)
			_spawn_footstep_puff(player.global_position + foot_offset + Vector3(0, 0.05, 0), is_running, wish)
	else:
		_step_distance_accum = 0.0
		_step_sfx_accum = 0.0

	var d := 0.0
	if moving:
		wish = wish.normalized()
		# Mirando siempre a la mira: de lado y hacia atrás se avanza más despacio que de frente
		var flat_fwd := Vector3(fwd.x, 0.0, fwd.z).normalized()
		d = wish.dot(flat_fwd)
		# Supervivencia: movimiento libre (el personaje mira hacia donde camina), misma velocidad en todas direcciones
		if GameData.game_mode == "dungeon":
			var side := SIDE_SPEED_GAIT if _gs_active() else SIDE_SPEED_DUNGEON
			var back := BACK_SPEED_GAIT if _gs_active() else BACK_SPEED_DUNGEON
			current_speed *= lerpf(side, 1.0, d) if d >= 0.0 else lerpf(side, back, -d)
	else:
		wish = Vector3.ZERO
	# Tercera persona convencional: el personaje mira SIEMPRE hacia la mira (el frente de la cámara), se mueva
	# o no; se desplaza en cualquier dirección sin girarse. Solo manda otra orientación mientras dura una
	# rodada, un golpe o un remate (face_lock_until), que fijan la suya.
	if not attacking and not is_dodging() and Time.get_ticks_msec() / 1000.0 >= face_lock_until:
		if GameData.game_mode == "dungeon":
			var yaw := atan2(-fwd.x, -fwd.z)
			# Corriendo en diagonal el cuerpo se gira hacia donde corre: con el cuerpo de frente a la mira, el clip
			# de carrera mezclado con las piernas del paso lateral se veía como un cangrejo patinando. Andando
			# (o casi de lado, d <= RUN_FORWARD_DOT) sigue mirando a la mira y usa el paso lateral.
			var w := smoothstep(RUN_FORWARD_DOT, RUN_FACE_FULL_DOT, d) if moving and _runs_now(current_speed) else 0.0
			if w > 0.0:
				yaw = lerp_angle(yaw, atan2(-wish.x, -wish.z), w)
			player.mesh.rotation.y = lerp_angle(player.mesh.rotation.y, yaw, AIM_TURN_SPEED * delta)
		elif moving:
			# Supervivencia: movimiento libre como en el salon. El cuerpo gira hacia donde camina;
			# parado conserva su orientacion. Al atacar se gira hacia la mira (PlayerCombatController).
			player.mesh.rotation.y = lerp_angle(player.mesh.rotation.y, atan2(-wish.x, -wish.z), FREE_TURN_SPEED * delta)
		
	var dashing := dash_velocity.length_squared() > 1.0
	var control := 0.25 if dashing else 1.0
	player.velocity.x = wish.x * current_speed * control + dash_velocity.x + root_motion_velocity.x
	player.velocity.z = wish.z * current_speed * control + dash_velocity.z + root_motion_velocity.z
	# Deslizamiento (supervivencia): Ctrl recién pulsado; mientras dura, manda su velocidad
	_slide_cd = maxf(_slide_cd - delta, 0.0)
	var slide_down := _slide_pressed()
	if not player.is_on_floor():
		# En el aire: pulsar (o mantener) la tecla deja el deslizamiento listo para el aterrizaje
		if slide_down and not _sliding:
			_slide_queued = true
		elif not slide_down:
			_slide_queued = false
	elif slide_down and not _slide_was_pressed:
		_try_start_slide()
	elif not _sliding and GameData.game_mode == "survival" and player.is_on_floor():
		# Tobogán: entrar cuesta abajo con algo de velocidad te tumba y te lleva
		var cd := _chute_here()
		if cd != Vector2.ZERO and Vector2(player.velocity.x, player.velocity.z).dot(cd) > CHUTE_AUTO_SPEED:
			_try_start_slide()
	_slide_was_pressed = slide_down
	if _sliding:
		_update_slide(delta, wish)
	if _launch_vel != Vector3.ZERO:
		if player.is_on_floor() and _launch_air:
			_launch_vel = Vector3.ZERO                 # aterrizó
		else:
			player.velocity.x = _launch_vel.x + wish.x * current_speed * LAUNCH_STEER
			player.velocity.z = _launch_vel.z + wish.z * current_speed * LAUNCH_STEER
	dash_velocity = dash_velocity.move_toward(Vector3.ZERO, _dash_decel * delta)

	# Jump mechanic
	var jump_pressed: bool = Input.is_physical_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_SPACE) or Input.is_joy_button_pressed(0, JOY_BUTTON_A) or VirtualInput.is_jumping
	var jump_just_pressed: bool = jump_pressed and not _jump_was_pressed
	_jump_was_pressed = jump_pressed
	var jump_velocity: float = BASE_JUMP_VELOCITY * (player.stat_block.jump_velocity_mult() if player.stat_block else 1.0)

	if player.is_on_floor() and _launch_vel == Vector3.ZERO:
		_air_jumps_used = 0
		if jump_pressed and _can_pay_jump():
			if _sliding:
				_end_slide(true)                # salto deslizando: conserva el impulso
			player.velocity.y = jump_velocity
			_spawn_jump_burst(player.global_position + Vector3(0, 0.05, 0))
			# The animation controller will detect the jump automatically
	elif jump_just_pressed and player.stat_block and _air_jumps_used < player.stat_block.extra_jumps() and _can_pay_jump():
		# Salto en el aire (objetos con saltos extra)
		_air_jumps_used += 1
		player.velocity.y = jump_velocity * 0.92
		_spawn_jump_burst(player.global_position + Vector3(0, 0.05, 0), true)

	# Gravity / grounding
	if not player.is_on_floor():
		player.velocity.y -= gravity * delta
	elif player.velocity.y <= 0:
		player.velocity.y = -1.0

	var was_floor: bool = player.is_on_floor()
	var fall_speed: float = -player.velocity.y
	player.move_and_slide()
	var gy := player.global_position.y
	if not player.is_on_floor():
		if not _was_airborne:
			_was_airborne = true
			_air_start_y = gy
			_air_peak_y = gy
		_air_peak_y = maxf(_air_peak_y, gy)
		if _launch_vel != Vector3.ZERO:
			_launch_air = true
	elif _was_airborne:
		_was_airborne = false
		if _air_start_y - gy >= SLAM_MIN_DROP and _air_peak_y - gy >= SLAM_MIN_FALL and EnemyMotion.has_relief():
			ground_slam(player.global_position, _air_peak_y - gy)
		if _slide_queued and _slide_pressed():
			_slide_cd = 0.0                        # el deslizamiento al aterrizar no espera a la recarga
			_try_start_slide(fall_speed)
		_slide_queued = false
	if not was_floor and player.is_on_floor() and fall_speed >= LAND_MIN_SPEED:
		_on_land(fall_speed)
