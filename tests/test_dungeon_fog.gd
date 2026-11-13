extends Node

## Niebla entre salas (DungeonFog): hay una cortina por frontera de túnel, la zona del jugador se dibuja y las
## demás cavernas no.

func _ready() -> void:
	print("--- TEST: NIEBLA ENTRE SALAS ---")
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.game_mode = "dungeon"
	SaveManager.save_path = "user://test_save.json"
	SaveManager.meta = {}
	var scene: Node = load("res://scenes/core/main_dungeon.tscn").instantiate()
	get_tree().root.add_child.call_deferred(scene)
	await get_tree().process_frame
	get_tree().current_scene = scene
	var fog = null
	for i in 600:
		await get_tree().process_frame
		fog = scene.get_node_or_null("DungeonFog")
		if fog and fog._nodes.size() > 0:
			break
	assert(fog != null, "Existe DungeonFog")
	var map: DungeonMap = fog.map
	var gates: int = fog._gate_list.size()
	var links: int = map.get_meta("links").size()
	print("cortinas=%d enlaces=%d nodos=%d" % [gates, links, fog._nodes.size()])
	assert(gates >= links, "Al menos una cortina por túnel")
	print("CHECK 1 PASSED: %d cortinas para %d túneles" % [gates, links])

	# La zona del jugador es la de la caverna inicial y sus trozos se dibujan
	var p: Node3D = fog.player
	for i in 30:
		await get_tree().process_frame
	var z: int = fog.zone_at(p.global_position)
	assert(z == 0 or map.rooms[z]["type"] == "start", "El jugador empieza en la zona inicial (%d)" % z)
	var shown := 0
	var hidden := 0
	for n in fog._nodes:
		if is_instance_valid(n):
			if n.visible: shown += 1
			else: hidden += 1
	print("visibles=%d ocultos=%d" % [shown, hidden])
	assert(shown > 0 and hidden > 0, "Se dibuja la zona propia y se oculta el resto")
	print("CHECK 2 PASSED: %d trozos visibles, %d ocultos" % [shown, hidden])

	# Solo se dibujan las cortinas que tocan la zona del jugador, y todas comparten un material
	var gate_on := 0
	for g in fog._gate_list:
		var touches: bool = g["a"] == z or g["b"] == z
		for mi in g["nodes"]:
			assert(mi.visible == touches, "Cortina visible solo si toca la zona del jugador")
			assert(mi.material_override == fog._mat, "Material compartido")
		if touches: gate_on += 1
	assert(gate_on > 0, "Hay al menos una cortina en la zona inicial")
	print("CHECK 2b PASSED: %d/%d cortinas dibujadas" % [gate_on, fog._gate_list.size()])

	# Luces: todas las de la sala del jugador (dentro del corte) encendidas; las de otras salas no gastan cupo
	map.refresh_lights()
	var limit: float = map.LIGHT_CULL_DIST_MOBILE if map._mobile else map.LIGHT_CULL_DIST_PC
	var in_zone := 0
	var in_zone_on := 0
	var far_on := 0
	for l in map._lights:
		var d := (l as Node3D).global_position.distance_to(p.global_position)
		var lz: int = fog.zone_near(l.global_position)
		if lz == z and d <= limit:
			in_zone += 1
			if l.visible: in_zone_on += 1
		elif l.visible and d > fog.LIGHT_NEAR and lz >= 0:
			far_on += 1
	print("luces sala=%d encendidas=%d ajenas_encendidas=%d cupo=%d total=%d" % [in_zone, in_zone_on, far_on, map.visible_lights, map._lights.size()])
	assert(in_zone_on == mini(in_zone, map.visible_lights), "Se encienden las luces de la sala del jugador")
	assert(far_on == 0, "Las luces de otras salas no gastan cupo")
	print("CHECK 2c PASSED: %d/%d luces de la sala encendidas" % [in_zone_on, in_zone])

	# Pasar a otra caverna cambia qué se dibuja
	var other := -1
	for i in map.rooms.size():
		if i != z:
			other = i
			break
	var c := map.room_center(other)
	p.global_position = Vector3(c.x, 0.3, c.z)
	for i in 40:
		await get_tree().process_frame
	assert(fog._cur_zone == other, "La zona cambia al cruzar (%d)" % fog._cur_zone)
	print("CHECK 3 PASSED: zona %d → %d" % [z, other])
	print("ALL FOG CHECKS PASSED")
	get_tree().quit(0)

