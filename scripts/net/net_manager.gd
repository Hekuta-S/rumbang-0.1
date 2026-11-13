extends Node

## Multijugador LAN (hasta 4 jugadores, modo mazmorra). Autoload "Net".
##
##  - El ANFITRIÓN (peer 1) crea la partida (ENet) y la anuncia por broadcast UDP; los demás ven la lista de
##    partidas de su wifi o se conectan por IP. Todos eligen personaje en la sala y el anfitrión inicia.
##  - Durante la partida el anfitrión es la autoridad: simula enemigos, puertas y niveles (NetWorld). Cada
##    jugador controla su propio personaje y los demás se ven como RemotePlayer.
##  - SERVIDOR DEDICADO (online / web): un Godot sin ventana (--server) abre un WebSocket y hace de anfitrión
##    SIN jugador propio; todos los jugadores son clientes y se conectan por dirección (ws:// o wss://, p. ej.
##    a través de un túnel). En la sala, el primero que entró es el líder y es quien inicia la partida.
## Este autoload solo gestiona la conexión, el descubrimiento y la sala; el juego usa NetWorld.

signal lobby_changed
signal games_changed
signal connection_failed
signal disconnected(reason: String)
signal peer_left(peer_id: int)
signal game_starting

const GAME_PORT := 45677
const DISCOVERY_PORT := 45678
const MAX_PLAYERS := 4
const PROTOCOL := 1
const ANNOUNCE_INTERVAL := 1.0
const GAME_TTL := 3.5                 ## s sin oír una partida antes de quitarla de la lista
const GAME_SCENE := "res://scenes/core/main_dungeon.tscn"

## Escena de la partida del mundo elegido (GameData.world).
static func game_scene() -> String:
	return str(WorldDefs.get_def(GameData.world).get("scene", GAME_SCENE))
const SERVER_SCENE := "res://scenes/net/dedicated_server.tscn"
const SERVER_PORT := 45680            ## WebSocket del servidor dedicado
const WS_BUFFER := 1 << 20            ## bytes por sentido (las instantáneas de enemigos superan el valor por defecto)

enum Mode { OFFLINE, HOST, CLIENT }

var mode: int = Mode.OFFLINE
var players: Dictionary = {}          ## peer_id -> {"name": String, "char": int, "look": Dictionary (CharacterLook)}
var player_name := "Jugador"
var game_name := ""
var level_seed := 0
var in_game := false
var auto_load_scene := true           ## las pruebas lo desactivan y cargan la escena ellas mismas
var games: Dictionary = {}            ## "ip:port" -> {"ip", "port", "name", "count", "max", "started", "seen"}
var dedicated := false                ## este proceso es el servidor dedicado (anfitrión sin jugador)
var server_dedicated := false         ## cliente: la partida a la que entré la lleva un servidor dedicado
var world_ready: Dictionary = {}      ## peer_id -> true: ese equipo ya cargó la partida (su NetWorld recibe RPC)
var _join_seq := 0

var _udp_out: PacketPeerUDP
var _udp_in: PacketPeerUDP
var _announce_t := 0.0
var _browse_prune_t := 0.0

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	var h := OS.get_environment("USERNAME")
	player_name = h if h != "" else "Jugador"
	# Servidor dedicado: Godot --headless --path . -- --server
	if OS.get_cmdline_user_args().has("--server"):
		get_tree().change_scene_to_file.call_deferred(SERVER_SCENE)

# ───────────────────────────── Estado ─────────────────────────────

func is_online() -> bool:
	return mode != Mode.OFFLINE

func is_host() -> bool:
	return mode == Mode.HOST

func is_client() -> bool:
	return mode == Mode.CLIENT

func is_dedicated() -> bool:
	return dedicated and mode == Mode.HOST

## Quien puede iniciar la partida: el anfitrión LAN, o con servidor dedicado el primero que entró en la sala.
func leader_id() -> int:
	if is_dedicated() or server_dedicated:
		var ids := peer_ids()
		return ids[0] if not ids.is_empty() else 0
	return 1

func can_start() -> bool:
	if in_game or not players.has(my_id()) or leader_id() != my_id():
		return false
	return (is_host() and not dedicated) or (is_client() and server_dedicated)

func my_id() -> int:
	return multiplayer.get_unique_id() if is_online() else 1

## Ids de todos los jugadores por orden de llegada (el anfitrión LAN primero).
func peer_ids() -> Array:
	var ids: Array = players.keys()
	ids.sort_custom(func(a, b): return _order_of(a) < _order_of(b))
	return ids

func _order_of(peer_id: int) -> int:
	return 0 if peer_id == 1 else int(players.get(peer_id, {}).get("order", peer_id))

## Casilla (0-3) de un jugador: su posición en la lista (sirve para repartir los puntos de aparición).
func slot_of(peer_id: int) -> int:
	return maxi(peer_ids().find(peer_id), 0)

func name_of(peer_id: int) -> String:
	return str(players.get(peer_id, {}).get("name", "Jugador"))

func char_of(peer_id: int) -> int:
	return int(players.get(peer_id, {}).get("char", 0))

## Apariencia (CharacterLook.to_dict) de un jugador; vacía si no la mandó.
func look_of(peer_id: int) -> Dictionary:
	var l: Variant = players.get(peer_id, {}).get("look", {})
	return l if l is Dictionary else {}

# ───────────────────────────── Anfitrión / cliente ─────────────────────────────

func host_game(p_game_name: String = "") -> int:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(GAME_PORT, MAX_PLAYERS - 1)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	mode = Mode.HOST
	game_name = p_game_name if p_game_name != "" else "Partida de %s" % player_name
	in_game = false
	players = {1: {"name": player_name, "char": GameData.selected_index, "look": CharacterLook.current().to_dict()}}
	_udp_out = PacketPeerUDP.new()
	_udp_out.set_broadcast_enabled(true)
	_announce_t = 0.0
	lobby_changed.emit()
	return OK

func join_game(ip: String, port: int = GAME_PORT) -> int:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	mode = Mode.CLIENT
	players = {}
	in_game = false
	return OK

## Servidor dedicado: escucha WebSocket en `port` (sin jugador propio ni anuncio LAN).
func host_dedicated(port: int = SERVER_PORT) -> int:
	leave()
	var peer := _ws_peer()
	var err := peer.create_server(port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	mode = Mode.HOST
	dedicated = true
	game_name = "Servidor Rumbang"
	in_game = false
	players = {}
	return OK

## Cliente de un servidor dedicado. `address`: "wss://algo.trycloudflare.com", "ws://192.168.1.5:45680",
## o sin esquema (se completa con normalize_server_url).
func join_server(address: String) -> int:
	var url := normalize_server_url(address)
	if url == "":
		return ERR_INVALID_PARAMETER
	leave()
	var peer := _ws_peer()
	var err := peer.create_client(url)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	mode = Mode.CLIENT
	server_dedicated = true
	players = {}
	in_game = false
	return OK

## Completa una dirección escrita a mano: sin esquema, las IP y "localhost" van por ws:// (con el puerto del
## servidor si no lleva otro); un nombre de dominio (túnel) va por wss://, que es lo que exige una página https.
static func normalize_server_url(address: String) -> String:
	var a := address.strip_edges()
	if a == "":
		return ""
	if a.begins_with("ws://") or a.begins_with("wss://"):
		return a
	if a.begins_with("https://"):
		return "wss://" + a.substr(8)
	if a.begins_with("http://"):
		return "ws://" + a.substr(7)
	var host := a.split("/")[0]
	var bare := host.split(":")[0]
	if bare == "localhost" or bare.is_valid_ip_address():
		if not ":" in host:
			a = host + ":" + str(SERVER_PORT) + a.substr(host.length())
		return "ws://" + a
	return "wss://" + a

func _ws_peer() -> WebSocketMultiplayerPeer:
	var peer := WebSocketMultiplayerPeer.new()
	peer.inbound_buffer_size = WS_BUFFER
	peer.outbound_buffer_size = WS_BUFFER
	peer.max_queued_packets = 4096
	return peer

func leave(reason: String = "") -> void:
	var was_online := is_online()
	stop_browsing()
	if _udp_out:
		_udp_out.close()
		_udp_out = null
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	mode = Mode.OFFLINE
	dedicated = false
	server_dedicated = false
	world_ready = {}
	players = {}
	in_game = false
	if was_online:
		disconnected.emit(reason)

func _on_peer_connected(_id: int) -> void:
	pass   # el cliente se registra solo tras conectar (_srv_register)

func _on_peer_disconnected(id: int) -> void:
	if is_host():
		players.erase(id)
		if not in_game:
			_sync_lobby.rpc(players, dedicated)
		lobby_changed.emit()
	world_ready.erase(id)
	peer_left.emit(id)
	# Servidor dedicado: si se van todos durante la partida, vuelve a esperar en la sala
	if is_dedicated() and in_game and players.is_empty():
		server_back_to_lobby()

## Servidor dedicado: termina la partida en curso y vuelve a la sala (sigue escuchando).
func server_back_to_lobby() -> void:
	if not is_dedicated():
		return
	in_game = false
	for id in multiplayer.get_peers():
		multiplayer.multiplayer_peer.disconnect_peer(id)
	players = {}
	print("[servidor] partida terminada, esperando jugadores")
	get_tree().paused = false
	get_tree().change_scene_to_file(SERVER_SCENE)

func _on_connected_to_server() -> void:
	_srv_register.rpc_id(1, player_name, GameData.selected_index, CharacterLook.current().to_dict())

func _on_connection_failed() -> void:
	leave()
	connection_failed.emit()

func _on_server_disconnected() -> void:
	leave("Se perdió la conexión con el servidor" if server_dedicated else "El anfitrión cerró la partida")

# ───────────────────────────── Sala ─────────────────────────────

@rpc("any_peer", "reliable")
func _srv_register(p_name: String, p_char: int, p_look: Dictionary = {}) -> void:
	if not is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	if in_game or players.size() >= MAX_PLAYERS:
		_rejected.rpc_id(sender, "Partida llena o ya empezada")
		multiplayer.multiplayer_peer.disconnect_peer(sender)
		return
	_join_seq += 1
	players[sender] = {"name": p_name.substr(0, 16), "char": clampi(p_char, 0, GameData.CHARACTERS.size() - 1), "order": _join_seq,
		"look": CharacterLook.from_dict(p_look).to_dict()}   # validada: no se reenvía nada raro
	if dedicated:
		print("[servidor] entra %s (%d/%d)" % [players[sender]["name"], players.size(), MAX_PLAYERS])
	_sync_lobby.rpc(players, dedicated)
	lobby_changed.emit()

@rpc("any_peer", "reliable")
func _srv_set_char(p_char: int) -> void:
	if not is_host() or in_game:
		return
	var sender := multiplayer.get_remote_sender_id()
	if players.has(sender):
		players[sender]["char"] = clampi(p_char, 0, GameData.CHARACTERS.size() - 1)
		_sync_lobby.rpc(players, dedicated)
		lobby_changed.emit()

## Servidor dedicado: el líder de la sala pide empezar.
@rpc("any_peer", "reliable")
func _srv_request_start(world: String) -> void:
	if is_dedicated() and multiplayer.get_remote_sender_id() == leader_id():
		start_game(world)

@rpc("authority", "reliable")
func _sync_lobby(p_players: Dictionary, p_dedicated: bool) -> void:
	players = p_players
	server_dedicated = p_dedicated
	lobby_changed.emit()

@rpc("authority", "reliable")
func _rejected(reason: String) -> void:
	leave(reason)

## Elige el personaje de este jugador (en la sala).
func set_my_char(index: int) -> void:
	if not GameData.is_index_unlocked(index):
		index = GameData.first_unlocked_index()
	GameData.selected_index = index
	if is_host() and not dedicated:
		players[1]["char"] = index
		_sync_lobby.rpc(players, false)
		lobby_changed.emit()
	elif is_client():
		_srv_set_char.rpc_id(1, index)

## El anfitrión (o el líder, con servidor dedicado): empieza la partida para todos en el mundo
## `world` (ver WorldDefs; por defecto el elegido en GameData.world).
func start_game(world: String = "") -> void:
	if world == "" or not WorldDefs.has(world):
		world = GameData.world if WorldDefs.has(GameData.world) else WorldDefs.DEFAULT
	if is_client() and server_dedicated:
		if can_start():
			_srv_request_start.rpc_id(1, world)
		return
	if not is_host() or in_game or players.is_empty():
		return
	in_game = true
	if dedicated:
		print("[servidor] empieza la partida con %d jugador(es)" % players.size())
	level_seed = randi()
	_begin.rpc(level_seed, players, world)

@rpc("authority", "call_local", "reliable")
func _begin(p_seed: int, p_players: Dictionary, p_world: String) -> void:
	players = p_players
	level_seed = p_seed
	in_game = true
	world_ready = {}
	GameData.game_mode = "dungeon"
	GameData.world = p_world if WorldDefs.has(p_world) else WorldDefs.DEFAULT
	if not dedicated:
		GameData.selected_index = char_of(my_id())
	game_starting.emit()
	if dedicated:
		get_tree().change_scene_to_file(game_scene())   # sin pantalla de carga: nadie la ve
	elif auto_load_scene:
		SceneLoader.load_scene(game_scene())

## NetWorld avisa al cargar la partida; hasta entonces no se le mandan RPC a ese equipo (se perderían).
## El aviso va por este autoload, que existe siempre, así que nunca se pierde.
func announce_world_ready() -> void:
	_world_ready.rpc()

@rpc("any_peer", "reliable")
func _world_ready() -> void:
	world_ready[multiplayer.get_remote_sender_id()] = true

# ───────────────────────────── Descubrimiento LAN ─────────────────────────────

## Empieza a escuchar los anuncios de partidas de la red local.
func start_browsing() -> int:
	if _udp_in != null:
		return OK
	games.clear()
	_udp_in = PacketPeerUDP.new()
	var err := _udp_in.bind(DISCOVERY_PORT)
	if err != OK:
		_udp_in = null
		return err
	return OK

func stop_browsing() -> void:
	if _udp_in:
		_udp_in.close()
		_udp_in = null
	games.clear()

func _process(delta: float) -> void:
	if is_host() and not in_game and _udp_out:
		_announce_t -= delta
		if _announce_t <= 0.0:
			_announce_t = ANNOUNCE_INTERVAL
			_announce()
	if _udp_in:
		_read_announcements()
		_browse_prune_t -= delta
		if _browse_prune_t <= 0.0:
			_browse_prune_t = 1.0
			_prune_games()

func _announce() -> void:
	var data := JSON.stringify({
		"g": "rumbang", "p": PROTOCOL, "name": game_name, "port": GAME_PORT,
		"count": players.size(), "max": MAX_PLAYERS, "started": in_game,
	}).to_utf8_buffer()
	for addr in _broadcast_targets():
		_udp_out.set_dest_address(addr, DISCOVERY_PORT)
		_udp_out.put_packet(data)

## Broadcast general, el de cada subred local (a.b.c.255) y el propio equipo (pruebas en una sola máquina).
func _broadcast_targets() -> Array:
	var out: Array = ["255.255.255.255", "127.0.0.1"]
	for ip in IP.get_local_addresses():
		var parts: PackedStringArray = ip.split(".")
		if parts.size() == 4 and not ip.begins_with("127.") and not ip.begins_with("169.254."):
			var b := "%s.%s.%s.255" % [parts[0], parts[1], parts[2]]
			if not out.has(b):
				out.append(b)
	return out

func _read_announcements() -> void:
	var changed := false
	while _udp_in.get_available_packet_count() > 0:
		var pkt := _udp_in.get_packet()
		var ip := _udp_in.get_packet_ip()
		var info: Variant = JSON.parse_string(pkt.get_string_from_utf8())
		if not (info is Dictionary) or info.get("g", "") != "rumbang" or int(info.get("p", 0)) != PROTOCOL:
			continue
		var key := "%s:%d" % [ip, int(info["port"])]
		if not games.has(key):
			changed = true
		games[key] = {"ip": ip, "port": int(info["port"]), "name": str(info["name"]), "count": int(info["count"]),
			"max": int(info["max"]), "started": bool(info.get("started", false)), "seen": Time.get_ticks_msec()}
	if changed:
		games_changed.emit()

func _prune_games() -> void:
	var now := Time.get_ticks_msec()
	var gone: Array = []
	for k in games:
		if now - int(games[k]["seen"]) > int(GAME_TTL * 1000.0):
			gone.append(k)
	for k in gone:
		games.erase(k)
	if not gone.is_empty():
		games_changed.emit()
	elif _udp_in:
		games_changed.emit()   # refresca el nº de jugadores
