extends Node

## Capturas del editor de ropa (necesita ventana, no headless):
##   res://tests/shot_clothing.tscn -- <prefijo> [ui] [tpose|down|up] [id ...]
## Guarda <prefijo>_<id>_<vista>.png de cada prenda indicada (por defecto todas), de frente y de lado.

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var prefix := "user://clothing" if args.is_empty() else String(args[0])
	var with_ui := args.has("ui")
	var arms := 0.0
	if args.has("down"):
		arms = -80.0
	elif args.has("up"):
		arms = 80.0
	var ids: Array[String] = []
	for a in args.slice(1):
		if a not in ["ui", "tpose", "down", "up", "skin"]:
			ids.append(String(a))
	var ed := (load("res://tools/clothing_editor.tscn") as PackedScene).instantiate()
	add_child(ed)
	await get_tree().create_timer(1.5).timeout
	if ids.is_empty():
		ids.assign(ClothingFit.garment_ids())
	if not with_ui:
		ed.hide_ui()
	ed.set_arms(arms, arms)
	if args.has("skin"):
		ed.set_skin_preview(true)
		await get_tree().create_timer(6.0).timeout
	var prev := ""
	for id in ids:
		if prev != "":
			ed.show_garment(prev, false)
		prev = id
		ed.select_garment(id)
		for view in [["front", 0.0, 8.0, 1.9], ["side", 90.0, 8.0, 1.9], ["back", 180.0, 8.0, 1.9]]:
			ed.set_view(view[1], view[2], view[3], Vector3(0, 1.2, 0))
			await get_tree().create_timer(0.3).timeout
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			var path := "%s_%s_%s.png" % [prefix, id, view[0]]
			img.save_png(path)
			print("SHOT ", ProjectSettings.globalize_path(path))
	print("CHECK shot_clothing PASSED")
	get_tree().quit(0)
