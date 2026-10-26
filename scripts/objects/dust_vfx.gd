class_name DustVFX
extends RefCounted

## Piezas visuales de los POLVOS MÁGICOS de Tatan: neblina blanca suave, granos finos
## que titilan y destellos en cruz. Partículas billboard baratas con materiales cacheados.
## Todo en blanco con un toque del tinte de cada polvo.

static var _soft_tex: GradientTexture2D = null
static var _star_tex: ImageTexture = null
static var _quad: QuadMesh = null
static var _haze_mat: StandardMaterial3D = null
static var _grain_mat: StandardMaterial3D = null
static var _star_mat: StandardMaterial3D = null

static func _ensure() -> void:
	if _soft_tex != null:
		return
	_soft_tex = GradientTexture2D.new()
	_soft_tex.width = 64
	_soft_tex.height = 64
	_soft_tex.fill = GradientTexture2D.FILL_RADIAL
	_soft_tex.fill_from = Vector2(0.5, 0.5)
	_soft_tex.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.4), Color(1, 1, 1, 0)])
	g.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	_soft_tex.gradient = g

	# Destello en cruz: núcleo suave + 4 rayos finos
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in range(64):
		for x in range(64):
			var dx := (x + 0.5 - 32.0) / 32.0
			var dy := (y + 0.5 - 32.0) / 32.0
			var r2 := dx * dx + dy * dy
			var core := exp(-r2 * 38.0)
			var ray_h := exp(-absf(dy) * 55.0) * exp(-absf(dx) * 3.2)
			var ray_v := exp(-absf(dx) * 55.0) * exp(-absf(dy) * 3.2)
			var v := clampf(core + (ray_h + ray_v) * 0.9, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, v))
	_star_tex = ImageTexture.create_from_image(img)

	_quad = QuadMesh.new()
	_quad.size = Vector2(1, 1)

	_haze_mat = _billboard_mat(_soft_tex, false)
	_grain_mat = _billboard_mat(_soft_tex, true)
	_star_mat = _billboard_mat(_star_tex, true)

static func _billboard_mat(tex: Texture2D, additive: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = tex
	m.disable_receive_shadows = true
	return m

## Blanco con un toque (25 %) del tinte del polvo
static func whiten(tint: Color, amount: float = 0.75) -> Color:
	return Color(tint.r, tint.g, tint.b).lerp(Color.WHITE, amount)

## Neblina blanca suave.
static func haze(amount: int, lifetime: float, radius: float, size_min: float, size_max: float, tint: Color, alpha: float = 0.16) -> CPUParticles3D:
	_ensure()
	var p := CPUParticles3D.new()
	p.amount = Quality.count(int(amount))
	p.lifetime = lifetime
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 0.05
	p.initial_velocity_max = 0.4
	p.gravity = Vector3(0, 0.1, 0)
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.scale_amount_min = size_min
	p.scale_amount_max = size_max
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.6))
	grow.add_point(Vector2(1.0, 1.35))
	p.scale_amount_curve = grow
	var c := whiten(tint)
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([Color(c.r, c.g, c.b, 0.0), Color(c.r, c.g, c.b, alpha), Color(c.r, c.g, c.b, 0.0)])
	ramp.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	p.color_ramp = ramp
	p.mesh = _quad
	p.material_override = _haze_mat
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p

## Granos de polvo: puntitos blancos que titilan y caen despacio.
static func grains(amount: int, lifetime: float, radius: float, size_min: float, size_max: float, tint: Color, drift: float = 0.6) -> CPUParticles3D:
	_ensure()
	var p := CPUParticles3D.new()
	p.amount = Quality.count(int(amount))
	p.lifetime = lifetime
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = drift * 0.15
	p.initial_velocity_max = drift
	p.gravity = Vector3(0, -0.18, 0)          # el polvo se asienta lentamente
	p.damping_min = 0.4
	p.damping_max = 1.2
	p.randomness = 1.0
	p.scale_amount_min = size_min
	p.scale_amount_max = size_max
	var tw := Curve.new()                      # titileo: crece, parpadea y se apaga
	tw.add_point(Vector2(0.0, 0.0))
	tw.add_point(Vector2(0.15, 1.0))
	tw.add_point(Vector2(0.4, 0.45))
	tw.add_point(Vector2(0.6, 1.0))
	tw.add_point(Vector2(0.85, 0.5))
	tw.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = tw
	var c := whiten(tint, 0.85)
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([Color(1, 1, 1, 1), Color(c.r, c.g, c.b, 0.9), Color(c.r, c.g, c.b, 0.0)])
	ramp.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	p.color_ramp = ramp
	p.mesh = _quad
	p.material_override = _grain_mat
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p

## Destellos en cruz (pocos y más grandes).
static func sparkles(amount: int, lifetime: float, radius: float, size_min: float, size_max: float, tint: Color) -> CPUParticles3D:
	_ensure()
	var p := grains(amount, lifetime, radius, size_min, size_max, tint, 0.35)
	p.material_override = _star_mat
	p.angle_min = -20.0
	p.angle_max = 20.0
	return p

## Calienta shaders/partículas (evita el tirón de compilación en el primer lanzamiento).
static var _warmed: bool = false

static func prewarm(parent: Node3D, shader: Shader) -> void:
	if _warmed or parent == null or not parent.is_inside_tree():
		return
	_warmed = true
	var holder := Node3D.new()
	parent.add_child(holder)
	var cam := parent.get_viewport().get_camera_3d()
	holder.global_position = cam.global_position - cam.global_transform.basis.z * 2.0 if cam else Vector3.ZERO
	holder.scale = Vector3.ONE * 0.001
	var mi := MeshInstance3D.new()
	mi.mesh = SphereMesh.new()
	var sm := ShaderMaterial.new()
	sm.shader = shader
	mi.material_override = sm
	holder.add_child(mi)
	for ps in [haze(2, 0.2, 0.1, 0.1, 0.1, Color.WHITE), grains(2, 0.2, 0.1, 0.1, 0.1, Color.WHITE), sparkles(2, 0.2, 0.1, 0.1, 0.1, Color.WHITE)]:
		holder.add_child(ps)
		ps.emitting = true
	parent.get_tree().create_timer(0.5).timeout.connect(holder.queue_free)
