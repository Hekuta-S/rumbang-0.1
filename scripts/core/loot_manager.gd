extends Node
class_name LootManager

var weapon_pickup_scene = preload("res://scenes/objects/weapon_pickup.tscn")
var xp_orb_scene = preload("res://scenes/objects/xp_orb.tscn")
var item_pickup_scene = preload("res://scenes/objects/item_pickup.tscn")

const PLAYABLE_MIN_X: float = -2300.0
const PLAYABLE_MAX_X: float = 2300.0
const PLAYABLE_MIN_Z: float = -2300.0
const PLAYABLE_MAX_Z: float = 2300.0

var player: Node3D

func initialize(p_player: Node3D) -> void:
	player = p_player

func spawn_weapon_pickup() -> void:
	# Clear any leftover pickups from a previous floor.
	for pickup in get_tree().get_nodes_in_group("weapon_pickups"):
		pickup.queue_free()

	if not player: return

	var available: Array = []
	for w_type in range(9):
		if not player.weapon_slots.has(w_type):
			available.append(w_type)
	if available.is_empty():
		return

	var pickup = weapon_pickup_scene.instantiate()
	pickup.weapon_type = available[randi() % available.size()]
	
	var px = randf_range(PLAYABLE_MIN_X, PLAYABLE_MAX_X)
	var pz = randf_range(PLAYABLE_MIN_Z, PLAYABLE_MAX_Z)
	var main_node = get_tree().current_scene
	var py = main_node.get_floor_y(px, pz) if main_node.has_method("get_floor_y") else 0.0
	pickup.position = Vector3(px, py + 1.0, pz)
	get_parent().add_child(pickup)

func spawn_item_pickup() -> void:
	var pickup = item_pickup_scene.instantiate()
	var px = randf_range(PLAYABLE_MIN_X, PLAYABLE_MAX_X)
	var pz = randf_range(PLAYABLE_MIN_Z, PLAYABLE_MAX_Z)
	var main_node = get_tree().current_scene
	var py = main_node.get_floor_y(px, pz) if main_node.has_method("get_floor_y") else 0.0
	pickup.position = Vector3(px, py + 0.5, pz)
	get_parent().add_child(pickup)

func spawn_xp_orb(pos: Vector3) -> void:
	if xp_orb_scene:
		var orb = xp_orb_scene.instantiate()
		orb.position = pos + Vector3(0, 0.5, 0)
		get_parent().add_child(orb)

func spawn_debug_orbs() -> void:
	if not player: return
	for i in range(2):
		var pickup = item_pickup_scene.instantiate()
		var offset = Vector3(randf_range(-2.0, 2.0), 0.0, randf_range(-2.0, 2.0))
		pickup.position = player.global_position + offset
		get_parent().add_child(pickup)
