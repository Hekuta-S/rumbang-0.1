extends Node

## Capturas de los prisioneros (ventana, no headless):
##   godot --path . res://tests/shot_dungeon_prisoner.tscn -- <prefijo>
## <prefijo>_jaula / _abierta / _libre (minero en las Cavernas) y, en el salÃ³n con el minero liberado,
## <prefijo>_salon (junto al cofre) y <prefijo>_nivel (pestaÃ±a NIVEL apagada: falta la ladrona).

var _prefix := "user://preso"

func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s_%s.png" % [_prefix, tag])
	print("SHOT ", tag)

func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_prefix = args[0]
	SaveManager.save_path = "user://shot_save_prisoner.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.save_path))
	SaveManager.load_save()
	SaveManager.mago_rescatado = true
	GameData.armory_path = "user://shot_armeria_prisoner.cfg"
	GameData.game_mode = "dungeon"
	GameData.world = "caves"
	var scene: Node = load("res://scenes/core/main_dungeon.tscn").instantiate()
	get_tree().root.add_child.call_deferred(scene)
	await get_tree().process_frame
	get_tree().current_scene = scene
	var enc: DungeonEncounter = null
	for i in 600:
		await get_tree().process_frame
		enc = scene.get_node_or_null("DungeonEncounter")
		if enc and enc.map and is_instance_valid(enc.player):
			break
	var player: Node3D = enc.player
	var pr := enc.prisoner
	if not is_instance_valid(pr):
		enc._setup_level_extras()
		pr = enc.prisoner
	enc._pending.erase(enc.prisoner_room)    # sin enemigos para la foto
	for d in enc._dice:
		if is_instance_valid(d):
			d.queue_free()
	for ui in get_tree().get_nodes_in_group("dungeon_choice_ui"):
		ui.queue_free()
	get_tree().paused = false
	player.global_position = pr.global_position + Vector3(0.0, 0.3, 3.2)
	await _wait(3.5)
	await _shot("jaula")
	enc._room_cleared(enc.prisoner_room)
	await _wait(1.3)
	await _shot("abierta")
	pr.interact()
	await _wait(0.6)
	await _shot("libre")
	await _wait(DungeonPrisoner.LINE_TIME)
	await _shot("libre2")
	scene.queue_free()
	get_tree().paused = false
	await _wait(0.3)
	# SalÃ³n con el minero liberado (la ladrona no)
	DungeonHub.config_path = "user://shot_prisoner_hub.cfg"
	DungeonHub.set_intro_seen(true)
	SaveManager.prisoners = {"caves": true}
	var hub := (load("res://scenes/ui/dungeon_hub.tscn") as PackedScene).instantiate() as DungeonHub
	add_child(hub)
	get_tree().current_scene = hub
	await _wait(1.8)
	hub.player.global_position = Vector3(4.6, DungeonHub.FLOOR_Y, 4.0)
	hub.player.face(DungeonHub.PRISONER_SPOTS["cofre"])
	await _wait(2.0)
	await _shot("salon")
	hub.use_station("yunque")
	await _wait(1.0)
	hub.panels.show_anvil_tab("nivel")
	await _wait(0.4)
	await _shot("nivel")
	for p in [SaveManager.save_path, GameData.armory_path, DungeonHub.config_path]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	SaveManager.save_path = SaveManager.SAVE_PATH
	SaveManager.load_save()
	get_tree().quit(0)
