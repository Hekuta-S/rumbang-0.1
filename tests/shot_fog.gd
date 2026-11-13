extends Node

## Capturas de la niebla entre salas (necesita ventana): res://tests/shot_fog.tscn -- <prefijo>
## Pone al jugador a 12 m, 5 m y sobre la primera cortina y guarda <prefijo>_a/_b/_c.png (vista real de juego).

func _ready() -> void:
	GameData.game_mode = "dungeon"
	var main: Node = (load(Net.game_scene()) as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	_run.call_deferred(main)

func _run(main: Node) -> void:
	var args := OS.get_cmdline_user_args()
	var prefix: String = args[0] if args.size() > 0 else "user://fog"
	await get_tree().process_frame
	get_tree().current_scene = main
	await get_tree().create_timer(4.0).timeout
	var fog = main.get_node("DungeonFog")
	var player: Node3D = main.get_node("Player")
	var enc = main.get_node_or_null("DungeonEncounter")
	if enc:
		enc.process_mode = Node.PROCESS_MODE_DISABLED
	var gate: Node3D = fog._gates.get_child(1)
	var fwd := -gate.global_transform.basis.z
	var base := gate.global_position
	base.y = 0.3
	var cam := Camera3D.new()
	cam.fov = 70.0
	main.add_child(cam)
	cam.current = true
	var i := 0
	for off in [14.0, 8.0, 3.0]:
		player.global_position = base - fwd * off
		cam.global_position = base - fwd * (off + 3.0) + Vector3(0, 1.9, 0)
		cam.look_at(base + fwd * 6.0 + Vector3(0, 1.3, 0))
		await get_tree().create_timer(1.2).timeout
		get_viewport().get_texture().get_image().save_png("%s_%s.png" % [prefix, "abc"[i]])
		i += 1
	print("SHOTS DONE zone=", fog._cur_zone)
	get_tree().quit(0)
