class_name SlashVFX
extends RefCounted

## Pool de tajos. Evita crear MeshInstance3D/QuadMesh/ShaderMaterial en cada
## golpe. El shader por defecto es el tajo polar (espada); cada arma puede pasar
## el suyo (p. ej. la Espalanza usa spear_slash.gdshader, tajo horizontal).
## Hay un pool independiente por shader.

static var _default_shader: Shader = preload("res://assets/shaders/slash_2_optimized.gdshader")
static var _pools: Dictionary = {}   # Shader -> Array[MeshInstance3D] libres

const DURATION := 0.18
static var last_duration: float = DURATION   ## última duración usada (para tests/depuración)

static func _acquire(parent: Node, size: float, shader: Shader) -> MeshInstance3D:
	var pool: Array = _pools.get(shader, [])
	_pools[shader] = pool
	var inst: MeshInstance3D = null
	while not pool.is_empty():
		var cand: MeshInstance3D = pool.pop_back()
		if is_instance_valid(cand) and cand.is_inside_tree():
			inst = cand
			break
	if inst == null:
		inst = MeshInstance3D.new()
		inst.mesh = QuadMesh.new()
		var mat := ShaderMaterial.new()
		mat.shader = shader
		inst.material_override = mat
		inst.set_meta("slash_shader", shader)
		parent.add_child(inst)
	(inst.mesh as QuadMesh).size = Vector2(size, size)
	inst.visible = true
	return inst

## params: parámetros del shader (slash_color, core_color, emission_strength, ...).
## `shader` null = tajo polar por defecto.
static func spawn(tween_owner: Node, parent: Node, pos: Vector3, facing_dir: Vector3,
		size: float, forward_offset: float, flip: bool, params: Dictionary,
		duration: float = DURATION, shader: Shader = null) -> void:
	last_duration = duration
	var sh: Shader = shader if shader != null else _default_shader
	var inst := _acquire(parent, size, sh)
	var mat := inst.material_override as ShaderMaterial
	for key in params:
		mat.set_shader_parameter(key, params[key])
	mat.set_shader_parameter("rotate_all", 0.0)
	mat.set_shader_parameter("flip_side", flip)
	mat.set_shader_parameter("progress", 0.0)

	inst.global_position = pos + facing_dir * forward_offset + Vector3(0, 1.0, 0)
	# Reiniciar orientación antes de rotar (la instancia se reutiliza)
	inst.global_transform.basis = Basis()
	if facing_dir.cross(Vector3.UP).length() > 0.001:
		inst.look_at(inst.global_position + facing_dir, Vector3.UP)
	inst.rotate_object_local(Vector3.RIGHT, deg_to_rad(-90))
	inst.rotate_object_local(Vector3.FORWARD, deg_to_rad(180))

	var tween := tween_owner.create_tween()
	tween.tween_method(func(val: float) -> void:
		if is_instance_valid(mat):
			mat.set_shader_parameter("progress", val)
	, 0.0, 1.0, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func() -> void:
		if is_instance_valid(inst):
			inst.visible = false
			var pool: Array = _pools.get(sh, [])
			pool.append(inst)
			_pools[sh] = pool
	)
