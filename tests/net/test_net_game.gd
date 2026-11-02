extends Node

## Partida en red con DOS procesos (--role=host / --role=client): jugadores remotos, enemigos del anfitrión como
## "puppets" en el cliente, golpes del cliente que llegan al anfitrión, daño del anfitrión al cliente, caída y
## reanimación. Carga la mazmorra real.

var _scene: Node
var _enc: DungeonEncounter
var _nw: NetWorld
var _player: CharacterBody3D

func _role() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			return a.substr(7)
	return "host"

func _wait_for(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while t < timeout:
		if cond.call():
			return true
		await get_tree().create_timer(0.1).timeout
		t += 0.1
	return false

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
	assert(_nw != null, "NetWorld debe existir en la partida en red")
	_player = _enc.player
	_player.health_comp.max_hp = 200.0
	_player.health_comp.hp = 200.0
	await get_tree().create_timer(0.5).timeout

func _ready() -> void:
	Net.auto_load_scene = false
	if _role() == "host":
		await _host()
	else:
		await _client()

# ───────────────────────────── Anfitrión ─────────────────────────────

func _host() -> void:
	Net.player_name = "Host"
	assert(Net.host_game("Prueba") == OK)
	assert(await _wait_for(func(): return Net.players.size() == 2, 30.0), "Entra el cliente")
	Net.set_my_char(0)
	await get_tree().create_timer(0.5).timeout
	Net.start_game()
	await _load_game()
	print("HOST semilla=", _enc.map.used_seed, " net_seed=", Net.level_seed)
	assert(_enc.map.used_seed == Net.level_seed, "El mapa usa la semilla de la partida")

	# 1. Jugadores remotos
	assert(await _wait_for(func(): return _nw.remotes.size() == 1, 10.0), "El anfitrión ve al cliente")
	var rp: RemotePlayer = _nw.remotes.values()[0]
	assert(await _wait_for(func(): return rp._got_state, 5.0), "Llega el estado del cliente")
	print("HOST CHECK 1 PASSED: ve al cliente en ", rp.global_position)

	# 2. Un enemigo del anfitrión aparece como puppet en el cliente
	var g := _enc.spawn_goblin()
	g.global_position = _player.global_position + Vector3(0, 0, -6)
	await get_tree().create_timer(3.0).timeout
	print("HOST goblin net_id=", g.net_id, " hp=", g.hp)
	assert(g.net_id > 0, "El goblin se registra para la red")
	# El cliente golpeará al puppet (10 de daño): el anfitrión lo ve en el HP real
	var hp0 := g.max_hp
	assert(await _wait_for(func(): return g.hp < hp0, 15.0), "El golpe del cliente llega al enemigo real")
	print("HOST CHECK 2 PASSED: hp %.0f -> %.0f" % [hp0, g.hp])

	# 3. El enemigo golpea al cliente (reenviado a su dueño)
	await get_tree().create_timer(1.0).timeout
	rp.take_damage(25.0, Vector3.ZERO)
	await get_tree().create_timer(1.5).timeout
	print("HOST CHECK 3 enviado daño al cliente")

	# 4. Muerte: el puppet del cliente desaparece
	g.take_damage(99999.0, Vector3.ZERO)
	await get_tree().create_timer(4.0).timeout
	print("HOST CHECK 4 PASSED: enemigo muerto")

	# 5. El cliente cae y se le reanima al despejar la caverna
	assert(await _wait_for(func(): return _nw._downed.has(Net.peer_ids()[1]), 15.0), "El anfitrión sabe que el cliente cayó")
	await get_tree().create_timer(1.0).timeout
	_nw._revive_downed()
	assert(_nw._downed.is_empty())
	await get_tree().create_timer(2.5).timeout
	print("HOST CHECK 5 PASSED: caído y reanimado")

	# 6. Bajar de nivel juntos: ambos eligen arma (aquí: listos) y el anfitrión reparte una semilla nueva
	var seed1 := Net.level_seed
	_nw.player_ready_for_next()
	assert(await _wait_for(func(): return _enc.level == 2, 30.0), "El anfitrión baja de nivel")
	await get_tree().create_timer(3.0).timeout
	assert(Net.level_seed != seed1 and _enc.map.used_seed == Net.level_seed, "Mapa nuevo con la semilla nueva")
	print("HOST CHECK 6 PASSED: nivel 2 semilla=", _enc.map.used_seed)
	print("HOST PASSED")
	await get_tree().create_timer(8.0).timeout   # el cliente aún comprueba su nivel 2
	get_tree().quit()

# ───────────────────────────── Cliente ─────────────────────────────

func _client() -> void:
	Net.player_name = "Cliente"
	Net.start_browsing()
	assert(await _wait_for(func(): return not Net.games.is_empty(), 20.0), "Descubre la partida")
	var g: Dictionary = Net.games.values()[0]
	assert(Net.join_game(g["ip"], g["port"]) == OK)
	assert(await _wait_for(func(): return Net.in_game, 40.0), "El anfitrión inicia la partida")
	await _load_game()
	print("CLIENT semilla=", _enc.map.used_seed, " net_seed=", Net.level_seed)
	assert(_enc.map.used_seed == Net.level_seed, "El mapa usa la semilla de la partida")

	assert(await _wait_for(func(): return _nw.remotes.size() == 1, 10.0), "El cliente ve al anfitrión")
	var host_rp: RemotePlayer = _nw.remotes.values()[0]
	assert(await _wait_for(func(): return host_rp._got_state, 5.0))
	print("CLIENT CHECK 1 PASSED: ve al anfitrión en ", host_rp.global_position)

	# 2. Puppet del enemigo
	assert(await _wait_for(func(): return EnemyRegistry.count() == 1, 15.0), "El cliente recibe el enemigo")
	var puppet: DungeonGoblin = EnemyRegistry.all()[0]
	assert(puppet.puppet, "En el cliente el enemigo es una copia (puppet)")
	print("CLIENT CHECK 2a PASSED: puppet en ", puppet.global_position)
	await get_tree().create_timer(1.0).timeout
	puppet.take_damage(10.0, Vector3.ZERO)

	# 3. Daño recibido del anfitrión
	var hp_before := float(_player.hp)
	assert(await _wait_for(func(): return float(_player.hp) < hp_before, 15.0), "El daño del anfitrión llega al cliente")
	print("CLIENT CHECK 3 PASSED: hp %.0f -> %.0f" % [hp_before, _player.hp])

	# 4. Muerte del enemigo: el puppet se va
	assert(await _wait_for(func(): return EnemyRegistry.count() == 0, 10.0), "El puppet muere con el enemigo")
	print("CLIENT CHECK 4 PASSED: puppet eliminado")

	# 5. Caer y revivir
	_player.health_comp.invincibility_time = 0.0
	_player.health_comp.take_damage(99999.0)
	assert(await _wait_for(func(): return bool(_player.get_meta("downed", false)), 5.0), "El cliente pasa a espectador")
	assert(await _wait_for(func(): return not bool(_player.get_meta("downed", false)), 20.0), "El cliente revive")
	assert(float(_player.hp) > 0.0)
	print("CLIENT CHECK 5 PASSED: espectador y revivido con hp ", _player.hp)

	var seed1 := Net.level_seed
	await get_tree().create_timer(1.0).timeout
	_nw.player_ready_for_next()
	assert(await _wait_for(func(): return _enc.level == 2, 30.0), "El cliente baja de nivel")
	await get_tree().create_timer(3.0).timeout
	assert(Net.level_seed != seed1 and _enc.map.used_seed == Net.level_seed, "Mapa nuevo con la semilla nueva")
	print("CLIENT CHECK 6 PASSED: nivel 2 semilla=", _enc.map.used_seed)
	print("CLIENT PASSED")
	await get_tree().create_timer(1.0).timeout
	get_tree().quit()
