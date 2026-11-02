extends Node

## Dos jugadores QUIETOS con el mismo personaje (--role=host / --role=client): ninguno debe atacar, lanzarse ni
## moverse solo. Regresión: la biblioteca de animaciones del modelo era compartida entre el jugador local y la
## copia del remoto, y sus ventanas de golpe disparaban el impulso del golpe sin que nadie atacara.

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

func _ready() -> void:
	Net.auto_load_scene = false
	var role := _role()
	if role == "host":
		Net.host_game("Quietos")
		assert(await _wait_for(func(): return Net.players.size() == 2, 40.0))
		Net.start_game()
	else:
		Net.start_browsing()
		assert(await _wait_for(func(): return not Net.games.is_empty(), 30.0))
		var g: Dictionary = Net.games.values()[0]
		Net.join_game(g["ip"], g["port"])
		assert(await _wait_for(func(): return Net.in_game, 60.0))
	var scene: Node = load(Net.GAME_SCENE).instantiate()
	get_tree().root.add_child.call_deferred(scene)
	await get_tree().process_frame
	get_tree().current_scene = scene
	var nw: NetWorld = null
	var enc: DungeonEncounter = null
	for i in 900:
		await get_tree().process_frame
		enc = scene.get_node_or_null("DungeonEncounter")
		nw = scene.get_node_or_null("NetWorld")
		if enc and enc.map and nw and is_instance_valid(enc.player):
			break
	var p: CharacterBody3D = enc.player
	var hits := [0]
	var actions := [0]
	p.animation_controller.hit_window_opened.connect(func(_id, _n): hits[0] += 1)
	p.animation_controller.net_action.connect(func(_n, _f, _s): actions[0] += 1)
	assert(await _wait_for(func(): return nw.remotes.size() == 1, 15.0))
	var rp: RemotePlayer = nw.remotes.values()[0]
	var rhits := [0]
	rp.animation_controller.hit_window_opened.connect(func(_id, _n): rhits[0] += 1)
	await get_tree().create_timer(1.0).timeout
	var start := p.global_position
	var rstart := rp.global_position
	await get_tree().create_timer(6.0).timeout
	print(role, " quieto: golpes=", hits[0], " golpes_remoto=", rhits[0], " acciones=", actions[0],
		" desplazado=%.2f remoto=%.2f" % [p.global_position.distance_to(start), rp.global_position.distance_to(rstart)])
	assert(hits[0] == 0 and rhits[0] == 0 and actions[0] == 0, "Nadie ataca solo")
	assert(p.global_position.distance_to(start) < 0.1 and rp.global_position.distance_to(rstart) < 0.1, "Nadie se mueve solo")
	print(role.to_upper(), " IDLE PASSED")
	await get_tree().create_timer(2.0).timeout
	get_tree().quit()
