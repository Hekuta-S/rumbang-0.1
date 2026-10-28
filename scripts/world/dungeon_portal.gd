class_name DungeonPortal
extends Node3D

## Portal que aparece al limpiar la caverna final de un nivel de la mazmorra. Al cruzarlo se elige
## un arma nueva y se baja al siguiente nivel (lo gestiona DungeonEncounter).

signal entered

const COLOR := Color(0.55, 0.3, 1.0)
const RADIUS := 1.5

const SWIRL := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 col : source_color = vec4(0.55, 0.3, 1.0, 1.0);
uniform float fade = 1.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ang = atan(p.y, p.x);
	float swirl = 0.5 + 0.5 * sin(ang * 5.0 + r * 14.0 - TIME * 4.0);
	float core = smoothstep(1.0, 0.0, r);
	float edge = smoothstep(0.75, 0.98, r) * smoothstep(1.02, 0.96, r);
	vec3 c = mix(col.rgb, vec3(0.6, 1.0, 1.0), swirl * core * 0.6);
	ALBEDO = c * (1.0 + swirl * 1.5 + edge * 3.0);
	ALPHA = clamp((core * (0.35 + 0.45 * swirl) + edge) * step(r, 1.0) * fade, 0.0, 1.0);
}
"""
static var _swirl_shader: Shader

var _area: Area3D
var _used := false

static func spawn(parent: Node, at: Vector3) -> DungeonPortal:
	var p := DungeonPortal.new()
	parent.add_child(p)
	p.global_position = at
	return p

func _ready() -> void:
	if _swirl_shader == null:
		_swirl_shader = Shader.new()
		_swirl_shader.code = SWIRL
	var holder := Node3D.new()
	holder.position = Vector3(0, RADIUS + 0.2, 0)
	add_child(holder)
	# Disco giratorio (billboard en el eje vertical: siempre de cara al jugador)
	var disc := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(RADIUS * 2.0, RADIUS * 2.0)
	disc.mesh = quad
	var dm := ShaderMaterial.new()
	dm.shader = _swirl_shader
	disc.material_override = dm
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(disc)
	# Aro de piedra rúnica
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = RADIUS * 0.95
	torus.outer_radius = RADIUS * 1.12
	torus.rings = 32
	torus.ring_segments = 10
	ring.mesh = torus
	ring.rotation.x = PI * 0.5
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.12, 0.1, 0.16)
	rm.emission_enabled = true
	rm.emission = COLOR
	rm.emission_energy_multiplier = 1.8
	ring.material_override = rm
	holder.add_child(ring)
	var light := Quality.new_light()
	light.light_color = COLOR
	light.light_energy = 3.0
	light.omni_range = 7.0
	holder.add_child(light)
	var sparks := DustVFX.sparkles(16, 1.2, RADIUS, 0.12, 0.25, COLOR)
	sparks.gravity = Vector3(0, 0.6, 0)
	holder.add_child(sparks)
	sparks.emitting = true
	# Zona de entrada
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = 2        # jugador
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = RADIUS * 0.8
	shape.height = 2.5
	cs.shape = shape
	cs.position = Vector3(0, 1.25, 0)
	_area.add_child(cs)
	add_child(_area)
	_area.body_entered.connect(_on_body)
	# Aparece creciendo
	holder.scale = Vector3.ONE * 0.05
	create_tween().tween_property(holder, "scale", Vector3.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	AudioManager.play_at("boss_sting", global_position, -6.0, 1.2)
	_holder = holder

var _holder: Node3D
## Respaldo por si el área física no detecta al jugador: basta con acercarse al centro
var player: Node3D
const TOUCH_RADIUS := 1.4
## Solo se activa después de que el jugador haya estado fuera de él (si aparece encima, no salta)
var _armed := false

func _process(_delta: float) -> void:
	if _used or not is_instance_valid(player):
		return
	var d := Vector2(player.global_position.x - global_position.x, player.global_position.z - global_position.z).length()
	if not _armed:
		_armed = d > TOUCH_RADIUS + 0.6
	elif d < TOUCH_RADIUS:
		_used = true
		entered.emit()
	# El disco y el aro miran siempre a la cámara (solo giro horizontal)
	var cam := get_viewport().get_camera_3d()
	if cam and _holder:
		var to_cam := cam.global_position - _holder.global_position
		to_cam.y = 0.0
		if to_cam.length_squared() > 0.01:
			_holder.look_at(_holder.global_position - to_cam, Vector3.UP)

func _on_body(body: Node) -> void:
	if _used or not _armed or not body.is_in_group("player"):
		return
	_used = true
	entered.emit()
