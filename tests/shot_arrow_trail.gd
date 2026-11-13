extends Node

## Captura de la estela de las flechas (necesita ventana, no headless):
##   res://tests/shot_arrow_trail.tscn -- <prefijo>
## Dispara una flecha normal y una cargada (con brillo) y guarda <prefijo>.png: de lado y desde detrás del tirador.

var _prefix := "user://arrow_trail"
var _main: Node
const CELL := Vector2i(480, 320)

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
	await get_tree().create_timer(3.0).timeout
	var enc = _main.get_node_or_null("DungeonEncounter")
	if enc:
		enc.process_mode = Node.PROCESS_MODE_DISABLED
	for e in get_tree().get_nodes_in_group("enemies"):
		(e as Node).queue_free()
	for c in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(c as CanvasLayer).visible = false
	var map: DungeonMap = _main.get_node("ProceduralMap")
	var player: CharacterBody3D = _main.get_node("Player")
	var o := map.room_center(0) + Vector3(0, 1.3, 0)
	player.global_position = o + Vector3(0, -1.0, 3.0)
	var cam := Camera3D.new()
	cam.fov = 50.0
	_main.add_child(cam)
	cam.current = true
	get_viewport().size = CELL
	var sheet := Image.create(CELL.x * 2, CELL.y * 2, false, Image.FORMAT_RGBA8)
	var row := 0
	for glow in [0.0, 1.0]:
		var col := Color(1.0, 0.85, 0.5) if glow == 0.0 else Color(0.5, 0.9, 1.0)
		for view in 2:
			var a := BowArrow.shoot(_main, o, Vector3(0, 0, -24.0), 0.0, {"gravity": 0.0, "color": col, "glow": glow, "range": 40.0})
			await get_tree().create_timer(0.12).timeout
			var p := a.global_position
			if view == 0:
				cam.global_position = p + Vector3(3.5, 0.4, 1.2)
			else:
				cam.global_position = o + Vector3(0.6, 0.5, 2.0)
			cam.look_at(p + Vector3(0, 0, 0.8))
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i(view * CELL.x, row * CELL.y))
			a.queue_free()
			await get_tree().create_timer(0.3).timeout
		row += 1
	var path := "%s.png" % _prefix
	sheet.save_png(path)
	print("SHOT ", ProjectSettings.globalize_path(path))
	get_tree().quit(0)
