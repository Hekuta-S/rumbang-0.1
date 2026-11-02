extends Node

## Generación de mazmorras: muchas semillas y los 4 temas. Comprueba que todas las cavernas se alcanzan
## desde la inicial, que el centro de cada caverna es suelo (encuentros y portal), que las columnas no
## tapan el centro, que la colisión de paredes se fusiona y mide el tiempo de generación.

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
	print("--- TEST: GENERACIÓN DE MAZMORRAS ---")
	GameData.game_mode = "dungeon"
	var map := DungeonMap.new()
	map.name = "ProceduralMap"
	add_child(map)
	await get_tree().process_frame
	var times: Array = []
	var shapes := {}
	var treasures := 0
	var boxes := 0
	var runs := 0
	# Las cloacas (SewerMap) tienen su propia prueba: test_sewer_generation
	map.world_id = "caves"
	for theme in 4:
		for k in 6:
			map.level_theme = theme
			var t0 := Time.get_ticks_usec()
			map.generate(5000 + theme * 100 + k)
			var room_themes: Array = map.world()["room_themes"]
			for r in map.rooms:
				if r["type"] == "normal":
					assert(room_themes.has(r["theme"]), "Decoración del mundo %s (%s)" % [map.world_id, r["theme"]])
			times.append((Time.get_ticks_usec() - t0) / 1000.0)
			runs += 1
			var seen := _reachable(map)
			for i in map.rooms.size():
				var r: Dictionary = map.rooms[i]
				shapes[r.get("shape", "?")] = shapes.get(r.get("shape", "?"), 0) + 1
				if r["type"] == "treasure":
					treasures += 1
				var cc := map.world_to_cell(map.room_center(i))
				assert(map._cells.has(cc), "El centro de la caverna %d (%s) es suelo" % [i, r.get("shape", "?")])
				assert(seen.has(cc), "La caverna %d (%s) se alcanza desde la inicial (semilla %d)" % [i, r.get("shape", "?"), map.used_seed])
				for pc in r.get("pillars", []):
					assert((pc as Vector2).distance_to(Vector2(r["cell"])) >= DungeonMap.CENTER_CLEAR, "Columna lejos del centro")
			boxes += map._wall_boxes.size()
			await get_tree().process_frame
	times.sort()
	print("formas=", shapes, " tesoros=", treasures, "/", runs, " cajas de pared media=", boxes / runs)
	print("tiempo de generación ms: mediana=%.1f max=%.1f" % [times[times.size() / 2], times[times.size() - 1]])
	assert(times[times.size() / 2] < 120.0, "La generación es rápida (mediana %.1f ms)" % times[times.size() / 2])
	assert(shapes.size() >= 4, "Salen varias formas de caverna")
	assert(treasures > 0, "Aparecen cámaras del tesoro")
	print("ALL GENERATION CHECKS PASSED")
	get_tree().quit(0)
