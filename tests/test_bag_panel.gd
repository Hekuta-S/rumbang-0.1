extends Node

## Supervivencia (partida real): se pueden llevar 5 armas (y no 6), y la bolsa del HUD muestra los tomos
## y los objetos recogidos (objetos repetidos en una sola casilla con su número).
const W := WeaponData.WeaponType
var _fail := false
var _n := 0

func _check(ok: bool, msg: String) -> void:
	_n += 1
	print("CHECK %d %s: %s" % [_n, "PASSED" if ok else "FAILED", msg])
	if not ok:
		_fail = true

func _ready() -> void:
	GameData.game_mode = "survival"
	SaveManager.save_path = "user://test_save.json"   # no tocar la partida guardada real
	SaveManager.meta = {}
	var scene: Node = load("res://scenes/core/main_procedural.tscn").instantiate()
	get_tree().root.add_child.call_deferred(scene)
	await get_tree().process_frame
	get_tree().current_scene = scene
	var p = null
	for i in 600:
		await get_tree().process_frame
		p = scene.get_node_or_null("Player")
		if p and p.weapon_inventory and not p.weapon_inventory.weapon_slots.is_empty():
			break
	p.health_comp.max_hp = 99999.0
	p.health_comp.hp = 99999.0
	GameState.get_instance().reset_session()
	var winv = p.weapon_inventory
	winv.weapon_slots.clear()
	winv.reset_progress()

	# 5 armas sí, la sexta no
	for w in [W.SPEAR_LANCE, W.SPINNING_AXE, W.FLAME_THROWER, W.DAGGERS, W.MACE]:
		p.add_weapon(w)
	_check(winv.weapon_slots.size() == 5, "caben 5 armas (%d)" % winv.weapon_slots.size())
	_check(not winv.add_weapon(W.BOW) and winv.weapon_slots.size() == 5, "la sexta no entra")
	var ui_script := load("res://scripts/ui/upgrade_choice_ui.gd")
	var hands_ok := true
	for i in 10:
		if ui_script.build_choices(p).any(func(c): return c["type"] == "new_weapon"):
			hands_ok = false
	_check(hands_ok, "con 5 armas no salen cartas de arma nueva")

	# Bolsa: tomos y objetos
	var hud = get_tree().get_first_node_in_group("hud")
	var bag: BagPanel = hud.bag if hud else null
	_check(bag != null and bag.is_inside_tree(), "la bolsa existe en el HUD de supervivencia")
	p.stat_block.add_tome("poder", 0)
	p.stat_block.add_tome("zancada", 0)
	p.inventory.add_item("botas_caminante")
	p.inventory.add_item("botas_caminante")
	p.inventory.add_item("pluma_condor")
	await get_tree().process_frame
	_check(bag.tome_count() == 2, "bolsa: 2 tomos (%d)" % bag.tome_count())
	_check(bag.item_count() == 2, "bolsa: 2 casillas de objeto, las botas repetidas juntas (%d)" % bag.item_count())
	var r := bag.get_global_rect()
	var vp := get_viewport().get_visible_rect().size
	_check(r.end.x <= vp.x + 1.0 and r.position.x > vp.x * 0.5, "la bolsa está a la derecha (%s)" % [r])

	GameState.get_instance().reset_session()
	print("ALL BAG CHECKS PASSED" if not _fail else "BAG CHECKS FAILED")
	get_tree().quit(1 if _fail else 0)
