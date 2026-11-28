extends Node3D

## Captura (con ventana, no headless) de los Polvos Alquímicos y la Escopeta de Humo dibujados (cómic):
## polvo en vuelo, explosión de polvo (3 tipos), bocanada del polvo de velocidad y escopetazo.
## Sale en user://shot_dust_shotgun_*.png

const DUST := preload("res://scenes/objects/dust_projectile.tscn")

func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.7, 0.85)
	env.environment.ambient_light_color = Color(0.8, 0.8, 0.8)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.45, 0.62, 0.32)
	ground.material_override = gm
	add_child(ground)
	var cam := Camera3D.new()
	add_child(cam)
	cam.global_position = Vector3(0, 6.5, 11)
	cam.look_at(Vector3(0, 0.5, -1))
	cam.current = true

	# polvos en vuelo (largo: no llegan a explotar durante la captura)
	for m in 3:
		var d = DUST.instantiate()
		add_child(d)
		d.max_lifetime = 100.0
		d.setup(Vector3(-7 + m * 2.0, 2.0, 3), Vector3(-7 + m * 2.0 + 20.0, 2.0, 3), m, null)
		d.gravity_vec = Vector3.ZERO
		d.velocity = Vector3(0.4, 0, 0)
		d.flight_time = 100.0
	# explosiones de polvo (modo 1 y 2: sin daño)
	for m in [1, 2, 1]:
		var e = DUST.instantiate()
		add_child(e)
		e.setup(Vector3(-2 + m * 3.0, 0.6, -2), Vector3(-2 + m * 3.0, 0.6, -2), m, null)
		e._burst(e.global_position)
	# escopetazos
	var sg := WeaponStrategy.TriShotgunStrategy.new(null)
	sg._create_toon_blast(self, Vector3(3, 1.2, 4), Vector3(1, 0, -0.3).normalized(), 1.0, 14.0, 6.0)
	sg._create_toon_blast(self, Vector3(-4, 1.2, 6), Vector3(-1, 0, -0.6).normalized(), 1.4, 20.0, 8.4)

	var k := 0
	for dt in [0.08, 0.15, 0.2, 0.4]:
		await get_tree().create_timer(dt).timeout
		k += 1
		var img := get_viewport().get_texture().get_image()
		var path := "user://shot_dust_shotgun_%d.png" % k
		img.save_png(path)
		print("captura ", ProjectSettings.globalize_path(path))
	get_tree().quit(0)
