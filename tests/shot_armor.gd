extends Node3D

## Capturas de las armaduras sobre el personaje (necesita ventana, no headless):
##   res://tests/shot_armor.tscn -- <prefijo> [set,set,...] [casco] [cerca]
## Para cada set guarda <prefijo>_<set>.png: el torso de frente, de lado, a tres cuartos y por detrás en reposo, y de frente
## y a tres cuartos con el clip de reposo ya en marcha (la pieza va rígida sobre un hueso: debe seguir el movimiento).

var _prefix := "user://armor"
const CELL := Vector2i(360, 480)

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_prefix = args[0]
	_run.call_deferred()

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
	get_viewport().size = Vector2i(CELL)
	var scene := load(GameData.get_idle_model_path(CharacterLook.CHAR_ID)) as PackedScene
	var tex := load(GameData.get_texture_path(CharacterLook.CHAR_ID)) as Texture2D
	var sets: Array = Array(CharacterLookApplier.ARMOR_SETS)
	var args := OS.get_cmdline_user_args()
	if args.size() > 1:
		sets = String(args[1]).split(",")
	var helmet := String(args[2]) if args.size() > 2 else ""
	var close := args.size() > 3 and String(args[3]) == "cerca"   # torso y hombros de cerca
	# [nombre, posición de la cámara, animar]
	var views := [
		["front", Vector3(0, 1.0, 4.4), false], ["side", Vector3(4.4, 1.0, 0), false], ["34", Vector3(3.1, 1.2, 3.1), false],
		["back", Vector3(0, 1.0, -4.4), false], ["front_anim", Vector3(0, 1.0, 4.4), true], ["34_anim", Vector3(3.1, 1.2, 3.1), true],
	]
	for set_id in sets:
		var sheet := Image.create(CELL.x * 3, CELL.y * 2, false, Image.FORMAT_RGBA8)
		for vi in views.size():
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
			var ap := CharacterLookApplier.apply_to(model, CharacterLook.new())
			ap.set_armor("pechera", String(set_id))
			ap.set_armor("pantalones", String(set_id))
			if helmet != "":
				ap.set_helmet(helmet)
			if views[vi][2]:
				var anim := CharacterLookApplier._find(model, "AnimationPlayer") as AnimationPlayer
				if anim and anim.get_animation_list().size() > 0:
					anim.play(anim.get_animation_list()[0])
					anim.seek(0.9, true)
			cam.position = views[vi][1]
			if close:
				cam.position = Vector3(views[vi][1].x * 0.55, 1.4, views[vi][1].z * 0.55)
			cam.look_at(Vector3(0, 1.3 if close else 0.85, 0))
			await get_tree().create_timer(0.3).timeout
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i((vi % 3) * CELL.x, (vi / 3) * CELL.y))
			model.queue_free()
			await get_tree().process_frame
		var path := "%s_%s.png" % [_prefix, set_id]
		sheet.save_png(path)
		print("SHOT ", ProjectSettings.globalize_path(path))
	print("CHECK shot_armor PASSED")
	get_tree().quit(0)
