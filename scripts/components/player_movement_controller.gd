extends Node
class_name PlayerMovementController

var player: CharacterBody3D
var gravity: float = 22.0

var dust_particles: CPUParticles3D
var jump_particles: CPUParticles3D

func _ready() -> void:
	player = get_parent() as CharacterBody3D
	_setup_particles()

var _step_distance_accum: float = 0.0
var _last_foot_side: float = 1.0

func _setup_particles() -> void:
	pass

func _spawn_footstep_puff(pos: Vector3, is_running: bool) -> void:
	if not player or not player.is_inside_tree(): return
	var parent = player.get_parent()
	if not parent or not is_instance_valid(parent): return

	var puff := CPUParticles3D.new()
	puff.amount = 14 if is_running else 8
	puff.lifetime = 0.45
	puff.one_shot = true
	puff.explosiveness = 0.95
	puff.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	puff.emission_sphere_radius = 0.2
	puff.direction = Vector3.UP
	puff.spread = 60.0
	puff.gravity = Vector3(0, 0.4, 0)
	puff.initial_velocity_min = 0.6
	puff.initial_velocity_max = 1.8 if is_running else 1.2
	puff.scale_amount_min = 0.25
	puff.scale_amount_max = 0.55 if is_running else 0.4

	var mesh := SphereMesh.new()
	mesh.radius = 0.05
	mesh.height = 0.1
	puff.mesh = mesh

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.85, 0.8, 0.7, 0.65)
	puff.material_override = mat

	var color_ramp := Gradient.new()
	color_ramp.set_color(0, Color(0.85, 0.8, 0.7, 0.7))
	color_ramp.add_point(1.0, Color(0.85, 0.8, 0.7, 0.0))
	puff.color_ramp = color_ramp

	parent.add_child(puff)
	puff.global_position = pos
	puff.restart()
	puff.emitting = true

	var tw = puff.create_tween()
	tw.tween_interval(0.55)
	tw.tween_callback(puff.queue_free)

func _spawn_jump_burst(pos: Vector3) -> void:
	if not player or not player.is_inside_tree(): return
	var parent = player.get_parent()
	if not parent or not is_instance_valid(parent): return

	var jump_puff := CPUParticles3D.new()
	jump_puff.amount = 26
	jump_puff.lifetime = 0.5
	jump_puff.one_shot = true
	jump_puff.explosiveness = 0.98
	jump_puff.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	jump_puff.emission_sphere_radius = 0.35
	jump_puff.direction = Vector3.UP
	jump_puff.spread = 85.0
	jump_puff.initial_velocity_min = 2.0
	jump_puff.initial_velocity_max = 4.8
	jump_puff.gravity = Vector3(0, -2.5, 0)
	jump_puff.scale_amount_min = 0.6
	jump_puff.scale_amount_max = 1.3

	var mesh := SphereMesh.new()
	mesh.radius = 0.12
	mesh.height = 0.24
	jump_puff.mesh = mesh

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.9, 0.85, 0.75, 0.75)
	jump_puff.material_override = mat

	var color_ramp := Gradient.new()
	color_ramp.set_color(0, Color(0.9, 0.85, 0.75, 0.8))
	color_ramp.add_point(1.0, Color(0.9, 0.85, 0.75, 0.0))
	jump_puff.color_ramp = color_ramp

	parent.add_child(jump_puff)
	jump_puff.global_position = pos
	jump_puff.restart()
	jump_puff.emitting = true

	var tw = jump_puff.create_tween()
	tw.tween_interval(0.6)
	tw.tween_callback(jump_puff.queue_free)

func handle_movement(delta: float) -> void:
	if not player: return

	var inp: Vector2 = player.input_controller.get_movement_vector()
	var cam_basis: Basis = player.spring_arm.global_transform.basis
	var fwd := -cam_basis.z
	var right := cam_basis.x
	var wish := fwd * -inp.y + right * inp.x
	wish.y = 0.0
	
	var current_speed: float = player.move_speed * (1.3 if player.is_berserk else 1.0) * (1.35 if player.dust_speed_boost_timer > 0 else 1.0)
	
	# Run mechanic
	var is_running = false
	if (Input.is_physical_key_pressed(KEY_SHIFT) or Input.is_joy_button_pressed(0, JOY_BUTTON_LEFT_STICK) or VirtualInput.is_running) and wish.length_squared() > 0.0001 and player.is_on_floor():
		if player.passive and player.passive.has_method("override_run"):
			player.passive.override_run(player, wish, delta)
		elif player.stats.consume_energy(15.0 * delta):
			current_speed *= 1.8
			is_running = true

	var moving = wish.length_squared() > 0.0001
	if moving and player.is_on_floor():
		var dist_step = current_speed * delta
		_step_distance_accum += dist_step
		var step_interval = 0.9 if is_running else 1.4
		if _step_distance_accum >= step_interval:
			_step_distance_accum = 0.0
			_last_foot_side = -_last_foot_side
			var foot_offset = right * (_last_foot_side * 0.25)
			_spawn_footstep_puff(player.global_position + foot_offset + Vector3(0, 0.05, 0), is_running)
	else:
		_step_distance_accum = 0.0

	if moving:
		wish = wish.normalized()
		# Rotate the character mesh to face the movement direction.
		player.mesh.rotation.y = lerp_angle(player.mesh.rotation.y, atan2(-wish.x, -wish.z), 14.0 * delta)
	else:
		wish = Vector3.ZERO
		
	player.velocity.x = wish.x * current_speed
	player.velocity.z = wish.z * current_speed

	# Jump mechanic
	if (Input.is_physical_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_SPACE) or Input.is_joy_button_pressed(0, JOY_BUTTON_A) or VirtualInput.is_jumping) and player.is_on_floor():
		if player.stats.consume_energy(25.0):
			player.velocity.y = 8.5
			_spawn_jump_burst(player.global_position + Vector3(0, 0.05, 0))
			# The animation controller will detect the jump automatically

	# Gravity / grounding
	if not player.is_on_floor():
		player.velocity.y -= gravity * delta
	else:
		if player.velocity.y <= 0:
			player.velocity.y = -1.0

	player.move_and_slide()
