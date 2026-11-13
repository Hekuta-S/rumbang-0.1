extends Node

## Capturas del patio del tutorial (necesita ventana): res://tests/shot_patio.tscn -- <prefijo>

var _prefix := "user://patio"

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_prefix = args[0]
	_run.call_deferred()

func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s_%s.png" % [_prefix, tag])
	print("SHOT ", tag)

func _run() -> void:
	DungeonHub.config_path = "user://shot_patio.cfg"
	var scene: TutorialPatio = load("res://scenes/core/tutorial_patio.tscn").instantiate()
	add_child(scene)
	for t in [3.0, 7.0, 9.4, 10.3, 14.0, 19.5]:
		while scene.cine.time < t:
			await get_tree().process_frame
		await _shot("cine_%04.1f" % t)
	while scene.cinematic:
		await get_tree().process_frame
	await _shot("mover")
	scene.director.report("move", 6.5)
	await get_tree().create_timer(1.5).timeout
	await _shot("golpear")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://shot_patio.cfg"))
	get_tree().quit(0)
