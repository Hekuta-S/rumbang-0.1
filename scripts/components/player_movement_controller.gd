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
	pass

func _spawn_footstep_puff(pos: Vector3, is_running: bool) -> void:
	if not player or not player.is_inside_tree(): return
	var parent = player.get_parent()
	if not parent or not is_instance_valid(parent): return

	var puff := CPUParticles3D.new()
	puff.amount = Quality.count(int(14 if is_running else 8))
	puff.lifetime = 0.45
	puff.one_shot = true
	puff.explosiveness = 0.95
	puff.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	puff.emission_sphere_radius = 0.2
	puff.direction = Vector3.UP
	puff.spread = 60.0
	puff.gravity = Vector3(0, 0.4, 0)
	puff.initial_velocity_min = 0.6
	puff.initial_velocity_max = 1.8 if is_running else 1.2
	puff.scale_amount_min = 0.25
	puff.scale_amount_max = 0.55 if is_running else 0.4

	var mesh := SphereMesh.new()
	mesh.radius = 0.05
	mesh.height = 0.1
	puff.mesh = mesh

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.85, 0.8, 0.7, 0.65)
	puff.material_override = mat

	var color_ramp := Gradient.new()
	color_ramp.set_color(0, Color(0.85, 0.8, 0.7, 0.7))
	color_ramp.add_point(1.0, Color(0.85, 0.8, 0.7, 0.0))
	puff.color_ramp = color_ramp

	parent.add_child(puff)
	puff.global_position = pos
	puff.restart()
	puff.emitting = true

	var tw = puff.create_tween()
	tw.tween_interval(0.55)
	tw.tween_callback(puff.queue_free)

func _spawn_jump_burst(pos: Vector3) -> void:
	if not player or not player.is_inside_tree(): return
	var parent = player.get_parent()
	if not parent or not is_instance_valid(parent): return

	var jump_puff := CPUParticles3D.new()
	jump_puff.amount = Quality.count(26)
	jump_puff.lifetime = 0.5
	jump_puff.one_shot = true
	jump_puff.explosiveness = 0.98
	jump_puff.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	jump_puff.emission_sphere_radius = 0.35
	jump_puff.direction = Vector3.UP
	jump_puff.spread = 85.0
	jump_puff.initial_velocity_min = 2.0
	jump_puff.initial_velocity_max = 4.8
	jump_puff.gravity = Vector3(0, -2.5, 0)
	jump_puff.scale_amount_min = 0.6
	jump_puff.scale_amount_max = 1.3

	var mesh := SphereMesh.new()
	mesh.radius = 0.12
	mesh.height = 0.24
	jump_puff.mesh = mesh

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.9, 0.85, 0.75, 0.75)
	jump_puff.material_override = mat

	var color_ramp := Gradient.new()
	color_ramp.set_color(0, Color(0.9, 0.85, 0.75, 0.8))
	color_ramp.add_point(1.0, Color(0.9, 0.85, 0.75, 0.0))
	jump_puff.color_ramp = color_ramp

	parent.add_child(jump_puff)
	jump_puff.global_position = pos
	jump_puff.restart()
	jump_puff.emitting = true

	var tw = jump_puff.create_tween()
	tw.tween_interval(0.6)
	tw.tween_callback(jump_puff.queue_free)

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
	_spawn_footstep_puff(player.global_position + Vector3(0, 0.05, 0), true)

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
	if k > 0.15:
		_spawn_jump_burst(player.global_position + Vector3(0, 0.05, 0))
	else:
		_spawn_footstep_puff(player.global_position + Vector3(0, 0.05, 0), true)
	AudioManager.play_at("step", player.global_position, -9.0 + 5.0 * k, 0.8 - 0.15 * k)
	if k > 0.5:
		AudioManager.play_at("impact_blunt", player.global_position, -14.0 + 6.0 * k, 0.55)

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
	if moving and player.is_on_floor():
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
			_spawn_footstep_puff(player.global_position + foot_offset + Vector3(0, 0.05, 0), is_running)
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
	dash_velocity = dash_velocity.move_toward(Vector3.ZERO, _dash_decel * delta)

	# Jump mechanic
	var jump_pressed: bool = Input.is_physical_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_SPACE) or Input.is_joy_button_pressed(0, JOY_BUTTON_A) or VirtualInput.is_jumping
	var jump_just_pressed: bool = jump_pressed and not _jump_was_pressed
	_jump_was_pressed = jump_pressed
	var jump_velocity: float = BASE_JUMP_VELOCITY * (player.stat_block.jump_velocity_mult() if player.stat_block else 1.0)

	if player.is_on_floor():
		_air_jumps_used = 0
		if jump_pressed and _can_pay_jump():
			player.velocity.y = jump_velocity
			_spawn_jump_burst(player.global_position + Vector3(0, 0.05, 0))
			# The animation controller will detect the jump automatically
	elif jump_just_pressed and player.stat_block and _air_jumps_used < player.stat_block.extra_jumps() and _can_pay_jump():
		# Salto en el aire (objetos con saltos extra)
		_air_jumps_used += 1
		player.velocity.y = jump_velocity * 0.92
		_spawn_jump_burst(player.global_position + Vector3(0, 0.05, 0))

	# Gravity / grounding
	if not player.is_on_floor():
		player.velocity.y -= gravity * delta
	else:
		if player.velocity.y <= 0:
			player.velocity.y = -1.0

	var was_floor: bool = player.is_on_floor()
	var fall_speed: float = -player.velocity.y
	player.move_and_slide()
	if not was_floor and player.is_on_floor() and fall_speed >= LAND_MIN_SPEED:
		_on_land(fall_speed)
