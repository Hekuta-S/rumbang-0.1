extends Node

## Captura de la bolsa de supervivencia (necesita ventana): res://tests/shot_bag.tscn -- <archivo.png>
var _out := "user://bolsa.png"

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	GameData.game_mode = "survival"
	SaveManager.save_path = "user://test_save.json"
	SaveManager.meta = {}
	var scene: Node = load("res://scenes/core/main_procedural.tscn").instantiate()
	get_tree().root.add_child.call_deferred(scene)
	_run.call_deferred(scene)

func _run(scene: Node) -> void:
	await get_tree().process_frame
	get_tree().current_scene = scene
	var p = null
	for i in 900:
		await get_tree().process_frame
		p = scene.get_node_or_null("Player")
		if p and p.weapon_inventory and not p.weapon_inventory.weapon_slots.is_empty():
			break
	for t in ["poder", "zancada"]:
		p.stat_block.add_tome(t, 0)
	for it in ["botas_caminante", "botas_caminante", "pluma_condor"]:
		p.inventory.add_item(it)
	var hud = get_tree().get_first_node_in_group("hud")
	hud.bag.set_collapsed(false)
	await get_tree().create_timer(1.0).timeout
	get_viewport().get_texture().get_image().save_png(_out)
	print("guardado ", ProjectSettings.globalize_path(_out))
	get_tree().quit()
