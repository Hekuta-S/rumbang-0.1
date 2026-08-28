extends Area3D

## RadiationZone.gd
## Damages enemies standing inside the aura on a fixed tick interval.
## Attached to the player so it follows them automatically.

@export var radius: float = 4.5
@export var damage_per_tick: float = 2.5
@export var tick_interval: float = 0.5

var _tick_accum: float = 0.0

func _ready() -> void:
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 1  # enemies live on collision layer 1
	add_to_group("radiation_zones")

	var shape := SphereShape3D.new()
	shape.radius = radius
	var col := CollisionShape3D.new()
	col.shape = shape
	add_child(col)

	_build_visual()

func _physics_process(delta: float) -> void:
	_tick_accum += delta
	if _tick_accum < tick_interval:
		return
	_tick_accum = 0.0
	for body in get_overlapping_bodies():
		if body.is_in_group("enemies") and body.has_method("take_damage"):
			body.take_damage(damage_per_tick, Vector3.ZERO)

## Visuals: a faint radioactive ring on the ground + rising green motes.
func _build_visual() -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius * 0.82
	torus.outer_radius = radius
	ring.mesh = torus
	ring.rotate_object_local(Vector3.RIGHT, deg_to_rad(90))
	ring.position.y = 0.12
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.35, 1.0, 0.3, 0.4)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.4, 1.0, 0.3)
	mat.emission_energy_multiplier = 1.5
	ring.material_override = mat
	add_child(ring)

	var particles := CPUParticles3D.new()
	particles.amount = 26
	particles.lifetime = 1.4
	particles.one_shot = false
	particles.direction = Vector3.UP
	particles.spread = 180.0
	particles.flatness = 1.0
	particles.initial_velocity_min = 0.4
	particles.initial_velocity_max = 1.4
	particles.gravity = Vector3(0, 0.4, 0)
	particles.scale_amount_min = 0.15
	particles.scale_amount_max = 0.3
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = radius * 0.7

	var p_mesh := SphereMesh.new()
	p_mesh.radius = 0.05
	p_mesh.height = 0.1
	particles.mesh = p_mesh

	var p_mat := StandardMaterial3D.new()
	p_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	p_mat.albedo_color = Color(0.5, 1.0, 0.4, 0.8)
	p_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	p_mat.emission_enabled = true
	p_mat.emission = Color(0.4, 1.0, 0.3)
	p_mat.emission_energy_multiplier = 2.0
	particles.material_override = p_mat

	add_child(particles)
	particles.emitting = true
