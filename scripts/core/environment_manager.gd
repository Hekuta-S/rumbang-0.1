extends Node3D
class_name EnvironmentManager

signal generation_finished

func generate_environment() -> void:
	spawn_medieval_props()
	spawn_terrain_slopes()
	call_deferred("_correct_prop_heights")

func spawn_terrain_slopes() -> void:
	pass


func spawn_medieval_props() -> void:
	pass

func get_floor_y(x: float, z: float) -> float:
	var terrain = get_tree().current_scene.get_node_or_null("TerrainCSG/Terrain3D")
	if terrain:
		if "storage" in terrain and terrain.storage and terrain.storage.has_method("get_height"):
			var h = terrain.storage.get_height(Vector3(x, 0, z))
			if is_finite(h) and not is_nan(h):
				return h
		if "data" in terrain and terrain.data and terrain.data.has_method("get_height"):
			var h = terrain.data.get_height(Vector3(x, 0, z))
			if is_finite(h) and not is_nan(h):
				return h

	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(Vector3(x, 100.0, z), Vector3(x, -100.0, z))
	query.collision_mask = 1 # Solo detectar el mundo (Layer 1), ignorar al jugador (2) y enemigos (4)
	var hit = space_state.intersect_ray(query)
	if not hit.is_empty():
		return hit.position.y
	return 0.0

func _correct_prop_heights() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var env = get_node_or_null("MedievalEnvironment")
	if env:
		for child in env.get_children():
			var y = get_floor_y(child.position.x, child.position.z)
			child.position.y += y
	generation_finished.emit()
