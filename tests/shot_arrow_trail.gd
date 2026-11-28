extends Node

## Estela de la flecha del arco en vuelo (necesita ventana, no headless):
##   res://tests/shot_arrow_trail.tscn -- <prefijo>
## Riva dispara en la mazmorra una flecha normal, la flecha potente (3.er disparo) y una cargada contra un enemigo a
## 14 m; una cámara de lado guarda 6 fotogramas de cada una en <prefijo>_<tipo>.png (incluye el impacto, para ver
## que la cola se apaga sola en vez de desaparecer).

var _prefix := "user://arrow_trail"
var _player: CharacterBody3D
var _enc: DungeonEncounter
const CELL := Vector2i(480, 300)

func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_prefix = args[0]
	GameData.game_mode = "dungeon"
	SaveManager.save_path = "user://test_save.json"
	GameData.selected_index = GameData.custom_index()
	var scene: Node = load("res://scenes/core/main_dungeon.tscn").instantiate()
	get_tree().root.add_child.call_deferred(scene)
	await get_tree().process_frame
	get_tree().current_scene = scene
	for i in 600:
		await get_tree().process_frame
		_enc = scene.get_node_or_null("DungeonEncounter")
		if _enc and _enc.map and is_instance_valid(_enc.player):
			break
	_enc._pending.clear()
	_player = _enc.player
	_player.health_comp.max_hp = 9999.0
	_player.health_comp.hp = 9999.0
	_player.global_position = _enc.map.room_center(_enc.map.arena_index) + Vector3(0, 0.3, 0)
	await _wait(0.5)
	var W := WeaponData.WeaponType.BOW
	if not _player.weapon_slots.has(W):
		_player.add_weapon(W)
	_player.select_slot(_player.weapon_slots.find(W))
	await _wait(0.6)

	var f: Vector3 = -_player.mesh.global_transform.basis.z
	f.y = 0.0
	f = f.normalized()
	var right := Vector3(-f.z, 0, f.x)
	var g := _enc._spawn_at(_enc.map.arena_index, _player.global_position + f * 14.0)
	g.global_position = _player.global_position + f * 14.0
	g.max_hp = 99999.0
	g.hp = 99999.0
	g.set_physics_process(false)
	_player.get("target_lock")._set_target(g)

	var cam := Camera3D.new()
	cam.fov = 50.0
	get_tree().current_scene.add_child(cam)
	cam.global_position = _player.global_position + f * 7.0 + right * 9.0 + Vector3(0, 2.0, 0)
	cam.look_at(_player.global_position + f * 7.0 + Vector3(0, 1.2, 0))
	cam.current = true
	get_viewport().size = CELL

	var bow = _player.combat_controller._strategies[W]
	for kind in ["normal", "potente", "cargada"]:
		_player.resources.energy = PlayerResources.ENERGY_MAX
		_player.combat_controller.attack_cooldown = 0.0
		if kind == "cargada":
			bow.start_charge()
			await _wait(1.1)
			bow.release_charge()
		else:
			if kind == "potente":
				bow._chain = 2
				bow._last_shot = Time.get_ticks_msec() / 1000.0
			_player.combat_controller.attack()
		# Espera a que salga la flecha y captura su vuelo
		for i in 90:
			await get_tree().physics_frame
			if not get_tree().root.find_children("*", "BowArrow", true, false).is_empty():
				break
		var sheet := Image.create(CELL.x * 3, CELL.y * 2, false, Image.FORMAT_RGBA8)
		for i in 6:
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i((i % 3) * CELL.x, (i / 3) * CELL.y))
			await _wait(0.06)
		var path := "%s_%s.png" % [_prefix, kind]
		sheet.save_png(path)
		print("SHOT ", ProjectSettings.globalize_path(path))
		await _wait(1.2)
	get_tree().quit(0)
