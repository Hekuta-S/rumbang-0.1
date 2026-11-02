extends Node

## Prueba de la sala LAN con DOS procesos: uno anfitrión (--role=host) y uno cliente (--role=client).
## El cliente descubre la partida por broadcast, se conecta y ambos ven la sala completa.

func _role() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			return a.substr(7)
	return "host"

func _ready() -> void:
	var role := _role()
	if role == "host":
		await _host()
	else:
		await _client()

func _wait_for(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while t < timeout:
		if cond.call():
			return true
		await get_tree().create_timer(0.1).timeout
		t += 0.1
	return false

func _host() -> void:
	Net.player_name = "Anfitrion"
	assert(Net.host_game("Sala de prueba") == OK, "El anfitrión debe poder abrir el puerto")
	var ok := await _wait_for(func(): return Net.players.size() == 2, 25.0)
	assert(ok, "El anfitrión debe ver al cliente en la sala")
	print("HOST lobby: ", Net.players)
	Net.set_my_char(2)
	await get_tree().create_timer(1.0).timeout
	assert(Net.char_of(1) == 2, "El anfitrión cambia de personaje")
	var left := await _wait_for(func(): return Net.players.size() == 1, 15.0)
	assert(left, "El anfitrión ve salir al cliente")
	print("HOST PASSED")
	get_tree().quit()

func _client() -> void:
	Net.player_name = "Cliente"
	assert(Net.start_browsing() == OK, "El cliente debe poder escuchar anuncios")
	var found := await _wait_for(func(): return not Net.games.is_empty(), 15.0)
	assert(found, "El cliente debe descubrir la partida por broadcast")
	var g: Dictionary = Net.games.values()[0]
	print("CLIENT descubrió: ", g)
	assert(g["name"] == "Sala de prueba" and g["count"] >= 1, "Datos del anuncio")
	assert(Net.join_game(g["ip"], g["port"]) == OK)
	var ok := await _wait_for(func(): return Net.players.size() == 2, 10.0)
	assert(ok, "El cliente recibe la sala")
	print("CLIENT lobby: ", Net.players)
	Net.set_my_char(3)
	var ok2 := await _wait_for(func(): return Net.char_of(Net.my_id()) == 3, 5.0)
	assert(ok2, "El servidor confirma el personaje del cliente")
	await get_tree().create_timer(2.0).timeout
	Net.leave()
	print("CLIENT PASSED")
	get_tree().quit()
