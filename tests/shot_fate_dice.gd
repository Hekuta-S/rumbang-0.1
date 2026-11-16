extends Node

## Capturas del dado del destino y de los recogibles cartoon (necesita ventana):
##   res://tests/shot_fate_dice.tscn -- <prefijo>
## Supervivencia: dado y los cuatro recogibles delante de la cámara (<prefijo>_objetos.png), la pregunta
## (<prefijo>_pregunta.png), el dado en el aire (<prefijo>_tirada.png) y el resultado (<prefijo>_resultado.png).

var _prefix := "user://dado"
var _main: Node

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_prefix = args[0]
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
	p.health_comp.max_hp = 9999.0
	p.health_comp.hp = 9999.0
	await get_tree().create_timer(1.0).timeout
	var c := p.global_position
	var fwd := Vector3(0, 0, -1)
	var side := Vector3(1, 0, 0)
	var ev: RunEvents = waves.events
	var dice := FateDice.spawn(_main, ev._ground(c + fwd * 6.0 + side * 0.0))
	var kinds := ["bomb", "magnet", "food", "clock"]
	for i in kinds.size():
		MapPickup.spawn(_main, ev._ground(c + fwd * 4.0 + side * (-3.6 + 2.4 * i) + (fwd * 2.5 if i % 3 != 0 else Vector3.ZERO)), kinds[i])
	var cam := Camera3D.new()
	cam.fov = 55.0
	_main.add_child(cam)
	cam.look_at_from_position(c + Vector3(0, 3.0, 3.5), c + fwd * 5.0 + Vector3(0, 0.9, 0))
	cam.current = true
	p.visible = false
	dice.player = null
	await get_tree().create_timer(0.8).timeout
	# de frente para la captura (los recogibles giran solos)
	for pk in get_tree().get_nodes_in_group("map_pickups"):
		pk.set_process(false)
		pk._holder.rotation.y = 0.0
	await _save("_objetos")
	dice.ask()
	await get_tree().create_timer(1.4, true, false, true).timeout
	await _save("_pregunta")
	for n in get_tree().root.find_children("*", "DungeonChoiceUI", true, false):
		n.queue_free()
	get_tree().paused = false
	dice._asking = false
	dice.roll(6)
	await get_tree().create_timer(0.45).timeout
	await _save("_tirada")
	await get_tree().create_timer(1.3).timeout
	await _save("_resultado")
	get_tree().quit(0)

func _save(suffix: String) -> void:
	await RenderingServer.frame_post_draw
	var path := _prefix + suffix + ".png"
	get_viewport().get_texture().get_image().save_png(path)
	print("captura guardada: ", ProjectSettings.globalize_path(path))
