extends Node3D

## Polvo de los pies (FootDustVFX): cada efecto crea su nodo con partículas emitiendo y se libera solo.
## Sin --headless guarda una captura en user://foot_dust.png con los cuatro efectos a la vez.

func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _ready() -> void:
	var ok := true
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 1.4, 3.2)
	cam.look_at(Vector3(0, 0.2, 0))
	var sun := DirectionalLight3D.new()
	add_child(sun)
	sun.rotation_degrees = Vector3(-50, 30, 0)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(12, 12)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.35, 0.3, 0.25)
	floor_mi.material_override = fm
	add_child(floor_mi)

	FootDustVFX.prewarm(self)
	await _wait(0.6)
	var before := get_child_count()
	GameData.game_mode = "survival"
	FootDustVFX.step(self, Vector3(-1.5, 0.05, 0), Vector3(1, 0, 0), false)
	FootDustVFX.step(self, Vector3(-0.5, 0.05, 0), Vector3(1, 0, 0), true)
	FootDustVFX.takeoff(self, Vector3(0.5, 0.05, 0))
	GameData.game_mode = "dungeon"
	FootDustVFX.land(self, Vector3(1.5, 0.05, 0), 1.0)
	FootDustVFX.air_jump(self, Vector3(0, 1.2, 0))
	var spawned := get_child_count() - before
	print("CHECK 1 spawned=%d %s" % [spawned, "PASSED" if spawned == 5 else "FAILED"])
	ok = ok and spawned == 5
	var emitting := 0
	for c in get_children().slice(before):
		for p in c.get_children():
			if p is CPUParticles3D and p.emitting:
				emitting += 1
	print("CHECK 2 emitting=%d %s" % [emitting, "PASSED" if emitting >= 9 else "FAILED"])
	ok = ok and emitting >= 9
	for i in 3:
		await _wait(0.1)
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("user://foot_dust_%d.png" % i)
	await _wait(1.5)
	var left := get_child_count() - before
	print("CHECK 3 freed left=%d %s" % [left, "PASSED" if left == 0 else "FAILED"])
	ok = ok and left == 0
	get_tree().quit(0 if ok else 1)
