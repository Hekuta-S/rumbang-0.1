extends Node

## Captura de la fase 2 del juice (necesita ventana): un goblin muere de un golpe fuerte delante de la
## cámara y se guardan fotos del salto, la disolución y el cartel. res://tests/shot_death_fx.tscn -- <prefijo>
## SHOT_COMPARE=1: en vez de matar, fotos del material antes/después del cambio y a 30/60/85 % de disolución.

var _out := "user://death_fx"

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	GameData.game_mode = "dungeon"
	var scene: Node = load("res://scenes/core/main_dungeon.tscn").instantiate()
	get_tree().root.add_child.call_deferred(scene)
	await get_tree().process_frame
	get_tree().current_scene = scene
	var enc: DungeonEncounter = null
	for i in 600:
		await get_tree().process_frame
		enc = scene.get_node_or_null("DungeonEncounter")
		if enc and enc.map and is_instance_valid(enc.player):
			break
	enc._pending.clear()
	var player = enc.player
	var c := enc.map.room_center(enc.map.arena_index)
	player.global_position = c + Vector3(0, 0.3, 0)
	await get_tree().create_timer(2.0).timeout
	var cam := get_viewport().get_camera_3d()
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var gobs: Array = []
	for i in 2:
		var g = enc.spawn_brute()
		gobs.append(g)
	await get_tree().physics_frame
	for i in gobs.size():
		gobs[i].global_position = player.global_position + fwd * 3.2 + cam.global_basis.x * (float(i) - 0.5) * 1.6
		gobs[i].set_physics_process(true)
	# SHOT_WAIT=<s>: cuánto viven antes del golpe (0,6 = aún materializándose; 2 = ya enteros)
	var wait_env := OS.get_environment("SHOT_WAIT")
	await get_tree().create_timer(wait_env.to_float() if wait_env != "" else 0.6).timeout
	if OS.get_environment("SHOT_COMPARE") == "1":
		for g in gobs:
			g.set_physics_process(false)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_out + "_before.png")
		HitFeedback.death_fx(gobs[0]._model, gobs[0]._meshes)
		for t in gobs[0]._model.get_tree().get_processed_tweens():
			t.kill()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_out + "_after.png")
		for d in [0.3, 0.6, 0.85]:
			for mi in gobs[0]._meshes:
				for si in (mi as MeshInstance3D).mesh.get_surface_count():
					var sm := (mi as MeshInstance3D).get_surface_override_material(si) as ShaderMaterial
					if sm:
						sm.set_shader_parameter("dissolve", d)
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(_out + "_d%d.png" % int(d * 100))
		get_tree().quit(0)
		return
	HitFeedback.weapon_tag = WeaponData.WeaponType.GREATSWORD
	for g in gobs:
		g.take_damage(9999.0, fwd * 8.0)
	var shots := [0.06, 0.25, 0.5, 0.95, 1.15, 1.35]
	var t := 0.0
	for i in shots.size():
		var wait: float = shots[i] - t
		t = shots[i]
		await get_tree().create_timer(wait, true, false, true).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s_%d.png" % [_out, i])
		print("SHOT ", i)
	get_tree().quit(0)
