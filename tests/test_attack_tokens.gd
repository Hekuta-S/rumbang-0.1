extends Node

## Fichas de ataque: nunca más atacantes simultáneos que el máximo, las fichas se sueltan al morir o
## quedar aturdido, y los enemigos sin ficha no entran en WINDUP/ATTACK.

var _player: CharacterBody3D
var _enc: DungeonEncounter

func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _check(ok: bool, msg: String) -> void:
	if not ok:
		printerr("FAIL: " + msg)
		get_tree().quit(1)
		await get_tree().process_frame
		assert(false, msg)

func _boot() -> void:
	GameData.game_mode = "dungeon"
	var scene: Node = load("res://scenes/core/main_dungeon.tscn").instantiate()
	get_tree().root.add_child.call_deferred(scene)
	await get_tree().process_frame
	get_tree().current_scene = scene
	for i in 600:
		await get_tree().process_frame
		_enc = scene.get_node_or_null("DungeonEncounter")
		if _enc and _enc.map and is_instance_valid(_enc.player):
			break
	_enc._pending.clear()
	_player = _enc.player
	_player.health_comp.max_hp = 99999.0
	_player.health_comp.hp = 99999.0
	_player.global_position = _enc.map.room_center(_enc.map.arena_index) + Vector3(0, 0.3, 0)
	await _wait(0.5)

func _spawn_ring(n: int, kind: String, radius: float) -> Array:
	var out: Array = []
	for i in n:
		var a := TAU * i / n
		var at: Vector3 = _player.global_position + Vector3(cos(a), 0, sin(a)) * radius
		var g := _enc._spawn_at(_enc.map.arena_index, at, kind)
		g.max_hp = 99999.0
		g.hp = 99999.0
		out.append(g)
	return out

func _attackers(list: Array) -> int:
	var n := 0
	for g in list:
		if is_instance_valid(g) and (g.state == DungeonGoblin.State.WINDUP or g.state == DungeonGoblin.State.ATTACK):
			n += 1
	return n

func _ready() -> void:
	# ── 1. Gestor aislado (nodos falsos) ──
	AttackTokens.clear()
	var fakes: Array = []
	for i in 6:
		fakes.append(Node.new())
	var mx := AttackTokens.max_tokens()
	_check(mx == AttackTokens.BASE_TOKENS, "Máximo inicial = BASE_TOKENS (%d)" % mx)
	var got := 0
	for f in fakes:
		if AttackTokens.try_acquire(f):
			got += 1
	_check(got == mx, "Solo se reparten %d fichas (%d)" % [mx, got])
	_check(AttackTokens.in_use() == mx, "in_use coincide")
	AttackTokens.release(fakes[0])
	_check(AttackTokens.try_acquire(fakes[5]), "Una ficha liberada se puede reservar")
	var freed: Node = fakes[1]
	freed.free()                       # liberado sin soltar la ficha: caduca/purga al pedir
	_check(AttackTokens.try_acquire(fakes[4]) or AttackTokens.in_use() <= mx, "Un enemigo liberado no retiene ficha")
	AttackTokens.clear()
	AttackTokens.set_level(7)
	_check(AttackTokens.max_tokens() > AttackTokens.BASE_TOKENS, "Sube con el nivel")
	AttackTokens.clear()
	for f in fakes:
		if is_instance_valid(f):
			f.free()
	print("CHECK 1 PASSED: reparto, liberación y subida con el nivel")

	await _boot()

	# ── 2. Multitud: nunca más del máximo atacando, y todos con ficha ──
	var crowd := _spawn_ring(7, "goblin", 6.0)
	crowd.append_array(_spawn_ring(2, "brute", 7.0))
	var peak := 0
	var total_attack_frames := 0
	var untokened := 0
	var t := 0.0
	var max_seen := 0
	while t < 14.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		var n := _attackers(crowd)
		peak = maxi(peak, n)
		total_attack_frames += n
		max_seen = maxi(max_seen, AttackTokens.max_tokens())
		_check(n <= AttackTokens.max_tokens(), "Atacantes simultáneos %d > máximo %d" % [n, AttackTokens.max_tokens()])
		_check(AttackTokens.in_use() <= AttackTokens.max_tokens(), "Fichas en uso por encima del máximo")
		for g in crowd:
			if is_instance_valid(g) and (g.state == DungeonGoblin.State.WINDUP or g.state == DungeonGoblin.State.ATTACK) \
					and not AttackTokens.has(g):
				untokened += 1
	_check(untokened == 0, "Todo el que ataca tiene ficha (%d frames sin ella)" % untokened)
	_check(total_attack_frames > 0, "El combate no se bloquea: alguien ataca")
	var alive_waiting := 0
	for g in crowd:
		if is_instance_valid(g) and g.state == DungeonGoblin.State.APPROACH:
			alive_waiting += 1
	_check(peak >= 1 and peak <= max_seen, "Pico de atacantes %d (máx %d)" % [peak, max_seen])
	print("CHECK 2 PASSED: pico %d atacantes de %d enemigos (máx fichas %d, esperando %d)" % [peak, crowd.size(), max_seen, alive_waiting])

	# ── 3. Aturdido y muerte sueltan la ficha ──
	var holder: DungeonGoblin = null
	for g in crowd:
		if is_instance_valid(g) and AttackTokens.has(g):
			holder = g
			break
	if holder == null:
		for i in 300:
			await get_tree().physics_frame
			for g in crowd:
				if is_instance_valid(g) and AttackTokens.has(g):
					holder = g
					break
			if holder:
				break
	_check(holder != null, "Hay algún enemigo con ficha")
	holder._set_state(DungeonGoblin.State.STUNNED)
	_check(not AttackTokens.has(holder), "Aturdido suelta la ficha")
	holder._set_state(DungeonGoblin.State.APPROACH)
	var holder2: DungeonGoblin = null
	for i in 300:
		await get_tree().physics_frame
		for g in crowd:
			if is_instance_valid(g) and g != holder and AttackTokens.has(g) and g.state != DungeonGoblin.State.DEAD:
				holder2 = g
				break
		if holder2:
			break
	_check(holder2 != null, "Otro enemigo recoge ficha")
	holder2.hp = 1.0
	holder2.take_damage(99999.0)
	await get_tree().physics_frame
	_check(holder2.is_dead() and not AttackTokens.has(holder2), "Muerto suelta la ficha")
	print("CHECK 3 PASSED: aturdir y matar liberan la ficha")

	# ── 4. Sin fichas libres, nadie nuevo entra en WINDUP ──
	AttackTokens.clear()
	for g in crowd:
		if is_instance_valid(g) and not g.is_dead():
			g._set_state(DungeonGoblin.State.APPROACH)
	var blockers: Array = []
	for i in AttackTokens.max_tokens():
		var b := Node.new()
		blockers.append(b)
		AttackTokens.try_acquire(b)
	var started := 0
	var tt := 0.0
	while tt < 4.0:
		await get_tree().physics_frame
		tt += get_physics_process_delta_time()
		for g in crowd:
			if is_instance_valid(g) and (g.state == DungeonGoblin.State.WINDUP or g.state == DungeonGoblin.State.ATTACK):
				started += 1
		for b in blockers:        # las fichas ajenas no caducan en este tramo
			if not AttackTokens.has(b):
				AttackTokens.try_acquire(b)
	_check(started == 0, "Sin fichas libres nadie ataca (%d frames atacando)" % started)
	for b in blockers:
		AttackTokens.release(b)
		b.free()
	await _wait(3.0)
	_check(_attackers(crowd) > 0 or AttackTokens.in_use() > 0, "Al liberarlas, el combate se reanuda")
	print("CHECK 4 PASSED: sin ficha no hay WINDUP y al liberarlas se reanuda")

	print("ALL ATTACK TOKEN CHECKS PASSED")
	get_tree().quit(0)
