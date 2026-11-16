extends Node

## Saltos y caídas del mapa de supervivencia: golpe de caída (PlayerMovementController.ground_slam) y
## runas lanzadoras (JumpPad) que llevan a la cima de las mesetas.
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
	p.health_comp.max_hp = 100000.0
	p.health_comp.hp = 100000.0
	waves.stop_run()
	waves._running = true
	var map: ProceduralMap = _main.get_node("ProceduralMap")
	var mc: PlayerMovementController = p.movement_controller

	# 1. Parámetros: más altura, más radio y más daño
	var lo := PlayerMovementController.slam_params(3.0)
	var hi := PlayerMovementController.slam_params(9.0)
	_check(hi["radius"] > lo["radius"] and hi["frac"] > lo["frac"], "caer más alto pega más fuerte y más lejos")

	# 2. Golpe: daña a los cercanos, menos a los élites, nada a los lejanos
	var at: Vector3 = p.global_position
	var near: EnemyData = waves._spawn_single_enemy(at + Vector3(1.5, 0, 0), EnemyData.EnemyType.NORMAL_GOBLIN)[0]
	var elite: EnemyData = waves._spawn_single_enemy(at + Vector3(0, 0, 1.5), EnemyData.EnemyType.NORMAL_GOBLIN)[0]
	waves.events.make_elite(elite, "acorazado")
	var far: EnemyData = waves._spawn_single_enemy(at + Vector3(25, 0, 0), EnemyData.EnemyType.NORMAL_GOBLIN)[0]
	var hp_n := near.hp
	var hp_e := elite.hp
	var hp_f := far.hp
	var hits := mc.ground_slam(at, 5.0)
	var frac_n := (hp_n - near.hp) / near.max_hp if not near.recycled else 1.0
	var frac_e := (hp_e - elite.hp) / elite.max_hp
	_check(hits >= 2 and frac_n >= 0.25, "el golpe daña a los cercanos (%d alcanzados, %.0f %% de vida)" % [hits, frac_n * 100.0])
	_check(frac_e > 0.0 and frac_e < frac_n, "a los élites les quita menos (%.0f %%)" % (frac_e * 100.0))
	_check(far.hp == hp_f, "no llega a los lejanos")

	# 3. Caída real desde 6 m sobre el llano: el aterrizaje hace el golpe
	var spot := Vector3(at.x + 3.0, map.get_height_at(at.x + 3.0, at.z - 3.0), at.z - 3.0)
	var victim: EnemyData = waves._spawn_single_enemy(spot + Vector3(1.2, 0, 0), EnemyData.EnemyType.NORMAL_GOBLIN)[0]
	victim.slow_multiplier = 0.0
	victim.slow_timer = 30.0
	var hp_v := victim.hp
	p.velocity = Vector3.ZERO
	p.global_position = spot + Vector3(0, 6.0, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	mc._air_start_y = p.global_position.y           # despega "desde" 6 m (como bajar de una meseta)
	mc._air_peak_y = p.global_position.y
	mc._was_airborne = true
	for i in 120:
		await get_tree().physics_frame
		if p.is_on_floor():
			break
	await get_tree().physics_frame
	_check(p.is_on_floor() and (victim.recycled or victim.hp < hp_v), "caer desde lo alto revienta el suelo")
	# Un salto normal en llano no hace golpe
	var victim2: EnemyData = waves._spawn_single_enemy(spot + Vector3(-1.2, 0, 0), EnemyData.EnemyType.NORMAL_GOBLIN)[0]
	victim2.slow_multiplier = 0.0
	victim2.slow_timer = 30.0
	var hp_v2 := victim2.hp
	p.velocity.y = PlayerMovementController.BASE_JUMP_VELOCITY
	for i in 120:
		await get_tree().physics_frame
		if i > 5 and p.is_on_floor():
			break
	await get_tree().physics_frame
	_check(victim2.hp == hp_v2, "un salto normal no hace golpe de caída")

	# 4. Runa lanzadora: pisarla deja en la cima
	var pads: Array = get_tree().get_nodes_in_group("jump_pads")
	_check(not pads.is_empty(), "hay runas lanzadoras en el mapa (%d)" % pads.size())
	if not pads.is_empty():
		var pad: JumpPad = pads[0]
		p.velocity = Vector3.ZERO
		p.global_position = pad.global_position + Vector3(0, 0.3, 0)
		var landed := false
		var launched := false
		for i in 300:
			await get_tree().physics_frame
			launched = launched or mc.is_launched()
			if launched and not mc.is_launched() and p.is_on_floor():
				landed = true
				break
		var d := Vector2(p.global_position.x - pad.target.x, p.global_position.z - pad.target.z).length()
		_check(launched and landed and d < 2.5 and absf(p.global_position.y - pad.target.y) < 1.0,
			"la runa lanza a la cima (a %.1f m del destino, altura %.1f / %.1f)" % [d, p.global_position.y, pad.target.y])
		_check(EnemyMotion.player_mesa(p.global_position) >= 0, "arriba cuenta como meseta para los enemigos")
	get_tree().quit(1 if _fail else 0)
