class_name SpawnDissolve
extends RefCounted

## Efecto de materialización (shader dissolve_spawn) reutilizable para el jugador
## y la vista previa del selector de personaje.

const SHADER: Shader = preload("res://assets/shaders/dissolve_spawn.gdshader")

static var _noise_tex: NoiseTexture2D

static func _get_noise() -> NoiseTexture2D:
	if _noise_tex == null:
		_noise_tex = NoiseTexture2D.new()
		_noise_tex.noise = FastNoiseLite.new()
		_noise_tex.seamless = true
		_noise_tex.width = 256
		_noise_tex.height = 256
	return _noise_tex

static func _collect_meshes(n: Node, out: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_collect_meshes(c, out)

## Materializa `root` de pies a cabeza. `tween_owner` es el nodo que crea el tween.
## Devuelve el Tween (o null si no hay mallas).
static func play(root: Node3D, tween_owner: Node, duration: float = 1.4,
		border_color: Color = Color(1.0, 0.85, 0.1), model_height: float = 1.7) -> Tween:
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(root, meshes)
	if meshes.is_empty():
		root.visible = true
		return null

	var originals: Dictionary = {}
	var mats: Array[ShaderMaterial] = []
	for m in meshes:
		originals[m] = m.material_override
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		mat.set_shader_parameter("noiseTexture", _get_noise())
		mat.set_shader_parameter("up", false)
		mat.set_shader_parameter("offset", 1.0)
		mat.set_shader_parameter("borderColor", border_color)
		mat.set_shader_parameter("borderHeight", 0.12)
		mat.set_shader_parameter("noiseInfluence", 0.1)
		mat.set_shader_parameter("model_height", model_height)
		mat.set_shader_parameter("base_y", root.global_position.y)
		var src: Material = m.material_override if m.material_override else m.get_active_material(0)
		if src is BaseMaterial3D:
			mat.set_shader_parameter("base_color", src.albedo_color)
			if src.albedo_texture:
				mat.set_shader_parameter("has_texture", true)
				mat.set_shader_parameter("albedo_texture", src.albedo_texture)
		m.material_override = mat
		mats.append(mat)

	# Con todo disuelto (offset = 1) ya se puede mostrar el modelo sin que se vea de golpe
	root.visible = true

	var tween := tween_owner.create_tween()
	tween.tween_method(func(v: float) -> void:
		if not is_instance_valid(root):
			return
		for mat in mats:
			mat.set_shader_parameter("offset", v)
			mat.set_shader_parameter("base_y", root.global_position.y)
	, 1.0, 0.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func() -> void:
		for m in meshes:
			if is_instance_valid(m):
				m.material_override = originals[m]
	)
	return tween
