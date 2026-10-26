extends Area3D

## SporeCloud.gd
## Nube corrosiva de esporas dejada por la bazoca de Bronch.
## Usa el shader FBM biológico con distorsión ondulatoria orgánica en las membranas de esporas.

@export var radius: float = 2.6
@export var damage_per_tick: float = 3.0
@export var tick_interval: float = 0.5
@export var lifetime: float = 3.5

var _tick_accum: float = 0.0
var _age: float = 0.0
var _fade_after: float = 0.55
var _spore_shader_mat: ShaderMaterial = null
var _particles: Array[CPUParticles3D] = []
var _particles_stopped: bool = false

static var spore_shader: Shader = preload("res://assets/shaders/spore_fbm_cloud.gdshader")

func _ready() -> void:
	set_deferred("monitoring", true)
	set_deferred("monitorable", false)
	collision_layer = 0
	collision_mask = 4 # enemies
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

	# Desvanecimiento orgánico con disolución FBM al final del tiempo de vida
	if _age >= lifetime * _fade_after and _spore_shader_mat:
		var t = clamp((_age - lifetime * _fade_after) / (lifetime * (1.0 - _fade_after)), 0.0, 1.0)
		_spore_shader_mat.set_shader_parameter("dissolve_fade", t)
		if not _particles_stopped:
			_particles_stopped = true
			for ps in _particles:
				if is_instance_valid(ps):
					ps.emitting = false

	_tick_accum += delta
	if _tick_accum < tick_interval:
		return
	_tick_accum = 0.0
	for body in EnemyQuery.overlapping(self):
		if body.is_in_group("enemies") and body.has_method("take_damage"):
			body.take_damage(damage_per_tick, Vector3.ZERO)

## Nube de esporas: gas verde translúcido (shader volumétrico barato sobre unas pocas
## esferas), jirones de niebla y muchas esporas brillantes flotando. Todo escala con `radius`.
func _build_visual() -> void:
	var root := Node3D.new()
	root.name = "Visual"
	add_child(root)

	_spore_shader_mat = ShaderMaterial.new()
	_spore_shader_mat.shader = spore_shader
	_spore_shader_mat.set_shader_parameter("color_deep", Vector4(0.08, 0.42, 0.18, 1.0))
	_spore_shader_mat.set_shader_parameter("color_mid", Vector4(0.45, 0.9, 0.18, 1.0))
	_spore_shader_mat.set_shader_parameter("color_peak", Vector4(1.0, 0.92, 0.35, 1.0))
	_spore_shader_mat.set_shader_parameter("color_rim", Vector4(0.25, 1.0, 0.85, 1.0))
	_spore_shader_mat.set_shader_parameter("height_scale", 0.35)
	_spore_shader_mat.set_shader_parameter("wave_speed", 0.7)
	_spore_shader_mat.set_shader_parameter("global_transparency", 0.9)
	_spore_shader_mat.set_shader_parameter("gas_density", 0.3)
	_spore_shader_mat.set_shader_parameter("dissolve_fade", 0.0)

	# 5 cúmulos distribuidos por el radio de daño (antes eran 6 esferas de 0.55 m: la nube
	# se veía mucho más pequeña que su zona real de daño)
	var offsets := [
		Vector3(0, 0.35, 0), Vector3(0.55, 0.3, 0.25), Vector3(-0.5, 0.25, 0.45),
		Vector3(0.3, 0.45, -0.5), Vector3(-0.45, 0.4, -0.3),
	]
	for off in offsets:
		var puff := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = radius * 0.5
		sphere.height = radius
		sphere.radial_segments = 16
		sphere.rings = 10
		puff.mesh = sphere
		puff.position = (off as Vector3) * radius * 0.9
		puff.scale = Vector3(1.0, 0.7, 1.0)
		puff.material_override = _spore_shader_mat
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(puff)

	# Niebla verde de fondo
	var mist := SporeVFX.gas(16, 2.4, radius * 0.6, radius * 0.9, radius * 1.5, 0.16)
	mist.position = Vector3(0, 0.5, 0)
	root.add_child(mist)
	mist.emitting = true
	_particles.append(mist)

	# Esporas pequeñas (muchas) y esporas "vaina" grandes (pocas)
	var small := SporeVFX.specks(70, 2.2, radius * 0.8, 0.05, 0.1, 0.5)
	small.position = Vector3(0, 0.6, 0)
	root.add_child(small)
	small.emitting = true
	_particles.append(small)
	var pods := SporeVFX.specks(10, 2.8, radius * 0.7, 0.16, 0.26, 0.25)
	pods.position = Vector3(0, 0.7, 0)
	root.add_child(pods)
	pods.emitting = true
	_particles.append(pods)
