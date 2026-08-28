class_name XPOrb
extends Area3D

@export var xp_amount: float = 1.0
@export var speed: float = 10.0
@export var attract_radius: float = 8.0

var target: Node3D = null
var _velocity: Vector3 = Vector3.ZERO
var _magnetized: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_setup_particles()

func _setup_particles() -> void:
	var particles = CPUParticles3D.new()
	particles.amount = 16
	particles.lifetime = 1.2
	particles.randomness = 0.5
	particles.local_coords = false # Leave a trail as it flies to player
	
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 0.15
	particles.gravity = Vector3(0, 1.0, 0)
	particles.scale_amount_min = 0.1
	particles.scale_amount_max = 0.35
	
	var p_mesh = SphereMesh.new()
	p_mesh.radius = 0.1
	p_mesh.height = 0.2
	particles.mesh = p_mesh
	
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.1, 0.8, 1.0, 0.8) # Cyan/blue xp color
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.9, 1.0)
	mat.emission_energy_multiplier = 3.0
	particles.material_override = mat
	
	var ramp = Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.add_point(0.6, Color(1, 1, 1, 0.8))
	ramp.add_point(1.0, Color(1, 1, 1, 0))
	particles.color_ramp = ramp
	
	add_child(particles)

func _physics_process(delta: float) -> void:
	if not _magnetized:
		var players = get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			var p = players[0]
			if global_position.distance_to(p.global_position) < attract_radius:
				target = p
				_magnetized = true

	if _magnetized and is_instance_valid(target):
		var dir = (target.global_position - global_position).normalized()
		global_position += dir * speed * delta
		
		if global_position.distance_to(target.global_position) < 1.0:
			_on_body_entered(target)

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		# Get stats component to add XP
		var stats = body.get_node_or_null("StatsComponent")
		if not stats:
			stats = body.get("stats")
		if stats and stats.has_method("gain_experience"):
			stats.gain_experience(xp_amount)
			queue_free()
