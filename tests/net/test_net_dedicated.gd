extends Node

## Servidor dedicado con TRES procesos: el servidor (sin jugador) y dos clientes por WebSocket.
##   servidor:  Godot --headless --path . -- --server --port=45690 --autostart=2
##   clientes:  Godot --headless --path . res://tests/net/test_net_dedicated.tscn -- --role=a   (y --role=b)
## Comprueba: los dos entran y el servidor empieza solo, mismo mapa, cada cliente ve al otro y no al servidor,
## los enemigos del servidor llegan como puppets, un golpe del cliente llega al servidor, el servidor hace daño
## a un cliente, y al caer todos el servidor vuelve a la sala (se puede volver a entrar).

const URL := "ws://127.0.0.1:45690"

var _scene: Node
var _enc: DungeonEncounter
var _nw: NetWorld
var _player: CharacterBody3D

func _role() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			return a.substr(7)
	return "a"

func _wait_for(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while t < timeout:
		if cond.call():
			return true
		await get_tree().create_timer(0.1).timeout
		t += 0.1
	return false

func _check(ok: bool, what: String) -> void:
	if not ok:
		printerr("%s FAILED: %s" % [_role().to_upper(), what])
		get_tree().quit(1)
		await get_tree().create_timer(10.0).timeout

func _load_game() -> void:
	_scene = load(Net.GAME_SCENE).instantiate()
	get_tree().root.add_child.call_deferred(_scene)
	await get_tree().process_frame
	get_tree().current_scene = _scene
	for i in 900:
		await get_tree().process_frame
		_enc = _scene.get_node_or_null("DungeonEncounter")
		_nw = _scene.get_node_or_null("NetWorld")
		if _enc and _enc.map and _nw and is_instance_valid(_enc.player):
			break
	_player = _enc.player
	_player.health_comp.max_hp = 400.0
	_player.health_comp.hp = 400.0
	await get_tree().create_timer(0.5).timeout

func _ready() -> void:
	Net.auto_load_scene = false
	var me := _role()
	Net.player_name = "Cliente_" + me
	if me == "b":
		await get_tree().create_timer(1.0).timeout   # entra el segundo: "a" es el líder
	await _check(Net.join_server(URL) == OK, "join_server")
	await _check(await _wait_for(func(): return Net.players.size() >= 1 and Net.server_dedicated, 20.0), "entra en la sala del servidor dedicado")
	await _check(not Net.players.has(1), "el servidor no es un jugador")
	print("%s CHECK 1 PASSED: en la sala, líder=%d yo=%d" % [me.to_upper(), Net.leader_id(), Net.my_id()])
	await _check(await _wait_for(func(): return Net.in_game, 30.0), "el servidor empieza la partida")
	await _load_game()
	await _check(_enc.map.used_seed == Net.level_seed, "mismo mapa (semilla)")
	await _check(await _wait_for(func(): return _nw.remotes.size() == 1, 10.0), "ve al otro cliente")
	await _check(not _nw.remotes.has(1), "no hay RemotePlayer del servidor")
	print("%s CHECK 2 PASSED: semilla=%d, ve a %s" % [me.to_upper(), Net.level_seed, Net.name_of(_nw.remotes.keys()[0])])

	# 3. "a" entra en la arena: el servidor dispara el encuentro y los enemigos llegan como puppets a los dos
	if me == "a":
		var c := _enc.map.room_center(_enc.map.arena_index)
		_player.global_position = Vector3(c.x, 0.3, c.z)
	await _check(await _wait_for(func(): return EnemyRegistry.count() > 0, 20.0), "llegan los enemigos")
	for e in EnemyRegistry.all():
		await _check(e.puppet, "los enemigos son puppets en el cliente")
	print("%s CHECK 3 PASSED: %d enemigo(s) puppet" % [me.to_upper(), EnemyRegistry.count()])

	if me == "a":
		# 4. Golpe del cliente -> HP real en el servidor (vuelve en la instantánea)
		var target: DungeonGoblin = EnemyRegistry.all()[0]
		await get_tree().create_timer(1.0).timeout
		var hp0: float = target.hp
		target.take_damage(15.0, Vector3.ZERO)
		target.hp = hp0                    # el valor bueno es el que manda el servidor
		await _check(await _wait_for(func(): return not is_instance_valid(target) or target.hp < hp0 - 1.0, 10.0), "el golpe llega al servidor")
		print("A CHECK 4 PASSED: hp %.0f -> %.0f" % [hp0, target.hp if is_instance_valid(target) else 0.0])
		# 5. Los enemigos del servidor atacan a "a" (que está en la arena)
		var hp_before := float(_player.hp)
		await _check(await _wait_for(func(): return float(_player.hp) < hp_before, 40.0), "el servidor hace daño al cliente")
		print("A CHECK 5 PASSED: hp %.0f -> %.0f" % [hp_before, _player.hp])
	else:
		await get_tree().create_timer(12.0).timeout

	# 6. Caen los dos -> fin de partida -> el servidor vuelve a la sala
	await get_tree().create_timer(2.0 if me == "a" else 0.5).timeout
	_player.health_comp.invincibility_time = 0.0
	_player.health_comp.take_damage(99999.0)
	await _check(await _wait_for(func(): return not Net.is_online(), 30.0), "fin de partida al caer todos")
	print("%s CHECK 6 PASSED: fin de partida" % me.to_upper())
	if me == "a":
		await get_tree().create_timer(4.0).timeout
		await _check(Net.join_server(URL) == OK, "volver a entrar")
		await _check(await _wait_for(func(): return Net.players.size() == 1 and not Net.in_game, 15.0), "el servidor volvió a la sala")
		print("A CHECK 7 PASSED: el servidor aceptó una sala nueva")
		Net.leave()
	print("%s PASSED" % me.to_upper())
	await get_tree().create_timer(1.0).timeout
	get_tree().quit(0)
