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

	# 1. Carcasa de la cueva (paredes + techo en trozos, cave_rock) con colisión de techo, y suelo con su shader
	var walls := map.get_node("Walls")
	var parts := {"Pared": 0, "Techo": 0}
	for mi in walls.get_children():
		if mi is MeshInstance3D:
			assert((mi as MeshInstance3D).material_override.shader == DungeonMap.ROCK_SHADER, "La carcasa usa cave_rock")
			parts[String(mi.name).rstrip("0123456789")] += 1
	assert(parts["Pared"] > 1 and parts["Techo"] > 1, "Paredes y techo en varios trozos (%s)" % str(parts))
	assert(walls.get_node_or_null("CeilingBody") != null, "El techo tiene colisión (cámara)")
	# Antorchas de pared y braseros con luz, encendidas aunque la calidad apague las luces
	assert(map._instances.get("torch_wall", []).size() > 5, "Hay antorchas de pared")
	assert(map._instances.get("brazier_pillar", []).size() > 0, "Hay braseros en las bocas de túnel")
	assert(map.lights_essential and map._lights.size() > 16, "Las luces de la cueva son imprescindibles (%d)" % map._lights.size())
	# Hongos que brillan (sin los morados antiguos) con el shader mushroom_glow
	assert(map._instances.get("mush_small", []).size() > 0 and not map._instances.has("mushroom"), "Hongos nuevos en vez de los morados")
	assert((map._load_kind("mush_big").surface_get_material(0) as ShaderMaterial).shader == DungeonMap.MUSH_SHADER, "Los hongos usan mushroom_glow")
	# Pack de cueva: piezas sueltas (luces por pieza en el renderizador Mobile) con estalactitas, y pinturas
	var pack := map.get_node_or_null("PackProps")
	assert(pack != null and pack.get_child_count() > 10, "Piezas del pack como mallas sueltas")
	var stalactites := pack.get_children().filter(func(n): return String(n.name).begins_with("stalactite"))
	assert(stalactites.size() > 0, "Hay estalactitas")
	for st in stalactites:
		assert((st as Node3D).position.y - 2.6 * (st as Node3D).transform.basis.get_scale().y >= DungeonMap.STALACTITE_CLEAR - 1.0, "Las estalactitas no bajan a la altura del jugador")
	assert(map.get_node_or_null("RockArt") != null, "Nodo de pinturas rupestres")
	var floor_mm := map.get_node("Floor") as MultiMeshInstance3D
	assert((floor_mm.multimesh.mesh.surface_get_material(0) as ShaderMaterial).shader == DungeonMap.FLOOR_SHADER, "El suelo usa cave_floor")
	print("CHECK 1 PASSED: carcasa %s y suelo texturizado" % str(parts))

	# 2. Props con detalle de madera/piedra y piezas preparadas
	var barrel_mesh := map._load_kind("barrel")
	assert((barrel_mesh.surface_get_material(0) as ShaderMaterial).shader == DungeonMap.DETAIL_SHADER, "Los props usan prop_detail")
	for k in ["barrel", "crate", "hut", "totem"]:
		DestructibleProp.prewarm(k, String(map._prop_def(k)["file"]), map._load_kind(k), map._mesh_xf[k])
	var nb: int = DestructibleProp._pieces_cache["barrel"].size()
	var nc: int = DestructibleProp._pieces_cache["crate"].size()
	var nh: int = DestructibleProp._pieces_cache["hut"].size()
	var nt: int = DestructibleProp._pieces_cache["totem"].size()
	assert(nb >= 20, "El barril se parte en sus duelas, aros y tapas (%d)" % nb)
	assert(nc >= 20, "La caja se parte en sus tablas y postes (%d)" % nc)
	assert(nh >= 40, "La choza se parte en sus troncos, sectores del techo, cuerdas... (%d)" % nh)
	assert(nt >= 10, "El tótem se parte en sus cabezas, alas, cuerdas... (%d)" % nt)
	for k in ["hut", "totem"]:
		for pc in DestructibleProp._pieces_cache[k]:
			assert((pc["mesh"] as Mesh).get_surface_count() == 1, "Cada pieza tiene malla")
			assert((pc["hull"] as PackedVector3Array).size() >= 4, "Las piezas de estructura chocan con su casco convexo")
			assert(pc.has("tex_offset"), "La pieza sabe dónde estaba su textura")
	# La choza lleva piedra, paja, piel y corteza (UV2 = clase de detalle) y la AO horneada en el color
	# de vértice: la paja del techo no es de un solo tono.
	var arr := map._load_kind("hut").surface_get_arrays(0)
	var classes := {}
	var straw_lo := 9.0
	var straw_hi := 0.0
	var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var uv2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
	for i in uv2.size():
		var cl := int(uv2[i].x)
		classes[cl] = true
		if cl == 2:
			straw_lo = minf(straw_lo, cols[i].g)
			straw_hi = maxf(straw_hi, cols[i].g)
	for cl in [0, 1, 2, 3, 4]:
		assert(classes.has(cl), "La choza usa la clase de detalle %d (%s)" % [cl, classes.keys()])
	assert(straw_lo < straw_hi * 0.5, "La paja tiene oclusión horneada (%.3f..%.3f)" % [straw_lo, straw_hi])
	print("CHECK 2 PASSED: barril %d piezas, caja %d, choza %d, tótem %d" % [nb, nc, nh, nt])

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
	var stored := EnemyMotion._obs.size() / EnemyMotion.OBS_STRIDE
	var counted := 0
	for c in EnemyMotion._ocell_count:
		counted += c
	assert(expected > 0 and stored == expected and counted == expected,
		"Cada celda guarda todos sus obstáculos (%d / %d de %d)" % [stored, counted, expected])
	print("CHECK 4 PASSED: rejilla de obstáculos completa (%d entradas)" % stored)

	# 5. Un enemigo dentro de un obstáculo sale fuera (rejilla densa)
	var pushed := 0
	for o in EnemyMotion._map.get_colliders():
		var c: Vector2 = o["pos"]
		var start := c + Vector2(0.05, 0.03)
		var out := EnemyMotion._push_out_of_obstacles(start)
		assert(out != start, "El punto dentro del obstáculo en %s se empuja fuera" % c)
		pushed += 1
	assert(EnemyMotion._push_out_of_obstacles(Vector2(99999, 99999)) == Vector2(99999, 99999), "Fuera de la rejilla no se toca")
	print("CHECK 5 PASSED: empuje fuera de obstáculos (%d obstáculos)" % pushed)

	print("ALL PROPS/DESTRUCTION CHECKS PASSED")
	get_tree().quit(0)
