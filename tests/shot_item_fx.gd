extends Node3D

## Captura (con ventana, no headless) de los efectos 2D de los objetos de supervivencia (ToonFX objetos.png):
## trompo, enredaderas, remolino, tajo, campana, cura, fantasma, pata, moneda, furia y nota.
## Sale en user://shot_item_fx_*.png

func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.7, 0.85)
	env.environment.ambient_light_color = Color(0.8, 0.8, 0.8)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
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
	cam.global_position = Vector3(0, 7.5, 12)
	cam.look_at(Vector3(0, 0.5, -1))
	cam.current = true

	var dummy := Node3D.new()
	add_child(dummy)
	dummy.global_position = Vector3(-5, 0, 2)
	WarTop.spawn(self, dummy, 100.0, 1.0)
	VinePatch.spawn(self, Vector3(4, 0, 3))
	VinePatch.spawn(self, Vector3(7, 0, 0))
	var whirl := ToonFX.item_decal(ToonFX.ITEM_FX_WHIRL, 6.0)
	add_child(whirl)
	whirl.global_position = Vector3(-1, 0.1, -4)
	var slash := ToonFX.item_sprite(ToonFX.ITEM_FX_SLASH, 6.0, false)
	add_child(slash)
	slash.global_position = Vector3(1, 1, 3)
	slash.rotation.y = 0.3
	var frames := [ToonFX.ITEM_FX_BELL, ToonFX.ITEM_FX_HEAL, ToonFX.ITEM_FX_GHOST, ToonFX.ITEM_FX_LEG,
		ToonFX.ITEM_FX_COIN, ToonFX.ITEM_FX_ANGER, ToonFX.ITEM_FX_NOTE, ToonFX.ITEM_FX_EYE]
	for i in frames.size():
		var s := ToonFX.item_sprite(frames[i], 1.3)
		add_child(s)
		s.global_position = Vector3(-7 + i * 2.0, 3.2, -2)
	ToonFX.ring_burst(self, Vector3(0, 0, 0), 5.0, Color(1.0, 0.85, 0.35), 2.0)

	var k := 0
	for dt in [0.3, 0.2]:
		await get_tree().create_timer(dt).timeout
		k += 1
		var img := get_viewport().get_texture().get_image()
		var path := "user://shot_item_fx_%d.png" % k
		img.save_png(path)
		print("captura ", ProjectSettings.globalize_path(path))
	get_tree().quit(0)
