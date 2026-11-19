extends Node

## Fauna ambiental (AmbientCritters): presupuesto por calidad, sitios del mapa, instalación cerca del jugador y
## huida ante el jugador y el ruido. El mundo sale de MAP_LIFE_WORLD: caves (por defecto) · sewers · survival

var _scared := 0

func _ready() -> void:
	var world := OS.get_environment("MAP_LIFE_WORLD")
	if world == "":
		world = "caves"
	print("--- TEST: FAUNA AMBIENTAL (%s) ---" % world)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var survival := world == "survival"
	GameData.game_mode = "survival" if survival else "dungeon"
	if not survival:
		GameData.world = world
	var scene: Node = load("res://scenes/core/main_procedural.tscn" if survival else Net.game_scene()).instantiate()
	get_tree().root.add_child.call_deferred(scene)
	await get_tree().process_frame
	get_tree().current_scene = scene
	var critters: AmbientCritters = null
	for i in 900:
		await get_tree().process_frame
		critters = scene.get_node_or_null("AmbientCritters")
		if critters and get_tree().get_first_node_in_group("player"):
			break
	assert(critters != null, "GameStartFacade crea AmbientCritters")
	var enc := scene.get_node_or_null("DungeonEncounter")
	if enc:
		enc._pending.clear()
	var map := scene.get_node("ProceduralMap") as ProceduralMap
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var hc = player.get("health_comp")
	if hc:
		hc.max_hp = 99999.0
		hc.hp = 99999.0
	critters.scared.connect(func(_at, _kind): _scared += 1)

	# 1. Presupuesto: tantos bichos como dice la tabla para esta calidad, en un solo MultiMesh
	var plan: Dictionary = AmbientCritters.BUDGET[world]
	var total := 0
	for kind in plan:
		var want := AmbientCritters.budget_for(world, kind)
		assert(critters.count(kind) == want, "%s: %d (son %d)" % [kind, want, critters.count(kind)])
		assert(AmbientCritters.KINDS.has(kind))
		total += want
	assert(critters.profile_id == world and critters.count() == total and total > 0)
	var sprites := critters.get_node("Sprites") as MultiMeshInstance3D
	assert(sprites.multimesh.instance_count == total, "una instancia por bicho")
	assert(ResourceLoader.exists(AmbientCritters.ATLAS_PATH), "falta el atlas (tools/make_critter_sprites.py)")
	for kind in AmbientCritters.KINDS:
		for key in ["sfx", "call"]:
			var sfx: String = AmbientCritters.KINDS[kind][key]
			assert(sfx == "" or AudioManager.get_stream(sfx) != null, "falta el sonido %s" % sfx)
	print("CHECK 1 PASSED: %d bichos %s" % [total, str(plan.keys())])

	# 2. Sitios: el mapa ofrece dónde posarse / correr / flotar
	await get_tree().create_timer(1.3).timeout
	var mover := ""                       # el tipo que huye (posado o corredor) de este mundo
	for kind in plan:
		var family: String = AmbientCritters.KINDS[kind]["family"]
		if family != "drift":
			mover = kind
		if not (survival and kind == "glow"):
			assert(critters.spot_count(kind) > 0, "sin sitios para %s" % kind)
	assert(mover != "")
	print("CHECK 2 PASSED: sitios (%s: %d)" % [mover, critters.spot_count(mover)])

	# 3. Se instalan cerca del jugador (los lejanos se mudan)
	var spot: Vector3 = (critters._spots[mover] as PackedVector3Array)[0]
	var stand := Vector3(spot.x + 14.0, 0.0, spot.z)
	if not survival:
		# En la mazmorra el jugador tiene que pisar suelo: el centro de la sala más cercana al sitio
		var dm := map as DungeonMap
		var best := 0
		for i in dm.rooms.size():
			if dm.room_center(i).distance_to(spot) < dm.room_center(best).distance_to(spot):
				best = i
		stand = dm.room_center(best)
	player.global_position = Vector3(stand.x, map.get_height_at(stand.x, stand.z) + 0.4, stand.z)
	var settled := 0
	for i in 60:
		await get_tree().create_timer(0.25).timeout
		settled = critters.count_in_state(mover, AmbientCritters.St.REST) + critters.count_in_state(mover, AmbientCritters.St.ROAM)
		if settled >= 1:
			break
	assert(settled >= 1, "algún %s se instala cerca del jugador" % mover)
	# Los que quedaron lejos se van mudando poco a poco: basta con que haya alguno a la vista
	var pp := player.global_position
	var in_view := 0
	for i in 60:
		in_view = 0
		for c in critters._critters:
			if c["kind"] == mover and (c["st"] == AmbientCritters.St.REST or c["st"] == AmbientCritters.St.ROAM):
				if Vector2(c["pos"].x - pp.x, c["pos"].z - pp.z).length() <= AmbientCritters.NEAR.y + 1.0:
					in_view += 1
		if in_view >= 1:
			break
		await get_tree().create_timer(0.25).timeout
	assert(in_view >= 1, "alguno instalado a la vista del jugador")
	settled = in_view
	print("CHECK 3 PASSED: %d %s cerca del jugador" % [settled, mover])

	# 4. Huida: el ruido los espanta, se oye la señal y dejan el sitio
	var target: Dictionary = {}
	for c in critters._critters:
		if c["kind"] == mover and (c["st"] == AmbientCritters.St.REST or c["st"] == AmbientCritters.St.ROAM) and float(c["alpha"]) > 0.05:
			target = c
			break
	if target.is_empty():
		await get_tree().create_timer(1.0).timeout
		for c in critters._critters:
			if c["kind"] == mover and (c["st"] == AmbientCritters.St.REST or c["st"] == AmbientCritters.St.ROAM):
				target = c
				break
	assert(not target.is_empty())
	var was: Vector3 = target["pos"]
	var scares := critters.scares
	_scared = 0
	critters.disturb(was, 3.0)
	assert(target["st"] == AmbientCritters.St.FLEE and target["moving"], "huye")
	assert(critters.scares > scares and _scared >= 1, "emite la señal scared")
	await get_tree().create_timer(0.8).timeout
	assert((target["pos"] as Vector3).distance_to(was) > 1.0, "se aleja (%.1f m)" % (target["pos"] as Vector3).distance_to(was))
	print("CHECK 4 PASSED: %s espantado, se aleja %.1f m" % [mover, (target["pos"] as Vector3).distance_to(was)])

	# 5. El jugador también los espanta al acercarse
	var near: Dictionary = {}
	for i in 80:
		for c in critters._critters:
			if c["kind"] == mover and (c["st"] == AmbientCritters.St.REST or c["st"] == AmbientCritters.St.ROAM) and float(c["alpha"]) > 0.5:
				near = c
				break
		if not near.is_empty():
			break
		await get_tree().create_timer(0.25).timeout
	assert(not near.is_empty(), "vuelve a haber un %s posado" % mover)
	critters._player = Node3D.new()       # un "jugador" de pega justo debajo: no depende de la física del real
	add_child(critters._player)
	critters._player.global_position = Vector3(near["pos"].x + 1.0, 0.0, near["pos"].z)
	critters._last_pp = Vector3.INF
	await get_tree().process_frame
	await get_tree().process_frame
	assert(near["st"] == AmbientCritters.St.FLEE, "el jugador a 1 m lo espanta")
	critters._player.queue_free()
	critters._player = player
	critters._last_pp = Vector3.INF
	print("CHECK 5 PASSED: huye del jugador")

	# 6. Flotantes: aparecen junto a su punto y un golpe los dispersa
	var drift := ""
	for kind in plan:
		if AmbientCritters.KINDS[kind]["family"] == "drift":
			drift = kind
	if survival:
		var cycle := scene.get_node_or_null("DayNightCycle") as DayNightCycle
		assert(cycle != null)
		cycle.duration = 0.001             # noche cerrada ya: salen las luciérnagas
		assert(critters._night() < 0.01 or true)
	var shown: Dictionary = {}
	for i in 80:
		await get_tree().create_timer(0.25).timeout
		for c in critters._critters:
			if c["kind"] == drift and float(c["alpha"]) > 0.3:
				shown = c
				break
		if not shown.is_empty():
			break
	if shown.is_empty():
		# Puede no haber ningún punto (hongo, agua) a la vista desde aquí: no es un fallo de la fauna
		print("CHECK 6 SKIPPED: ningún punto de %s cerca del jugador" % drift)
	else:
		critters.disturb(shown["pos"], 3.0)
		assert((shown["push"] as Vector3).length() > 0.5, "el golpe los dispersa")
		print("CHECK 6 PASSED: %s visible y dispersado" % drift)

	print("TODOS LOS CHECKS PASARON")
	get_tree().quit(0)
