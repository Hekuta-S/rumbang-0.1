class_name Prewarm
extends RefCounted

## Precalienta lo que más tirones da al aparecer por primera vez: compilación de shaders
## (orbes elementales, haz del jefe, estelas) y carga de modelos/animaciones de enemigos.
## Se ejecuta durante la pantalla de carga.

const SHADERS: Array[String] = [
	"res://assets/shaders/orbe_elemental.gdshader",
	"res://assets/shaders/necro_beam.gdshader",
	"res://assets/shaders/ribbon_mesh.gdshader",
	"res://assets/shaders/spear_slash.gdshader",
	"res://assets/shaders/sword_slash.gdshader",
	"res://assets/shaders/spirit.gdshader",
	"res://assets/shaders/hit_mark.gdshader",
	"res://assets/shaders/enemy_dissolve.gdshader",
	"res://assets/shaders/afterimage.gdshader",
	# Efectos de armas, aparición y avisos de enemigos: antes se compilaban en su primer uso, en pleno combate
	"res://assets/shaders/blade_trail.gdshader",
	"res://assets/shaders/slash_2_optimized.gdshader",
	"res://assets/shaders/spear_aura.gdshader",
	"res://assets/shaders/spear_thrust.gdshader",
	"res://assets/shaders/shotgun_distortion.gdshader",
	"res://assets/shaders/fire_flame.gdshader",
	"res://assets/shaders/dissolve_spawn.gdshader",
	"res://assets/shaders/depth_scan_spawn.gdshader",
	"res://assets/shaders/enemy_telegraph.gdshader",
	"res://assets/shaders/obsidian_cracks.gdshader",
	"res://assets/shaders/fog_gate.gdshader",
]

static var _done := false

static func run(parent: Node3D) -> void:
	if _done or parent == null or not parent.is_inside_tree():
		return
	_done = true
	_shaders(parent)
	# (los enemigos son datos: no hay nada que instanciar)

## Una malla diminuta por shader (y por elemento en los orbes) delante de la cámara durante medio segundo.
static func _shaders(parent: Node3D) -> void:
	var holder := Node3D.new()
	parent.add_child(holder)
	var cam := parent.get_viewport().get_camera_3d()
	holder.global_position = cam.global_position - cam.global_transform.basis.z * 2.0 if cam else Vector3.ZERO
	holder.scale = Vector3.ONE * 0.001
	for path in SHADERS:
		var shader := load(path) as Shader
		if shader == null:
			continue
		var variants := 6 if path.ends_with("orbe_elemental.gdshader") else 1
		for v in range(variants):
			var mi := MeshInstance3D.new()
			mi.mesh = SphereMesh.new()
			var sm := ShaderMaterial.new()
			sm.shader = shader
			if variants > 1:
				sm.set_shader_parameter("element", v)
			mi.material_override = sm
			holder.add_child(mi)
	parent.get_tree().create_timer(0.6).timeout.connect(holder.queue_free)
