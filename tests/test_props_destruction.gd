extends Node

## Assets de la mazmorra: paredes de roca y suelo con texturas, props con detalle, rotura en piezas reales
## (barril y caja desde *_pieces.glb, estructuras partidas en sus partes) y la rejilla de obstáculos de
## EnemyMotion (cada celda guarda TODOS sus obstáculos). Carga la mazmorra y la partida de supervivencia.

func _ready() -> void:
	print("--- TEST: PROPS, ROTURA Y MATERIALES ---")
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.game_mode = "dungeon"
	var scene: Node = load("res://scenes/core/main_dungeon.tscn").instantiate()
	get_tree().root.add_child.call_deferred(scene)
	await get_tree().process_frame
	get_tree().current_scene = scene
	var enc: DungeonEncounter = null
	for i in 600:
		await get_tree().process_frame
		enc = scene.get_node_or_null("DungeonEncounter")
		if enc and enc.map and is_instance_valid(enc.player):
			break
	enc._pending.clear()
	var map: DungeonMap = enc.map
	var p = enc.player
	p.health_comp.max_hp = 9999.0
	p.health_comp.hp = 9999.0

	# 1. Paredes de roca (3 variantes, en trozos) y suelo con su shader
	var walls := map.get_node("Walls")
	var meshes := {}
	for mmi in walls.get_children():
		assert((mmi as MultiMeshInstance3D).material_override.shader == DungeonMap.ROCK_SHADER, "Las paredes usan cave_rock")
		meshes[(mmi as MultiMeshInstance3D).multimesh.mesh] = true
	assert(meshes.size() == DungeonMap.ROCK_MESHES.size(), "Hay %d variantes de roca (%d)" % [DungeonMap.ROCK_MESHES.size(), meshes.size()])
	assert(walls.get_child_count() > meshes.size(), "Las paredes van en varios trozos (%d)" % walls.get_child_count())
	var floor_mm := map.get_node("Floor") as MultiMeshInstance3D
	assert((floor_mm.multimesh.mesh.surface_get_material(0) as ShaderMaterial).shader == DungeonMap.FLOOR_SHADER, "El suelo usa cave_floor")
	print("CHECK 1 PASSED: %d trozos de pared con %d rocas y suelo texturizado" % [walls.get_child_count(), meshes.size()])

	# 2. Props con detalle de madera/piedra y piezas preparadas
	var barrel_mesh := map._load_kind("barrel")
	assert((barrel_mesh.surface_get_material(0) as ShaderMaterial).shader == DungeonMap.DETAIL_SHADER, "Los props usan prop_detail")
	for k in ["barrel", "crate", "hut"]:
		DestructibleProp.prewarm(k, String(map._prop_def(k)["file"]), map._load_kind(k), map._mesh_xf[k])
	var nb: int = DestructibleProp._pieces_cache["barrel"].size()
	var nc: int = DestructibleProp._pieces_cache["crate"].size()
	var nh: int = DestructibleProp._pieces_cache["hut"].size()
	assert(nb >= 20, "El barril se parte en sus duelas, aros y tapas (%d)" % nb)
	assert(nc >= 20, "La caja se parte en sus tablas y postes (%d)" % nc)
	assert(nh > 2 and nh <= DestructibleProp.MAX_SPLIT, "La choza se parte en sus partes (%d)" % nh)
	for pc in DestructibleProp._pieces_cache["hut"]:
		assert((pc["mesh"] as Mesh).get_surface_count() == 1, "Cada parte tiene malla")
	print("CHECK 2 PASSED: barril %d piezas, caja %d, choza %d" % [nb, nc, nh])

	# 3. Romper un barril suelta sus piezas con física; luego se retiran
	var d: DestructibleProp = null
	for x in map.destructibles:
		if is_instance_valid(x) and x.kind == "barrel":
			d = x
			break
	if d == null:
		d = DestructibleProp.new()
		d.setup("barrel", barrel_mesh, map._mesh_xf["barrel"], map._prop_def("barrel"), Transform3D(Basis(), p.global_position + Vector3(3, 0, 0)), 18.0)
		map.add_child(d)
	var holder := d.get_parent()
	var before := DestructibleProp._alive_pieces
	d.take_damage(999.0, Vector3(6, 0, 0))
	await get_tree().physics_frame
	var bodies := holder.get_children().filter(func(n): return n is RigidBody3D)
	assert(DestructibleProp._alive_pieces >= before + 20, "Salen las piezas (%d -> %d)" % [before, DestructibleProp._alive_pieces])
	assert(bodies.size() >= 20, "Son cuerpos con física (%d)" % bodies.size())
	assert(DestructibleProp._alive_pieces <= DestructibleProp.max_pieces(), "Respeta el tope de piezas")
	var moving := bodies.filter(func(b): return (b as RigidBody3D).linear_velocity.length() > 1.0).size()
	assert(moving > bodies.size() / 2, "Revientan hacia fuera (%d de %d)" % [moving, bodies.size()])
	Engine.time_scale = 4.0
	var t0 := Time.get_ticks_msec()
	while DestructibleProp._alive_pieces > before and Time.get_ticks_msec() - t0 < 15000:
		await get_tree().process_frame
	Engine.time_scale = 1.0
	assert(DestructibleProp._alive_pieces <= before, "Las piezas se retiran solas (%d)" % DestructibleProp._alive_pieces)
	print("CHECK 3 PASSED: %d piezas con física, se retiran solas" % bodies.size())

	scene.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	# 4. Supervivencia: la rejilla de obstáculos de EnemyMotion guarda todos los de cada celda
	GameData.game_mode = "survival"
	EnemyMotion.reset()
	var surv: Node = load("res://scenes/core/main_procedural.tscn").instantiate()
	get_tree().root.add_child(surv)
	get_tree().current_scene = surv
	for i in 600:
		await get_tree().process_frame
		if EnemyMotion.available():
			break
	assert(EnemyMotion.available(), "Hay mapa procedural")
	EnemyMotion.height_at(0.0, 0.0)            # construye la rejilla
	var expected := 0
	for o in EnemyMotion._map.get_colliders():
		var c: Vector2 = o["pos"]
		var reach: float = o["r"]
		var c0 := Vector2i(int(floor((c.x - reach) / EnemyMotion.CELL)), int(floor((c.y - reach) / EnemyMotion.CELL)))
		var c1 := Vector2i(int(floor((c.x + reach) / EnemyMotion.CELL)), int(floor((c.y + reach) / EnemyMotion.CELL)))
		expected += (c1.x - c0.x + 1) * (c1.y - c0.y + 1)
	var stored := 0
	for k in EnemyMotion._grid:
		stored += (EnemyMotion._grid[k] as PackedFloat32Array).size() / EnemyMotion.OBS_STRIDE
	assert(expected > 0 and stored == expected, "Cada celda guarda todos sus obstáculos (%d de %d)" % [stored, expected])
	print("CHECK 4 PASSED: rejilla de obstáculos completa (%d entradas)" % stored)

	print("ALL PROPS/DESTRUCTION CHECKS PASSED")
	get_tree().quit(0)
