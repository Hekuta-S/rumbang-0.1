extends Node3D

## Capturas del personaje personalizable (necesita ventana, no headless):
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
	out.append(CharacterLook.new())                       # 0: base en calzones
	var a := CharacterLook.new()                          # 1: gorro + botas, piel morena, pelo rubio
	a.hat = "gorro"; a.footwear = "botas"
	a.colors["skin"] = Color(0.7, 0.5, 0.35); a.colors["hair"] = Color(0.92, 0.8, 0.45)
	a.colors["underwear"] = Color(0.15, 0.6, 0.3); a.hair_style = "riva"; a.colors["eyes"] = Color(0.25, 0.45, 0.75)
	out.append(a)
	var b := CharacterLook.new()                          # 2: gorra + converse, grande
	b.hat = "gorra"; b.footwear = "converse"
	b.colors["underwear"] = Color(0.78, 0.16, 0.16); b.colors["shoes"] = Color(0.1, 0.11, 0.16)
	b.colors["hat"] = Color(0.2, 0.45, 0.85); b.colors["hair"] = Color(0.75, 0.2, 0.12)
	b.height = 1.12; b.build = 1.2; b.head = 1.25; b.hair_style = "rapado"
	out.append(b)
	var c := CharacterLook.new()                          # 3: sombrero, pequeño
	c.hat = "sombrero"; c.footwear = "botas"; c.colors["hat"] = Color(0.4, 0.25, 0.12)
	c.colors["hat2"] = Color(0.1, 0.1, 0.1); c.colors["skin"] = Color(0.36, 0.24, 0.16)
	c.height = 0.88; c.build = 0.85; c.head = 0.85; c.hair_style = "riva"; c.colors["eyes"] = Color(0.3, 0.45, 0.2)
	out.append(c)
	var d := CharacterLook.new()                          # 4: gorra al revés
	d.hat = "gorra_atras"; d.colors["hat"] = Color(0.95, 0.8, 0.2); d.colors["skin"] = Color(0.98, 0.86, 0.76)
	d.hair_style = "riva"; d.colors["hair"] = Color(0.62, 0.42, 0.22)
	out.append(d)
	for id in ClothingFit.fitted_ids():                   # 5..: una por camiseta (resources/clothing_fit.json)
		var e := CharacterLook.new()
		e.shirt = id; e.hair_style = "riva"
		out.append(e)
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
		for view in [["front", Vector3(0, 1.0, 4.2)], ["34", Vector3(2.6, 1.3, 3.2)], ["head", Vector3(0.7, 1.62, 1.2)], ["feet", Vector3(0.8, 0.35, 1.6)]]:
			cam.position = view[1]
			var target := Vector3(0, 1.45 if view[0] == "head" else (0.15 if view[0] == "feet" else 0.85), 0)
			cam.look_at(target)
			await get_tree().create_timer(0.4).timeout
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			var path := "%s_%d_%s.png" % [_prefix, i, view[0]]
			img.save_png(path)
			print("SHOT ", ProjectSettings.globalize_path(path))
		model.queue_free()
		await get_tree().process_frame
	print("CHECK shot_look PASSED")
	get_tree().quit(0)
