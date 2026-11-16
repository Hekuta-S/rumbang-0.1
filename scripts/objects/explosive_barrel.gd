class_name ExplosiveBarrel
extends StaticBody3D

## Barril explosivo del mapa de supervivencia (ProceduralMap lo pone en el borde de las mesetas, arriba de
## los toboganes y en laderas). Golpearlo (MeleeHitbox, grupo "destructibles"), chocar con él corriendo o
## deslizándose lo tumba y lo hace rodar: la cuesta abajo lo acelera (la misma física que el deslizamiento,
## PlayerMovementController.slope_accel). Estalla al tocar a un enemigo, al chocar con una pared o un
## obstáculo, al caer desde alto o, si se para, tras una mecha corta. La explosión daña y aparta a los
## enemigos (no al jugador) y enciende a los barriles cercanos (cadena). Reaparece en su sitio más tarde.

enum State { IDLE, ROLLING, FUSE, GONE }

const RADIUS := 0.45
const HEIGHT := 0.92
const KICK_SPEED_MIN := 6.0
const KICK_SPEED_MAX := 18.0
const PLAYER_KICK_R := 1.3
const PLAYER_KICK_MIN_SPEED := 2.5
const ROLL_FRICTION := 1.6            ## m/s² (rueda lejos)
const ROLL_SLOPE_GAIN := 0.85
const GRAVITY := 22.0
const MAX_ROLL_TIME := 8.0
const STOP_SPEED := 0.6
const STOP_FUSE := 0.8                ## mecha si se para rodando
const CHAIN_FUSE := 0.3
const ENEMY_HIT_R := 1.15
const IMPACT_SPEED := 3.0             ## contra una pared u obstáculo a más de esto, estalla
const FALL_EXPLODE_VY := -9.0         ## caída que lo revienta al tocar suelo
const BLAST_RADIUS := 5.5
const BLAST_MIN_DAMAGE := 35.0        ## × daño del jugador
const BLAST_FRAC := 0.6               ## de la vida máxima de los normales
const BLAST_ELITE_FRAC := 0.2
const BLAST_KNOCKBACK := 14.0
const RESPAWN_TIME := 75.0
const RESPAWN_PLAYER_DIST := 25.0
const FIRE := Color(1.0, 0.5, 0.15)

var barrel_mesh: Mesh
var barrel_mesh_xf := Transform3D.IDENTITY
var state := State.IDLE
var hits := 0                          ## enemigos alcanzados por la última explosión (tests)

var _home := Vector3.ZERO
var _vel := Vector3.ZERO               ## horizontal
var _vy := 0.0
var _roll_t := 0.0
var _slow_t := 0.0
var _fuse := 0.0
var _respawn_t := 0.0
var _pivot: Node3D                     ## tumbar y girar
var _spin: Node3D                      ## gira sobre el eje del barril al rodar
var _lay: Node3D                       ## de pie (identidad) o tumbado (eje a lo ancho de la marcha)
var _band_mat: StandardMaterial3D
var _shape: CollisionShape3D
var _t := 0.0

func _ready() -> void:
	add_to_group("destructibles")
	add_to_group("explosive_barrels")
	collision_layer = 1
	collision_mask = 0
	_home = global_position
	_shape = CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = RADIUS
	cyl.height = HEIGHT
	_shape.shape = cyl
	_shape.position.y = HEIGHT * 0.5
	add_child(_shape)
	_pivot = Node3D.new()
	add_child(_pivot)
	_spin = Node3D.new()
	_pivot.add_child(_spin)
	_lay = Node3D.new()
	_spin.add_child(_lay)
	if barrel_mesh:
		var mi := MeshInstance3D.new()
		mi.mesh = barrel_mesh
		mi.transform = barrel_mesh_xf
		_lay.add_child(mi)
	else:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = RADIUS
		cm.bottom_radius = RADIUS
		cm.height = HEIGHT
		mi.mesh = cm
		mi.position.y = HEIGHT * 0.5
		_lay.add_child(mi)
	# Franja encendida: se lee como "esto explota"
	var band := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = RADIUS + 0.03
	bm.bottom_radius = RADIUS + 0.03
	bm.height = 0.14
	bm.radial_segments = 12
	bm.rings = 1
	band.mesh = bm
	band.position.y = HEIGHT * 0.5
	_band_mat = StandardMaterial3D.new()
	_band_mat.albedo_color = FIRE
	_band_mat.emission_enabled = true
	_band_mat.emission = FIRE
	_band_mat.emission_energy_multiplier = 1.5
	band.material_override = _band_mat
	band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lay.add_child(band)

## Golpe de un arma del jugador: lo tumba y sale rodando hacia donde iba el golpe.
func take_damage(amount: float, dir: Vector3 = Vector3.ZERO) -> void:
	if state != State.IDLE:
		return
	var d := Vector3(dir.x, 0.0, dir.z)
	if d.length_squared() < 0.001:
		var p := get_tree().get_first_node_in_group("player") as Node3D
		d = global_position - p.global_position if p else Vector3.FORWARD
		d.y = 0.0
	kick(d.normalized() * clampf(KICK_SPEED_MIN + amount * 0.08, KICK_SPEED_MIN, KICK_SPEED_MAX))

## Lo tumba y lo lanza rodando a `v` (horizontal).
func kick(v: Vector3) -> void:
	if state != State.IDLE:
		return
	v.y = 0.0
	if v.length_squared() < 0.01:
		v = Vector3.FORWARD * KICK_SPEED_MIN
	state = State.ROLLING
	_vel = v.limit_length(KICK_SPEED_MAX)
	_vy = 0.0
	_roll_t = 0.0
	_slow_t = 0.0
	collision_layer = 0                 # rodando no estorba al jugador
	_lay_down()
	AudioManager.play_at("impact_blunt", global_position, -8.0, 0.7)

## Encendido por otra explosión: sale despedido y estalla enseguida.
func ignite(push: Vector3) -> void:
	if state == State.IDLE:
		kick(push)
	if state == State.ROLLING:
		state = State.FUSE
		_fuse = CHAIN_FUSE

func _lay_down() -> void:
	# Tumbado con el eje perpendicular a la marcha, y apoyado sobre su costado
	var fwd := _vel.normalized()
	_pivot.transform = Transform3D(Basis(Vector3.UP, atan2(fwd.x, fwd.z)), Vector3.ZERO)
	_spin.transform = Transform3D(Basis.IDENTITY, Vector3(0, RADIUS, 0))
	# El eje del barril (su Y, de 0 a HEIGHT) pasa a la X del pivote, centrado
	_lay.transform = Transform3D(Basis(Vector3(0, 0, 1), -PI * 0.5), Vector3(-HEIGHT * 0.5, 0, 0))

func _physics_process(delta: float) -> void:
	_t += delta
	match state:
		State.IDLE:
			_check_player_kick()
		State.ROLLING:
			_roll(delta)
		State.FUSE:
			_roll(delta)
			_fuse -= delta
			_band_mat.emission_energy_multiplier = 1.5 + 6.0 * (0.5 + 0.5 * sin(_t * 40.0))
			if _fuse <= 0.0 and state == State.FUSE:
				explode()
		State.GONE:
			_respawn_t -= delta
			if _respawn_t <= 0.0:
				_try_respawn()

func _check_player_kick() -> void:
	var p := get_tree().get_first_node_in_group("player") as CharacterBody3D
	if p == null:
		return
	var to_b := global_position - p.global_position
	if absf(to_b.y) > 1.2:
		return
	to_b.y = 0.0
	if to_b.length() > PLAYER_KICK_R:
		return
	var pv := Vector3(p.velocity.x, 0.0, p.velocity.z)
	var mc = p.get("movement_controller")
	if mc and mc.has_method("is_sliding") and mc.is_sliding():
		pv = mc._slide_vel
	if pv.length() < PLAYER_KICK_MIN_SPEED or pv.dot(to_b) <= 0.0:
		return
	kick((pv.normalized() * 0.7 + to_b.normalized() * 0.3).normalized() * maxf(pv.length() * 1.3, KICK_SPEED_MIN))

func _roll(delta: float) -> void:
	if not EnemyMotion.available():
		explode()
		return
	_roll_t += delta
	var pos := global_position
	var ground := EnemyMotion.height_at(pos.x, pos.z)
	var on_ground := pos.y <= ground + 0.06
	if on_ground:
		var grad := PlayerMovementController.ground_gradient(pos)
		_vel += PlayerMovementController.slope_accel(grad, GRAVITY) * (ROLL_SLOPE_GAIN / PlayerMovementController.SLIDE_SLOPE_GAIN) * delta
		var spd := _vel.length()
		if spd > 0.001:
			_vel = _vel / spd * maxf(spd - ROLL_FRICTION * delta, 0.0)
	var speed := _vel.length()
	var step := Vector2(_vel.x, _vel.z) * delta
	var np := Vector2(pos.x, pos.z) + step
	var h_new := EnemyMotion.height_at(np.x, np.y)
	# Pared cuesta arriba u obstáculo: choque
	var blocked := on_ground and h_new - pos.y > maxf(step.length() * 1.3, 0.05)
	if not blocked:
		var pushed := EnemyMotion._push_out_of_obstacles(np)
		blocked = pushed.distance_squared_to(np) > 0.0001
	if blocked:
		if speed > IMPACT_SPEED:
			explode()
			return
		_vel = Vector3.ZERO
		np = Vector2(pos.x, pos.z)
		h_new = pos.y
	# Enemigos al paso
	if speed > 2.0:
		for e in EnemyRegistry.all():
			if e is EnemyData and not e.recycled:
				var de: Vector3 = e.global_position - pos
				if absf(de.y) < 1.6 and Vector2(de.x, de.z).length() < ENEMY_HIT_R * (1.0 + (e.scale.x - 1.0) * 0.5):
					explode()
					return
	# Altura: sigue el suelo o cae (un borde de meseta)
	var y := pos.y
	if h_new < y - 0.06 or _vy > 0.0:
		_vy -= GRAVITY * delta
		y += _vy * delta
		if y <= h_new:
			if _vy < FALL_EXPLODE_VY:
				global_position = Vector3(np.x, h_new, np.y)
				explode()
				return
			y = h_new
			_vy = 0.0
	else:
		y = h_new
		_vy = 0.0
	global_position = Vector3(np.x, y, np.y)
	# Giro sobre su eje según lo recorrido
	if speed > 0.01:
		_pivot.rotation.y = lerp_angle(_pivot.rotation.y, atan2(_vel.x, _vel.z), 0.3)
		_spin.rotate_object_local(Vector3.RIGHT, step.length() / RADIUS)
	# Parado: mecha corta
	if state == State.ROLLING:
		_slow_t = _slow_t + delta if speed < STOP_SPEED else 0.0
		if _slow_t > 0.3 or _roll_t > MAX_ROLL_TIME:
			state = State.FUSE
			_fuse = STOP_FUSE

## Explota: daña y aparta a los enemigos del radio (no al jugador) y enciende a los barriles cercanos.
func explode() -> void:
	if state == State.GONE:
		return
	state = State.GONE
	_respawn_t = RESPAWN_TIME
	visible = false
	collision_layer = 0
	var pos := global_position
	var p := get_tree().get_first_node_in_group("player")
	var mult: float = p.stat_block.damage_mult() if p and p.get("stat_block") else 1.0
	hits = 0
	HitFeedback.weapon_tag = -1
	for e in EnemyRegistry.all().duplicate():
		if not (e is EnemyData) or e.recycled:
			continue
		var to_e: Vector3 = e.global_position - pos
		if absf(to_e.y) > 3.0:
			continue
		to_e.y = 0.0
		var d := to_e.length()
		if d > BLAST_RADIUS:
			continue
		var frac := BLAST_ELITE_FRAC if e.xp_reward >= XpCurve.XP_ELITE else BLAST_FRAC
		var dmg := maxf(BLAST_MIN_DAMAGE * mult, e.max_hp * frac) * lerpf(1.0, 0.55, d / BLAST_RADIUS)
		var dir := to_e / d if d > 0.05 else Vector3.FORWARD
		e.take_damage(dmg, dir * BLAST_KNOCKBACK)
		hits += 1
	for b in get_tree().get_nodes_in_group("explosive_barrels"):
		if b == self or not (b is ExplosiveBarrel) or b.state == State.GONE:
			continue
		var to_b: Vector3 = b.global_position - pos
		to_b.y = 0.0
		if to_b.length() <= BLAST_RADIUS:
			b.ignite(to_b.normalized() * 9.0 if to_b.length() > 0.05 else Vector3.FORWARD * 9.0)
	if is_inside_tree():
		var scene := get_parent()
		NecroVFX.shockwave(scene, pos + Vector3(0, 0.2, 0), BLAST_RADIUS * 2.0, FIRE)
		FootDustVFX.land(scene, pos + Vector3(0, 0.05, 0), 1.0)
		_burst(scene, pos + Vector3(0, 0.5, 0))
		AudioManager.play_at("explosion", pos, -2.0, randf_range(0.85, 1.0))
		HitFeedback.shake(0.35)
		if hits >= 4:
			HitFeedback.slowmo(0.45, 0.15)

func _burst(scene: Node, at: Vector3) -> void:
	var fx := CPUParticles3D.new()
	fx.one_shot = true
	fx.amount = Quality.count(28)
	fx.lifetime = 0.7
	fx.explosiveness = 1.0
	fx.direction = Vector3.UP
	fx.spread = 80.0
	fx.initial_velocity_min = 4.0
	fx.initial_velocity_max = 10.0
	fx.gravity = Vector3(0, -6.0, 0)
	fx.scale_amount_min = 0.15
	fx.scale_amount_max = 0.4
	var m := SphereMesh.new()
	m.radius = 0.5
	m.height = 1.0
	m.radial_segments = 6
	m.rings = 3
	fx.mesh = m
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = FIRE
	mat.emission_enabled = true
	mat.emission = FIRE
	mat.emission_energy_multiplier = 4.0
	fx.material_override = mat
	fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(fx)
	fx.global_position = at
	fx.emitting = true
	scene.get_tree().create_timer(1.2).timeout.connect(fx.queue_free)

func _try_respawn() -> void:
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p and p.global_position.distance_to(_home) < RESPAWN_PLAYER_DIST:
		_respawn_t = 3.0
		return
	global_position = _home
	_vel = Vector3.ZERO
	_vy = 0.0
	_pivot.transform = Transform3D.IDENTITY
	_spin.transform = Transform3D.IDENTITY
	_lay.transform = Transform3D.IDENTITY
	_band_mat.emission_energy_multiplier = 1.5
	visible = true
	collision_layer = 1
	state = State.IDLE
