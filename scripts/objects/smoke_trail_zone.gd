extends Area3D

## SmokeTrailZone.gd — estela de humo abrasador de Riva.
## Zona que el RivaSpeedController deja tras de sí en modo ráfaga: quema a los
## enemigos que están encima (DPS) durante unos segundos y luego se desvanece.

@export var radius: float = 1.3
@export var damage_per_tick: float = 4.5
@export var tick_interval: float = 0.5
@export var lifetime: float = 3.0

var _tick_accum: float = 0.0
var _fade_accum: float = 0.0

func _ready() -> void:
	add_to_group("riva_smoke")
	_build_visual()

func _physics_process(delta: float) -> void:
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()
		return
	_fade_accum += delta
	if _fade_accum >= 0.15:
		_fade_accum = 0.0
		_apply_fade(clampf(lifetime, 0.0, 1.0))

	_tick_accum += delta
	if _tick_accum < tick_interval:
		return
	_tick_accum = 0.0
	# Detección por distancia sobre el grupo "enemies" (mismo patrón que el
	# railgun / skill de Kaionz): más robusto que el overlap físico.
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		if enemy.global_position.distance_to(global_position) <= radius and enemy.has_method("take_damage"):
			enemy.take_damage(damage_per_tick, Vector3.ZERO)

## Visuales: una nube semitransparente + partículas de humo gris que ascienden.
var _smoke_particles: CPUParticles3D

func _build_visual() -> void:
	var cloud := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 8
	sphere.rings = 5
	cloud.mesh = sphere
	cloud.position.y = 0.35
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(0.85, 0.55, 0.3, 0.18)
	mat.emission_enabled = true
	mat.emission = Color(0.9, 0.5, 0.2)
	mat.emission_energy_multiplier = 1.6
	cloud.material_override = mat
	add_child(cloud)

	_smoke_particles = CPUParticles3D.new()
	_smoke_particles.amount = 22
	_smoke_particles.lifetime = 1.6
	_smoke_particles.one_shot = false
	_smoke_particles.direction = Vector3.UP
	_smoke_particles.spread = 70.0
	_smoke_particles.initial_velocity_min = 0.5
	_smoke_particles.initial_velocity_max = 1.4
	_smoke_particles.gravity = Vector3(0, 0.4, 0)
	_smoke_particles.scale_amount_min = 0.18
	_smoke_particles.scale_amount_max = 0.42
	_smoke_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_smoke_particles.emission_sphere_radius = radius * 0.8
	var p_mesh := SphereMesh.new()
	p_mesh.radius = 0.07
	p_mesh.height = 0.14
	_smoke_particles.mesh = p_mesh
	var p_mat := StandardMaterial3D.new()
	p_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	p_mat.albedo_color = Color(0.75, 0.6, 0.5, 0.75)
	p_mat.emission_enabled = true
	p_mat.emission = Color(0.6, 0.4, 0.3)
	p_mat.emission_energy_multiplier = 1.2
	_smoke_particles.material_override = p_mat
	add_child(_smoke_particles)
	_smoke_particles.emitting = true

func _apply_fade(alpha: float) -> void:
	for child in get_children():
		if child is MeshInstance3D and child.mesh is SphereMesh:
			var m: StandardMaterial3D = child.material_override as StandardMaterial3D
			if m:
				m.albedo_color.a = 0.18 * alpha
				m.emission_energy_multiplier = 1.6 * alpha
	if _smoke_particles:
		_smoke_particles.amount = maxi(1, int(22 * alpha))
