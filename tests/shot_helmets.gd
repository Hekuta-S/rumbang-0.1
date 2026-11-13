extends Node3D

## Capturas de los cascos sobre el personaje (necesita ventana, no headless):
##   res://tests/shot_helmets.tscn -- <prefijo> [id,id,...]
## Para cada casco guarda <prefijo>_<id>.png: una hoja con la cabeza de frente, de lado, a tres cuartos y por detrás,
## y de frente con la cabeza al mínimo y al máximo del deslizador (el casco debe seguirla sin atravesarla).

var _prefix := "user://helmet"
const CELL := Vector2i(360, 360)

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
	var ids: Array = CharacterLookApplier.helmet_fit().keys()
	var args := OS.get_cmdline_user_args()
	if args.size() > 1:
		ids = String(args[1]).split(",")
	var views := [
		["front", Vector3(0, 1.55, 1.15), 1.0], ["side", Vector3(1.15, 1.55, 0), 1.0],
		["34", Vector3(0.85, 1.6, 0.85), 1.0], ["back", Vector3(0, 1.55, -1.15), 1.0],
		["front_small", Vector3(0, 1.55, 1.15), 0.85], ["front_big", Vector3(0, 1.55, 1.15), 1.3],
	]
	for id in ids:
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
			var look := CharacterLook.new()
			look.head = views[vi][2]
			var ap := CharacterLookApplier.apply_to(model, look)
			ap.set_helmet(String(id))
			cam.position = views[vi][1]
			cam.look_at(Vector3(0, 1.5, 0))
			await get_tree().create_timer(0.3).timeout
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i((vi % 3) * CELL.x, (vi / 3) * CELL.y))
			model.queue_free()
			await get_tree().process_frame
		var path := "%s_%s.png" % [_prefix, id]
		sheet.save_png(path)
		print("SHOT ", ProjectSettings.globalize_path(path))
	print("CHECK shot_helmets PASSED")
	get_tree().quit(0)
