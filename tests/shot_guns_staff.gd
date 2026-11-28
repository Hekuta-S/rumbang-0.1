extends Node

## Capturas de la pistola, el fusil y el bastón de fuego en la mano (necesita ventana, no headless):
##   res://tests/shot_guns_staff.tscn -- <ruta.png>
## Una hoja de 3×2: arriba cada arma en reposo a tres cuartos, abajo en pleno disparo/lanzamiento.

const CELL := Vector2i(420, 480)
var _out := "user://guns_staff.png"
var _player: CharacterBody3D
var _enc: DungeonEncounter

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	_run.call_deferred()

func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _run() -> void:
	GameData.game_mode = "dungeon"
	SaveManager.save_path = "user://test_save.json"
	var scene: Node = load("res://scenes/core/main_dungeon.tscn").instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	for i in 600:
		await get_tree().process_frame
		_enc = scene.get_node_or_null("DungeonEncounter")
		if _enc and _enc.map and is_instance_valid(_enc.player):
			break
	_enc._pending.clear()
	for e in EnemyRegistry.all():
		if is_instance_valid(e) and e is Node:
			EnemyRegistry.unregister(e)
			e.queue_free()
	_player = _enc.player
	_player.health_comp.max_hp = 9999.0
	_player.health_comp.hp = 9999.0
	_player.global_position = _enc.map.room_center(_enc.map.arena_index) + Vector3(0, 0.3, 0)
	get_window().size = CELL
	await _wait(1.0)
	var cam := Camera3D.new()
	cam.fov = 40.0
	scene.add_child(cam)
	var sheet := Image.create(CELL.x * 3, CELL.y * 2, false, Image.FORMAT_RGBA8)
	var W := WeaponData.WeaponType
	var list := [W.PISTOL, W.RIFLE, W.FIRE_STAFF]
	for i in list.size():
		var w: int = list[i]
		var slots: Array = _player.weapon_inventory.weapon_slots
		if not slots.has(w):
			slots[0] = w
			_player.combat_controller.weapon_slots = slots
		_player.select_slot(_player.weapon_slots.find(w))
		_player.mesh.rotation.y = 0.0
		await _wait(0.8)
		for row in 2:
			_player.mesh.rotation.y = 0.0
			var f: Vector3 = -_player.mesh.global_transform.basis.z
			var r: Vector3 = _player.mesh.global_transform.basis.x
			var c: Vector3 = _player.global_position + Vector3(0, 1.15, 0)
			cam.global_position = c + f * 2.3 + r * 1.5 + Vector3(0, 0.25, 0)
			cam.look_at(c, Vector3.UP)
			cam.current = true
			if row == 1:
				_player.combat_controller.attack_cooldown = 0.0
				_player.combat_controller.attack()
				_player.mesh.rotation.y = 0.0
				await _wait(0.1 if w != W.FIRE_STAFF else 0.28)
			else:
				await _wait(0.3)
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			img.resize(CELL.x, CELL.y)
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i(i * CELL.x, row * CELL.y))
			await _wait(0.6)
	sheet.save_png(_out)
	print("SAVED ", _out)
	get_tree().quit(0)
