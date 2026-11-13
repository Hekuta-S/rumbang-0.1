extends Node

## Capturas de las poses de los clips del arco sobre Riva en la mazmorra (necesita ventana, no headless):
##   res://tests/shot_bow.tscn -- <prefijo>
## Para cada clip (combo bow_shot_1/2/3, tensado bow_charge_draw/hold y suelta bow_charge_release) congela varios
## instantes clave (antes, en y después de soltar la cuerda) y guarda <prefijo>_<clip>_<ms>_<vista>.png, de lado y a
## tres cuartos por delante.

var _prefix := "user://bow"
var _player: CharacterBody3D

const POSES := {
	"bow_shot_1": [0.0, 0.133, 0.167, 0.233, 0.4],
	"bow_shot_2": [0.0, 0.167, 0.233, 0.4, 0.533],
	"bow_shot_3": [0.0, 0.2, 0.267, 0.333, 0.5],
	"bow_charge_draw": [0.0, 0.2, 0.5],
	"bow_charge_hold": [0.33, 0.66],
	"bow_charge_release": [0.067, 0.167, 0.333, 0.567],
}

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_prefix = args[0]
	_run()

func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _run() -> void:
	GameData.game_mode = "dungeon"
	SaveManager.save_path = "user://test_save.json"
	var scene: Node = load("res://scenes/core/main_dungeon.tscn").instantiate()
	get_tree().root.add_child.call_deferred(scene)
	await get_tree().process_frame
	get_tree().current_scene = scene
	var enc: DungeonEncounter
	for i in 600:
		await get_tree().process_frame
		enc = scene.get_node_or_null("DungeonEncounter")
		if enc and enc.map and is_instance_valid(enc.player):
			break
	enc._pending.clear()
	_player = enc.player
	_player.health_comp.max_hp = 9999.0
	_player.health_comp.hp = 9999.0
	_player.global_position = enc.map.room_center(enc.map.arena_index) + Vector3(0, 0.3, 0)
	var W := WeaponData.WeaponType.BOW
	if not _player.weapon_slots.has(W):
		_player.add_weapon(W)
	_player.select_slot(_player.weapon_slots.find(W))
	await _wait(3.0)   # que acabe el brillo de aparición (SpawnDissolve)
	for c in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(c as CanvasLayer).visible = false
	_player.set_physics_process(false)
	var ac: PlayerAnimationController = _player.animation_controller
	var vis = _player.weapon_visuals
	var light := OmniLight3D.new()
	light.omni_range = 8.0
	light.light_energy = 2.5
	scene.add_child(light)
	var cam := Camera3D.new()
	cam.fov = 35.0
	scene.add_child(cam)
	cam.current = true
	var fwd: Vector3 = -_player.mesh.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP)
	var chest: Vector3 = _player.global_position + Vector3(0, 1.0, 0)
	light.global_position = chest + right * 1.5 + fwd * 1.5 + Vector3.UP
	ac.anim_tree.active = false
	for clip in POSES:
		if not ac.anim_player.has_animation(clip):
			push_error("Falta el clip %s" % clip)
			continue
		var rel := WeaponStrategy.BowStrategy.release_time(clip) if clip in PlayerAnimationController.BOW_ACTIONS else 99.0
		for t in POSES[clip]:
			ac.anim_player.play(clip)
			ac.anim_player.seek(t, true)
			ac.anim_player.pause()
			vis.set_bow_draw(1.0 if t < rel else -1.0)
			for view in [["lado", right * 3.4 + Vector3(0, 0.25, 0)], ["frente", fwd * 2.6 - right * 1.6 + Vector3(0, 0.45, 0)]]:
				cam.global_position = chest + view[1]
				cam.look_at(chest, Vector3.UP)
				for i in 3:
					await get_tree().process_frame
				var img := get_viewport().get_texture().get_image()
				img.save_png("%s_%s_%03d_%s.png" % [_prefix, clip, int(round(t * 1000.0)), view[0]])
	print("SHOTS DONE")
	get_tree().quit(0)
