extends Node

## Captura de las criaturas de las cloacas (EnemyData dibujados como sprites; necesita ventana):
## res://tests/shot_critters.tscn -- <prefijo>   -> <prefijo>_critters.png (cámara del juego, jugador de testigo)
var _prefix := "user://critters"

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_prefix = args[0]
	GameData.game_mode = "survival"
	var main: Node = (load("res://scenes/core/main_procedural.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	get_tree().current_scene = main
	await get_tree().create_timer(4.0).timeout
	var waves: WaveManager = main.find_child("WaveManager", true, false)
	var p: Node3D = main.get_node("Player")
	waves.stop_run()
	for e in EnemyRegistry.all().duplicate():
		if e is EnemyData and not e.recycled:
			e.take_damage(1.0e9, Vector3.ZERO)
	var base := p.global_position
	var kinds := ["rat", "slug", "bloater", "rat_big", "rat", "slug"]
	for i in kinds.size():
		var pack: Array = waves.spawn_critter_pack(kinds[i], base + Vector3(-6.0 + 2.4 * i, 0.0, -7.0))
		for e: EnemyData in pack:
			e.speed = 0.0                       # quietos para la foto (siguen animando el reposo)
			EnemyManager.mark_dirty(e)
	await get_tree().create_timer(1.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_prefix + "_critters.png")
	print("guardado")
	get_tree().quit()
