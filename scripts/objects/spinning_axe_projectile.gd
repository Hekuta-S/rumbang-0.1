extends Area3D

var direction: Vector3
var damage: float = 0.0
var speed: float = 0.0
var max_range: float = 0.0
var traveled: float = 0.0
var is_spinning_in_place: bool = false
var spin_duration: float = 2.0
var spin_timer: float = 0.0
var tick_timer: float = 0.0
const DAMAGE_TICK_RATE = 0.2

@onready var visual = $Visual

func setup(dir: Vector3, dmg: float, spd: float, rng: float):
	direction = dir
	damage = dmg
	speed = spd
	max_range = rng

var spin_sfx: AudioStreamPlayer3D

func _ready():
	collision_layer = 0
	collision_mask = 1 # enemies
	body_entered.connect(_on_body_entered)
	
	spin_sfx = AudioStreamPlayer3D.new()
	var stream = AudioManager.get_stream("ataque-espalanza")
	spin_sfx.stream = stream
	spin_sfx.volume_db = -10.0
	spin_sfx.pitch_scale = 1.6
	add_child(spin_sfx)

	# --- Orbital / Flying Trail ---
	var trail := CPUParticles3D.new()
	trail.name = "AxeTrail"
	trail.local_coords = false
	trail.amount = 25
	trail.lifetime = 0.25
	trail.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	trail.emission_sphere_radius = 0.4
	trail.gravity = Vector3.ZERO
	trail.spread = 45.0
	trail.initial_velocity_min = 0.5
	trail.initial_velocity_max = 2.0
	trail.scale_amount_min = 0.3
	trail.scale_amount_max = 0.7

	var p_mesh := BoxMesh.new()
	p_mesh.size = Vector3(0.06, 0.06, 0.2)
	trail.mesh = p_mesh

	var t_mat := StandardMaterial3D.new()
	t_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	t_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	t_mat.albedo_color = Color(0.2, 0.9, 0.3, 0.45)
	t_mat.emission_enabled = true
	t_mat.emission = Color(0.2, 0.9, 0.3)
	t_mat.emission_energy_multiplier = 2.0
	trail.material_override = t_mat

	var color_ramp := Gradient.new()
	color_ramp.set_color(0, Color(0.2, 0.9, 0.3, 0.5))
	color_ramp.add_point(1.0, Color(0.1, 0.5, 0.2, 0.0))
	trail.color_ramp = color_ramp

	add_child(trail)
	trail.emitting = true

func _physics_process(delta: float):
	visual.rotate_y(15.0 * delta)
	visual.rotate_x(10.0 * delta)
	
	if spin_sfx and not spin_sfx.playing:
		spin_sfx.play()
	
	if not is_spinning_in_place:
		var move = direction * speed * delta
		global_position += move
		traveled += move.length()
		if traveled >= max_range:
			_start_spinning_in_place()
	else:
		spin_timer += delta
		tick_timer += delta
		
		if tick_timer >= DAMAGE_TICK_RATE:
			tick_timer = 0.0
			_apply_area_damage()
			
		if spin_timer >= spin_duration:
			queue_free()

func _on_body_entered(body: Node3D):
	if not is_spinning_in_place and body.is_in_group("enemies"):
		if body.has_method("take_damage"):
			body.take_damage(damage, direction)
		_start_spinning_in_place()

func _start_spinning_in_place():
	if is_spinning_in_place: return
	is_spinning_in_place = true
	# Make the hitbox a bit larger for area damage
	$CollisionShape3D.shape.radius = 2.0

	# --- Orbital Cutting Sparks ---
	var orbit_sparks := CPUParticles3D.new()
	orbit_sparks.name = "OrbitSparks"
	orbit_sparks.local_coords = true
	orbit_sparks.amount = 24
	orbit_sparks.lifetime = 0.35
	orbit_sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	orbit_sparks.emission_ring_radius = 1.8
	orbit_sparks.emission_ring_inner_radius = 1.2
	orbit_sparks.direction = Vector3.UP
	orbit_sparks.spread = 30.0
	orbit_sparks.initial_velocity_min = 2.0
	orbit_sparks.initial_velocity_max = 5.0
	orbit_sparks.scale_amount_min = 0.4
	orbit_sparks.scale_amount_max = 0.9

	var p_mesh := BoxMesh.new()
	p_mesh.size = Vector3(0.06, 0.06, 0.18)
	orbit_sparks.mesh = p_mesh

	var sp_mat := StandardMaterial3D.new()
	sp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sp_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sp_mat.albedo_color = Color(0.4, 1.0, 0.5, 0.55)
	sp_mat.emission_enabled = true
	sp_mat.emission = Color(0.3, 1.0, 0.4)
	sp_mat.emission_energy_multiplier = 2.5
	orbit_sparks.material_override = sp_mat

	var sp_ramp = Gradient.new()
	sp_ramp.set_color(0, Color(0.4, 1.0, 0.5, 0.6))
	sp_ramp.add_point(1.0, Color(0.2, 0.6, 0.3, 0.0))
	orbit_sparks.color_ramp = sp_ramp

	add_child(orbit_sparks)
	orbit_sparks.emitting = true

func _apply_area_damage():
	for body in get_overlapping_bodies():
		if body.is_in_group("enemies") and body.has_method("take_damage"):
			body.take_damage(damage * 0.5, Vector3.ZERO)
