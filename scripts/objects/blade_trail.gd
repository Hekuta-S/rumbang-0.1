class_name BladeTrail
extends MeshInstance3D

## Estela que sigue la hoja de un arma: guarda la posición de `base` y `tip`
## cada frame mientras está activa y dibuja una cinta que se desvanece.
## Uso: emit(duración) al iniciar el golpe.

const SHADER: Shader = preload("res://assets/shaders/blade_trail.gdshader")
const LIFETIME := 0.22                 ## cuánto dura cada tramo de la cinta (s)
const MAX_POINTS := 48

var base: Node3D
var tip: Node3D
var _points: Array = []                # [[base: Vector3, tip: Vector3, time: float]]
var _emit_left: float = 0.0
var _time: float = 0.0
var _imesh := ImmediateMesh.new()

func setup(p_base: Node3D, p_tip: Node3D, color: Color = Color(0.2, 1.0, 0.45)) -> void:
	base = p_base
	tip = p_tip
	top_level = true
	mesh = _imesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("trail_color", color)
	material_override = mat

func emit(duration: float) -> void:
	_emit_left = maxf(_emit_left, duration)

func _process(delta: float) -> void:
	_time += delta
	global_transform = Transform3D.IDENTITY
	if _emit_left > 0.0 and is_instance_valid(base) and base.is_visible_in_tree():
		_emit_left -= delta
		_points.push_front([base.global_position, tip.global_position, _time])
		if _points.size() > MAX_POINTS:
			_points.pop_back()
	while not _points.is_empty() and _time - float(_points.back()[2]) > LIFETIME:
		_points.pop_back()
	_imesh.clear_surfaces()
	if _points.size() < 2:
		return
	_imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for pt in _points:
		var life := 1.0 - (_time - float(pt[2])) / LIFETIME
		_imesh.surface_set_color(Color(1, 1, 1, life))
		_imesh.surface_set_uv(Vector2(life, 0.0))
		_imesh.surface_add_vertex(pt[0])
		_imesh.surface_set_color(Color(1, 1, 1, life))
		_imesh.surface_set_uv(Vector2(life, 1.0))
		_imesh.surface_add_vertex(pt[1])
	_imesh.surface_end()
