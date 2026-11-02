class_name SlimePuddle
extends Node3D

## Mancha de baba que deja la babosa de basura al arrastrarse: frena al jugador local mientras la
## pisa (como el agua de las cloacas) y se seca en LIFETIME segundos. Cada equipo la deja con su
## copia de la babosa (también las marionetas), así que no viaja por la red.

const LIFETIME := 5.0
const FADE := 1.2                     ## s finales en los que se desvanece
const SLOW := 0.7                     ## velocidad del jugador encima
const COLOR := Color(0.45, 0.6, 0.12, 0.75)

static var _mesh: Mesh

var radius := 0.6
var _t := 0.0
var _mat: StandardMaterial3D

static func spawn(parent: Node, at: Vector3, p_radius: float) -> SlimePuddle:
	var s := SlimePuddle.new()
	s.radius = p_radius
	parent.add_child(s)
	s.global_position = Vector3(at.x, at.y + 0.03, at.z)
	s.rotation.y = randf() * TAU
	return s

func _ready() -> void:
	if _mesh == null:
		var disc := CylinderMesh.new()
		disc.top_radius = 1.0
		disc.bottom_radius = 1.0
		disc.height = 0.01
		disc.radial_segments = 14
		disc.rings = 1
		_mesh = disc
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	mi.scale = Vector3(radius * randf_range(0.85, 1.15), 1.0, radius * randf_range(0.7, 1.0))
	_mat = StandardMaterial3D.new()
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_color = COLOR
	_mat.roughness = 0.1
	_mat.metallic_specular = 0.9
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

func _physics_process(delta: float) -> void:
	_t += delta
	if _t >= LIFETIME:
		queue_free()
		return
	_mat.albedo_color.a = COLOR.a * clampf((LIFETIME - _t) / FADE, 0.0, 1.0)
	if Net.is_dedicated():
		return
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p == null:
		return
	var off := p.global_position - global_position
	if absf(off.y) > 0.6 or Vector2(off.x, off.z).length() > radius:
		return
	var mc = p.get("movement_controller")
	if mc != null:
		var now := Time.get_ticks_msec() / 1000.0
		mc.slow_mult = SLOW if now >= mc.slow_until else minf(mc.slow_mult, SLOW)
		mc.slow_until = maxf(mc.slow_until, now + 0.15)
