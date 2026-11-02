extends Node

## Sala del servidor dedicado (sin ventana). Se arranca con:
##     Godot --headless --path . -- --server [--port=45680] [--autostart=N]
## (Net detecta --server y abre esta escena). Escucha WebSocket y espera a los jugadores; el líder de la sala
## inicia la partida desde su menú. Al terminar la partida, o si se van todos, el servidor vuelve aquí.
##   --autostart=N  empieza solo en cuanto haya N jugadores (pruebas).

const STATUS_EVERY := 30.0

var _autostart := 0
var _status_t := 0.0

func _ready() -> void:
	Engine.max_fps = 60        # sin ventana no hace falta más; ahorra CPU del PC
	var port := Net.SERVER_PORT
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--port="):
			port = int(a.substr(7))
		elif a.begins_with("--autostart="):
			_autostart = int(a.substr(12))
	if not Net.is_dedicated():
		var err := Net.host_dedicated(port)
		if err != OK:
			printerr("[servidor] no se pudo abrir el puerto %d (error %d). ¿Ya hay otro servidor abierto?" % [port, err])
			get_tree().quit(1)
			return
		print("[servidor] escuchando en ws://0.0.0.0:%d" % port)
	print("[servidor] esperando jugadores (máx. %d)" % Net.MAX_PLAYERS)
	Net.lobby_changed.connect(_on_lobby_changed)

func _on_lobby_changed() -> void:
	if _autostart > 0 and not Net.in_game and Net.players.size() >= _autostart:
		Net.start_game()

func _process(delta: float) -> void:
	_status_t += delta
	if _status_t >= STATUS_EVERY:
		_status_t = 0.0
		print("[servidor] en la sala: %d jugador(es)" % Net.players.size())
