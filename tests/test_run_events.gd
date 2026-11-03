extends Node

## Fase 3 del plan de mejora (supervivencia): mareas, élites, minijefe, cofre maldito, santuarios,
## modo infinito y resumen de la partida. Carga la partida real.

var _main: Node

func _ready() -> void:
	print("--- TEST: EVENTOS DE LA PARTIDA ---")
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.game_mode = "survival"
	_main = load("res://scenes/core/main_procedural.tscn").instantiate()
	get_tree().root.add_child.call_deferred(_main)
	await get_tree().process_frame
	get_tree().current_scene = _main
	var p = null
	var waves: WaveManager = null
	for i in 900:
		await get_tree().process_frame
		p = _main.get_node_or_null("Player")
		waves = _main.find_child("WaveManager", true, false)
		if p and waves and waves._running:
			break
	assert(waves != null and waves._running, "Arranca la partida")
	p.health_comp.max_hp = 99999.0
	p.health_comp.hp = 99999.0
	var ev: RunEvents = waves.events
	assert(ev != null and ev._shrines.size() == RunEvents.SHRINES, "Hay %d santuarios al empezar" % RunEvents.SHRINES)
	assert(_main.has_method("show_item_choice"), "La escena sabe abrir la elección de objeto (ItemPickup)")
	assert(LootManager.PLAYABLE_MAX_X < 100.0, "Los objetos del suelo caen dentro del mapa")

	# 1. Marea: un muro de enemigos que llega repartido en varios fotogramas
	waves.stop_run()                 # sin aparición normal para contar solo los de la marea
	waves._running = true            # ...pero los eventos siguen activos
	var before := EnemyRegistry.count()
	ev._start_horde()
	var queued := ev._queue.size()
	assert(queued >= RunEvents.HORDE_BASE, "La marea encola %d enemigos" % queued)
	for i in 30:
		await get_tree().physics_frame
	assert(ev._queue.is_empty() and EnemyRegistry.count() >= before + queued - 2, "La marea aparece (%d → %d)" % [before, EnemyRegistry.count()])
	print("CHECK 1 PASSED: marea de %d enemigos" % queued)

	# 2. Élite: más vida y tamaño, marca encima y un objeto al morir
	var en: EnemyData = waves._spawn_single_enemy(p.global_position + Vector3(12, 0, 0), EnemyData.EnemyType.NORMAL_GOBLIN)[0]
	var hp0 := en.max_hp
	ev.make_elite(en, "acorazado")
	assert(is_equal_approx(en.max_hp, hp0 * 12.0) and en.scale.x > 1.5, "El élite acorazado tiene ×12 vida y es grande")
	await get_tree().process_frame
	var mk: Node3D = ev._elites[ev._elites.size() - 1]["marker"]
	assert(is_instance_valid(mk) and mk.global_position.distance_to(en.global_position) < 0.5, "La marca sigue al élite")
	var items_before := get_tree().get_nodes_in_group("item_pickups").size()
	HitFeedback.weapon_tag = WeaponData.WeaponType.SPEAR_LANCE
	en.take_damage(en.hp + 10.0)
	await get_tree().process_frame
	assert(RunStats.elites == 1, "Cuenta el élite (%d)" % RunStats.elites)
	assert(get_tree().get_nodes_in_group("item_pickups").size() == items_before + 1, "El élite suelta un objeto")
	assert(not is_instance_valid(mk) or mk.is_queued_for_deletion(), "La marca desaparece")
	assert(float(RunStats.damage_by_weapon.get(WeaponData.WeaponType.SPEAR_LANCE, 0.0)) >= hp0 * 12.0 - 1.0, "El daño cuenta para su arma")
	print("CHECK 2 PASSED: élite acorazado, marca, objeto y daño por arma")

	# 3. Minijefe al llegar su minuto
	GameState.get_instance().elapsed_time = RunEvents.MINIBOSS_TIME + 1.0
	for i in 5:
		await get_tree().process_frame
	assert(ev._miniboss_done and ev._elites.any(func(e): return e["miniboss"]), "Sale el minijefe")
	print("CHECK 3 PASSED: minijefe a los %d s" % int(RunEvents.MINIBOSS_TIME))

	# 4. Cofre maldito: botín, oro y maldición (lotes más grandes)
	var batch := waves._current_batch()
	var gold := GameState.get_instance().gold
	ev._spawn_cursed_chest()
	await get_tree().process_frame
	var chests := get_tree().get_nodes_in_group("cursed_chests")
	var chest: Node3D = chests[0] if not chests.is_empty() else null
	assert(chest != null, "Aparece el cofre maldito")
	ev._open_cursed_chest(chest)
	assert(waves.is_cursed() and waves._current_batch() > batch, "Maldición: más enemigos por lote (%d → %d)" % [batch, waves._current_batch()])
	assert(GameState.get_instance().gold == gold + RunEvents.CHEST_GOLD, "El cofre da oro")
	print("CHECK 4 PASSED: cofre maldito")

	# 5. Santuario: quedarse dentro lo activa (cura y objeto) y luego reaparece otro
	var shrine: Node3D = ev._shrines[0]["node"]
	p.global_position = shrine.global_position + Vector3(0, 0.3, 0)
	p.health_comp.hp = 50000.0
	var shrines := RunStats.shrines
	var t0 := Time.get_ticks_msec()
	while RunStats.shrines == shrines and Time.get_ticks_msec() - t0 < 20000:
		p.global_position = shrine.global_position + Vector3(0, 0.3, 0)
		await get_tree().physics_frame
	assert(RunStats.shrines == shrines + 1, "Se activa el santuario")
	assert(p.health_comp.hp > 50000.0, "El santuario cura")
	assert(ev._shrine_respawn.size() == 1, "Se programa otro santuario")
	get_tree().paused = false        # la elección de objeto del santuario pausa
	print("CHECK 5 PASSED: santuario activado")

	# 6. Modo infinito: sigue la aparición y los enemigos son más duros pasado el jefe
	GameState.get_instance().elapsed_time = WaveManager.BOSS_TIME_S + 120.0
	var normal: EnemyData = waves._spawn_single_enemy(p.global_position + Vector3(20, 0, 0), EnemyData.EnemyType.NORMAL_GOBLIN)[0]
	waves.stop_run()
	_main._start_endless()
	assert(waves.endless and waves._running and RunStats.endless_from > 0.0, "Empieza el modo infinito")
	var hard: EnemyData = waves._spawn_single_enemy(p.global_position + Vector3(-20, 0, 0), EnemyData.EnemyType.NORMAL_GOBLIN)[0]
	assert(hard.max_hp > normal.max_hp * 1.3, "En el modo infinito más vida (%.0f → %.0f)" % [normal.max_hp, hard.max_hp])
	print("CHECK 6 PASSED: modo infinito")

	# 7. Resumen de la partida
	var lines := RunStats.summary_lines(p.weapon_inventory)
	assert(lines.size() >= 4 and lines[0].begins_with("ENEMIGOS"), "Resumen: %s" % [lines])
	assert(lines.any(func(l): return l.begins_with("MODO INFINITO")), "El resumen cuenta el modo infinito")
	print("CHECK 7 PASSED: resumen\n  " + "\n  ".join(lines))

	print("ALL RUN EVENT CHECKS PASSED")
	get_tree().quit(0)
