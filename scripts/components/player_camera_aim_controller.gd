extends Node
class_name PlayerCameraAndAimController

var player: CharacterBody3D
var spring_arm: SpringArm3D
var camera: Camera3D
var muzzle: Marker3D
var mesh: Node3D

func get_camera_aim_point() -> Vector3:
	if not player:
		return Vector3.ZERO

	if is_instance_valid(player) and player.has_method("get_camera_aim_point"):
		# Avoid recursion when called from Player after delegation.
		return _compute_camera_aim_point()
	return Vector3.ZERO

func _compute_camera_aim_point() -> Vector3:
	var viewport_rect = player.get_viewport().get_visible_rect()
	var screen_center = viewport_rect.size * 0.5

	if camera == null:
		return player.global_position + Vector3(0, 1.0, 0)

	var ray_origin = camera.project_ray_origin(screen_center)
	var ray_normal = camera.project_ray_normal(screen_center)
	var max_range = 100.0
	var ray_target = ray_origin + ray_normal * max_range

	var space_state = player.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_target)
	query.exclude = [player.get_rid()]
	query.collision_mask = 1

	var result = space_state.intersect_ray(query)
	if not result.is_empty():
		return result.position
	return ray_target

func get_attack_forward_dir() -> Vector3:
	if not player:
		return Vector3.FORWARD
	var aim = get_camera_aim_point()
	var dir = aim - player.global_position
	dir.y = 0
	if dir.length_squared() < 0.001:
		if mesh and is_instance_valid(mesh):
			return -mesh.global_transform.basis.z
		return -player.global_transform.basis.z
	return dir.normalized()

func orient_player_to_aim(_aim_point: Vector3) -> void:
	# The model no longer rotates to face the aim target when attacking;
	# the attack effect plays in place without turning the character.
	pass

func apply_camera_recoil(pitch_amount: float, yaw_amount: float, kick_z: float = 0.08) -> void:
	# Recoil is intentionally kept in the camera controller layer. The current model
	# uses the camera rig directly when present; otherwise it does nothing.
	if not spring_arm or not is_instance_valid(spring_arm):
		return

	var current_rotation = spring_arm.rotation
	var target_pitch = current_rotation.x + pitch_amount
	var target_yaw = current_rotation.y + yaw_amount
	var target_z = spring_arm.position.z + kick_z
	
	var tween = player.create_tween()
	tween.tween_property(spring_arm, "rotation", Vector3(target_pitch, target_yaw, current_rotation.z), 0.06)
	tween.tween_property(spring_arm, "position:z", target_z, 0.06)
	tween.chain().tween_property(spring_arm, "rotation", current_rotation, 0.12)
	tween.chain().tween_property(spring_arm, "position:z", 0.0, 0.12)

func create_muzzle_flash(flash_color: Color, scale_multiplier: float = 1.0) -> void:
	if not player or not is_instance_valid(player):
		return
	if not muzzle or not is_instance_valid(muzzle):
		return
	if not player.is_inside_tree():
		return
	var parent = player.get_parent()
	if not parent or not is_instance_valid(parent) or not parent.is_inside_tree():
		return
	# Pool de fogonazos: antes cada disparo creaba nodo, luz, malla, material y partículas (≈ 0,45 ms)
	_flash_pool = _flash_pool.filter(func(en): return is_instance_valid(en["root"]) and en["root"].is_inside_tree())
	var entry: Dictionary = {}
	for en in _flash_pool:
		if not en["busy"]:
			entry = en
			break
	if entry.is_empty():
		if _flash_pool.size() >= FLASH_POOL_MAX:
			return
		entry = _build_flash_entry(parent)
		_flash_pool.append(entry)
	entry["busy"] = true

	var flash_node: Node3D = entry["root"]
	var light: OmniLight3D = entry["light"]
	var flash_mesh: MeshInstance3D = entry["mesh"]
	var sphere: SphereMesh = flash_mesh.mesh
	var mat: StandardMaterial3D = entry["mat"]
	var particles: CPUParticles3D = entry["particles"]
	var p_mat: StandardMaterial3D = entry["p_mat"]

	flash_node.global_position = muzzle.global_position
	flash_node.visible = true
	light.light_color = flash_color
	light.light_energy = 7.0 * scale_multiplier
	light.omni_range = 5.0 * scale_multiplier
	if not is_equal_approx(sphere.radius, 0.2 * scale_multiplier):
		sphere.radius = 0.2 * scale_multiplier
		sphere.height = 0.4 * scale_multiplier
	flash_mesh.scale = Vector3.ONE
	mat.albedo_color = Color.WHITE.lerp(flash_color, 0.4)
	mat.emission = flash_color

	var amount: int = Quality.count(int(18 * scale_multiplier))
	if particles.amount != amount:      # cambiar la cantidad realoca el buffer: solo si hace falta
		particles.amount = amount
	particles.lifetime = 0.18 * scale_multiplier
	particles.initial_velocity_min = 7.0 * scale_multiplier
	particles.initial_velocity_max = 16.0 * scale_multiplier
	if spring_arm and is_instance_valid(spring_arm):
		particles.direction = -spring_arm.global_transform.basis.z
	else:
		particles.direction = Vector3.FORWARD
	var box_size := Vector3(0.06, 0.06, 0.22) * scale_multiplier
	if (particles.mesh as BoxMesh).size != box_size:
		(particles.mesh as BoxMesh).size = box_size
	p_mat.albedo_color = Color.WHITE.lerp(flash_color, 0.3)
	p_mat.emission = flash_color
	particles.restart()
	particles.emitting = true

	var tween = flash_node.create_tween().set_parallel(true)
	tween.tween_property(light, "light_energy", 0.0, 0.12)
	tween.tween_property(flash_mesh, "scale", Vector3(2.4, 2.4, 2.4) * scale_multiplier, 0.1)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.12)
	tween.chain().tween_callback(func():
		flash_node.visible = false
		particles.emitting = false
		entry["busy"] = false)

static var _flash_pool: Array = []
const FLASH_POOL_MAX := 12

static func _build_flash_entry(parent: Node) -> Dictionary:
	var root := Node3D.new()
	parent.add_child(root)
	var light = Quality.new_light()
	light.light_energy = 0.0
	root.add_child(light)
	var flash_mesh := MeshInstance3D.new()
	flash_mesh.mesh = SphereMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission_energy_multiplier = 5.0
	flash_mesh.material_override = mat
	root.add_child(flash_mesh)
	var particles := CPUParticles3D.new()
	particles.explosiveness = 1.0
	particles.one_shot = true
	particles.spread = 35.0
	particles.mesh = BoxMesh.new()
	var p_mat := StandardMaterial3D.new()
	p_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	p_mat.emission_enabled = true
	p_mat.emission_energy_multiplier = 5.0
	particles.material_override = p_mat
	root.add_child(particles)
	particles.emitting = false
	root.visible = false
	return {"root": root, "light": light, "mesh": flash_mesh, "mat": mat, "particles": particles, "p_mat": p_mat, "busy": false}
