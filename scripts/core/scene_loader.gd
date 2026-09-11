extends Node

var next_scene_path: String = ""

func load_scene(path: String) -> void:
	next_scene_path = path
	get_tree().change_scene_to_file("res://scenes/ui/loading_screen.tscn")
