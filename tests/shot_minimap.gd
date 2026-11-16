extends Node

## Captura del minimapa dibujado (necesita ventana): res://tests/shot_minimap.tscn -- <prefijo>
## Monta la mazmorra, pasea al jugador por las primeras salas para descubrir mapa y guarda el minimapa
## compacto (<prefijo>_compacto.png) y ampliado (<prefijo>_ampliado.png).

var _prefix := "user://minimap"
var _main: Node

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_prefix = args[0]
	GameData.game_mode = "dungeon"
	_main = (load(Net.game_scene()) as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(_main)
	_run.call_deferred()

func _run() -> void:
	await get_tree().process_frame
	get_tree().current_scene = _main
	await get_tree().create_timer(4.0).timeout
	var enc = _main.get_node_or_null("DungeonEncounter")
	if enc:
		enc.process_mode = Node.PROCESS_MODE_DISABLED
	var map: DungeonMap = _main.get_node("ProceduralMap")
	var player: Node3D = _main.get_node("Player")
	var mm := _main.find_child("Minimap", true, false) as Minimap
	if mm == null:
		for n in get_tree().root.find_children("*", "Control", true, false):
			if n is Minimap:
				mm = n
	# Sin cofres: al pasar por encima abren su elección de arma y taparían la captura
	for ch in get_tree().get_nodes_in_group("treasure_chests"):
		(ch as Node).queue_free()
	# Recorre el camino de sala en sala (las celdas del suelo entre centros) para que se descubra
	var stops := mini(4, map.rooms.size())
	for i in stops - 1:
		var a := map.room_center(i)
		var b := map.room_center(i + 1)
		for k in 12:
			player.global_position = a.lerp(b, float(k) / 11.0) + Vector3(0, 0.3, 0)
			await get_tree().create_timer(0.15).timeout
	player.global_position = map.room_center(0) + Vector3(0, 0.3, 0)
	await get_tree().create_timer(0.5).timeout
	_save("_compacto")
	mm.toggle()
	await get_tree().create_timer(1.2).timeout
	_save("_ampliado")
	print("CHECK minimapa: ", "PASSED" if mm._seen.size() > 100 else "FAILED", " (", mm._seen.size(), " celdas)")
	get_tree().quit(0)

func _save(suffix: String) -> void:
	var path := _prefix + suffix + ".png"
	get_viewport().get_texture().get_image().save_png(path)
	print("captura guardada: ", ProjectSettings.globalize_path(path))
