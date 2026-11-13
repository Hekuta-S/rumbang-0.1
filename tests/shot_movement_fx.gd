extends Node

## Captura de la fase 3 del juice (necesita ventana): voltereta con fantasmas, esquiva perfecta y líneas
## de velocidad. res://tests/shot_movement_fx.tscn -- <prefijo>

var _out := "user://move_fx"

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	GameData.game_mode = "dungeon"
	Quality._level = 2   # alta: en baja no hay líneas de velocidad y solo un fantasma
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
	player.global_position = enc.map.room_center(enc.map.arena_index) + Vector3(0, 0.3, 0)
	await get_tree().create_timer(2.0).timeout
	var mc = player.movement_controller
	# 1. Voltereta normal
	mc.perform_dodge()
	await get_tree().create_timer(0.2).timeout
	await _shot("dodge")
	await get_tree().create_timer(1.0).timeout
	# 2. Esquiva perfecta
	mc._dodge_cooldown_timer = 0.0
	mc.perform_dodge()
	await get_tree().physics_frame
	player.take_damage(5.0, Vector3.FORWARD)
	await get_tree().create_timer(0.12, true, false, true).timeout
	await _shot("perfect")
	await get_tree().create_timer(1.5, true, false, true).timeout
	# 3. Líneas de velocidad (forzadas)
	for c in player.get_children():
		if c is CameraController:
			c.set_physics_process(false)
	HitFeedback.speed_lines(1.0)
	await get_tree().create_timer(0.1).timeout
	await _shot("lines")
	get_tree().quit(0)

func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s_%s.png" % [_out, tag])
	print("SHOT ", tag)
