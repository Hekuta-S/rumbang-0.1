extends Node

## Captura de los enemigos IMPOSTORES (sprites 2D de móvil) de cerca (necesita ventana):
##   RUMBANG_FORCE_MOBILE=1 godot --path . res://tests/shot_impostors.tscn -- <archivo.png>
## Supervivencia con un corro de enemigos de los cuatro tipos alrededor del jugador.

var _out := "user://impostores.png"
var _main: Node

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	GameData.game_mode = "survival"
	SaveManager.save_path = "user://test_save.json"
	_main = load("res://scenes/core/main_procedural.tscn").instantiate()
	get_tree().root.add_child.call_deferred(_main)
	_run.call_deferred()

func _run() -> void:
	await get_tree().process_frame
	get_tree().current_scene = _main
	var p: Node3D = null
	var waves: WaveManager = null
	for i in 900:
		await get_tree().process_frame
		p = _main.get_node_or_null("Player")
		waves = _main.find_child("WaveManager", true, false)
		if p and waves and waves._running:
			break
	waves.stop_run()
	waves._running = true
	waves.set_process(false)
	waves.events.set_process(false)
	p.health_comp.max_hp = 99999.0
	p.health_comp.hp = 99999.0
	await get_tree().create_timer(0.5).timeout
	var c := p.global_position
	var types := [EnemyData.EnemyType.NORMAL_GOBLIN, EnemyData.EnemyType.HEAVY_BRUTE, EnemyData.EnemyType.GOBLIN_RANGED, EnemyData.EnemyType.ZOMBIE_GOBLIN]
	for i in 12:
		var a := -PI * 0.15 - PI * 0.7 * float(i) / 11.0
		var pos := waves.events._ground(c + Vector3(cos(a), 0, sin(a)) * (5.0 + 1.6 * (i % 2)))
		waves._spawn_single_enemy(pos, types[i % types.size()])
	await get_tree().create_timer(0.8).timeout
	var cam := Camera3D.new()
	cam.fov = 50.0
	_main.add_child(cam)
	cam.look_at_from_position(c + Vector3(0, 4.0, 4.5), c + Vector3(0, 0.8, -4.0))
	cam.current = true
	print("impostores: ", Quality.use_impostors())
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out)
	print("captura guardada: ", ProjectSettings.globalize_path(_out))
	get_tree().quit(0)
