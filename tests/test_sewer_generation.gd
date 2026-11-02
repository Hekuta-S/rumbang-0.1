extends Node

## Generación de las cloacas (SewerMap): muchas semillas y los 4 temas del mundo "sewers". Comprueba que
## todas las salas se alcanzan desde la inicial, que su centro es suelo seco (encuentros, portal, altar),
## que hay canales de agua y que el agua frena y envenena, que salen las formas y decoraciones propias,
## que los props de primitivas tienen malla y que un bidón tóxico revienta a su vecino.

func _reachable(map: DungeonMap) -> Dictionary:
	var start := map.world_to_cell(map.room_center(0))
	for i in map.rooms.size():
		if map.rooms[i]["type"] == "start":
			start = map.world_to_cell(map.room_center(i))
	var seen := {start: true}
	var q: Array = [start]
	while not q.is_empty():
		var c: Vector2i = q.pop_back()
		for d in DungeonMap.DIRS:
			var n: Vector2i = c + d
			if map._cells.has(n) and not seen.has(n):
				seen[n] = true
				q.append(n)
	return seen

func _ready() -> void:
	print("--- TEST: GENERACIÓN DE CLOACAS ---")
	GameData.game_mode = "dungeon"
	GameData.world = "sewers"
	var map := SewerMap.new()
	map.name = "ProceduralMap"
	add_child(map)
	await get_tree().process_frame
	var times: Array = []
	var shapes := {}
	var themes := {}
	var kinds := {}
	var runs := 0
	var water_cells := 0
	for theme in 4:
		for k in 5:
			map.level_theme = theme
			var t0 := Time.get_ticks_usec()
			map.generate(7000 + theme * 100 + k)
			times.append((Time.get_ticks_usec() - t0) / 1000.0)
			runs += 1
			var seen := _reachable(map)
			water_cells += map._water.size()
			for c in map._water:
				assert(map._cells.has(c), "El agua está sobre suelo")
			for i in map.rooms.size():
				var r: Dictionary = map.rooms[i]
				shapes[r["shape"]] = shapes.get(r["shape"], 0) + 1
				themes[r["theme"]] = themes.get(r["theme"], 0) + 1
				var cc := map.world_to_cell(map.room_center(i))
				assert(map._cells.has(cc), "El centro de la sala %d (%s) es suelo" % [i, r["shape"]])
				assert(not map._water.has(cc), "El centro de la sala %d (%s) está seco" % [i, r["shape"]])
				assert(seen.has(cc), "La sala %d (%s) se alcanza desde la inicial (semilla %d)" % [i, r["shape"], map.used_seed])
			for d in map.destructibles:
				kinds[d.kind] = kinds.get(d.kind, 0) + 1
			await get_tree().process_frame
	times.sort()
	print("formas=", shapes, "\ntemas=", themes, "\nrompibles=", kinds, "\nceldas de agua media=", water_cells / runs)
	print("tiempo de generación ms: mediana=%.1f max=%.1f" % [times[times.size() / 2], times[times.size() - 1]])
	assert(times[times.size() / 2] < 150.0, "La generación es rápida (mediana %.1f ms)" % times[times.size() / 2])
	for s in SewerMap.SEWER_SHAPES:
		assert(shapes.has(s), "Sale la forma %s" % s)
	for t in ["collector", "dump", "pumps"]:
		assert(themes.has(t), "Sale la decoración %s" % t)
	assert(water_cells / runs > 40, "Hay canales de agua")
	for kind in SewerMap.SEWER_PROPS:
		assert(map._load_kind(kind) != null, "Malla del prop %s" % kind)
	assert(kinds.get("toxic_barrel", 0) > 0 and kinds.get("trash_bag", 0) > 0, "Salen bidones tóxicos y bolsas de basura")
	assert(map.get_node_or_null("Water") != null, "Se construye el agua")

	# Bidón tóxico: al romperse revienta a un vecino y suelta la nube
	var a: DestructibleProp = null
	var b: DestructibleProp = null
	for d in map.destructibles:
		if d.kind != "toxic_barrel" or d.is_broken():
			continue
		for e in map.destructibles:
			if e != d and e.kind == "toxic_barrel" and d.global_position.distance_to(e.global_position) < SewerMap.TOXIC_RADIUS * 0.8:
				a = d
				b = e
				break
		if a != null:
			break
	assert(a != null, "Hay dos bidones tóxicos juntos")
	a.take_damage(999.0, Vector3.FORWARD)
	await get_tree().create_timer(SewerMap.TOXIC_CHAIN_DELAY + 0.3).timeout
	assert(not is_instance_valid(b) or b.is_broken(), "El bidón vecino revienta en cadena")
	var clouds := 0
	for c in map.get_children():
		if c.is_in_group("spore_clouds"):
			clouds += 1
	assert(clouds >= 2, "Cada bidón suelta su nube (%d)" % clouds)

	# Agua: frena y envenena al jugador que la pisa
	var player := preload("res://scenes/entities/player.tscn").instantiate()
	add_child(player)
	await get_tree().process_frame
	var wc: Vector2i = map._water.keys()[0]
	player.global_position = Vector3(wc.x * DungeonMap.CELL, 0.1, wc.y * DungeonMap.CELL)
	await get_tree().create_timer(SewerMap.WATER_POISON_EVERY + 0.3).timeout
	var mc = player.movement_controller
	assert(mc.slow_mult <= SewerMap.WATER_SLOW + 0.001 and mc.slow_until > Time.get_ticks_msec() / 1000.0, "El agua frena")
	var fx := StatusEffects.get_for(player)
	assert(fx != null and fx.has("poison"), "El agua envenena")
	print("ALL SEWER CHECKS PASSED")
	get_tree().quit(0)
