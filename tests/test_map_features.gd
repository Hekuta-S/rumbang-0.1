extends Node

## Barriles explosivos, puentes y toboganes del mapa de supervivencia, en partida con el jugador real.
var _main: Node
var _fail := false
func _check(ok: bool, msg: String) -> void:
	print("%s: %s" % ["PASSED" if ok else "FAILED", msg])
	if not ok:
		_fail = true

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

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
	_check(get_tree().get_nodes_in_group("explosive_barrels").size() == map.get_barrel_spots().size() and map.get_barrel_spots().size() > 0,
		"hay barriles explosivos en el mapa (%d)" % map.get_barrel_spots().size())
	for b in get_tree().get_nodes_in_group("explosive_barrels"):
		b.queue_free()                   # los del mapa no estorban a las pruebas
	_kill_all()
	await _frames(5)

	# 1. Golpe: rueda y estalla al llegar a los enemigos
	var at: Vector3 = p.global_position
	var bpos := Vector3(at.x + 2.0, map.get_height_at(at.x + 2.0, at.z + 3.0), at.z + 3.0)
	var barrel := _barrel(map, bpos)
	await _frames(2)
	var targets: Array = []
	for k in 3:
		var e: EnemyData = waves._spawn_single_enemy(bpos + Vector3(7.0, 0, k * 0.8 - 0.8), EnemyData.EnemyType.NORMAL_GOBLIN)[0]
		e.speed = 0.0
		targets.append(e)
	var hp0: float = targets[1].hp
	barrel.take_damage(20.0, Vector3(1, 0, 0))
	var rolled := barrel.state == ExplosiveBarrel.State.ROLLING
	for i in 180:
		await get_tree().physics_frame
		if barrel.state == ExplosiveBarrel.State.GONE:
			break
	_check(rolled and barrel.state == ExplosiveBarrel.State.GONE and barrel.hits >= 2,
		"golpeado rueda y estalla contra los enemigos (%d alcanzados)" % barrel.hits)
	_check(targets[1].recycled or targets[1].hp < hp0, "la explosión les hace daño")

	# 2. Cadena: un barril encendido por otro
	_kill_all()
	var b1 := _barrel(map, bpos + Vector3(0, 0, 6.0))
	var b2 := _barrel(map, bpos + Vector3(3.0, 0, 6.0))
	await _frames(2)
	b1.explode()
	for i in 90:
		await get_tree().physics_frame
		if b2.state == ExplosiveBarrel.State.GONE:
			break
	_check(b2.state == ExplosiveBarrel.State.GONE, "una explosión enciende a los barriles cercanos")

	# 3. Deslizarse contra un barril lo patea
	var spot: Vector3 = p.global_position
	var b3 := _barrel(map, Vector3(spot.x - 3.0, map.get_height_at(spot.x - 3.0, spot.z), spot.z))
	await _frames(2)
	mc.slide_input_override = true
	mc._slide_was_pressed = true
	p.velocity = Vector3(-9.0, 0, 0)
	mc._try_start_slide()
	for i in 60:
		await get_tree().physics_frame
		if b3.state != ExplosiveBarrel.State.IDLE:
			break
	mc.slide_input_override = false
	_check(b3.state != ExplosiveBarrel.State.IDLE, "deslizarse contra un barril lo manda rodando")

	# 4. Reaparece en su sitio cuando el jugador está lejos
	b1._home = p.global_position + Vector3(40, 0, 0)
	b1._respawn_t = 0.0
	await _frames(2)
	_check(b1.state == ExplosiveBarrel.State.IDLE and b1.visible and b1.global_position.distance_to(b1._home) < 0.01, "reaparece en su sitio")

	# 5. Puente: el jugador lo cruza de una cima a la otra sin caerse
	var found := false
	for sd in [11, 27, 58, 91, 144, 202, 377, 512, 999, 1234, 4321, 777]:
		map.generate(sd)
		EnemyMotion.reset()
		if not map.get_bridges().is_empty():
			found = true
			break
	await _frames(3)
	_check(found, "hay mapas con puente")
	if found:
		var br: Dictionary = map.get_bridges()[0]
		var a: Vector2 = br["a"]
		var b: Vector2 = br["b"]
		var d := (b - a).normalized()
		var from := a - d * 1.0
		p.velocity = Vector3.ZERO
		p.global_position = Vector3(from.x, float(br["ya"]) + 0.3, from.y)
		await _frames(10)
		mc.add_dash(Vector3(d.x, 0, d.y) * 6.0, 0.0)
		var min_gap := INF
		var reached := false
		for i in 600:
			await get_tree().physics_frame
			var q := Vector2(p.global_position.x, p.global_position.z)
			var t := (q - a).dot(b - a) / (b - a).length_squared()
			if t > 0.1 and t < 0.9:
				min_gap = minf(min_gap, p.global_position.y - lerpf(float(br["ya"]), float(br["yb"]), t))
			if t > 1.05:
				reached = true
				break
		mc.dash_velocity = Vector3.ZERO
		_check(reached and min_gap > -0.3, "el jugador cruza el puente sin caerse (altura mínima sobre la tabla %.2f m)" % min_gap)

	# 6. Tobogán: entrar cuesta abajo te tumba y te acelera
	var chute := {}
	for m in map.get_mesas():
		for rp in m["ramps"]:
			if rp.get("chute", false) and chute.is_empty():
				chute = {"c": m["c"], "r": m["r"], "dir": rp["dir"]}
	if chute.is_empty():
		for sd in [3, 11, 27, 58, 91]:
			map.generate(sd)
			EnemyMotion.reset()
			for m in map.get_mesas():
				for rp in m["ramps"]:
					if rp.get("chute", false) and chute.is_empty():
						chute = {"c": m["c"], "r": m["r"], "dir": rp["dir"]}
			if not chute.is_empty():
				break
		await _frames(3)
	_check(not chute.is_empty(), "hay toboganes")
	if not chute.is_empty():
		var cd: Vector2 = chute["dir"]
		var top: Vector2 = (chute["c"] as Vector2) + cd * (float(chute["r"]) + 0.5)
		p.velocity = Vector3.ZERO
		mc.dash_velocity = Vector3.ZERO
		p.global_position = Vector3(top.x, map.get_height_at(top.x, top.y) + 0.3, top.y)
		await _frames(8)
		mc.add_dash(Vector3(cd.x, 0, cd.y) * 5.0, 0.0)
		var slid := false
		var top_speed := 0.0
		for i in 300:
			await get_tree().physics_frame
			slid = slid or mc.is_sliding()
			if mc.is_sliding():
				top_speed = maxf(top_speed, mc._slide_vel.length())
			elif slid:
				break
		_check(slid and top_speed > 11.0, "el tobogán te tumba y te lleva (hasta %.1f m/s)" % top_speed)
	get_tree().quit(1 if _fail else 0)

func _barrel(map: Node, pos: Vector3) -> ExplosiveBarrel:
	var b := ExplosiveBarrel.new()
	b.position = pos
	map.add_child(b)
	return b

func _kill_all() -> void:
	for e in EnemyRegistry.all().duplicate():
		if e is EnemyData and not e.recycled:
			e.take_damage(e.hp + 1.0)
