extends Control

@onready var progress_bar = $VBoxContainer/ProgressBar

var progress = []
var scene_load_status = 0

func _ready():
	if SceneLoader.next_scene_path != "":
		ResourceLoader.load_threaded_request(SceneLoader.next_scene_path)
	else:
		push_error("No scene path provided to SceneLoader")

func _process(_delta):
	if SceneLoader.next_scene_path == "":
		return
		
	scene_load_status = ResourceLoader.load_threaded_get_status(SceneLoader.next_scene_path, progress)
	
	if scene_load_status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		progress_bar.value = progress[0] * 100
	elif scene_load_status == ResourceLoader.THREAD_LOAD_LOADED:
		set_process(false)
		var new_scene = ResourceLoader.load_threaded_get(SceneLoader.next_scene_path)
		get_tree().change_scene_to_packed(new_scene)
	elif scene_load_status == ResourceLoader.THREAD_LOAD_FAILED or scene_load_status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		push_error("Error loading scene: " + SceneLoader.next_scene_path)
		set_process(false)
