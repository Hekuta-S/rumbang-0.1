class_name FlameStream
extends Node3D

## Chorro de fuego del lanzallamas (Vangry). Todo procedural y barato:
##  - 1 emisor de llamas (partículas billboard aditivas, ~46 vivas) con cambio de color
##    blanco-amarillo → naranja → rojo oscuro y crecimiento,
##  - 1 emisor de chispas (14),
##  - 1 luz naranja que parpadea (sin sombras).
## Sustituye al prefab BinbunVFX (shaders con depth-texture y mucho overdraw).
##
## Uso: crear una vez, llamar aim(dir) y keep_alive() mientras se dispara;
## se apaga solo ~0.25 s después del último keep_alive().

const FLAME_AMOUNT := 120
const SPARK_AMOUNT := 14
const IDLE_TIMEOUT := 0.28
const BASE_SCALE_MIN := 0.55
const BASE_SCALE_MAX := 0.85
const BASE_SPEED_MIN := 15.0
const BASE_SPEED_MAX := 19.0
const BASE_DAMP_MIN := 11.0
const BASE_DAMP_MAX := 14.0

static var _soft_texture: GradientTexture2D = null
static var _flame_mesh: QuadMesh = null
static var _flame_material: StandardMaterial3D = null
static var _spark_mesh: SphereMesh = null
static var _spark_material: StandardMaterial3D = null

var _flames: CPUParticles3D
var _sparks: CPUParticles3D
var _light: OmniLight3D
var _alive_time: float = 0.0
var _flicker_t: float = 0.0
var _anchor: Node3D = null
var _size_mult: float = 1.0

func _init() -> void:
	top_level = true     # orientación propia (apunta donde se ataca), no la del modelo

func _ready() -> void:
	_build()

## Nodo del que toma la posición (el cañón del jugador).
func set_anchor(anchor: Node3D) -> void:
	_anchor = anchor
	if is_inside_tree() and anchor:
		global_position = anchor.global_position

func aim(dir: Vector3) -> void:
	if dir.length_squared() < 0.0001:
		return
	var target := global_position + dir.normalized()
	if absf(dir.normalized().dot(Vector3.UP)) > 0.99:
		return
	look_at(target, Vector3.UP)

func keep_alive() -> void:
	_alive_time = IDLE_TIMEOUT
	if _flames and not _flames.emitting:
		_flames.emitting = true
		_sparks.emitting = true
		_light.visible = true

## Escala el fuego: tamaño de las llamas, alcance y luz (la mejora "Llamarada ancha").
## El hitbox crece igual, así que alcance visual y real coinciden.
func apply_size(mult: float) -> void:
	if _flames == null or is_equal_approx(mult, _size_mult):
		return
	_size_mult = mult
	_flames.scale_amount_min = BASE_SCALE_MIN * mult
	_flames.scale_amount_max = BASE_SCALE_MAX * mult
	_flames.initial_velocity_min = BASE_SPEED_MIN * mult
	_flames.initial_velocity_max = BASE_SPEED_MAX * mult
	_flames.damping_min = BASE_DAMP_MIN * mult      # v y amortiguación ×m ⇒ alcance ×m
	_flames.damping_max = BASE_DAMP_MAX * mult
	_sparks.initial_velocity_min = 10.0 * mult
	_sparks.initial_velocity_max = 17.0 * mult
	_sparks.damping_min = 6.0 * mult
	_sparks.damping_max = 9.0 * mult
	_light.omni_range = 8.0 * mult
	_light.position = Vector3(0, 0, -3.0 * mult)

## Apaga el chorro de inmediato (recalentamiento).
func extinguish() -> void:
	_alive_time = 0.0
	if _flames:
		_flames.emitting = false
		_sparks.emitting = false
		_light.visible = false

func is_burning() -> bool:
	return _alive_time > 0.0

func _process(delta: float) -> void:
	if _anchor and is_instance_valid(_anchor):
		global_position = _anchor.global_position
	if _alive_time > 0.0:
		_alive_time -= delta
		_flicker_t += delta
		_light.light_energy = 2.6 * (0.8 + 0.2 * sin(_flicker_t * 31.0) + 0.1 * sin(_flicker_t * 13.0))
		if _alive_time <= 0.0:
			_flames.emitting = false
			_sparks.emitting = false
			_light.visible = false

# ───────────────────────────── Construcción ─────────────────────────────

func _build() -> void:
	_ensure_shared()

	_flames = CPUParticles3D.new()
	_flames.amount = Quality.count(int(FLAME_AMOUNT))
	_flames.lifetime = 0.65
	_flames.local_coords = false
	_flames.direction = Vector3(0, 0, -1)
	_flames.spread = 8.0
	_flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_flames.emission_sphere_radius = 0.18
	_flames.initial_velocity_min = BASE_SPEED_MIN
	_flames.initial_velocity_max = BASE_SPEED_MAX
	_flames.damping_min = BASE_DAMP_MIN
	_flames.damping_max = BASE_DAMP_MAX
	_flames.gravity = Vector3(0, 1.0, 0)          # las llamas se elevan un poco
	_flames.angle_min = 0.0
	_flames.angle_max = 360.0
	_flames.scale_amount_min = BASE_SCALE_MIN
	_flames.scale_amount_max = BASE_SCALE_MAX
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.45))
	grow.add_point(Vector2(0.4, 1.0))
	grow.add_point(Vector2(1.0, 2.8))
	_flames.scale_amount_curve = grow
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([
		Color(1.0, 0.82, 0.32, 0.34),    # núcleo amarillo cálido
		Color(1.0, 0.48, 0.08, 0.34),    # naranja
		Color(0.8, 0.14, 0.03, 0.24),    # rojo
		Color(0.25, 0.04, 0.02, 0.0),    # se apaga
	])
	ramp.offsets = PackedFloat32Array([0.0, 0.28, 0.65, 1.0])
	_flames.color_ramp = ramp
	_flames.mesh = _flame_mesh
	_flames.material_override = _flame_material
	_flames.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flames.emitting = false
	add_child(_flames)

	_sparks = CPUParticles3D.new()
	_sparks.amount = Quality.count(int(SPARK_AMOUNT))
	_sparks.lifetime = 0.6
	_sparks.local_coords = false
	_sparks.direction = Vector3(0, 0, -1)
	_sparks.spread = 22.0
	_sparks.initial_velocity_min = 10.0
	_sparks.initial_velocity_max = 17.0
	_sparks.damping_min = 6.0
	_sparks.damping_max = 9.0
	_sparks.gravity = Vector3(0, -4.0, 0)
	_sparks.scale_amount_min = 0.5
	_sparks.scale_amount_max = 1.0
	var sp_ramp := Gradient.new()
	sp_ramp.colors = PackedColorArray([Color(1.0, 0.9, 0.5, 1.0), Color(1.0, 0.4, 0.05, 0.0)])
	sp_ramp.offsets = PackedFloat32Array([0.0, 1.0])
	_sparks.color_ramp = sp_ramp
	_sparks.mesh = _spark_mesh
	_sparks.material_override = _spark_material
	_sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sparks.emitting = false
	add_child(_sparks)

	_light = Quality.new_light()
	_light.light_color = Color(1.0, 0.55, 0.18)
	_light.light_energy = 2.6
	_light.omni_range = 8.0
	_light.omni_attenuation = 1.4
	_light.shadow_enabled = false
	_light.position = Vector3(0, 0, -3.0)      # a media distancia del chorro
	_light.visible = false
	add_child(_light)

static func _ensure_shared() -> void:
	if _soft_texture != null:
		return
	_soft_texture = GradientTexture2D.new()
	_soft_texture.width = 64
	_soft_texture.height = 64
	_soft_texture.fill = GradientTexture2D.FILL_RADIAL
	_soft_texture.fill_from = Vector2(0.5, 0.5)
	_soft_texture.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.4), Color(1, 1, 1, 0)])
	g.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	_soft_texture.gradient = g

	_flame_mesh = QuadMesh.new()
	_flame_mesh.size = Vector2(1.0, 1.0)
	_flame_material = StandardMaterial3D.new()
	_flame_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flame_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flame_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flame_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_flame_material.billboard_keep_scale = true
	_flame_material.vertex_color_use_as_albedo = true
	_flame_material.albedo_texture = _soft_texture
	_flame_material.disable_receive_shadows = true

	_spark_mesh = SphereMesh.new()
	_spark_mesh.radius = 0.045
	_spark_mesh.height = 0.09
	_spark_mesh.radial_segments = 5
	_spark_mesh.rings = 2
	_spark_material = StandardMaterial3D.new()
	_spark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_spark_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_spark_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_spark_material.vertex_color_use_as_albedo = true
	_spark_material.albedo_color = Color(1, 1, 1, 1)
