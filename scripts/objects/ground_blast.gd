class_name GroundBlast
extends Node3D

## Erupción en el suelo: durante `delay` segundos el suelo burbujea (vapores que suben y una luz
## que late cada vez más fuerte) y, al completarse, estalla en una columna de llamas con onda
## expansiva; daña una vez al jugador si sigue dentro. La usa el jefe necromántico (varias a la vez).
## El burbujeo y el estallido se ven siempre; el círculo del suelo es la marca de ataque y
## respeta la opción SettingsManager.show_attack_marks.

const TELEGRAPH_SHADER: Shader = preload("res://assets/shaders/enemy_telegraph.gdshader")

var radius := 1.6
var delay := 1.0
var damage := 3.0
var color := Color(0.3, 1.0, 0.6)
var _t := 0.0
var _mat: ShaderMaterial
var _light: OmniLight3D
var _done := false
var visual_only := false              ## copia en un cliente: solo se ve, el daño lo decide el anfitrión

static func spawn(parent: Node, at: Vector3, p_radius: float, p_delay: float, p_damage: float, p_color: Color) -> GroundBlast:
	var g := GroundBlast.new()
	g.radius = p_radius
	g.delay = p_delay
	g.damage = p_damage
	g.color = p_color
	parent.add_child(g)
	g.global_position = Vector3(at.x, at.y + 0.05, at.z)
	if Net.is_host():
		var nw := g.get_tree().current_scene.get_node_or_null("NetWorld")
		if nw:
			nw.fx_blast(at, p_radius, p_delay, p_damage, p_color)
	return g

func _ready() -> void:
	# Marca de ataque (opcional)
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(radius * 2.0, radius * 2.0)
	mi.mesh = plane
	_mat = ShaderMaterial.new()
	_mat.shader = TELEGRAPH_SHADER
	_mat.set_shader_parameter("shape", 2)
	_mat.set_shader_parameter("color", Vector3(color.r, color.g, color.b))
	_mat.set_shader_parameter("progress", 0.0)
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = SettingsManager.show_attack_marks
	add_child(mi)
	# Burbujeo (siempre): vapores que suben por toda la zona y chispas
	var vapor := DustVFX.haze(22, 0.9, radius * 0.8, 0.5, 1.1, color, 0.32)
	vapor.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE_SURFACE
	vapor.emission_sphere_radius = radius * 0.75
	vapor.initial_velocity_min = 0.6
	vapor.initial_velocity_max = 1.4
	vapor.gravity = Vector3(0, 1.2, 0)
	add_child(vapor)
	vapor.emitting = true
	var sparks := DustVFX.sparkles(16, 0.6, radius * 0.6, 0.08, 0.18, color)
	sparks.gravity = Vector3(0, 2.0, 0)
	add_child(sparks)
	sparks.emitting = true
	_light = Quality.new_light()
	_light.light_color = color
	_light.light_energy = 0.2
	_light.omni_range = radius * 2.2
	_light.position = Vector3(0, 0.4, 0)
	add_child(_light)

func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	var k := clampf(_t / delay, 0.0, 1.0)
	_mat.set_shader_parameter("progress", k)
	# La luz late cada vez más rápido y más fuerte
	_light.light_energy = (0.3 + 2.2 * k) * (0.6 + 0.4 * sin(_t * (6.0 + 22.0 * k)))
	if _t >= delay:
		_explode()

func _explode() -> void:
	_done = true
	if not visual_only:
		for target in NetPlayers.alive():
			var toff: Vector3 = (target as Node3D).global_position - global_position
			if absf(toff.y) < 1.6 and Vector2(toff.x, toff.z).length() <= radius + 0.45:
				target.take_damage(damage, Vector3(toff.x, 0.0, toff.z).normalized())
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if is_instance_valid(player):
		var off := player.global_position - global_position
		var d := Vector2(off.x, off.z).length()
		HitFeedback.shake(0.3 * clampf(1.0 - d / 14.0, 0.0, 1.0))
	AudioManager.play_at("impact_magic", global_position, -1.0, 0.55)
	var root := get_tree().current_scene
	if root:
		_pillar(root)
		NecroVFX.shockwave(root, global_position, radius * 1.6, color)
		var flash := Quality.new_light()
		flash.light_color = color
		flash.light_energy = 6.0
		flash.omni_range = radius * 4.0
		root.add_child(flash)
		flash.global_position = global_position + Vector3(0, 1.0, 0)
		var tw := flash.create_tween()
		tw.tween_property(flash, "light_energy", 0.0, 0.45)
		tw.tween_callback(flash.queue_free)
	queue_free()

static var _dot: GradientTexture2D

## Punto redondo y difuminado para las llamas (sin textura, las partículas son cuadrados).
static func _soft_dot() -> GradientTexture2D:
	if _dot == null:
		var g := Gradient.new()
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
		g.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
		_dot = GradientTexture2D.new()
		_dot.gradient = g
		_dot.fill = GradientTexture2D.FILL_RADIAL
		_dot.fill_from = Vector2(0.5, 0.5)
		_dot.fill_to = Vector2(0.5, 0.0)
		_dot.width = 64
		_dot.height = 64
	return _dot

## Columna de llamas que sube del suelo (partículas aditivas, como la erupción de supervivencia).
func _pillar(root: Node) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.85
	p.amount = maxi(12, int(round(50.0 * Quality.particle_factor())))
	p.lifetime = 0.8
	p.local_coords = false
	var quad := QuadMesh.new()
	quad.size = Vector2(0.6, 0.6)
	p.mesh = quad
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius * 0.55
	p.direction = Vector3.UP
	p.spread = 14.0
	p.gravity = Vector3(0, 2.0, 0)
	p.initial_velocity_min = 5.0
	p.initial_velocity_max = 9.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.6
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.2))
	curve.add_point(Vector2(0.2, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = curve
	var m := StandardMaterial3D.new()
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(color.r, color.g, color.b, 0.85)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft_dot()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA   # sin esto, el aditivo ignora el alfa del punto
	p.material_override = m
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([Color(1, 1, 1, 1), Color(color.r, color.g, color.b, 0.9), Color(color.r * 0.3, color.g * 0.3, color.b * 0.3, 0.0)])
	ramp.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	p.color_ramp = ramp
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(p)
	p.global_position = global_position
	p.emitting = true
	get_tree().create_timer(1.4).timeout.connect(p.queue_free)
