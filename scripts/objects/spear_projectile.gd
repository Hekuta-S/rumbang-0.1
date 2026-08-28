extends Area3D

## Thrown Espalanza (spear-lance) projectile.
## Flies straight, damages the first enemy / wall it hits, then returns to the player's hand.

@export var speed: float = 30.0
@export var damage: float = 48.0
@export var max_lifetime: float = 4.0
@export var max_range: float = 45.0
@export var return_speed: float = 35.0

var direction: Vector3 = Vector3.FORWARD
var lifetime: float = 0.0
var distance_traveled: float = 0.0
var shooter_rid: RID = RID()
var returning: bool = false
var last_pos: Vector3 = Vector3.ZERO

func _ready() -> void:
	add_to_group("spear_projectiles")
	body_entered.connect(_on_body_entered)

func setup(dir: Vector3, speed_val: float, dmg: float, shooter: RID = RID()) -> void:
	direction = dir.normalized()
	speed = speed_val
	damage = dmg
	shooter_rid = shooter

	# Point the spear mesh along the flight direction.
	if direction.length_squared() > 0.001 and direction.cross(Vector3.UP).length_squared() > 0.001:
		look_at(global_position + direction, Vector3.UP)
		# Mesh was modelled pointing +Y; rotate so the tip (+Y local) faces forward.
		rotate_object_local(Vector3.RIGHT, deg_to_rad(-90))

	last_pos = global_position
	_setup_spear_trail()

func _setup_spear_trail() -> void:
	var trail := CPUParticles3D.new()
	trail.name = "SpearTrail"
	trail.local_coords = false
	trail.amount = 30
	trail.lifetime = 0.25
	trail.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINT
	trail.gravity = Vector3.ZERO
	trail.spread = 10.0
	trail.initial_velocity_min = 0.5
	trail.initial_velocity_max = 1.2
	trail.scale_amount_min = 0.3
	trail.scale_amount_max = 0.7

	var p_mesh := SphereMesh.new()
	p_mesh.radius = 0.1
	p_mesh.height = 0.2
	trail.mesh = p_mesh

	var t_mat := StandardMaterial3D.new()
	t_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	t_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	t_mat.albedo_color = Color(0.35, 1.0, 0.5, 0.45)
	t_mat.emission_enabled = true
	t_mat.emission = Color(0.3, 1.0, 0.5)
	t_mat.emission_energy_multiplier = 1.8
	trail.material_override = t_mat

	var color_ramp := Gradient.new()
	color_ramp.set_color(0, Color(0.35, 1.0, 0.5, 0.5))
	color_ramp.add_point(1.0, Color(0.1, 0.8, 0.3, 0.0))
	trail.color_ramp = color_ramp

	add_child(trail)
	trail.position = Vector3(0, 1.5, 0)
	trail.emitting = true

func _physics_process(delta: float) -> void:
	if returning:
		_physics_process_return(delta)
		return

	lifetime += delta
	if lifetime >= max_lifetime:
		_start_return()
		return

	var current_pos = global_position
	var move_step = direction * speed * delta
	var next_pos = current_pos + move_step
	distance_traveled += move_step.length()
	if distance_traveled >= max_range:
		_start_return()
		return

	# High accuracy raycast step to catch fast impacts.
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(current_pos, next_pos)
	query.exclude = []
	query.collision_mask = 0xFFFFFFFF
	if shooter_rid.is_valid():
		query.exclude.append(shooter_rid)
	var result = space_state.intersect_ray(query)
	if not result.is_empty():
		var body = result.collider
		if body and body != self:
			_apply_impact(body, result.position, result.normal)
			last_pos = result.position
			return

	global_position = next_pos
	last_pos = global_position

func _physics_process_return(delta: float) -> void:
	var player = _get_shooter()
	if not player or not is_instance_valid(player) or not player.is_inside_tree():
		queue_free()
		return

	var to_player = player.global_position + Vector3(0, 1.0, 0) - global_position
	var dist = to_player.length()
	if dist < 1.2:
		if player.has_method("on_spear_returned"):
			player.on_spear_returned()
		queue_free()
		return

	var step = to_player.normalized() * return_speed * delta
	global_position += step
	# Keep the spear tip aimed at the player while returning.
	if to_player.cross(Vector3.UP).length_squared() > 0.001:
		look_at(global_position + to_player.normalized(), Vector3.UP)
		rotate_object_local(Vector3.RIGHT, deg_to_rad(-90))

func _on_body_entered(body: Node) -> void:
	if returning:
		return
	if body == self:
		return
	if shooter_rid.is_valid() and body is CollisionObject3D and body.get_rid() == shooter_rid:
		return
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(last_pos, global_position)
	query.exclude = [get_rid()]
	if shooter_rid.is_valid():
		query.exclude.append(shooter_rid)
	var result = space_state.intersect_ray(query)
	if not result.is_empty() and result.collider == body:
		_apply_impact(body, result.position, result.normal)

func _apply_impact(body: Node, hit_pos: Vector3, hit_normal: Vector3) -> void:
	var BulletScript = load("res://scripts/objects/bullet.gd")
	var is_enemy := body.is_in_group("enemies")
	if is_enemy and body.has_method("take_damage"):
		body.take_damage(damage, direction)

	# Impact sparks.
	if BulletScript and BulletScript.has_method("spawn_impact_sparks"):
		var color := Color(0.35, 1.0, 0.5) if is_enemy else Color(0.7, 0.75, 0.8)
		BulletScript.spawn_impact_sparks(get_parent(), hit_pos, hit_normal, color)

	_start_return()

func _start_return() -> void:
	# Spectral spears don't return, they just vanish.
	queue_free()

func _get_shooter() -> Node:
	# shooter_rid is a physics RID, not an ObjectID — instance_from_id() cannot
	# resolve it back to a node. The player is the only node in the "player" group.
	var player = get_tree().get_first_node_in_group("player")
	if player and is_instance_valid(player):
		return player
	return null
