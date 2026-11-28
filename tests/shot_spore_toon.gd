extends Node3D

## Captura (con ventana, no headless) de la bazuca de esporas dibujada (cómic): proyectiles en vuelo, estallido,
## nube y perdigones. Sale en user://shot_spore_toon_*.png
const PROJ := preload("res://scenes/objects/spore_projectile.tscn")
const CLOUD := preload("res://scenes/objects/spore_cloud.tscn")

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

	for i in 2:
		var p = PROJ.instantiate()
		add_child(p)
		p.global_position = Vector3(-6 + i * 3.0, 1.6, 4)
		p.max_lifetime = 100.0
		p.setup(Vector3.RIGHT, 10.0, 0.6, 1.0, 1.0, 2.6)
	var c = CLOUD.instantiate()
	c.lifetime = 10.0
	add_child(c)
	c.global_position = Vector3(-3, 0.3, -2)
	var b = PROJ.instantiate()
	add_child(b)
	b.global_position = Vector3(4, 1.2, -1)
	b.setup(Vector3.RIGHT, 10.0, 0.0, 1.0, 10.0, 2.6)
	b._burst(null, b.global_position)
	for k in 9:
		var t := (float(k) / 8.0) * 2.0 - 1.0
		SporePellet.fire(self, Vector3(1, 1.2, 5), Vector3(t * 0.35, 0, -1).normalized(), 5.0, 1.0, 6.0, 9.0, null)

	var k2 := 0
	for dt in [0.1, 0.25, 0.5, 0.8]:
		await get_tree().create_timer(dt).timeout
		k2 += 1
		var img := get_viewport().get_texture().get_image()
		var path := "user://shot_spore_toon_%d.png" % k2
		img.save_png(path)
		print("captura ", ProjectSettings.globalize_path(path))
	get_tree().quit(0)
