extends Node

## Captura de pantalla de la mazmorra (necesita ventana, no headless): res://tests/shot_dungeon.tscn -- <archivo.png> [sala]
## Coloca al jugador en la sala indicada (índice; por defecto la inicial) y guarda varias vistas.
## SHOT_WORLD=sewers (variable de entorno) captura otro mundo (ver WorldDefs).

var _out := "user://shot.png"
var _main: Node

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	GameData.game_mode = "dungeon"
	if WorldDefs.has(OS.get_environment("SHOT_WORLD")):
		GameData.world = OS.get_environment("SHOT_WORLD")
	_main = (load(Net.game_scene()) as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(_main)
	_run.call_deferred()

func _run() -> void:
	await get_tree().process_frame
	get_tree().current_scene = _main
	await get_tree().create_timer(4.0).timeout
	var enc = _main.get_node_or_null("DungeonEncounter")
	var map: DungeonMap = _main.get_node("ProceduralMap")
	var player = _main.get_node("Player")
	var want: String = args_room()
	var idx := 0
	for i in map.rooms.size():
		if want != "" and (str(map.rooms[i]["type"]) == want or str(map.rooms[i]["theme"]) == want or str(map.rooms[i]["shape"]) == want):
			idx = i
			break
	var c := map.room_center(idx)
	player.global_position = Vector3(c.x + 4.0, 0.3, c.z + 4.0)
	await get_tree().create_timer(2.5).timeout
	if OS.get_environment("SHOT_PAUSE") == "1":
		var pm = _main.find_child("PauseMenu", true, false)
		pm.open_menu()
		await get_tree().create_timer(0.5).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out)
	print("captura guardada: ", ProjectSettings.globalize_path(_out), " sala=", map.rooms[idx]["theme"])
	get_tree().quit(0)

func args_room() -> String:
	var a := OS.get_cmdline_user_args()
	return a[1] if a.size() > 1 else ""
