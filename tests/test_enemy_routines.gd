extends Node

## Rutinas de los enemigos fuera de combate (EnemyRoutine + DungeonEncounter): la caverna se puebla antes de
## que el jugador la vea, el grupo hace su vida, oye ruidos, sufre emboscadas y corre la voz al ser descubierto.
## Carga las Cavernas reales.

func _ready() -> void:
	print("--- TEST: RUTINAS DE ENEMIGOS ---")
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.game_mode = "dungeon"
	GameData.world = "caves"
	DungeonEncounter.routines_enabled = true
	var scene: Node = load(Net.game_scene()).instantiate()
	get_tree().root.add_child.call_deferred(scene)
	await get_tree().process_frame
	get_tree().current_scene = scene
	var enc: DungeonEncounter = null
	for i in 900:
		await get_tree().process_frame
		enc = scene.get_node_or_null("DungeonEncounter")
		if enc and enc.map and is_instance_valid(enc.player):
			break
	var map: DungeonMap = enc.map
	var player: Node3D = enc.player
	player.health_comp.max_hp = 99999.0
	player.health_comp.hp = 99999.0
	var start := player.global_position

	# Dos cavernas normales pendientes, lo más lejos posible del jugador
	var normal: Array = []
	for i in enc._pending.keys():
		if map.rooms[i]["type"] == "normal" and i != map.arena_index:
			normal.append(i)
	normal.sort_custom(func(a, b): return map.room_center(a).distance_to(start) > map.room_center(b).distance_to(start))
	assert(normal.size() >= 2, "hacen falta dos cavernas normales (%d)" % normal.size())
	var room: int = normal[0]
	var room_b: int = normal[1]

	# 1. Puesta en escena: el grupo aparece con rutina, sin barreras y sin empezar el encuentro
	assert(not enc._staged.has(room), "lejos del jugador la caverna sigue vacía")
	var n: int = enc._pending[room]
	enc._stage_group(room, n, player)
	var group: Array = enc._staged[room]
	assert(group.size() >= n, "todo el grupo está colocado (%d de %d)" % [group.size(), n])
	var kinds_seen := {}
	for g in group:
		var r: EnemyRoutine = g.routine
		assert(r != null and r.room == room and r.is_unaware(), "cada uno con su rutina, sin haber visto a nadie")
		assert(g.state == DungeonGoblin.State.IDLE)
		assert(EnemyRoutine._cell_ok(map, g.global_position), "colocado en suelo libre")
		kinds_seen[r.kind] = int(kinds_seen.get(r.kind, 0)) + 1
	assert(kinds_seen.size() >= 2 or group.size() < 4, "rutinas variadas en un grupo (%s)" % str(kinds_seen))
	assert(enc._pending.has(room) and not enc.is_room_locked(room), "el encuentro no ha empezado")
	assert(enc.unaware_count(room) == group.size())
	print("CHECK 1 PASSED: %d enemigos con rutina %s" % [group.size(), str(kinds_seen)])

	# 2. Hacen su vida: nadie se alerta con el jugador lejos y los que rondan se mueven
	var before := {}
	for g in group:
		before[g] = g.global_position
	await get_tree().create_timer(3.5).timeout
	assert(enc.unaware_count(room) == group.size(), "siguen sin enterarse")
	var walkers := 0
	var moved := 0
	for g in group:
		var k: int = (g.routine as EnemyRoutine).kind
		if k == EnemyRoutine.Kind.PATROL or k == EnemyRoutine.Kind.WANDER:
			walkers += 1
			if g.global_position.distance_to(before[g]) > 0.3:
				moved += 1
		elif k == EnemyRoutine.Kind.GATHER or k == EnemyRoutine.Kind.SLEEP:
			assert(g.global_position.distance_to(before[g]) < 0.6, "los quietos no se pasean")
	assert(walkers == 0 or moved >= 1, "alguno de los que rondan ha andado (%d de %d)" % [moved, walkers])
	print("CHECK 2 PASSED: %d rondando, %d se han movido" % [walkers, moved])

	# 3. Pose de dormir: se tumba y, al acabar la rutina, vuelve a como estaba
	var probe: DungeonGoblin = group[0]
	var saved: EnemyRoutine = probe.routine
	var model_xf := probe.get_model().transform
	if saved.kind == EnemyRoutine.Kind.SLEEP:
		saved._stand_up(probe)
		model_xf = probe.get_model().transform
	var nap := EnemyRoutine.new()
	nap.kind = EnemyRoutine.Kind.SLEEP
	nap.room = room
	nap.begin(probe)
	assert(not probe.get_model().transform.is_equal_approx(model_xf), "dormido: el modelo está tumbado")
	assert(nap.notice_radius(probe, Vector3.FORWARD) < saved.notice_radius(probe, probe._facing) or saved.kind == EnemyRoutine.Kind.SLEEP,
		"dormido oye menos")
	probe.routine = nap
	nap.finish(probe)
	assert(probe.get_model().transform.is_equal_approx(model_xf), "al despertar recupera la postura")
	assert(probe.routine == null)
	probe.routine = saved
	if saved.kind == EnemyRoutine.Kind.SLEEP:
		saved._lie_down(probe)
	# Radios: por la espalda oye menos y un guardia ve más lejos que los reunidos
	var guard := EnemyRoutine.new()
	guard.kind = EnemyRoutine.Kind.GUARD
	var front := guard.notice_radius(probe, probe._facing)
	assert(guard.notice_radius(probe, -probe._facing) < front, "por la espalda, menos radio")
	assert(front > float(EnemyRoutine.NOTICE[EnemyRoutine.Kind.GATHER]))
	print("CHECK 3 PASSED: pose de dormir y radios de detección")

	# 4. Ruido: un golpe cerca y la fauna espantada los ponen en guardia (los dormidos no se enteran)
	var awake: DungeonGoblin = null
	for g in group:
		if (g.routine as EnemyRoutine).kind != EnemyRoutine.Kind.SLEEP:
			awake = g
			break
	assert(awake != null, "siempre queda alguien despierto")
	assert(enc.noise_at(awake.global_position, 3.0) >= 1)
	assert((awake.routine as EnemyRoutine).phase == EnemyRoutine.Phase.SUSPICIOUS, "el ruido le pone en guardia")
	assert((awake.routine as EnemyRoutine).is_unaware(), "pero aún no ha visto al jugador")
	(awake.routine as EnemyRoutine).phase = EnemyRoutine.Phase.CALM
	var critters := scene.get_node_or_null("AmbientCritters") as AmbientCritters
	assert(critters != null, "la fauna existe")
	critters.scared.emit(awake.global_position, "bat")
	assert((awake.routine as EnemyRoutine).phase == EnemyRoutine.Phase.SUSPICIOUS, "la fauna espantada delata")
	print("CHECK 4 PASSED: ruido y fauna ponen en guardia")

	# 5. Emboscada: más daño a quien no te ha visto, y la voz corre por el grupo
	var victim: DungeonGoblin = group[group.size() - 1]
	var vr: EnemyRoutine = victim.routine
	var expect := EnemyRoutine.SLEEP_MULT if vr.kind == EnemyRoutine.Kind.SLEEP else EnemyRoutine.AMBUSH_MULT
	assert(is_equal_approx(vr.on_hit(victim, 10.0), 10.0 * expect), "emboscada x%.2f" % expect)
	assert(victim.routine == null, "el golpe acaba su rutina")
	assert(enc._alerted_rooms.has(room), "el golpeado da la alarma")
	await get_tree().process_frame
	await get_tree().process_frame
	assert(not enc._pending.has(room), "el encuentro empieza")
	assert(enc._close_on_entry.has(room) and not enc.is_room_locked(room), "con el jugador fuera, las barreras esperan")
	await get_tree().create_timer(3.2).timeout
	for g in group:
		if is_instance_valid(g) and not g.is_dead():
			assert(g.routine == null and g.state != DungeonGoblin.State.IDLE, "todos despiertos y a por el jugador")
	print("CHECK 5 PASSED: emboscada x%.2f y alarma de grupo" % expect)

	# 6. Al entrar el jugador se cierran las barreras
	player.global_position = map.room_center(room) + Vector3(0.0, 0.3, 0.0)
	await get_tree().create_timer(0.4).timeout
	assert(not enc._close_on_entry.has(room), "ya no espera")
	assert(enc.is_room_locked(room) or enc._doors_waiting.has(room), "la caverna se cierra con el jugador dentro")
	print("CHECK 6 PASSED: barreras al entrar")

	# 7. Sin rutinas (interruptor): aparecen al entrar, como antes
	room_b = -1
	for i in enc._pending.keys():
		if not enc._staged.has(i) and i != room:
			room_b = i
	if room_b < 0:
		print("CHECK 7 SKIPPED: no queda ninguna caverna sin poblar")
	else:
		DungeonEncounter.routines_enabled = false
		player.global_position = map.room_center(room_b) + Vector3(0.0, 0.3, 0.0)
		for i in 30:
			await get_tree().process_frame
		assert(not enc._pending.has(room_b) and not enc._staged.has(room_b), "aparición directa")
		assert(int(enc._alive.get(room_b, 0)) > 0)
		for e in get_tree().get_nodes_in_group("enemies"):
			if map.is_in_room((e as Node3D).global_position, room_b):
				assert((e as DungeonGoblin).routine == null, "sin rutinas")
		DungeonEncounter.routines_enabled = true
		print("CHECK 7 PASSED: interruptor de rutinas")

	print("TODOS LOS CHECKS PASARON")
	get_tree().quit(0)
