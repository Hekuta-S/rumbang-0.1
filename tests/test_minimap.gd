extends Node

## Minimapa: se crea sobre una mazmorra, descubre celdas cerca del jugador y se expande con toggle().

func _ready() -> void:
	print("--- TEST: MINIMAPA ---")
	GameData.game_mode = "dungeon"
	var map := DungeonMap.new()
	map.name = "ProceduralMap"
	add_child(map)
	await get_tree().process_frame
	map.generate(5000)
	var player := Node3D.new()
	player.add_to_group("player")
	add_child(player)
	var c := map.room_center(0)
	player.global_position = Vector3(c.x, 0, c.z)
	var layer := CanvasLayer.new()
	add_child(layer)
	var mm := Minimap.new()
	layer.add_child(mm)
	await get_tree().create_timer(0.6).timeout
	assert(mm._seen.size() > 50, "Descubre celdas cerca del jugador (%d)" % mm._seen.size())
	assert(mm._seen.size() < map._cells.size() / 2, "No revela todo el mapa de golpe")
	var compact := mm.size.x
	mm.toggle()
	await get_tree().create_timer(1.0).timeout
	assert(mm.is_expanded() and mm.size.x > compact + 100.0, "Se expande (%.0f -> %.0f)" % [compact, mm.size.x])
	await get_tree().process_frame
	mm.toggle()
	await get_tree().create_timer(1.0).timeout
	assert(is_equal_approx(mm.size.x, compact), "Vuelve a compacto")
	# Cambio de nivel: la niebla se reinicia
	map.generate(5001)
	await get_tree().create_timer(0.4).timeout
	assert(mm._seen.size() < 400, "Niebla reiniciada con el mapa nuevo (%d)" % mm._seen.size())
	print("ALL MINIMAP CHECKS PASSED")
	get_tree().quit(0)
