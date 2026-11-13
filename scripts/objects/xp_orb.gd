class_name XPOrb
extends Area3D

@export var xp_amount: float = 1.0
@export var speed: float = 10.0
@export var attract_radius: float = 8.0

var target: Node3D = null
var _magnetized: bool = false
var _magnet_t := 0.0                 ## s desde que el imán la enganchó (acelera, RewardJuice.magnet_speed)
var _pop_vel := Vector3.ZERO         ## salto al soltarse (RewardJuice.pop_velocity)
var _pop_t := 0.0
var _rest_y := 0.0
const POP_TIME := 0.4
var _tier: int = -1
var _particles: CPUParticles3D = null
var _sprite: Sprite3D = null

## Imán del mapa: la gema vuela hacia `who` sin importar la distancia.
func pull_to(who: Node3D, pull_speed: float = 30.0) -> void:
	target = who
	_magnetized = true
	speed = pull_speed

## Suma XP a una gema ya existente (fusión por el tope de gemas): crece y cambia de color con el tier.
func add_xp(amount: float) -> void:
	xp_amount += amount
	_apply_tier()

## Color y tamaño según el valor de la gema (XpCurve.gem_tier): azul 1 · verde 5 · roja 25 · dorada 100.
func _apply_tier() -> void:
	var t := XpCurve.gem_tier(xp_amount)
	if t == _tier:
		return
	_tier = t
	scale = Vector3.ONE * float(XpCurve.TIER_SCALES[t])
	var col: Color = XpCurve.TIER_COLORS[t]
	if _particles:
		_particles.material_override = _tier_material(t)
	if _sprite:
		_sprite.modulate = col

static var _tier_mats: Array = []

static func _tier_material(t: int) -> StandardMaterial3D:
	_ensure_shared()
	if _tier_mats.is_empty():
		for i in range(XpCurve.TIER_COLORS.size()):
			var m: StandardMaterial3D = _shared_mat.duplicate()
			var c: Color = XpCurve.TIER_COLORS[i]
			m.albedo_color = Color(c.r, c.g, c.b, 0.8)
			m.emission = c
			_tier_mats.append(m)
	return _tier_mats[t]

func _ready() -> void:
	add_to_group("xp_orbs")
	body_entered.connect(_on_body_entered)
	_setup_particles()
	# Sale con un saltito y rebota antes de quedarse quieta
	_rest_y = global_position.y
	_pop_vel = RewardJuice.pop_velocity(3.0, 4.2, 1.4)
	_pop_t = POP_TIME

## Recursos compartidos por todos los orbes (antes cada orbe creaba su malla, material y gradiente).
static var _shared_mesh: SphereMesh = null
static var _shared_mat: StandardMaterial3D = null
static var _shared_ramp: Gradient = null
static var _shared_tex: GradientTexture2D = null

static func _ensure_shared() -> void:
	if _shared_mesh != null:
		return
	_shared_mesh = SphereMesh.new()
	_shared_mesh.radius = 0.1
	_shared_mesh.height = 0.2
	_shared_mesh.radial_segments = 8
	_shared_mesh.rings = 4
	_shared_mat = StandardMaterial3D.new()
	_shared_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shared_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shared_mat.albedo_color = Color(0.1, 0.8, 1.0, 0.8) # Cyan/blue xp color
	_shared_mat.emission_enabled = true
	_shared_mat.emission = Color(0.2, 0.9, 1.0)
	_shared_mat.emission_energy_multiplier = 3.0
	_shared_ramp = Gradient.new()
	_shared_ramp.set_color(0, Color(1, 1, 1, 1))
	_shared_ramp.add_point(0.6, Color(1, 1, 1, 0.8))
	_shared_ramp.add_point(1.0, Color(1, 1, 1, 0))

## Gráficos bajos: sprite billboard 2D ligero (sin malla CSG ni partículas 3D).
func _setup_sprite_2d() -> void:
	var csg := get_node_or_null("CSGSphere3D")
	if csg:
		csg.queue_free()
	if _shared_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(0.85, 1.0, 1.0, 1.0))
		g.add_point(0.45, Color(0.2, 0.9, 1.0, 0.9))
		g.set_color(g.get_point_count() - 1, Color(0.1, 0.7, 1.0, 0.0))
		_shared_tex = GradientTexture2D.new()
		_shared_tex.gradient = g
		_shared_tex.fill = GradientTexture2D.FILL_RADIAL
		_shared_tex.fill_from = Vector2(0.5, 0.5)
		_shared_tex.fill_to = Vector2(1.0, 0.5)
		_shared_tex.width = 32
		_shared_tex.height = 32
	var sprite := Sprite3D.new()
	sprite.texture = _shared_tex
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.shaded = false
	sprite.transparent = true
	sprite.pixel_size = 0.015
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sprite)
	_sprite = sprite

func _setup_particles() -> void:
	if Quality.level() == Quality.Level.LOW:
		_setup_sprite_2d()
		_apply_tier()
		return
	_ensure_shared()
	var particles = CPUParticles3D.new()
	particles.amount = int(maxi(4, round(8.0 * Quality.particle_factor())))
	particles.lifetime = 1.2
	particles.randomness = 0.5
	particles.local_coords = false # Leave a trail as it flies to player

	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 0.15
	particles.gravity = Vector3(0, 1.0, 0)
	particles.scale_amount_min = 0.1
	particles.scale_amount_max = 0.35
	particles.mesh = _shared_mesh
	particles.material_override = _shared_mat
	_particles = particles
	particles.color_ramp = _shared_ramp
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(particles)
	_apply_tier()

## Jugador cacheado y comprobación de atracción espaciada (cada ~0.1 s en vez de cada frame).
var _player: Node3D = null
var _check_timer: float = randf() * 0.1

func _physics_process(delta: float) -> void:
	if not _magnetized and (_pop_t > 0.0 or not RewardJuice.settled(self, _pop_vel, _rest_y)):
		_pop_t -= delta
		_pop_vel = RewardJuice.bounce(self, _pop_vel, _rest_y, delta)
		return
	if not _magnetized:
		_check_timer -= delta
		if _check_timer > 0.0:
			return
		_check_timer = 0.1
		if not is_instance_valid(_player):
			_player = get_tree().get_first_node_in_group("player")
		if _player:
			var radius := attract_radius
			var sb = _player.get("stat_block")
			if sb:
				radius += sb.magnet_bonus()
			if global_position.distance_squared_to(_player.global_position) < radius * radius:
				target = _player
				_magnetized = true
		return

	if is_instance_valid(target):
		var to: Vector3 = target.global_position - global_position
		_magnet_t += delta
		global_position += to.normalized() * minf(RewardJuice.magnet_speed(speed, _magnet_t) * delta, to.length())

		if global_position.distance_to(target.global_position) < 1.0:
			_on_body_entered(target)

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		# Get stats component to add XP
		var exp_comp = body.get_node_or_null("ExperienceComponent")
		if exp_comp and exp_comp.has_method("gain_experience"):
			exp_comp.gain_experience(xp_amount)
			_collect_fx()
			queue_free()
		else:
			var stats = body.get_node_or_null("StatsComponent")
			if not stats:
				stats = body.get("stats")
			if stats and stats.has_method("gain_experience"):
				stats.gain_experience(xp_amount)
				_collect_fx()
				queue_free()

## Tintineo con escalera de tono (las gemas grandes suenan más graves) y chispa del color del tier.
func _collect_fx() -> void:
	var t := maxi(_tier, 0)
	RewardJuice.collect(get_parent(), global_position, XpCurve.TIER_COLORS[t], "pickup", -13.0 + 2.0 * t, 1.25 - 0.1 * t)
