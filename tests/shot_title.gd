extends Node

## Captura de la pantalla de título (necesita ventana):  res://tests/shot_title.tscn -- <prefijo>
## Guarda <prefijo>_titulo.png tras unos segundos de panorama.

var _prefix := "user://title"

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_prefix = args[0]
	_run.call_deferred()

func _run() -> void:
	var t := (load("res://scenes/ui/title_screen.tscn") as PackedScene).instantiate()
	add_child(t)
	await get_tree().create_timer(3.0).timeout
	await RenderingServer.frame_post_draw
	var path := _prefix + "_titulo.png"
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT ", ProjectSettings.globalize_path(path))
	print("CHECK shot_title PASSED")
	get_tree().quit(0)
