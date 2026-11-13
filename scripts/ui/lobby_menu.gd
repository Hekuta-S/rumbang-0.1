extends Control

## Multijugador: lista de partidas de la red LAN, crear/unirse por IP, entrar en un servidor dedicado por su
## dirección (online, la única opción en la versión web) y sala de espera con selección de personaje.
## Inicia la partida el anfitrión LAN o, en un servidor dedicado, el líder de la sala (Net.start_game).

const Style := preload("res://scripts/ui/rumbang_style.gd")
const CONFIG_PATH := "user://net.cfg"

var _browse: Control
var _room: Control
var _name_edit: LineEdit
var _ip_edit: LineEdit
var _games_list: ItemList
var _status: Label
var _players_box: VBoxContainer
var _char_pick: OptionButton
var _world_row: HBoxContainer           ## mundo de la mazmorra (solo quien puede iniciar la partida)
var _world_pick: OptionButton
var _start_btn: Button
var _room_title: Label
var _game_keys: Array = []
var _server_edit: LineEdit
var _wait_label: Label
var _joining_server := false
var _web := OS.has_feature("web")       ## en el navegador no hay LAN (ni UDP ni ENet): solo servidor online

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	theme = Style.get_theme()
	var bg := ColorRect.new()
	bg.color = Style.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_build_browse()
	_build_room()
	Net.games_changed.connect(_refresh_games)
	Net.lobby_changed.connect(_refresh_room)
	Net.connection_failed.connect(func(): _set_status("No se pudo conectar con el servidor" if _joining_server else "No se pudo conectar con la partida"))
	Net.disconnected.connect(_on_disconnected)
	if Net.is_online() and not Net.in_game:
		_show_room()
	else:
		Net.leave()
		_show_browse()

func _exit_tree() -> void:
	if Net.is_online() and Net.in_game:
		return
	Net.stop_browsing()

func _title(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Style.style_title(l, 22)
	return l

func _center_panel() -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Style.panel_style())
	center.add_child(panel)
	NeonFrame.attach(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(560, 0)
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	add_child(center)
	return box

# ───────────────────────────── Lista de partidas ─────────────────────────────

func _build_browse() -> void:
	var box := _center_panel()
	_browse = box.get_parent().get_parent()
	box.add_child(_title("MULTIJUGADOR ONLINE" if _web else "MULTIJUGADOR"))

	var name_row := HBoxContainer.new()
	var nl := Label.new()
	nl.text = "Tu nombre"
	nl.custom_minimum_size = Vector2(150, 0)
	name_row.add_child(nl)
	_name_edit = LineEdit.new()
	_name_edit.text = Net.player_name
	_name_edit.max_length = 16
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text_changed.connect(func(t: String): Net.player_name = t if t != "" else "Jugador")
	name_row.add_child(_name_edit)
	box.add_child(name_row)

	# Servidor dedicado (online): dirección del túnel o IP del PC que hace de servidor
	var srv_sub := Label.new()
	srv_sub.text = "Servidor online:"
	srv_sub.add_theme_color_override("font_color", Style.TEXT_DIM)
	box.add_child(srv_sub)
	var srv_row := HBoxContainer.new()
	_server_edit = LineEdit.new()
	_server_edit.placeholder_text = "dirección del servidor"
	_server_edit.text = _initial_server_address()
	_server_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_server_edit.text_submitted.connect(func(_t): _join_server())
	srv_row.add_child(_server_edit)
	var srv_btn := Button.new()
	srv_btn.text = "Entrar"
	srv_btn.pressed.connect(_join_server)
	srv_row.add_child(srv_btn)
	box.add_child(srv_row)

	var lan := VBoxContainer.new()
	lan.add_theme_constant_override("separation", 12)
	lan.visible = not _web
	box.add_child(lan)

	var sub := Label.new()
	sub.text = "Partidas en tu red wifi:"
	sub.add_theme_color_override("font_color", Style.TEXT_DIM)
	lan.add_child(sub)

	_games_list = ItemList.new()
	_games_list.custom_minimum_size = Vector2(0, 170)
	_games_list.item_activated.connect(func(_i): _join_selected())
	lan.add_child(_games_list)

	var ip_row := HBoxContainer.new()
	_ip_edit = LineEdit.new()
	_ip_edit.placeholder_text = "o escribe la IP del anfitrión"
	_ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ip_row.add_child(_ip_edit)
	var ip_btn := Button.new()
	ip_btn.text = "Conectar"
	ip_btn.pressed.connect(_join_ip)
	ip_row.add_child(ip_btn)
	lan.add_child(ip_row)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var create := Button.new()
	create.text = "Crear partida"
	create.custom_minimum_size = Vector2(0, 44)
	create.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create.pressed.connect(_create)
	row.add_child(create)
	var join := Button.new()
	join.text = "Unirse"
	join.custom_minimum_size = Vector2(0, 44)
	join.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join.pressed.connect(_join_selected)
	row.add_child(join)
	lan.add_child(row)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_color_override("font_color", Style.ACCENT)
	box.add_child(_status)

	var back := Button.new()
	back.text = "Volver"
	back.custom_minimum_size = Vector2(0, 40)
	back.pressed.connect(func():
		Net.leave()
		SceneLoader.load_scene("res://scenes/ui/dungeon_hub.tscn"))
	box.add_child(back)

func _show_browse() -> void:
	_browse.visible = true
	_room.visible = false
	if _web:
		_set_status("")
		return
	var err := Net.start_browsing()
	_set_status("" if err == OK else "No se pudo escuchar la red (¿otra partida abierta en este equipo?)")
	_refresh_games()

## Dirección del servidor: la de la URL de la página (?server=...), o la última que se usó.
func _initial_server_address() -> String:
	if _web:
		var q: Variant = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('server') || ''", true)
		if q is String and q != "":
			return q
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) == OK:
		return str(cfg.get_value("net", "server", ""))
	return ""

func _join_server() -> void:
	var address := _server_edit.text.strip_edges()
	if address == "":
		_set_status("Escribe la dirección del servidor")
		return
	Net.player_name = _name_edit.text if _name_edit.text != "" else "Jugador"
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	cfg.set_value("net", "server", address)
	cfg.save(CONFIG_PATH)
	Net.stop_browsing()
	_joining_server = true
	_set_status("Conectando con el servidor…")
	if Net.join_server(address) != OK:
		_set_status("Dirección no válida")
		return
	_show_room()

func _set_status(text: String) -> void:
	if _status:
		_status.text = text

func _refresh_games() -> void:
	if _games_list == null or not _browse.visible:
		return
	var selected_key := ""
	var sel := _games_list.get_selected_items()
	if not sel.is_empty() and sel[0] < _game_keys.size():
		selected_key = _game_keys[sel[0]]
	_games_list.clear()
	_game_keys.clear()
	for key in Net.games:
		var g: Dictionary = Net.games[key]
		var label := "%s   (%d/%d)   %s" % [g["name"], g["count"], g["max"], g["ip"]]
		if g["started"]:
			label += "   [en juego]"
		var idx := _games_list.add_item(label)
		_game_keys.append(key)
		if key == selected_key:
			_games_list.select(idx)
	if _games_list.item_count == 0:
		_games_list.add_item("Buscando partidas…")
		_games_list.set_item_disabled(0, true)

func _create() -> void:
	Net.player_name = _name_edit.text if _name_edit.text != "" else "Jugador"
	var err := Net.host_game()
	if err != OK:
		_set_status("No se pudo crear la partida (puerto en uso)")
		return
	Net.stop_browsing()
	_show_room()

func _join_selected() -> void:
	var sel := _games_list.get_selected_items()
	if sel.is_empty() or sel[0] >= _game_keys.size():
		_set_status("Elige una partida de la lista")
		return
	var g: Dictionary = Net.games[_game_keys[sel[0]]]
	if g["started"] or g["count"] >= g["max"]:
		_set_status("Esa partida está llena o ya empezó")
		return
	_connect(g["ip"], g["port"])

func _join_ip() -> void:
	var ip := _ip_edit.text.strip_edges()
	if ip == "":
		_set_status("Escribe una IP")
		return
	_connect(ip, Net.GAME_PORT)

func _connect(ip: String, port: int) -> void:
	Net.stop_browsing()
	_joining_server = false
	_set_status("Conectando…")
	if Net.join_game(ip, port) != OK:
		_set_status("IP no válida")
		Net.start_browsing()
		return
	_show_room()

func _on_disconnected(reason: String) -> void:
	if Net.in_game:
		return
	_show_browse()
	_set_status(reason)

# ───────────────────────────── Sala ─────────────────────────────

func _build_room() -> void:
	var box := _center_panel()
	_room = box.get_parent().get_parent()
	_room_title = _title("SALA")
	box.add_child(_room_title)

	_players_box = VBoxContainer.new()
	_players_box.add_theme_constant_override("separation", 6)
	box.add_child(_players_box)

	var pick_row := HBoxContainer.new()
	var pl := Label.new()
	pl.text = "Tu personaje"
	pl.custom_minimum_size = Vector2(150, 0)
	pick_row.add_child(pl)
	_char_pick = OptionButton.new()
	_char_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in GameData.CHARACTERS.size():
		var c: Dictionary = GameData.CHARACTERS[i]
		_char_pick.add_item("%s — %s" % [c["name"], c["subtitle"]])
		_char_pick.set_item_disabled(i, not GameData.is_index_unlocked(i))
	_char_pick.item_selected.connect(func(i: int): Net.set_my_char(i))
	pick_row.add_child(_char_pick)
	box.add_child(pick_row)

	_world_row = HBoxContainer.new()
	var wl := Label.new()
	wl.text = "Mundo"
	wl.custom_minimum_size = Vector2(150, 0)
	_world_row.add_child(wl)
	_world_pick = OptionButton.new()
	_world_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for id in WorldDefs.ORDER:
		_world_pick.add_item(str(WorldDefs.get_def(id)["name"]))
	_world_pick.select(maxi(WorldDefs.ORDER.find(GameData.world), 0))
	_world_pick.item_selected.connect(func(i: int): GameData.world = WorldDefs.ORDER[i])
	_world_row.add_child(_world_pick)
	box.add_child(_world_row)

	_start_btn = Button.new()
	_start_btn.text = "Iniciar partida"
	_start_btn.custom_minimum_size = Vector2(0, 46)
	_start_btn.pressed.connect(func(): Net.start_game(WorldDefs.ORDER[_world_pick.selected]))
	box.add_child(_start_btn)

	_wait_label = Label.new()
	_wait_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wait_label.add_theme_color_override("font_color", Style.TEXT_DIM)
	box.add_child(_wait_label)

	var leave := Button.new()
	leave.text = "Salir de la sala"
	leave.custom_minimum_size = Vector2(0, 40)
	leave.pressed.connect(func():
		Net.leave()
		_show_browse())
	box.add_child(leave)
	_room.visible = false

func _show_room() -> void:
	_browse.visible = false
	_room.visible = true
	var idx := clampi(GameData.selected_index, 0, GameData.CHARACTERS.size() - 1)
	if not GameData.is_index_unlocked(idx):
		idx = GameData.first_unlocked_index()
		Net.set_my_char(idx)
	_char_pick.select(idx)
	_refresh_room()

func _refresh_room() -> void:
	if _players_box == null or not _room.visible:
		return
	for c in _players_box.get_children():
		c.queue_free()
	_room_title.text = ("SALA: %s" % Net.game_name) if Net.is_host() else ("SALA DEL SERVIDOR" if Net.server_dedicated else "SALA")
	for id in Net.peer_ids():
		var l := Label.new()
		var ch: Dictionary = GameData.CHARACTERS[clampi(Net.char_of(id), 0, GameData.CHARACTERS.size() - 1)]
		l.text = "%s%s — %s" % ["★ " if id == Net.leader_id() else "  ", Net.name_of(id), ch["name"]]
		l.add_theme_color_override("font_color", Style.ACCENT if id == Net.my_id() else Style.TEXT)
		_players_box.add_child(l)
	if Net.players.is_empty():
		var w := Label.new()
		w.text = "Entrando en la sala…"
		_players_box.add_child(w)
	_start_btn.visible = Net.can_start()
	_world_row.visible = _start_btn.visible
	_wait_label.text = "" if _start_btn.visible or Net.players.is_empty() else "Esperando a que %s (★) inicie la partida…" % Net.name_of(Net.leader_id())
	_start_btn.text = "Iniciar partida (%d jugador%s)" % [Net.players.size(), "" if Net.players.size() == 1 else "es"]
