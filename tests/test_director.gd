extends Node

## Fase 3 de supervivencia: director de intensidad (línea temporal + pulsos), formaciones,
## enemigos con rasgos (hinchado) y vida escalada por potencia del jugador.
var _main: Node
var _fail := false
func _check(ok: bool, msg: String) -> void:
	print("%s: %s" % ["PASSED" if ok else "FAILED", msg])
	if not ok:
		_fail = true

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.game_mode = "survival"
	SaveManager.save_path = "user://test_save.json"
	SaveManager.meta = {}
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
	_check(waves != null and waves._running, "arranca la partida")
	p.health_comp.max_hp = 99999.0
	p.health_comp.hp = 99999.0
	var cfg: Dictionary = waves.wave_config

	# 1. Director: línea temporal e intensidad creciente; pulso con calma
	var d0 := WaveManager.director_params(0.0, cfg)
	var d430 := WaveManager.director_params(430.0, cfg)
	_check(is_equal_approx(d0["interval"], 2.4) and is_equal_approx(d430["interval"], 0.25), "extremos de la línea temporal")
	_check(is_equal_approx(d430["cap"], 1.0) and is_equal_approx(d0["cap"], 0.0), "tope de vivos 0 -> 1")
	var phases := {}
	for t in range(60, 400):
		phases[WaveManager.director_params(float(t), cfg)["phase"]] = true
	_check(phases.has("build") and phases.has("peak") and phases.has("calm"), "hay acumulación, pico y calma")
	var calm_ok := true
	for t in range(120, 400, 30):          # el último tramo de cada bloque de 30 s es calma
		var calm := WaveManager.director_params(float(t) + 29.0, cfg)
		var peak := WaveManager.director_params(float(t) + 22.0, cfg)
		if not (calm["interval"] > peak["interval"] * 3.0 and calm["batch"] < peak["batch"]):
			calm_ok = false
	_check(calm_ok, "la calma espacia y reduce lotes frente al pico")
	_check(WaveManager.director_params(10.0, cfg)["phase"] == "build", "sin pulsos en los primeros 45 s")
	_check(WaveManager.director_params(9999.0, {})["interval"] == WaveManager.INTERVAL_END, "sin director: curva antigua")

	# 2. Rasgos de enemigo
	waves.stop_run()
	waves._running = true
	var pos: Vector3 = p.global_position + Vector3(12, 0, 0)
	var normal: EnemyData = waves._spawn_single_enemy(pos, EnemyData.EnemyType.NORMAL_GOBLIN)[0]
	var base_hp := normal.max_hp
	# 3. Hinchado: al morir suelta dos crías
	var splitter: EnemyData = waves._spawn_single_enemy(pos, EnemyData.EnemyType.NORMAL_GOBLIN, "splitter")[0]
	_check(splitter.scale.x > 1.3 and splitter.max_hp > base_hp * 2.0, "hinchado: grande y resistente")
	var alive := EnemyRegistry.count()
	splitter.take_damage(splitter.hp + 1.0)
	await get_tree().process_frame
	await get_tree().process_frame
	var minis := 0
	for e in EnemyRegistry.all():
		if e is EnemyData and e.trait_id == "mini":
			minis += 1
	_check(minis == 2, "el hinchado suelta 2 crías (%d)" % minis)

	# 4. Potencia del jugador
	var xp = p.experience_comp
	GameState.get_instance().elapsed_time = 120.0
	xp.level = 1
	var low := waves.power_factor()
	xp.level = 40
	var high := waves.power_factor()
	_check(low < 1.0 and high > 1.0 and low >= 0.8 and high <= 1.35, "más nivel que lo esperado -> enemigos más duros (%.2f / %.2f)" % [low, high])
	xp.level = 1
	GameState.get_instance().elapsed_time = 0.0

	# 5. Formaciones
	var ev: RunEvents = waves.events
	ev._queue.clear()
	ev._start_ring()
	var ring_n := ev._queue.size()
	var ok_ring := ring_n == RunEvents.ring_count(0.0)
	for job in ev._queue:
		var d: float = (job[0] as Vector3).distance_to(p.global_position)
		if absf(d - RunEvents.RING_DIST) > 3.0:      # el suelo mueve la altura, no la distancia en planta
			ok_ring = false
	_check(ok_ring, "cerco: %d enemigos en anillo" % ring_n)
	for i in 60:
		await get_tree().physics_frame
	_check(ev._queue.is_empty(), "la cola de formaciones se vacía")
	_check(RunEvents.EVENTS.size() == 4 and RunEvents.ring_count(600.0) <= 40, "eventos y topes de formación")
	print("ALL PASSED" if not _fail else "SOME FAILED")
	get_tree().quit(1 if _fail else 0)
