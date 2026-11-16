extends Node3D

## Hoja de contacto de todas las armas (necesita ventana): res://tests/shot_toon_weapons.tscn -- <archivo.png>
## TOON_OFF=1 las deja con sus materiales PBR originales (ToonWeapon.enabled = false) para comparar.

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://toon_weapons.png"
	ToonWeapon.enabled = OS.get_environment("TOON_OFF") != "1"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.3, 0.32, 0.38)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.62, 0.7)
	env.ambient_light_energy = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.6
	sun.rotation_degrees = Vector3(-35.0, 30.0, 0.0)
	add_child(sun)
	var groups := [GreatswordModels, SwordModels, KatanaModels, DaggerModels, MaceModels, BowModels]
	var row := 0
	var cols := 0
	for g in groups:
		var n: int = g.count()
		cols = maxi(cols, n)
		for i in n:
			var w: Node3D = g.build(i)
			add_child(w)
			w.position = Vector3(float(i) * 1.1, -float(row) * 1.9, 0.0)
			w.rotation_degrees = Vector3(0.0, 35.0, 0.0)
		row += 1
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = float(row) * 1.9 + 0.4
	add_child(cam)
	cam.position = Vector3(float(cols - 1) * 0.55, -float(row - 1) * 0.95 + 0.45, 12.0)
	cam.current = true
	await get_tree().create_timer(1.5).timeout
	get_viewport().get_texture().get_image().save_png(out)
	print("captura guardada: ", ProjectSettings.globalize_path(out))
	get_tree().quit(0)
