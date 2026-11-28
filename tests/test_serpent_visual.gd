extends Node3D
func _ready() -> void:
	var p = load("res://scenes/objects/serpent_projectile.tscn").instantiate()
	add_child(p)
	p.setup(Vector3.FORWARD, 1.0, 20.0)
	await get_tree().create_timer(0.2).timeout
	var live: Array = p.find_children("*", "MeshInstance3D", true, false).filter(func(n): return not n.is_queued_for_deletion())
	assert(live.is_empty(), "sin mallas 3D")
	assert(p.find_children("*", "Sprite3D", true, false).size() == 10, "cabeza + 9 segmentos")
	print("ALL SERPENT VISUAL CHECKS PASSED")
	get_tree().quit(0)
