extends Node

## Historia: la jaula del mago (MageCage) sale en la Supervivencia a los RunEvents.CAGE_TIME s si el mago sigue
## raptado, custodiada por élites. Quedarse dentro del círculo la abre, guarda el rescate y abre las mazmorras.
## Headless:  godot --headless --path . res://tests/test_mage_cage.tscn

var _fails := 0

func _check(ok: bool, msg: String) -> void:
	print(("PASSED: " if ok else "FAILED: ") + msg)
	if not ok:
		_fails += 1

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _ready() -> void:
	print("--- TEST: JAULA DEL MAGO ---")
	SaveManager.save_path = "user://test_save_cage.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.save_path))
	SaveManager.load_save()
	GameData.armory_path = "user://test_armeria_cage.cfg"
	GameData.game_mode = "survival"
	var main: Node = load("res://scenes/core/main_procedural.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	get_tree().current_scene = main
	var p: Node3D = null
	var waves: WaveManager = null
	for i in 900:
		await get_tree().process_frame
		p = main.get_node_or_null("Player")
		waves = main.find_child("WaveManager", true, false)
		if p and waves and waves._running:
			break
	waves.stop_run()
	waves._running = true
	waves.set_process(false)
	p.health_comp.max_hp = 9999.0
	p.health_comp.hp = 9999.0
	var events: RunEvents = waves.events
	events.set_process(false)
	var gs := GameState.get_instance()

	# 1. Con el mago ya rescatado no sale la jaula aunque llegue el minuto
	SaveManager.mago_rescatado = true
	events._queue.clear()
	gs.elapsed_time = RunEvents.CAGE_TIME + 1.0
	events._process(0.016)
	_check(get_tree().get_nodes_in_group("mage_cage").is_empty(), "mago rescatado: no hay jaula")

	# 2. Partida nueva (mago raptado): antes del minuto no sale; al llegar, sale con su guardia
	SaveManager.mago_rescatado = false
	events._cage_done = false
	events._queue.clear()
	gs.elapsed_time = RunEvents.CAGE_TIME - 5.0
	events._process(0.016)
	_check(get_tree().get_nodes_in_group("mage_cage").is_empty(), "antes del minuto 4 no hay jaula")
	gs.elapsed_time = RunEvents.CAGE_TIME + 0.5
	events._process(0.016)
	await _frames(1)
	var cages := get_tree().get_nodes_in_group("mage_cage")
	_check(cages.size() == 1, "a los %d s sale la jaula" % int(RunEvents.CAGE_TIME))
	for i in 10:
		events._drain_queue()
	_check(events._elites.size() >= RunEvents.CAGE_ELITES, "custodiada por %d élites" % events._elites.size())
	events._process(0.016)
	_check(get_tree().get_nodes_in_group("mage_cage").size() == 1, "una sola jaula por partida")
	if cages.is_empty():
		_finish()
		return
	var cage := cages[0] as MageCage
	_check(cage._mage != null, "el mago está dentro de la jaula")
	_check(is_instance_valid(cage._arrow), "hay indicador en pantalla")

	# 3. Resistir dentro: sube el progreso y llama a la emboscada; fuera, baja
	var amb := [0]
	cage.ambushed.connect(func(): amb[0] += 1)
	var before_q := events._queue.size()
	cage.step(MageCage.HOLD * 0.5, true)
	_check(absf(cage.progress - 0.5) < 0.01, "mitad del tiempo dentro: 50 %% (%.2f)" % cage.progress)
	_check(amb[0] == 1 and events._queue.size() > before_q, "al entrar llega una emboscada")
	cage.step(2.0, false)
	_check(cage.progress < 0.5 and cage.progress > 0.0, "fuera del círculo el progreso baja (%.2f)" % cage.progress)
	_check(not SaveManager.dungeon_unlocked(), "a medias no se guarda el rescate")

	# 4. Completar: se abre, guarda el rescate y lo anuncia
	var got := [false]
	cage.rescued.connect(func(): got[0] = true)
	cage.step(MageCage.HOLD * 2.0, true)
	_check(cage.is_open and got[0], "la jaula se abre")
	_check(SaveManager.dungeon_unlocked(), "el mago queda rescatado")
	SaveManager.load_save()
	_check(SaveManager.dungeon_unlocked(), "el rescate está en el save")
	_check(cage._speech.visible and cage._speech.text == MageCage.THANKS, "el mago da las gracias")
	cage.step(1.0, true)
	_check(cage.is_open, "abierta no vuelve a contar")
	await get_tree().create_timer(MageCage.LEAVE_AFTER + 0.8).timeout
	_check(not is_instance_valid(cage), "el mago se va al salón")
	_finish()

func _finish() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.save_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameData.armory_path))
	SaveManager.save_path = SaveManager.SAVE_PATH
	SaveManager.load_save()
	print("ALL MAGE CAGE TESTS PASSED" if _fails == 0 else "MAGE CAGE TESTS FAILED: %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
