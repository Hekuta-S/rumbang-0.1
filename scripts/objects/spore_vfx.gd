class_name SporeVFX
extends RefCounted

## Piezas visuales compartidas del bazuca de esporas (Bronch): jirones de gas suave y
## esporas brillantes. Todo con partículas billboard baratas y materiales cacheados
## (el shader volumétrico antiguo costaba decenas de FPS por partícula).

const GAS_COLOR := Color(0.35, 0.85, 0.22)
const SPORE_COLOR := Color(0.85, 1.0, 0.35)
const SPORE_GOLD := Color(1.0, 0.9, 0.3)

static var _soft_tex: GradientTexture2D = null
static var _quad: QuadMesh = null
static var _gas_mat: StandardMaterial3D = null
static var _speck_mat: StandardMaterial3D = null

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
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)])
	g.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	_soft_tex.gradient = g

	_quad = QuadMesh.new()
	_quad.size = Vector2(1, 1)

	# Gas: mezcla alfa (no aditiva) para que se vea como niebla verde y no como luz
	_gas_mat = StandardMaterial3D.new()
	_gas_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_gas_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_gas_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_gas_mat.billboard_keep_scale = true
	_gas_mat.vertex_color_use_as_albedo = true
	_gas_mat.albedo_texture = _soft_tex
	_gas_mat.no_depth_test = false
	_gas_mat.disable_receive_shadows = true

	# Esporas: aditivas y brillantes
	_speck_mat = StandardMaterial3D.new()
	_speck_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_speck_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_speck_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_speck_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_speck_mat.billboard_keep_scale = true
	_speck_mat.vertex_color_use_as_albedo = true
	_speck_mat.albedo_texture = _soft_tex
	_speck_mat.disable_receive_shadows = true

## Jirones de gas verde que derivan despacio.
static func gas(amount: int, lifetime: float, spread_radius: float, size_min: float, size_max: float, alpha: float = 0.2) -> CPUParticles3D:
	_ensure()
	var p := CPUParticles3D.new()
	p.amount = Quality.count(int(amount))
	p.lifetime = lifetime
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = spread_radius
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 0.05
	p.initial_velocity_max = 0.35
	p.gravity = Vector3(0, 0.12, 0)
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.scale_amount_min = size_min
	p.scale_amount_max = size_max
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.5))
	grow.add_point(Vector2(1.0, 1.4))
	p.scale_amount_curve = grow
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([
		Color(GAS_COLOR.r, GAS_COLOR.g, GAS_COLOR.b, 0.0),
		Color(GAS_COLOR.r, GAS_COLOR.g, GAS_COLOR.b, alpha),
		Color(0.2, 0.6, 0.15, 0.0)])
	ramp.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	p.color_ramp = ramp
	p.mesh = _quad
	p.material_override = _gas_mat
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p

## Esporas brillantes: puntitos aditivos que titilan y flotan.
static func specks(amount: int, lifetime: float, spread_radius: float, size_min: float, size_max: float, drift: float = 0.5) -> CPUParticles3D:
	_ensure()
	var p := CPUParticles3D.new()
	p.amount = Quality.count(int(amount))
	p.lifetime = lifetime
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = spread_radius
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = drift * 0.2
	p.initial_velocity_max = drift
	p.gravity = Vector3(0, 0.25, 0)
	p.randomness = 1.0
	p.scale_amount_min = size_min
	p.scale_amount_max = size_max
	var fade := Curve.new()
	fade.add_point(Vector2(0.0, 0.0))
	fade.add_point(Vector2(0.2, 1.0))
	fade.add_point(Vector2(0.75, 0.9))
	fade.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = fade
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([SPORE_GOLD, SPORE_COLOR, Color(0.3, 0.9, 0.5, 0.0)])
	ramp.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	p.color_ramp = ramp
	p.mesh = _quad
	p.material_override = _speck_mat
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p

## Calienta shaders y partículas una vez (evita el tirón de compilación la primera vez que
## se dispara el bazuca). Se crea un instante delante de la cámara con tamaño casi nulo.
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
	var g := gas(2, 0.2, 0.1, 0.1, 0.1)
	var s := specks(2, 0.2, 0.1, 0.1, 0.1)
	holder.add_child(g)
	holder.add_child(s)
	g.emitting = true
	s.emitting = true
	var t := parent.get_tree().create_timer(0.5)
	t.timeout.connect(holder.queue_free)
