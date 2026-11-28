extends Node

## Captura de la jaula del mago en la Supervivencia (ventana, no headless):
##   godot --path . res://tests/shot_mage_cage.tscn -- <salida.png> [behind]
## behind: la jaula detrás de la cámara, para ver la flecha del borde.

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://shot_mage_cage.png"
	var behind := args.has("behind")
	SaveManager.save_path = "user://test_save_cage_shot.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.save_path))
	SaveManager.load_save()
	GameData.game_mode = "survival"
	var main: Node = load("res://scenes/core/main_procedural.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	get_tree().current_scene = main
	var p: Node3D = null
	var waves: WaveManager = null
	for i in 900:
		await get_tree().process_frame
		p = main.get_node_or_null("Player")
		waves = main.find_child("WaveManager", true, false)
		if p and waves and waves._running:
			break
	waves.stop_run()
	waves._running = true
	waves.set_process(false)
	p.health_comp.max_hp = 9999.0
	p.health_comp.hp = 9999.0
	var events: RunEvents = waves.events
	events.set_process(false)
	var cam := get_viewport().get_camera_3d()
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var at := events._ground(p.global_position + fwd * (-30.0 if behind else 6.0))
	var cage := MageCage.spawn(main, at, p)
	cage.progress = 0.0 if behind else 0.45
	cage.step(0.0, false)
	for i in 90:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.save_path))
	SaveManager.save_path = SaveManager.SAVE_PATH
	SaveManager.load_save()
	get_tree().quit()
