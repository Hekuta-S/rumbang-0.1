class_name AxeRibbon
extends Node

## Estela fucsia del hacha de Garri, la misma que la del hacha de supervivencia
## (spinning_axe_projectile.gd): una cinta RibbonTrail3D con el shader ribbon_mesh que sigue a un
## punto (`target`). Con `always = true` deja rastro siempre (hacha lanzada); si no, solo mientras
## dura emit() (giros con el hacha en la mano). La malla va en el mundo (top_level).

const MESH_SHADER := preload("res://assets/shaders/ribbon_mesh.gdshader")
## Colores de supervivencia: trayectoria y punta giratoria
const PATH := {"width": 0.8, "lifetime": 0.35, "points": 40, "color": Vector4(1.0, 0.05, 0.45, 0.95), "rim": Vector4(1.0, 0.35, 0.75, 1.0), "fade": 1.2}
const TIP := {"width": 0.45, "lifetime": 0.28, "points": 48, "color": Vector4(0.95, 0.0, 0.5, 0.9), "rim": Vector4(1.0, 0.4, 0.9, 1.0), "fade": 1.0}

var target: Node3D
var always := false
var _ribbon: RibbonTrail3D
var _mesh: MeshInstance3D
var _until := 0.0

static func make(parent: Node, p_target: Node3D, style: Dictionary, p_always: bool) -> AxeRibbon:
	var r := AxeRibbon.new()
	r.target = p_target
	r.always = p_always
	r._build(style)
	parent.add_child(r)
	return r

func _build(style: Dictionary) -> void:
	_ribbon = RibbonTrail3D.new()
	_ribbon.trail_width = style["width"]
	_ribbon.lifetime = style["lifetime"]
	_ribbon.max_points = style["points"]
	_mesh = MeshInstance3D.new()
	_mesh.top_level = true
	_mesh.mesh = _ribbon
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = MESH_SHADER
	mat.set_shader_parameter("trail_color", style["color"])
	mat.set_shader_parameter("rim_color", style["rim"])
	mat.set_shader_parameter("trail_fade_power", style["fade"])
	_mesh.material_override = mat
	add_child(_mesh)

## Deja rastro durante `seconds`.
func emit(seconds: float) -> void:
	_until = Time.get_ticks_msec() / 1000.0 + seconds

func is_emitting() -> bool:
	return always or Time.get_ticks_msec() / 1000.0 < _until

func _process(delta: float) -> void:
	if not is_instance_valid(target) or not target.is_inside_tree():
		return
	var cam := get_viewport().get_camera_3d()
	var cam_pos := cam.global_position if cam else target.global_position + Vector3(0, 5, 5)
	if is_emitting():
		_ribbon.add_trail_point(target.global_position)
	_ribbon.update_trail(delta, cam_pos)

func _exit_tree() -> void:
	if is_instance_valid(_mesh):
		_mesh.queue_free()
