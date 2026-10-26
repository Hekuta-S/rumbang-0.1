class_name XPOrb
extends Area3D

@export var xp_amount: float = 1.0
@export var speed: float = 10.0
@export var attract_radius: float = 8.0

var target: Node3D = null
var _magnetized: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_setup_particles()

## Recursos compartidos por todos los orbes (antes cada orbe creaba su malla, material y gradiente).
static var _shared_mesh: SphereMesh = null
static var _shared_mat: StandardMaterial3D = null
static var _shared_ramp: Gradient = null

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

func _setup_particles() -> void:
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
	particles.color_ramp = _shared_ramp
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(particles)

## Jugador cacheado y comprobación de atracción espaciada (cada ~0.1 s en vez de cada frame).
var _player: Node3D = null
var _check_timer: float = randf() * 0.1

func _physics_process(delta: float) -> void:
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
		var dir = (target.global_position - global_position).normalized()
		global_position += dir * speed * delta

		if global_position.distance_to(target.global_position) < 1.0:
			_on_body_entered(target)

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		# Get stats component to add XP
		var exp_comp = body.get_node_or_null("ExperienceComponent")
		if exp_comp and exp_comp.has_method("gain_experience"):
			exp_comp.gain_experience(xp_amount)
			queue_free()
		else:
			var stats = body.get_node_or_null("StatsComponent")
			if not stats:
				stats = body.get("stats")
			if stats and stats.has_method("gain_experience"):
				stats.gain_experience(xp_amount)
				queue_free()
