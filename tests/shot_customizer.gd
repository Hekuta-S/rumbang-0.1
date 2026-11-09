extends Node

## Captura de la pantalla de personalización (necesita ventana): res://tests/shot_customizer.tscn -- <ruta.png>

func _ready() -> void:
	var path := "user://customizer.png"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		path = args[0]
	var ui := (load("res://scenes/ui/character_select.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(ui)
	await get_tree().create_timer(4.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT ", path)
	get_tree().quit(0)
