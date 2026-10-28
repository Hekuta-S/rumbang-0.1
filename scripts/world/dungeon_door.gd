class_name DungeonDoor
extends Node3D

## Barrera rúnica que tapa una boca de túnel mientras hay goblins vivos en la caverna (mazmorra).
## Una columna de energía roja por celda de la boca, con colisión en la capa del mundo (frena al
## jugador y a los goblins). Sube del suelo al cerrarse y se hunde al abrirse.

const CELL := 2.0
const HEIGHT := 3.6
const COLOR := Color(1.0, 0.18, 0.12)

const SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 col : source_color = vec4(1.0, 0.18, 0.12, 1.0);
uniform float fade = 1.0;
void fragment() {
	// Barrotes verticales que suben, más intensos abajo y en los bordes de la columna
	float bars = smoothstep(0.75, 1.0, abs(sin(UV.x * 18.0)));
	float flow = 0.5 + 0.5 * sin(UV.y * 22.0 - TIME * 5.0 + UV.x * 6.0);
	float rim = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.0);
	float bottom = 1.0 - UV.y * 0.6;
	float a = (0.18 + 0.55 * bars * flow + 0.5 * rim) * bottom * fade;
	ALBEDO = col.rgb * (1.5 + bars * 2.0);
	ALPHA = clamp(a, 0.0, 1.0);
}
"""
static var _shader: Shader

var _mat: ShaderMaterial
var _body: StaticBody3D
var _open := false

## Crea (cerrada) una barrera sobre las celdas `cells` (posiciones de mundo).
static func spawn(parent: Node, cells: Array) -> DungeonDoor:
	var d := DungeonDoor.new()
	parent.add_child(d)
	d._build(cells)
	return d

func _build(cells: Array) -> void:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = _shader
	_body = StaticBody3D.new()
	_body.collision_layer = 1
	_body.collision_mask = 0
	add_child(_body)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(CELL, HEIGHT, CELL)
	var center := Vector3.ZERO
	for c in cells:
		center += c
	center /= maxf(cells.size(), 1)
	global_position = Vector3(center.x, 0.0, center.z)
	for c in cells:
		var local: Vector3 = Vector3(c.x, 0.0, c.z) - global_position
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(CELL, HEIGHT, CELL)
		cs.shape = shape
		cs.position = local + Vector3(0.0, HEIGHT * 0.5, 0.0)
		_body.add_child(cs)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = _mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = local + Vector3(0.0, HEIGHT * 0.5, 0.0)
		add_child(mi)
	var light := Quality.new_light()
	light.light_color = COLOR
	light.light_energy = 1.6
	light.omni_range = 3.5 + cells.size() * 0.6
	light.position = Vector3(0.0, 1.4, 0.0)
	add_child(light)
	# Sube desde el suelo
	position.y = -HEIGHT
	_mat.set_shader_parameter("fade", 0.0)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "position:y", 0.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v): _mat.set_shader_parameter("fade", v), 0.0, 1.0, 0.35)
	AudioManager.play_at("impact_magic", global_position, -6.0, 0.6)

func open() -> void:
	if _open:
		return
	_open = true
	_body.collision_layer = 0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "position:y", -HEIGHT, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_method(func(v): _mat.set_shader_parameter("fade", v), 1.0, 0.0, 0.6)
	tw.chain().tween_callback(queue_free)
	AudioManager.play_at("impact_magic", global_position, -4.0, 1.3)
