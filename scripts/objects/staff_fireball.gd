class_name StaffFireball
extends Node3D

## Bola de fuego del Bastón de Fuego (FireStaffStrategy). Vuela recta, detecta enemigos sin física
## (EnemyQuery.segment_hit) y paredes/suelo con un rayo (capa 1). Al tocar algo, o al llegar a su alcance, estalla:
## daño en área (todo en el centro, la mitad en el borde) y quemadura (StatusEffects "burn") a los alcanzados.
## Dibujada como el resto del fuego (ToonFX): lenguas de fuego entintadas en la cabeza y una estela de llamas.

const EDGE_DAMAGE := 0.5              ## fracción del daño en el borde del área
const CORE_COLOR := Color(1.0, 0.62, 0.18)
const HOT_COLOR := Color(1.0, 0.92, 0.55)

var velocity := Vector3.ZERO
var damage := 15.0
var radius := 1.8
var max_range := 30.0
var burn_dps := 4.0
var burn_time := 3.0
var weapon := WeaponData.WeaponType.FIRE_STAFF
var source_player: Node = null
var size := 1.0
var _traveled := 0.0
var _done := false
var _trail: CPUParticles3D
var _core: Node3D

## Crea y lanza una bola desde `from` con velocidad `vel` (m/s).
static func shoot(parent: Node, from: Vector3, vel: Vector3, p_damage: float, opts: Dictionary = {}) -> StaffFireball:
	var b := StaffFireball.new()
	b.velocity = vel
	b.damage = p_damage
	b.radius = float(opts.get("radius", 1.8))
	b.max_range = float(opts.get("range", 30.0))
	b.burn_dps = float(opts.get("burn_dps", 4.0))
	b.burn_time = float(opts.get("burn_time", 3.0))
	b.weapon = int(opts.get("weapon", WeaponData.WeaponType.FIRE_STAFF))
	b.source_player = opts.get("player")
	b.size = float(opts.get("scale", 1.0))
	parent.add_child(b)
	b.global_position = from
	return b

func _ready() -> void:
	_core = Node3D.new()
	add_child(_core)
	# Cabeza: dos lenguas de fuego cruzadas (billboard) que laten, y un núcleo claro
	for i in 2:
		var s := _flame_sprite(0.55 * size if i == 0 else 0.35 * size, CORE_COLOR if i == 0 else HOT_COLOR)
		_core.add_child(s)
	var tw := _core.create_tween().set_loops()
	tw.tween_property(_core, "scale", Vector3.ONE * 1.15, 0.08)
	tw.tween_property(_core, "scale", Vector3.ONE * 0.9, 0.08)
	_trail = _make_trail()

func _flame_sprite(px: float, color: Color) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = ToonFX.flame_texture()
	s.hframes = ToonFX.FRAMES
	s.vframes = ToonFX.FRAMES
	s.frame = randi() % (ToonFX.FRAMES * ToonFX.FRAMES)
	s.pixel_size = px / 128.0
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.modulate = color
	return s

func _make_trail() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.45, 0.45) * size
	p.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	if not ToonFX.flame_material(m):
		return null
	p.material_override = m
	ToonFX.vary(p)
	p.amount = Quality.count(18)
	p.lifetime = 0.35
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 30.0
	p.gravity = Vector3(0, 1.5, 0)
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 1.0
	p.scale_amount_curve = ToonFX.pop_curve(0.9, 1.0, 0.2)
	p.color_ramp = ToonFX.pop_ramp([HOT_COLOR, CORE_COLOR, Color(0.8, 0.25, 0.08)])
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	p.emitting = true
	return p

func _physics_process(delta: float) -> void:
	if _done:
		return
	var from := global_position
	var step := velocity * delta
	var to := from + step
	var q := PhysicsRayQueryParameters3D.create(from, to + step.normalized() * 0.1, 1)
	if is_instance_valid(source_player) and source_player is CollisionObject3D:
		q.exclude = [(source_player as CollisionObject3D).get_rid()]
	var wall := get_world_3d().direct_space_state.intersect_ray(q)
	var limit := to if wall.is_empty() else (wall["position"] as Vector3)
	var hit := EnemyQuery.segment_hit(from, limit, 0.2 * size)
	if not hit.is_empty():
		_explode(hit["pos"])
		return
	if not wall.is_empty():
		var col: Object = wall.get("collider")
		if col is Node and (col as Node).is_in_group("destructibles") and col.has_method("take_damage"):
			col.take_damage(damage, velocity.normalized())
		_explode((wall["position"] as Vector3) - velocity.normalized() * 0.2)
		return
	global_position = to
	_traveled += step.length()
	if _traveled >= max_range:
		_explode(global_position)

## Estallido: daño en área (cae hacia el borde) y quemadura; fuego dibujado, anillo y sonido.
func _explode(at: Vector3) -> void:
	_done = true
	global_position = at
	var dir := Vector3(velocity.x, 0.0, velocity.z).normalized()
	for e in EnemyRegistry.query_radius(at, radius + 1.0):
		if not is_instance_valid(e) or not e.has_method("take_damage"):
			continue
		if e.has_method("is_dead") and e.is_dead():
			continue
		var d := Vector2(e.global_position.x - at.x, e.global_position.z - at.z).length() - EnemyQuery.radius_of(e)
		if d > radius or absf(e.global_position.y - at.y) > 2.5:
			continue
		var k := clampf(d / maxf(radius, 0.01), 0.0, 1.0)
		var dmg := damage * lerpf(1.0, EDGE_DAMAGE, k)
		var push: Vector3 = (e.global_position - at)
		push.y = 0.0
		push = (push.normalized() if push.length_squared() > 0.01 else dir) * 3.0
		HitFeedback.weapon_tag = weapon
		e.take_damage(dmg, push)
		StatusEffects.apply_to(e, "burn", burn_dps, burn_time, source_player, weapon)
		if is_instance_valid(source_player) and source_player.has_method("on_damage_dealt"):
			source_player.on_damage_dealt(dmg, weapon)
	var root := get_parent()
	ToonFX.impact_pop(root, at, CORE_COLOR, 1.1 * size)
	ToonFX.flame_column(root, at, radius * 0.6, CORE_COLOR)
	ToonFX.ring_burst(root, Vector3(at.x, at.y - 0.4, at.z), radius, CORE_COLOR, 0.35)
	ToonFX.puff_burst(root, at, Color(0.35, 0.32, 0.3), 5, 2.5, 0.5)
	AudioManager.play("impact_fire", -6.0, randf_range(0.9, 1.05))
	HitFeedback.shake(0.15)
	# La estela se queda apagándose; la bola desaparece ya
	if _trail:
		_trail.emitting = false
		_trail.reparent(root, true)
		_trail.get_tree().create_timer(_trail.lifetime + 0.1, false).timeout.connect(_trail.queue_free)
	queue_free()
