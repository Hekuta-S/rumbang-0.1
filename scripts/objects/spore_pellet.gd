class_name SporePellet
extends Node3D

## Perdigón del disparo secundario de la bazuca de Bronch (perdigonazo, solo mazmorra).
## Ligero a propósito: salen muchos a la vez. Una bolita de esporas brillante con estela corta;
## al tocar un enemigo le hace daño y lo empuja, al tocar un prop rompible lo rompe y al llegar
## a su alcance o chocar con la pared se deshace en un soplo de esporas.

const RADIUS := 0.07
const HIT_EXTRA := 0.12          ## margen extra contra enemigos (perdigones fáciles de acertar)

static var _mesh: SphereMesh
static var _mat: StandardMaterial3D

var direction := Vector3.FORWARD
var speed := 34.0
var max_range := 9.0
var damage := 7.0
var knockback := 2.2
var source_player: Node = null
var _travelled := 0.0
var _done := false

static func fire(parent: Node, from: Vector3, dir: Vector3, dmg: float, kb: float, spd: float, rng: float, src: Node) -> SporePellet:
	var p := SporePellet.new()
	p.direction = dir.normalized()
	p.damage = dmg
	p.knockback = kb
	p.speed = spd
	p.max_range = rng
	p.source_player = src
	parent.add_child(p)
	p.global_position = from
	return p

func _ready() -> void:
	if _mesh == null:
		_mesh = SphereMesh.new()
		_mesh.radius = RADIUS
		_mesh.height = RADIUS * 2.0
		_mesh.radial_segments = 8
		_mesh.rings = 4
		_mat = StandardMaterial3D.new()
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.albedo_color = Color(0.75, 1.0, 0.3)
		_mat.emission_enabled = true
		_mat.emission = Color(0.6, 1.0, 0.2)
		_mat.emission_energy_multiplier = 4.0
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var trail := SporeVFX.specks(Quality.count(8), 0.25, 0.04, 0.03, 0.06, 0.2)
	add_child(trail)
	trail.emitting = true

func _physics_process(delta: float) -> void:
	if _done:
		return
	var from := global_position
	var step := minf(speed * delta, max_range - _travelled)
	var to := from + direction * step
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	if source_player:
		q.exclude = [source_player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var eh := EnemyQuery.segment_hit(from, to, HIT_EXTRA)
	var world_dist: float = from.distance_to(hit.position) if not hit.is_empty() else INF
	if not eh.is_empty() and from.distance_to(eh["pos"]) <= world_dist:
		_hit_enemy(eh["enemy"], eh["pos"])
		return
	if not hit.is_empty():
		if hit.collider is DestructibleProp:
			hit.collider.take_damage(999.0, direction)
		_finish(hit.position)
		return
	global_position = to
	_travelled += step
	if _travelled >= max_range - 0.001:
		_finish(to)

func _hit_enemy(e, pos: Vector3) -> void:
	if is_instance_valid(e) and e.has_method("take_damage") and not (e.has_method("is_dead") and e.is_dead()):
		HitFeedback.weapon_tag = WeaponData.WeaponType.SPORE_BAZOOKA
		# Sin empuje en take_damage (lo sustituiría con un mínimo por impacto): cada perdigón suma
		# un poco con apply_knockback, así el empuje crece con los perdigones que aciertan.
		var push := Vector3(direction.x, 0.0, direction.z).normalized()
		e.take_damage(damage, Vector3.ZERO)
		if e.has_method("apply_knockback") and not (e.has_method("is_dead") and e.is_dead()):
			e.apply_knockback(push * knockback)
		if is_instance_valid(source_player) and source_player.has_method("on_damage_dealt"):
			source_player.on_damage_dealt(damage, WeaponData.WeaponType.SPORE_BAZOOKA)
	_finish(pos)

func _finish(pos: Vector3) -> void:
	_done = true
	global_position = pos
	var puff := SporeVFX.specks(Quality.count(10), 0.45, 0.1, 0.04, 0.09, 2.2)
	puff.one_shot = true
	puff.explosiveness = 0.95
	get_parent().add_child(puff)
	puff.global_position = pos
	puff.emitting = true
	puff.get_tree().create_timer(0.8).timeout.connect(puff.queue_free)
	queue_free()
