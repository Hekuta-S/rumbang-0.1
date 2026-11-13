class_name RewardJuice
extends RefCounted

## Fase 2 del plan de juice (docs/PLAN_JUICE.md): que recoger cosas se sienta.
##   - Escalera de tono: cada recogida encadenada (< CHAIN_WINDOW_MS) suena un semitono más aguda.
##   - Imán que acelera: arranca lento y se lanza hacia ti (magnet_speed).
##   - Salida en abanico con rebote (pop_velocity / bounce) en vez de aparecer quieto.
##   - Chispa al recoger y monedas visuales que vuelan al jugador cuando cae oro.

const CHAIN_WINDOW_MS := 900
const CHAIN_MAX := 12
const MAGNET_RAMP := 0.45          ## s hasta la velocidad máxima del imán
const MAGNET_MIN := 0.35           ## fracción de la velocidad base al engancharse
const MAGNET_MAX := 1.7            ## fracción de la velocidad base a tope
const BOUNCE_KEEP := 0.45          ## velocidad vertical que conserva al rebotar
const COIN_MAX := 7
const SOUND_GAP_MS := 30           ## entre sonidos de recogida (una ola de gemas no suena como una sola)
const SPARK_GAP_MS := 70           ## entre chispas de recogida (presupuesto de partículas)
static var _last_sound_ms := -100000
static var _last_spark_ms := -100000

static var _chain := 0
static var _last_ms := -100000
static var _spark_mesh: SphereMesh
static var _spark_mat: StandardMaterial3D
static var _coin_mesh: CylinderMesh
static var _coin_mat: StandardMaterial3D

## Pura: tono para el eslabón `chain` de la racha.
static func pitch_for(chain: int) -> float:
	return pow(2.0, float(clampi(chain, 0, CHAIN_MAX)) / 12.0)

## Avanza la racha (o la reinicia si pasó demasiado) y devuelve el tono de esta recogida.
static func next_pitch(now_ms: int = -1) -> float:
	if now_ms < 0:
		now_ms = Time.get_ticks_msec()
	_chain = _chain + 1 if now_ms - _last_ms <= CHAIN_WINDOW_MS else 0
	_last_ms = now_ms
	return pitch_for(_chain)

## Pura: velocidad del imán `t` segundos después de engancharse (ease-in: arranca suave y acelera).
static func magnet_speed(base: float, t: float) -> float:
	var k := clampf(t / MAGNET_RAMP, 0.0, 1.0)
	return base * lerpf(MAGNET_MIN, MAGNET_MAX, k * k)

## Velocidad de salida en abanico: hacia arriba y a un lado al azar.
static func pop_velocity(up_min: float = 3.5, up_max: float = 5.0, side: float = 2.2) -> Vector3:
	var a := randf() * TAU
	var h := randf_range(side * 0.5, side)
	return Vector3(cos(a) * h, randf_range(up_min, up_max), sin(a) * h)

## Un paso de vuelo balístico con rebote sobre la altura `rest_y`. Modifica y devuelve la velocidad.
static func bounce(node: Node3D, vel: Vector3, rest_y: float, delta: float, gravity: float = 16.0) -> Vector3:
	vel.y -= gravity * delta
	node.global_position += vel * delta
	if node.global_position.y < rest_y:
		node.global_position.y = rest_y
		vel.y = absf(vel.y) * BOUNCE_KEEP if absf(vel.y) > 1.0 else 0.0
		vel.x *= 0.6
		vel.z *= 0.6
	return vel

## ¿Ya se posó tras el salto? (en su altura y sin velocidad vertical)
static func settled(node: Node3D, vel: Vector3, rest_y: float) -> bool:
	return node.global_position.y <= rest_y + 0.005 and absf(vel.y) < 0.01

## Recogida: sonido con tono de racha + chispa del color del objeto.
static func collect(parent: Node, pos: Vector3, color: Color, sfx: String = "pickup", volume_db: float = -8.0,
		base_pitch: float = 1.0) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_sound_ms >= SOUND_GAP_MS:
		_last_sound_ms = now
		AudioManager.play(sfx, volume_db, base_pitch * next_pitch(now))
	if parent == null or not parent.is_inside_tree() or now - _last_spark_ms < SPARK_GAP_MS:
		return
	_last_spark_ms = now
	_ensure_shared()
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = maxi(Quality.count(10), 4)
	p.lifetime = 0.35
	p.local_coords = false
	p.spread = 180.0
	p.direction = Vector3.UP
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 4.5
	p.gravity = Vector3(0, -4.0, 0)
	p.damping_min = 4.0
	p.damping_max = 7.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.1
	p.mesh = _spark_mesh
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1).lerp(color, 0.4))
	grad.set_color(1, Color(color.r, color.g, color.b, 0.0))
	p.color_ramp = grad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.get_tree().create_timer(0.6).timeout.connect(p.queue_free)

## Oro de una baja: unas monedas saltan del cadáver y vuelan al jugador (solo visual: el oro ya se sumó).
static func gold_burst(parent: Node, from: Vector3, amount: int, player: Node3D) -> void:
	if parent == null or not parent.is_inside_tree() or not is_instance_valid(player) or amount <= 0:
		return
	_ensure_shared()
	var n := clampi(int(ceil(float(amount) / 4.0)), 2, COIN_MAX)
	for i in n:
		var c := MeshInstance3D.new()
		c.mesh = _coin_mesh
		c.material_override = _coin_mat
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(c)
		var start := from + Vector3(0, 0.8, 0)
		c.global_position = start
		c.rotation = Vector3(randf() * TAU, randf() * TAU, 0.0)
		var peak := start + pop_velocity(0.0, 0.0, 1.3) + Vector3(0, randf_range(0.9, 1.5), 0)
		var tw := c.create_tween()
		tw.tween_interval(0.03 * i)
		tw.tween_property(c, "global_position", peak, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(c, "rotation:x", c.rotation.x + TAU, 0.28)
		tw.tween_method(_coin_fly.bind(c, peak, player), 0.0, 1.0, randf_range(0.32, 0.42))
		tw.tween_callback(func(): _coin_arrive(c, player))

static func _coin_fly(t: float, c: MeshInstance3D, from: Vector3, player: Node3D) -> void:
	if not is_instance_valid(player) or not is_instance_valid(c):
		return
	var to := player.global_position + Vector3(0, 1.0, 0)
	c.global_position = from.lerp(to, t * t)
	c.rotation.y += 0.4

static func _coin_arrive(c: MeshInstance3D, player: Node3D) -> void:
	if is_instance_valid(c):
		if is_instance_valid(player):
			AudioManager.play("coin", -11.0, 0.9 * next_pitch())
		c.queue_free()

static func _ensure_shared() -> void:
	if _spark_mesh != null:
		return
	_spark_mesh = SphereMesh.new()
	_spark_mesh.radius = 0.035
	_spark_mesh.height = 0.07
	_spark_mesh.radial_segments = 4
	_spark_mesh.rings = 2
	_spark_mat = StandardMaterial3D.new()
	_spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_spark_mat.vertex_color_use_as_albedo = true
	_spark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_spark_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_spark_mesh.material = _spark_mat
	_coin_mesh = CylinderMesh.new()
	_coin_mesh.top_radius = 0.09
	_coin_mesh.bottom_radius = 0.09
	_coin_mesh.height = 0.025
	_coin_mesh.radial_segments = 10
	_coin_mesh.rings = 1
	_coin_mat = StandardMaterial3D.new()
	_coin_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_coin_mat.albedo_color = Color(1.0, 0.8, 0.25)
	_coin_mat.emission_enabled = true
	_coin_mat.emission = Color(1.0, 0.75, 0.2)
	_coin_mat.emission_energy_multiplier = 1.6
