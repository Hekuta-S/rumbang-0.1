extends Node

## Capturas de las pantallas de menú, una por una (necesita ventana):
##   res://tests/shot_menus.tscn -- <prefijo> [escena1,escena2...]
## Carga cada escena de res://scenes/ui/ (por defecto título, ajustes, pausa y selección de personaje), espera
## a que se asiente y guarda <prefijo>_<escena>.png. Sirve para revisar el tema (RumbangStyle) de un vistazo.

const DEFAULT := ["title_screen", "settings_menu", "pause_menu", "character_select"]

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var prefix: String = args[0] if args.size() > 0 else "user://menu"
	var names: Array = Array(args[1].split(",")) if args.size() > 1 else DEFAULT
	for n in names:
		var path := "res://scenes/ui/%s.tscn" % n
		if not ResourceLoader.exists(path):
			print("sin escena: ", path)
			continue
		var node := (load(path) as PackedScene).instantiate()
		add_child(node)
		if node is CanvasItem:
			(node as CanvasItem).visible = true
		elif node is CanvasLayer:
			(node as CanvasLayer).visible = true
		await get_tree().create_timer(2.0).timeout
		await RenderingServer.frame_post_draw
		var out := "%s_%s.png" % [prefix, n]
		get_viewport().get_texture().get_image().save_png(out)
		print("captura guardada: ", ProjectSettings.globalize_path(out))
		node.queue_free()
		await get_tree().process_frame
	get_tree().paused = false
	get_tree().quit(0)
