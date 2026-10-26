extends Area3D

## SmokeTrailZone.gd — estela de humo abrasador de Riva.
## Zona que el RivaSpeedController deja tras de sí en modo ráfaga: quema a los
## enemigos que están encima (DPS) durante unos segundos y luego se desvanece.
## Visual: pocas bocanadas de humo suaves (de naranja tenue a gris). Al terminar
## deja de emitir y espera a que el humo se disipe antes de borrarse.

@export var radius: float = 1.3
@export var damage_per_tick: float = 4.5
@export var tick_interval: float = 0.5
@export var lifetime: float = 3.0

const SMOKE_LIFETIME := 1.4

var _tick_accum: float = 0.0
var _ending: bool = false
var _smoke: CPUParticles3D

func _ready() -> void:
	add_to_group("riva_smoke")
	_build_visual()

func _physics_process(delta: float) -> void:
	if _ending:
		return
	lifetime -= delta
	if lifetime <= 0.0:
		_end()
		return

	_tick_accum += delta
	if _tick_accum < tick_interval:
		return
	_tick_accum = 0.0
	# Detección por distancia sobre el grupo "enemies" (mismo patrón que el
	# railgun / skill de Kaionz): más robusto que el overlap físico.
	for enemy in EnemyRegistry.query_radius(global_position, radius):
		if enemy.has_method("take_damage"):
			enemy.take_damage(damage_per_tick, Vector3.ZERO)

## Deja de dañar y de emitir; se borra cuando el humo restante se disipa.
func _end() -> void:
	_ending = true
	if _smoke:
		_smoke.emitting = false
	get_tree().create_timer(SMOKE_LIFETIME + 0.2).timeout.connect(queue_free)

func _build_visual() -> void:
	_smoke = CPUParticles3D.new()
	_smoke.amount = Quality.count(5)
	_smoke.lifetime = SMOKE_LIFETIME
	_smoke.preprocess = 0.2
	_smoke.direction = Vector3.UP
	_smoke.spread = 20.0
	_smoke.initial_velocity_min = 0.4
	_smoke.initial_velocity_max = 0.9
	_smoke.gravity = Vector3(0, 0.3, 0)
	_smoke.angle_max = 360.0
	_smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_smoke.emission_sphere_radius = radius * 0.4
	_smoke.position.y = 0.2
	var quad := QuadMesh.new()
	quad.size = Vector2(0.6, 0.6)
	_smoke.mesh = quad
	var smoke_mat := StandardMaterial3D.new()
	smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	smoke_mat.billboard_keep_scale = true
	smoke_mat.vertex_color_use_as_albedo = true
	smoke_mat.albedo_texture = _soft_puff_texture()
	_smoke.material_override = smoke_mat
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.9, 0.5, 0.2, 0.0))
	ramp.add_point(0.15, Color(0.75, 0.45, 0.25, 0.4))
	ramp.add_point(0.5, Color(0.35, 0.3, 0.28, 0.32))
	ramp.set_color(ramp.get_point_count() - 1, Color(0.2, 0.2, 0.2, 0.0))
	_smoke.color_ramp = ramp
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.5))
	grow.add_point(Vector2(1.0, 1.3))
	_smoke.scale_amount_curve = grow
	add_child(_smoke)
	_smoke.emitting = true

static var _puff_tex: GradientTexture2D

## Textura circular suave (en vez de esferas duras) para las bocanadas de humo.
static func _soft_puff_texture() -> GradientTexture2D:
	if _puff_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		_puff_tex = GradientTexture2D.new()
		_puff_tex.gradient = g
		_puff_tex.fill = GradientTexture2D.FILL_RADIAL
		_puff_tex.fill_from = Vector2(0.5, 0.5)
		_puff_tex.fill_to = Vector2(1.0, 0.5)
		_puff_tex.width = 64
		_puff_tex.height = 64
	return _puff_tex
