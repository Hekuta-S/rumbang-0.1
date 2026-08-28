extends Area3D

## SporeProjectile.gd
## A canister fired by Bronch's spore bazooka.
## On impact (or at max range) it bursts into a lingering corrosive
## spore cloud that damages enemies over time.

@export var speed: float = 18.0
@export var damage: float = 20.0
@export var max_lifetime: float = 2.5

var direction: Vector3 = Vector3.FORWARD
var lifetime: float = 0.0
var is_hit: bool = false

var cloud_dps: float = 3.0
var cloud_duration: float = 3.5
var cloud_radius: float = 2.6

var cloud_scene = preload("res://scenes/objects/spore_cloud.tscn")

func _ready() -> void:
	add_to_group("bullets")
	body_entered.connect(_on_body_entered)

func setup(dir: Vector3, dmg: float, speed_val: float, cloud_dps_val: float, cloud_dur: float, cloud_rad: float) -> void:
	direction = dir.normalized()
	damage = dmg
	speed = speed_val
	cloud_dps = cloud_dps_val
	cloud_duration = cloud_dur
	cloud_radius = cloud_rad

	if direction.length_squared() > 0.001 and direction.cross(Vector3.UP).length_squared() > 0.001:
		look_at(global_position + direction, Vector3.UP)

	_setup_spore_trail()

func _setup_spore_trail() -> void:
	var trail := CPUParticles3D.new()
	trail.name = "SporeTrail"
	trail.local_coords = false
	trail.amount = 24
	trail.lifetime = 0.28
	trail.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINT
	trail.gravity = Vector3(0, 1.0, 0)
	trail.spread = 20.0
	trail.initial_velocity_min = 0.5
	trail.initial_velocity_max = 1.2
	trail.scale_amount_min = 0.3
	trail.scale_amount_max = 0.8

	var p_mesh := SphereMesh.new()
	p_mesh.radius = 0.1
	p_mesh.height = 0.2
	trail.mesh = p_mesh

	var t_mat := StandardMaterial3D.new()
	t_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	t_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	t_mat.albedo_color = Color(0.8, 0.95, 0.3, 0.4)
	t_mat.emission_enabled = true
	t_mat.emission = Color(0.7, 0.95, 0.2)
	t_mat.emission_energy_multiplier = 1.8
	trail.material_override = t_mat

	var color_ramp := Gradient.new()
	color_ramp.set_color(0, Color(0.8, 0.95, 0.3, 0.45))
	color_ramp.add_point(1.0, Color(0.3, 0.7, 0.1, 0.0))
	trail.color_ramp = color_ramp

	add_child(trail)
	trail.emitting = true

func _physics_process(delta: float) -> void:
	if is_hit: return

	var current_pos = global_position
	var next_pos = current_pos + direction * speed * delta

	# Step collision so fast projectiles don't tunnel through geometry/enemies.
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(current_pos, next_pos)
	query.collision_mask = 1 # World + enemies layer
	var hit = space_state.intersect_ray(query)
	if not hit.is_empty():
		global_position = hit.position
		_burst(hit.collider, hit.position)
		return

	global_position = next_pos
	lifetime += delta
	if lifetime >= max_lifetime:
		_burst(null, global_position)

func _on_body_entered(body: Node3D) -> void:
	if is_hit: return
	if not is_inside_tree(): return
	_burst(body, global_position)

func _burst(hit_body: Node3D, hit_pos: Vector3) -> void:
	if is_hit: return
	is_hit = true

	# Direct impact damage on the enemy that was hit.
	if hit_body and hit_body.is_in_group("enemies") and hit_body.has_method("take_damage"):
		hit_body.take_damage(damage, direction)

	# Leave a lingering corrosive cloud.
	var cloud = cloud_scene.instantiate()
	cloud.damage_per_tick = cloud_dps
	cloud.lifetime = cloud_duration
	cloud.radius = cloud_radius
	get_parent().add_child(cloud)
	cloud.global_position = hit_pos

	_spawn_burst_visual(hit_pos)
	AudioManager.play_at("explosion_bits", hit_pos)
	queue_free()

func _spawn_burst_visual(pos: Vector3) -> void:
	if not is_inside_tree(): return
	var container = Node3D.new()
	get_parent().add_child(container)
	container.global_position = pos

	var light = OmniLight3D.new()
	light.light_color = Color(0.8, 0.95, 0.3)
	light.light_energy = 5.0
	light.omni_range = 4.5
	container.add_child(light)

	# --- Expanding Toxic Gas Ring ---
	var ring = MeshInstance3D.new()
	var torus = TorusMesh.new()
	torus.inner_radius = 0.15
	torus.outer_radius = 0.45
	ring.mesh = torus
	var r_mat = StandardMaterial3D.new()
	r_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	r_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	r_mat.albedo_color = Color(0.8, 0.95, 0.3, 0.5)
	r_mat.emission_enabled = true
	r_mat.emission = Color(0.7, 0.95, 0.2)
	r_mat.emission_energy_multiplier = 2.0
	ring.material_override = r_mat
	container.add_child(ring)

	# --- Violent Spore Shrapnel ---
	var particles = CPUParticles3D.new()
	particles.amount = 25
	particles.lifetime = 0.4
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.spread = 180.0
	particles.initial_velocity_min = 5.0
	particles.initial_velocity_max = 12.0
	particles.gravity = Vector3(0, 2.0, 0)
	particles.scale_amount_min = 0.35
	particles.scale_amount_max = 0.8
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 0.3

	var p_mesh = SphereMesh.new()
	p_mesh.radius = 0.09
	p_mesh.height = 0.18
	particles.mesh = p_mesh

	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.85, 1.0, 0.3, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.75, 0.95, 0.25)
	mat.emission_energy_multiplier = 2.5
	particles.material_override = mat

	var sp_ramp = Gradient.new()
	sp_ramp.set_color(0, Color(0.85, 1.0, 0.3, 0.6))
	sp_ramp.add_point(1.0, Color(0.4, 0.8, 0.2, 0.0))
	particles.color_ramp = sp_ramp

	container.add_child(particles)
	particles.emitting = true

	var tween = container.create_tween().set_parallel(true)
	tween.tween_property(light, "light_energy", 0.0, 0.35)
	tween.tween_property(ring, "scale", Vector3(3.0, 3.0, 3.0), 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(r_mat, "albedo_color:a", 0.0, 0.3)
	tween.chain().tween_callback(container.queue_free)
