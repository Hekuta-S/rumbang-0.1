extends Node3D
class_name EnvironmentManager

signal generation_finished

func generate_environment() -> void:
	spawn_medieval_props()
	spawn_terrain_slopes()
	call_deferred("_correct_prop_heights")

func spawn_terrain_slopes() -> void:
	var existing_floor = get_node_or_null("../Floor")
	if existing_floor:
		existing_floor.queue_free()
		
	var existing_terrain = get_node_or_null("TerrainCSG")
	if existing_terrain:
		existing_terrain.queue_free()

	var terrain_scene = load("res://scenes/core/mapa_principal/terreno_principal.tscn")
	if terrain_scene:
		var terrain = terrain_scene.instantiate()
		terrain.name = "TerrainCSG"
		add_child(terrain)


func spawn_medieval_props() -> void:
	pass

func get_floor_y(x: float, z: float) -> float:
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(Vector3(x, 100.0, z), Vector3(x, -100.0, z))
	query.collision_mask = 1 | 2 | 4
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
