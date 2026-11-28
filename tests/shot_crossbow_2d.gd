extends Node3D

## Captura (con ventana) de la flecha plana de la ballesta (cono de 5), gemas de XP dibujadas por tier y
## destellos de golpe. Sale en user://shot_crossbow_2d.png

func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.7, 0.85)
	add_child(env)
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
	cam.global_position = Vector3(0, 9, 10)
	cam.look_at(Vector3(0, 0, -6))
	cam.current = true
	for a in WeaponStrategy.CrossbowStrategy.cone_angles(5):
		var arrow := BowArrow.shoot(self, Vector3(0, 1.2, 4), Vector3(0, 0, -1).rotated(Vector3.UP, a) * 0.01, 1.0,
			{"range": 60.0, "gravity": 0.0, "pierce": -1, "color": Color(1.0, 0.9, 0.55), "glow": 3.0, "flat": true})
		arrow.velocity = Vector3(0, 0, -0.01).rotated(Vector3.UP, a)
	for i in 4:
		var orb = load("res://scenes/objects/xp_orb.tscn").instantiate()
		orb.xp_amount = [1.0, 5.0, 25.0, 100.0][i]
		add_child(orb)
		orb.global_position = Vector3(-3.0 + i * 2.0, 0.6, 6)
	await get_tree().create_timer(0.8).timeout
	var path := "user://shot_crossbow_2d.png"
	get_viewport().get_texture().get_image().save_png(path)
	print("captura ", ProjectSettings.globalize_path(path))
	get_tree().quit(0)
