extends Node

## Capturas de las Dagas Gemelas y la Maza Rúnica en las manos de Mikeura (necesita ventana, no headless):
##   res://tests/shot_melee.tscn -- <prefijo>
## Para cada arma guarda la guardia (_idle) y varios instantes de su primer golpe y de su especial, con la
## cámara de frente a tres cuartos.

var _prefix := "user://melee"
var _main: Node

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_prefix = args[0]
	GameData.game_mode = "dungeon"
	for i in GameData.CHARACTERS.size():
		if GameData.CHARACTERS[i]["id"] == "mikeura":
			GameData.selected_index = i
	_main = (load(Net.game_scene()) as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(_main)
	_run.call_deferred()

func _run() -> void:
	await get_tree().process_frame
	get_tree().current_scene = _main
	await get_tree().create_timer(3.0).timeout
	var enc = _main.get_node_or_null("DungeonEncounter")
	if enc:
		enc.process_mode = Node.PROCESS_MODE_DISABLED
	for e in get_tree().get_nodes_in_group("enemies"):
		(e as Node).queue_free()
	var player: CharacterBody3D = _main.get_node("Player")
	var map: DungeonMap = _main.get_node("ProceduralMap")
	player.global_position = map.room_center(0) + Vector3(0, 0.3, 0)
	player.health_comp.max_hp = 9999.0
	player.health_comp.hp = 9999.0
	var cam := Camera3D.new()
	cam.fov = 40.0
	_main.add_child(cam)
	cam.current = true
	var light := OmniLight3D.new()
	light.omni_range = 10.0
	light.light_energy = 1.6
	_main.add_child(light)
	var W := WeaponData.WeaponType
	for w in [W.DAGGERS, W.MACE]:
		if not player.weapon_slots.has(w):
			player.add_weapon(w)
		player.select_slot(player.weapon_slots.find(w))
		await get_tree().create_timer(0.6).timeout
		player.mesh.rotation.y = 0.0
		var fwd: Vector3 = -player.mesh.global_transform.basis.z
		var right: Vector3 = player.mesh.global_transform.basis.x
		var p := player.global_position
		cam.global_position = p + fwd * 3.2 + right * 1.6 + Vector3(0, 1.6, 0)
		cam.look_at(p + Vector3(0, 1.0, 0))
		light.global_position = p + fwd * 2.0 + Vector3(0, 2.5, 0)
		var tag := "dagas" if w == W.DAGGERS else "maza"
		await _save(tag + "_idle")
		player.resources.energy = PlayerResources.ENERGY_MAX
		player.combat_controller.attack_cooldown = 0.0
		player.attack()
		for t in [0.12, 0.2, 0.3]:
			await get_tree().create_timer(0.08 if t < 0.15 else 0.1).timeout
			player.mesh.rotation.y = 0.0
			await _save("%s_golpe_%02d" % [tag, int(t * 100)])
		await get_tree().create_timer(1.2).timeout
		player.resources.energy = PlayerResources.ENERGY_MAX
		player.combat_controller.attack_cooldown = 0.0
		cam.global_position = p + right * 4.0 + Vector3(0, 1.4, 0)
		cam.look_at(p + Vector3(0, 0.9, 0))
		if w == W.DAGGERS:
			player.global_position = p
			player.combat_controller.dagger_dash()
			await get_tree().create_timer(0.1).timeout
			await _save("dagas_embestida")
		else:
			player.combat_controller.mace_slam()
			await get_tree().create_timer(0.3).timeout
			await _save("maza_suelo_arriba")
			await get_tree().create_timer(0.27).timeout
			await _save("maza_suelo_impacto")
		await get_tree().create_timer(1.0).timeout
		player.global_position = p
	get_tree().quit(0)

func _save(tag: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s_%s.png" % [_prefix, tag]
	img.save_png(path)
	print("captura guardada: ", ProjectSettings.globalize_path(path))
