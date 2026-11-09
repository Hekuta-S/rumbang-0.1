extends Node3D

## Capturas de los peinados personalizable (necesita ventana, no headless):
##   res://tests/shot_look.tscn -- <prefijo>
## Monta el modelo idle de Riva, le aplica varias apariencias (CharacterLook) y guarda una captura de
## frente y otra a tres cuartos de cada una en <prefijo>_<n>.png.

var _prefix := "user://look"

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_prefix = args[0]
	_run.call_deferred()

func _looks() -> Array[CharacterLook]:
	var out: Array[CharacterLook] = []
	for id in CharacterLook.HAIR_STYLES:
		var l := CharacterLook.new()
		l.hair_style = id
		l.colors["hair"] = Color(0.45, 0.25, 0.12)
		out.append(l)
	return out

func _run() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.25, 0.26, 0.3)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.5, 0.5, 0.55)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 30.0
	add_child(cam)
	cam.current = true
	var scene := load(GameData.get_idle_model_path(CharacterLook.CHAR_ID)) as PackedScene
	var tex := load(GameData.get_texture_path(CharacterLook.CHAR_ID)) as Texture2D
	var looks := _looks()
	for i in looks.size():
		var model := scene.instantiate() as Node3D
		add_child(model)
		var mi := CharacterLookApplier.body_mesh(model)
		var aabb := mi.mesh.get_aabb()
		var s := 1.62 / aabb.size.y
		model.scale = Vector3.ONE * s
		model.position.y = -aabb.position.y * s
		var std := StandardMaterial3D.new()
		std.albedo_texture = tex
		mi.material_override = std
		var ap := CharacterLookApplier._find(model, "AnimationPlayer") as AnimationPlayer
		if ap and not OS.get_cmdline_user_args().has("rest"):
			ap.play(ap.get_animation_list()[0])
		CharacterLookApplier.apply_to(model, looks[i])
		for view in [["head", Vector3(0, 1.62, 1.6)], ["side", Vector3(1.6, 1.62, 0.3)], ["back", Vector3(0, 1.62, -1.6)]]:
			cam.position = view[1]
			var target := Vector3(0, 1.62, 0)
			cam.look_at(target)
			await get_tree().create_timer(0.4).timeout
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			var path := "%s_%d_%s.png" % [_prefix, i, view[0]]
			img.save_png(path)
			print("SHOT ", ProjectSettings.globalize_path(path))
		model.queue_free()
		await get_tree().process_frame
	print("CHECK shot_hairs PASSED")
	get_tree().quit(0)
