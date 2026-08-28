extends Area3D

## SporeCloud.gd
## A temporary corrosive cloud left behind by Bronch's spore bazooka.
## Damages every enemy inside on a fixed tick interval, then fades away.

@export var radius: float = 2.6
@export var damage_per_tick: float = 3.0
@export var tick_interval: float = 0.5
@export var lifetime: float = 3.5

var _tick_accum: float = 0.0
var _age: float = 0.0
var _fade_after: float = 0.55
var _fade_mat: StandardMaterial3D = null

func _ready() -> void:
	set_deferred("monitoring", true)
	set_deferred("monitorable", false)
	collision_layer = 0
	collision_mask = 1 # enemies
	add_to_group("spore_clouds")

	var shape := SphereShape3D.new()
	shape.radius = radius
	var col := CollisionShape3D.new()
	col.shape = shape
	add_child(col)

	_build_visual()

func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		queue_free()
		return

	# Fade the visuals near the end of the cloud's life.
	if _age >= lifetime * _fade_after and _fade_mat:
		var t = clamp((_age - lifetime * _fade_after) / (lifetime * (1.0 - _fade_after)), 0.0, 1.0)
		_fade_mat.albedo_color.a = 0.5 * (1.0 - t)
		_fade_mat.emission_energy_multiplier = 2.0 * (1.0 - t)

	_tick_accum += delta
	if _tick_accum < tick_interval:
		return
	_tick_accum = 0.0
	for body in get_overlapping_bodies():
		if body.is_in_group("enemies") and body.has_method("take_damage"):
			body.take_damage(damage_per_tick, Vector3.ZERO)

## Puffy toxic cloud: a cluster of soft spheres + drifting motes.
func _build_visual() -> void:
	var root := Node3D.new()
	root.name = "Visual"
	add_child(root)

	_fade_mat = StandardMaterial3D.new()
	_fade_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fade_mat.albedo_color = Color(0.75, 0.95, 0.3, 0.5)
	_fade_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fade_mat.emission_enabled = true
	_fade_mat.emission = Color(0.7, 0.95, 0.25)
	_fade_mat.emission_energy_multiplier = 2.0

	var offsets = [
		Vector3(0, 0, 0), Vector3(0.7, 0.2, 0.3), Vector3(-0.6, 0.1, 0.5),
		Vector3(0.4, 0.5, -0.5), Vector3(-0.5, 0.6, -0.2), Vector3(0.1, 0.9, 0.2),
	]
	for off in offsets:
		var puff = MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.55
		sphere.height = 1.1
		puff.mesh = sphere
		puff.position = off
		puff.scale = Vector3(1.0, 0.8, 1.0)
		puff.material_override = _fade_mat
		root.add_child(puff)

	var particles := CPUParticles3D.new()
	particles.amount = 30
	particles.lifetime = 1.2
	particles.one_shot = false
	particles.direction = Vector3.UP
	particles.spread = 60.0
	particles.flatness = 1.0
	particles.initial_velocity_min = 0.3
	particles.initial_velocity_max = 1.2
	particles.gravity = Vector3(0, 0.5, 0)
	particles.scale_amount_min = 0.2
	particles.scale_amount_max = 0.45
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = radius * 0.7

	var p_mesh := SphereMesh.new()
	p_mesh.radius = 0.08
	p_mesh.height = 0.16
	particles.mesh = p_mesh

	var p_mat := StandardMaterial3D.new()
	p_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	p_mat.albedo_color = Color(0.85, 1.0, 0.4, 0.8)
	p_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	p_mat.emission_enabled = true
	p_mat.emission = Color(0.75, 0.95, 0.25)
	p_mat.emission_energy_multiplier = 2.5
	particles.material_override = p_mat

	root.add_child(particles)
	particles.emitting = true
