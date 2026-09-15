extends Area3D

@export var speed: float = 30.0
@export var damage: float = 12.0
@export var is_enemy_bullet: bool = false
@export var max_lifetime: float = 3.0

var direction: Vector3 = Vector3.FORWARD
var lifetime: float = 0.0
var bullet_color: Color = Color(0.0, 0.85, 1.0)
var shooter_rid: RID = RID()
var is_hit: bool = false

func _ready() -> void:
	add_to_group("bullets")
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

func setup(dir: Vector3, dmg: float, speed_val: float, enemy_flag: bool = false, col: Color = Color(0.0, 0.85, 1.0), shooter: RID = RID()) -> void:
	direction = dir.normalized()
	damage = dmg
	speed = speed_val
	is_enemy_bullet = enemy_flag
	bullet_color = col
	shooter_rid = shooter

	if direction.length_squared() > 0.001 and direction.cross(Vector3.UP).length_squared() > 0.001:
		look_at(global_position + direction, Vector3.UP)

	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	if is_enemy_bullet:
		bullet_color = Color(1.0, 0.1, 0.3)
		mat.albedo_color = bullet_color
		if has_node("OmniLight3D"):
			$OmniLight3D.light_color = bullet_color
	else:
		mat.albedo_color = bullet_color
		if has_node("OmniLight3D"):
			$OmniLight3D.light_color = bullet_color

	if has_node("MeshInstance3D"):
		$MeshInstance3D.material_override = mat

	# --- Dynamic Bullet Trail ---
	_setup_trail(mat, bullet_color)

func _setup_trail(mat: StandardMaterial3D, col: Color) -> void:
	var trail: CPUParticles3D
	if has_node("TrailParticles"):
		trail = get_node("TrailParticles")
	else:
		trail = CPUParticles3D.new()
		trail.name = "TrailParticles"
		add_child(trail)

	trail.local_coords = false
	trail.amount = 25
	trail.lifetime = 0.18
	trail.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINT
	trail.gravity = Vector3.ZERO
	trail.spread = 15.0
	trail.initial_velocity_min = 0.5
	trail.initial_velocity_max = 1.5
	trail.scale_amount_min = 0.3
	trail.scale_amount_max = 0.8
	
	var p_mesh = SphereMesh.new()
	p_mesh.radius = 0.12
	p_mesh.height = 0.24
	trail.mesh = p_mesh
	
	var trail_mat = mat.duplicate() as StandardMaterial3D
	trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail_mat.albedo_color = Color(col.r, col.g, col.b, 0.4)
	trail_mat.emission_enabled = true
	trail_mat.emission = col
	trail_mat.emission_energy_multiplier = 1.5
	trail.material_override = trail_mat
	
	var color_ramp = Gradient.new()
	color_ramp.set_color(0, Color(col.r, col.g, col.b, 0.5))
	color_ramp.add_point(1.0, Color(col.r, col.g, col.b, 0.0))
	trail.color_ramp = color_ramp
	
	trail.emitting = true

func _physics_process(delta: float) -> void:
	if is_hit: return

	var current_pos = global_position
	var move_step = direction * speed * delta
	var next_pos = current_pos + move_step

	# High accuracy physics raycast step calculation
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(current_pos, next_pos)
	query.collision_mask = collision_mask
	if shooter_rid.is_valid():
		query.exclude = [shooter_rid]

	var hit = space_state.intersect_ray(query)
	if not hit.is_empty():
		global_position = hit.position
		_on_impact(hit.collider, hit.position, hit.normal)
		return

	global_position = next_pos
	lifetime += delta
	if lifetime >= max_lifetime:
		PoolManager.return_bullet(self)

func _on_body_entered(body: Node3D) -> void:
	if is_hit: return
	# Guard: the bullet may have been removed from the tree by the time this signal fires
	if not is_inside_tree(): return
	_on_impact(body, global_position, -direction)

func _on_area_entered(_area: Area3D) -> void:
	pass

func _on_impact(body: Node3D, hit_pos: Vector3, hit_normal: Vector3) -> void:
	if is_hit: return

	if is_enemy_bullet:
		if body.is_in_group("player") and body.has_method("take_damage"):
			is_hit = true
			body.take_damage(damage)
			spawn_impact_sparks(get_parent(), hit_pos, hit_normal, bullet_color)
			PoolManager.return_bullet(self)
		elif not body.is_in_group("enemies") and not body.is_in_group("bullets"):
			is_hit = true
			spawn_impact_sparks(get_parent(), hit_pos, hit_normal, bullet_color)
			PoolManager.return_bullet(self)
	else:
		if body.is_in_group("enemies") and body.has_method("take_damage"):
			is_hit = true
			body.take_damage(damage, direction)
			spawn_impact_sparks(get_parent(), hit_pos, hit_normal, bullet_color)
			PoolManager.return_bullet(self)
		elif not body.is_in_group("player") and not body.is_in_group("bullets"):
			is_hit = true
			spawn_impact_sparks(get_parent(), hit_pos, hit_normal, bullet_color)
			PoolManager.return_bullet(self)

static var CACHED_RING_MATS: Dictionary = {}
static var CACHED_SPARK_MATS: Dictionary = {}

static func spawn_impact_sparks(parent_node: Node, pos: Vector3, normal: Vector3, spark_color: Color) -> void:
	# Guard: parent must exist, be valid, and be inside the scene tree
	if not parent_node or not is_instance_valid(parent_node) or not parent_node.is_inside_tree(): return

	var spark_container = Node3D.new()
	parent_node.add_child(spark_container)
	spark_container.global_position = pos

	# 1. Flash Light
	var light = OmniLight3D.new()
	light.light_color = spark_color
	light.light_energy = 4.0
	light.omni_range = 3.5
	spark_container.add_child(light)

	# 2. Shockwave Ring (Impact Wave)
	var ring = MeshInstance3D.new()
	var torus = TorusMesh.new()
	torus.inner_radius = 0.08
	torus.outer_radius = 0.25
	torus.rings = 16
	torus.ring_segments = 12
	ring.mesh = torus
	
	var ring_key = spark_color.to_html()
	var r_mat: StandardMaterial3D
	if not CACHED_RING_MATS.has(ring_key):
		r_mat = StandardMaterial3D.new()
		r_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		r_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		r_mat.albedo_color = Color(spark_color.r, spark_color.g, spark_color.b, 0.45)
		r_mat.emission_enabled = true
		r_mat.emission = spark_color
		r_mat.emission_energy_multiplier = 2.5
		CACHED_RING_MATS[ring_key] = r_mat
	else:
		r_mat = CACHED_RING_MATS[ring_key].duplicate() # Duplicate so we can tween transparency independently
		
	ring.material_override = r_mat
	
	spark_container.add_child(ring)
	if normal != Vector3.ZERO and normal.cross(Vector3.UP).length_squared() > 0.001:
		ring.look_at(ring.global_position + normal, Vector3.UP)
	elif normal != Vector3.ZERO:
		ring.look_at(ring.global_position + normal, Vector3.FORWARD)

	# 3. High Velocity Flying Sparks
	var particles = CPUParticles3D.new()
	particles.amount = 18
	particles.lifetime = 0.3
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.direction = normal if normal != Vector3.ZERO else Vector3.UP
	particles.spread = 70.0
	particles.initial_velocity_min = 6.0
	particles.initial_velocity_max = 14.0
	particles.gravity = Vector3(0, -12.0, 0)
	particles.scale_amount_min = 0.5
	particles.scale_amount_max = 1.1

	var p_mesh = BoxMesh.new()
	p_mesh.size = Vector3(0.06, 0.06, 0.18)
	particles.mesh = p_mesh

	var mat_key = spark_color.to_html()
	if not CACHED_SPARK_MATS.has(mat_key):
		var new_mat = StandardMaterial3D.new()
		new_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		new_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		new_mat.albedo_color = Color(spark_color.r, spark_color.g, spark_color.b, 0.6)
		new_mat.emission_enabled = true
		new_mat.emission = Color(spark_color.r, spark_color.g, spark_color.b).lerp(Color.WHITE, 0.3)
		new_mat.emission_energy_multiplier = 2.5
		CACHED_SPARK_MATS[mat_key] = new_mat
		
	particles.material_override = CACHED_SPARK_MATS[mat_key]

	var sp_ramp = Gradient.new()
	sp_ramp.set_color(0, Color(spark_color.r, spark_color.g, spark_color.b, 0.65))
	sp_ramp.add_point(1.0, Color(spark_color.r, spark_color.g, spark_color.b, 0.0))
	particles.color_ramp = sp_ramp

	spark_container.add_child(particles)
	particles.emitting = true

	# 4. Smooth Animations & Cleanup
	var tween = spark_container.create_tween().set_parallel(true)
	tween.tween_property(light, "light_energy", 0.0, 0.25)
	tween.tween_property(ring, "scale", Vector3(2.5, 2.5, 2.5), 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(r_mat, "albedo_color:a", 0.0, 0.22)
	tween.chain().tween_callback(spark_container.queue_free)
