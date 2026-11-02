extends Node

## Estructuras destruibles: el tótem suelta almas verdes al romperse, el resto de estructuras se rompe y
## deja de bloquear, y el cofre del tesoro se abre al acercarse el jugador.

func _ready() -> void:
	print("--- TEST: ESTRUCTURAS DESTRUIBLES ---")
	GameData.game_mode = "dungeon"
	var map := DungeonMap.new()
	map.name = "ProceduralMap"
	add_child(map)
	await get_tree().process_frame
	map.generate(5000)
	var kinds := {}
	for d in map.destructibles:
		kinds[d.kind] = kinds.get(d.kind, 0) + 1
	print("rompibles por tipo: ", kinds)
	for k in DungeonMap.STRUCTURES:
		assert(kinds.has(k) or k == "tent", "Hay %s destruibles" % k)
	var totem: DestructibleProp = null
	for d in map.destructibles:
		if d.kind == "totem":
			totem = d
			break
	assert(totem != null, "Hay un tótem")
	var souls_before := get_tree().get_nodes_in_group("none").size()
	var colliders_before := map.get_colliders().size()
	totem.take_damage(5.0)
	assert(not totem.is_broken(), "Un golpe flojo no lo rompe")
	totem.take_damage(1000.0, Vector3.FORWARD)
	assert(totem.is_broken(), "El tótem se rompe")
	var souls := 0
	for c in map.get_children():
		if c is HealSoul:
			souls += 1
	assert(souls >= DungeonMap.TOTEM_SOULS, "El tótem suelta almas (%d)" % souls)
	assert(map.get_colliders().size() == colliders_before - 1, "El tótem roto deja de ser colisionador")
	print("almas=", souls, " colisionadores ", colliders_before, " -> ", map.get_colliders().size())
	# Cofre
	var fake := Node3D.new()
	add_child(fake)
	fake.global_position = Vector3(50, 0, 50)
	var chest := TreasureChest.spawn(self, Vector3.ZERO, fake)
	var opened := [false]
	chest.opened.connect(func(_c): opened[0] = true)
	await get_tree().create_timer(0.3).timeout
	assert(not chest.is_open, "El cofre sigue cerrado con el jugador lejos")
	fake.global_position = Vector3(1.0, 0, 0)
	await get_tree().create_timer(1.2).timeout
	assert(opened[0], "El cofre se abre al acercarse")
	print("ALL STRUCTURE CHECKS PASSED")
	get_tree().quit(0)
