class_name FlameBlast
extends Node3D

## Explosión de fuego del lanzallamas (click derecho de Vangry en la mazmorra). Solo visual:
## bola de fuego que se expande, onda en el suelo, ascuas, humo y un destello de luz.
## El daño y los empujes los aplica FlameThrowerStrategy.flame_blast().

const LIFE := 1.6

const FIREBALL_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, shadows_disabled, cull_back;
uniform float fade = 1.0;
void fragment() {
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 1.4);
	vec3 hot = mix(vec3(1.0, 0.62, 0.18), vec3(0.9, 0.16, 0.01), f);
	ALBEDO = hot * 1.5;
	ALPHA = (0.15 + 0.45 * (1.0 - f)) * fade;
}
"""
const RING_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, shadows_disabled, cull_disabled;
uniform float fade = 1.0;
void fragment() {
	float d = length(UV * 2.0 - 1.0);
	float ring = smoothstep(0.12, 0.0, abs(d - 0.88)) + smoothstep(0.9, 0.0, d) * 0.25;
	ALBEDO = vec3(1.0, 0.42, 0.06) * 3.0;
	ALPHA = clamp(ring, 0.0, 1.0) * fade;
}
"""

static var _fireball_shader: Shader
static var _ring_shader: Shader

static func spawn(parent: Node, pos: Vector3, radius: float) -> FlameBlast:
	var fb := FlameBlast.new()
	parent.add_child(fb)
	fb.global_position = pos
	fb._play(radius)
	return fb

func _play(radius: float) -> void:
	if _fireball_shader == null:
		_fireball_shader = Shader.new()
		_fireball_shader.code = FIREBALL_SHADER
		_ring_shader = Shader.new()
		_ring_shader.code = RING_SHADER

	# Bola de fuego
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 24
	sm.rings = 12
	ball.mesh = sm
	var ball_mat := ShaderMaterial.new()
	ball_mat.shader = _fireball_shader
	ball.material_override = ball_mat
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ball.scale = Vector3.ONE * 0.3
	add_child(ball)

	# Onda en el suelo
	var ring := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2.0, 2.0)
	ring.mesh = pm
	var ring_mat := ShaderMaterial.new()
	ring_mat.shader = _ring_shader
	ring.material_override = ring_mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position = Vector3(0.0, -global_position.y + 0.06, 0.0)
	ring.scale = Vector3.ONE * 0.4
	add_child(ring)

	# Luz
	var light := Quality.new_light()
	light.light_color = Color(1.0, 0.5, 0.15)
	light.light_energy = 9.0
	light.omni_range = radius * 2.5
	add_child(light)

	_add_embers(radius)
	_add_smoke(radius)

	var tw := create_tween().set_parallel(true)
	tw.tween_property(ball, "scale", Vector3.ONE * radius * 0.75, 0.32).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v): ball_mat.set_shader_parameter("fade", v), 1.0, 0.0, 0.5).set_delay(0.08)
	tw.tween_property(ring, "scale", Vector3.ONE * radius, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v): ring_mat.set_shader_parameter("fade", v), 1.0, 0.0, 0.45).set_delay(0.1)
	tw.tween_property(light, "light_energy", 0.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	get_tree().create_timer(LIFE).timeout.connect(queue_free)

func _add_embers(radius: float) -> void:
	var p := CPUParticles3D.new()
	p.amount = Quality.count(70)
	p.one_shot = true
	p.explosiveness = 0.95
	p.lifetime = 0.9
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.4
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = radius * 1.4
	p.initial_velocity_max = radius * 2.8
	p.gravity = Vector3(0, -7.0, 0)
	p.damping_min = 3.0
	p.damping_max = 5.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var mesh := SphereMesh.new()
	mesh.radius = 0.05
	mesh.height = 0.1
	mesh.radial_segments = 6
	mesh.rings = 3
	p.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.45, 0.1)
	mat.emission_energy_multiplier = 4.0
	p.material_override = mat
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.9, 0.5))
	g.set_color(1, Color(0.6, 0.08, 0.0))
	p.color_ramp = g
	add_child(p)
	p.emitting = true

func _add_smoke(radius: float) -> void:
	var p := CPUParticles3D.new()
	p.amount = Quality.count(14)
	p.one_shot = true
	p.explosiveness = 0.85
	p.lifetime = 1.4
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius * 0.35
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 2.5
	p.gravity = Vector3(0, 0.6, 0)
	p.scale_amount_min = 1.2
	p.scale_amount_max = 2.2
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	p.mesh = q
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	var tex := GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var tg := Gradient.new()
	tg.set_color(0, Color(1, 1, 1, 1))
	tg.set_color(1, Color(1, 1, 1, 0))
	tex.gradient = tg
	mat.albedo_texture = tex
	p.material_override = mat
	var g := Gradient.new()
	g.set_color(0, Color(0.25, 0.2, 0.18, 0.7))
	g.set_color(1, Color(0.1, 0.1, 0.1, 0.0))
	p.color_ramp = g
	add_child(p)
	p.emitting = true
