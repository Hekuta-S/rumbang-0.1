extends Node3D

## Captura (con ventana, no headless) de las armas y ataques 2D horneados: guitarra y brazo (en vuelo y en
## la mano), Maza Gigante, balas mágicas enemigas, mortero y golpe al suelo. Sale en user://shot_weapons_2d_*.png

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

	var dummy := Node3D.new()
	add_child(dummy)
	dummy.global_position = Vector3(0, 1, 8)
	# en vuelo
	var axe = load("res://scenes/objects/spinning_axe_projectile.tscn").instantiate()
	add_child(axe)
	axe.global_position = Vector3(-6, 1.2, 0)
	axe.setup(Vector3.FORWARD, 1.0, 0.5, 100.0)
	var arm = load("res://scripts/objects/zombie_arm_projectile.tscn").instantiate()
	add_child(arm)
	arm.global_position = Vector3(-3, 1.2, 2)
	arm.setup(Vector3.FORWARD, 1.0, dummy)
	arm.speed = 0.3
	# en la mano (recortes cruzados)
	var g := ToonFX.cutout_cross("guitarra.png", ToonFX.SPIN_FRAMES, 1, 0.011)
	add_child(g)
	g.global_position = Vector3(6, 1.2, 1)
	g.rotation.y = 0.5
	var a := ToonFX.cutout_cross("brazo.png", ToonFX.SPIN_FRAMES, 1, 0.011)
	add_child(a)
	a.global_position = Vector3(4, 1.0, 3)
	a.rotation.y = -0.4
	# balas mágicas enemigas
	for k in 3:
		var b = load("res://scenes/objects/bullet.tscn").instantiate()
		add_child(b)
		b.global_position = Vector3(-1.5 + k * 1.5, 1.2, 4)
		b.max_lifetime = 100.0
		b.setup(Vector3.LEFT, 1.0, 0.01, true, [Color(0.46, 0.51, 1.0), Color(1, 0.1, 0.3), Color(0.3, 1, 0.6)][k], RID(), EnemyBehavior.MAGO_SHOT_VFX if k != 1 else null)
	MortarShell.launch(self, Vector3(8, 1, -6), Vector3(4, 0, -4), 0.0)
	GroundBlast.spawn(self, Vector3(-5, 0, -5), 1.6, 0.6, 0.0, Color(1.0, 0.45, 0.2))
	# maza
	GiantMaceSlam.spawn(self, Vector3(0, 0, -2), 0.0, 3.0, 1.0, null)

	var k := 0
	for dt in [0.25, 0.15, 0.13, 0.6]:
		await get_tree().create_timer(dt).timeout
		k += 1
		var img := get_viewport().get_texture().get_image()
		var path := "user://shot_weapons_2d_%d.png" % k
		img.save_png(path)
		print("captura ", ProjectSettings.globalize_path(path))
	get_tree().quit(0)
