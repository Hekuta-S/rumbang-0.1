extends Node

## Capturas del equipo (necesita ventana, no headless): res://tests/shot_equipment.tscn -- <carpeta>
## Guarda equip_forja.png (Tatan en la forja), equip_tienda.png (la tienda), equip_panel.png
## (pausa > EQUIPO) y equip_hud.png (tira del HUD y una pieza en el suelo). No toca la partida guardada.

var _dir := "user://"
var _main: Node

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_dir = args[0].trim_suffix("/") + "/"
	SaveManager.save_path = "user://shot_equipment_save.json"
	SaveManager.meta = {}
	GameData.armory_path = "user://shot_equipment_armeria.cfg"
	GameData.game_mode = "dungeon"
	_main = (load(Net.game_scene()) as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(_main)
	_run.call_deferred()

func _shot(file: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(_dir + file)
	print("captura: ", ProjectSettings.globalize_path(_dir + file))

func _run() -> void:
	await get_tree().process_frame
	get_tree().current_scene = _main
	await get_tree().create_timer(4.0).timeout
	var enc: DungeonEncounter = _main.get_node("DungeonEncounter")
	enc._pending.clear()
	var map: DungeonMap = _main.get_node("ProceduralMap")
	var p = _main.get_node("Player")
	var eq: PlayerEquipment = p.equipment
	var c := map.room_center(map.arena_index)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	eq.receive(EquipmentDB.roll("casco", 2, rng))
	eq.receive(EquipmentDB.roll("pechera", 3, rng))
	eq.receive(EquipmentDB.roll("talisman", 4, rng))
	eq.receive(EquipmentDB.roll("casco", 1, rng))
	eq.receive(EquipmentDB.roll("pantalones", 0, rng))
	eq.receive(EquipmentDB.roll("talisman", 2, rng))
	eq.receive(EquipmentDB.roll("talisman", 3, rng))
	EquipmentPickup.spawn(_main, c + Vector3(3.0, 0.0, 0.0), EquipmentDB.roll("pechera", 4, rng))
	var shop := DungeonShop.spawn(_main, c + Vector3(0.0, 0.0, -4.0), p, 3)
	p.global_position = c + Vector3(2.2, 0.3, 2.5)
	p.look_at(shop.global_position, Vector3.UP)
	await get_tree().create_timer(2.0).timeout
	await _shot("equip_forja.png")
	await _shot("equip_hud.png")
	GameState.get_instance().gold = 400
	shop.open()
	await get_tree().create_timer(0.5).timeout
	await _shot("equip_tienda.png")
	shop._ui._close()
	var pm = _main.find_child("PauseMenu", true, false)
	pm.open_menu()
	pm.open_equipment()
	await get_tree().create_timer(0.5).timeout
	await _shot("equip_panel.png")
	# Tarjeta de información: ratón sobre una pieza de la mochila (equip_tarjeta.png) y sobre la pechera equipada
	var panel: EquipmentPanel = pm.find_child("*", true, false) as EquipmentPanel if false else null
	for n in get_tree().root.find_children("*", "Control", true, false):
		if n is EquipmentPanel:
			panel = n
	if panel:
		panel._bag_plate.sockets[0].mouse_entered.emit()
		await get_tree().create_timer(0.5).timeout
		await _shot("equip_tarjeta_mochila.png")
		panel._bag_plate.sockets[0].mouse_exited.emit()
		panel._plate.sockets[1].mouse_entered.emit()
		await get_tree().create_timer(0.5).timeout
		await _shot("equip_tarjeta_pechera.png")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://shot_equipment_save.json"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://shot_equipment_armeria.cfg"))
	get_tree().quit(0)
