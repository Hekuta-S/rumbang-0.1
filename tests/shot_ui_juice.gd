extends Node

## Captura de la fase 4 del juice (necesita ventana): contador de combo en el HUD de la mazmorra y cartas
## de elección entrando. res://tests/shot_ui_juice.tscn -- <prefijo>

var _out := "user://ui_fx"

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
	await get_tree().create_timer(2.0).timeout
	# 1. Combo en rango B
	for i in 23:
		ComboCounter.register_hit(false)
		await get_tree().create_timer(0.03).timeout
	await get_tree().create_timer(0.1).timeout
	await _shot("combo")
	# 2. Cartas entrando (a mitad y al final)
	var opts := [
		{"id": "a", "title": "Fuerza", "desc": "+20% daño cuerpo a cuerpo", "color": Color(1.0, 0.5, 0.3)},
		{"id": "b", "title": "Agilidad", "desc": "Volteretas más largas", "color": Color(0.4, 0.9, 1.0)},
		{"id": "c", "title": "Vigor", "desc": "+15 vida máxima", "color": Color(0.5, 1.0, 0.5)},
	]
	DungeonChoiceUI.present(scene, "Elige una bendición", "Prueba de captura", opts)
	await get_tree().create_timer(0.12, true, false, true).timeout
	await _shot("cards_mid")
	await get_tree().create_timer(0.6, true, false, true).timeout
	await _shot("cards_end")
	get_tree().quit(0)

func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s_%s.png" % [_out, tag])
	print("SHOT ", tag)
