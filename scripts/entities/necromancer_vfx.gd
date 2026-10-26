class_name NecroVFX
extends RefCounted

## Efectos visuales del Jefe Nigromante (aura, haz de robo de vida, columnas de invocación,
## ondas de choque, almas y golpes). Todo se genera por código con partículas y un shader de haz.

const BEAM_SHADER: Shader = preload("res://assets/shaders/necro_beam.gdshader")

## Color del aura/efectos por fase del jefe (0 = morado, 1 = magenta, 2 = rojo).
const PHASE_COLORS: Array[Color] = [Color(0.55, 0.2, 0.95), Color(0.9, 0.2, 0.75), Color(1.0, 0.2, 0.15)]

static func _particle_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	return m

## Emisor de quads aditivos que se desvanecen; el tono se cambia con `.color`.
static func _particles(color: Color, amount: int, lifetime: float, quad: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = maxi(2, int(round(amount * Quality.particle_factor())))
	p.lifetime = lifetime
	p.color = color
	var q := QuadMesh.new()
	q.size = Vector2(quad, quad)
	p.mesh = q
	p.material_override = _particle_mat()
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.0))
	ramp.add_point(0.2, Color(1, 1, 1, 0.85))
	ramp.set_color(ramp.get_point_count() - 1, Color(1, 1, 1, 0.0))
	p.color_ramp = ramp
	return p

# ── Aura permanente ──────────────────────────────────────────────────────

## Niebla a los pies, motas de alma que suben y una luz que pulsa. Devuelve {fog, motes, light}.
static func add_aura(boss: Node3D) -> Dictionary:
	var fog := _particles(PHASE_COLORS[0], 26, 2.4, 2.2)
	fog.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	fog.emission_sphere_radius = 1.9
	fog.direction = Vector3.UP
	fog.spread = 30.0
	fog.gravity = Vector3.ZERO
	fog.initial_velocity_min = 0.2
	fog.initial_velocity_max = 0.7
	fog.scale_amount_min = 0.8
	fog.scale_amount_max = 1.6
	fog.position = Vector3(0, 0.4, 0)
	boss.add_child(fog)

	var motes := _particles(Color(0.6, 1.0, 0.7), 14, 2.0, 0.22)
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	motes.emission_sphere_radius = 1.6
	motes.direction = Vector3.UP
	motes.spread = 15.0
	motes.gravity = Vector3(0, 0.6, 0)
	motes.initial_velocity_min = 0.8
	motes.initial_velocity_max = 1.8
	motes.position = Vector3(0, 0.3, 0)
	boss.add_child(motes)

	var light := Quality.new_light()
	light.light_color = PHASE_COLORS[0]
	light.light_energy = 1.5
	light.omni_range = 9.0
	light.position = Vector3(0, 2.2, 0)
	boss.add_child(light)
	return {"fog": fog, "motes": motes, "light": light}

static func set_aura_phase(aura: Dictionary, phase: int) -> void:
	var c: Color = PHASE_COLORS[clampi(phase, 0, PHASE_COLORS.size() - 1)]
	if aura.has("fog"):
		aura["fog"].color = c
	if aura.has("light"):
		aura["light"].light_color = c

# ── Haz de robo de vida ──────────────────────────────────────────────────

static func make_beam() -> Node3D:
	var root := Node3D.new()
	root.top_level = true
	root.visible = false
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.17
	cyl.bottom_radius = 0.17
	cyl.height = 1.0
	cyl.radial_segments = 12
	cyl.rings = 1
	mi.mesh = cyl
	mi.rotation_degrees.x = 90.0
	mi.material_override = ShaderMaterial.new()
	(mi.material_override as ShaderMaterial).shader = BEAM_SHADER
	root.add_child(mi)
	root.set_meta("mi", mi)
	return root

## Estira el haz entre dos puntos del mundo y le da el tono pedido.
static func update_beam(root: Node3D, from: Vector3, to: Vector3, color: Color) -> void:
	var d := to - from
	var length := d.length()
	if length < 0.2 or not root.is_inside_tree():
		return
	root.global_position = from + d * 0.5
	root.look_at(to, Vector3.UP if absf(d.normalized().y) < 0.98 else Vector3.RIGHT)
	root.scale = Vector3(1.0, 1.0, length)
	var mat := (root.get_meta("mi") as MeshInstance3D).material_override as ShaderMaterial
	mat.set_shader_parameter("beam_length", length)
	mat.set_shader_parameter("tint", color)

## Chispas en el punto donde el haz toca al jugador.
static func make_sparks() -> CPUParticles3D:
	var s := _particles(Color(0.5, 1.0, 0.6), 18, 0.5, 0.16)
	s.top_level = true
	s.emitting = false
	s.direction = Vector3.UP
	s.spread = 180.0
	s.gravity = Vector3(0, -2.0, 0)
	s.initial_velocity_min = 1.5
	s.initial_velocity_max = 3.5
	return s

# ── Invocación / erupciones / fase / muerte ─────────────────────────────

## Columna de luz con humo que se disipa (aparición de un zombi).
static func column(parent: Node, pos: Vector3, color: Color) -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.55
	cyl.bottom_radius = 0.8
	cyl.height = 6.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(color.r, color.g, color.b, 0.55)
	var mi := MeshInstance3D.new()
	mi.mesh = cyl
	mi.material_override = mat
	parent.add_child(mi)
	mi.global_position = pos + Vector3(0, 3.0, 0)

	var dust := _particles(Color(0.45, 0.35, 0.3), 18, 0.9, 0.7)
	dust.one_shot = true
	dust.explosiveness = 0.9
	dust.direction = Vector3.UP
	dust.spread = 60.0
	dust.gravity = Vector3(0, -1.5, 0)
	dust.initial_velocity_min = 1.5
	dust.initial_velocity_max = 3.5
	parent.add_child(dust)
	dust.global_position = pos
	dust.emitting = true

	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.9)
	tw.tween_property(mi, "scale", Vector3(0.2, 1.0, 0.2), 0.9)
	tw.chain().tween_callback(mi.queue_free)
	dust.get_tree().create_timer(1.6).timeout.connect(dust.queue_free)

## Anillo que se expande por el suelo y se desvanece.
static func shockwave(parent: Node, pos: Vector3, radius: float, color: Color) -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.9
	torus.outer_radius = 1.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color.r, color.g, color.b, 0.9)
	var mi := MeshInstance3D.new()
	mi.mesh = torus
	mi.material_override = mat
	mi.scale = Vector3(0.4, 0.4, 0.4)
	parent.add_child(mi)
	mi.global_position = pos + Vector3(0, 0.15, 0)
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(radius, 0.5, radius), 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.55)
	tw.chain().tween_callback(mi.queue_free)

## Almas que suben al morir el jefe.
static func souls(parent: Node, pos: Vector3) -> void:
	var p := _particles(Color(0.7, 1.0, 0.85), 60, 2.2, 0.35)
	p.one_shot = true
	p.explosiveness = 0.5
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 1.5
	p.direction = Vector3.UP
	p.spread = 25.0
	p.gravity = Vector3(0, 1.5, 0)
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 5.0
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.get_tree().create_timer(3.5).timeout.connect(p.queue_free)

## Esquirlas de hueso/energía al recibir un golpe.
static func make_hit_fx() -> CPUParticles3D:
	var p := _particles(Color(0.95, 0.95, 0.8), 10, 0.45, 0.14)
	p.one_shot = true
	p.explosiveness = 1.0
	p.emitting = false
	p.direction = Vector3.UP
	p.spread = 180.0
	p.gravity = Vector3(0, -9.0, 0)
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 6.0
	return p
