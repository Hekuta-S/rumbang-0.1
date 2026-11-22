extends Node

## Cartas de subida de nivel (design/ux/level-up-cards.md) con la partida real:
##  1. cada carta lleva imagen (TextureRect), y la de arma nueva que sube una sinergia, su fila "Potencia a";
##  2. la tira "Tu equipo" tiene tus armas y la barra de la etiqueta activa;
##  3. mantener la carta muestra el detalle y al soltar NO elige; un toque corto sí elige;
##  4. el HUD muestra la insignia de la sinergia activa.
const W := WeaponData.WeaponType
var _fail := false
var _n := 0

func _check(ok: bool, msg: String) -> void:
	_n += 1
	print("CHECK %d %s: %s" % [_n, "PASSED" if ok else "FAILED", msg])
	if not ok:
		_fail = true

func _press(btn: Button, down: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = down
	btn.gui_input.emit(ev)

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
	p.add_weapon(W.SPEAR_LANCE)

	# Mano fija: arma nueva de Filo (sube Filo 1→2), un tomo y una mejora de la lanza
	var ui = load("res://scenes/ui/upgrade_choice_ui.tscn").instantiate()
	scene.add_child(ui)
	var ui_mgr = scene.find_child("UIManager", true, false)
	ui.choice_made.connect(ui_mgr._on_upgrade_choice_made)     # como lo hace UIManager con la suya
	await get_tree().process_frame
	ui.present_choices(p)
	ui._choices = [
		{"type": "new_weapon", "weapon": W.SPINNING_AXE},
		{"type": "tome", "weapon": -1, "upgrade_id": "zancada", "rarity": 0},
		{"type": "upgrade", "weapon": W.SPEAR_LANCE},
	]
	ui._refresh()
	await get_tree().process_frame
	var cards: Array = []
	for col in ui.container.get_children():
		cards.append(col.get_child(0))
	_check(cards.all(func(b): return not b.find_children("*", "TextureRect", true, false).is_empty()),
		"las 3 cartas llevan imagen")
	var axe_links: Array = cards[0].get_meta("links", [])
	_check(not axe_links.is_empty() and axe_links[0]["tags"] == ["filo"], "arma nueva: fila Potencia a con Filo (%s)" % [axe_links])
	_check(ui._strip_nodes.has("w:%d" % W.SPEAR_LANCE), "Tu equipo: la lanza está en la tira")

	# Mantener = detalle, sin elegir
	_press(cards[1], true)
	await get_tree().create_timer(ui.HOLD_S + 0.15, true).timeout
	_check(is_instance_valid(ui._detail), "mantener muestra el detalle")
	_press(cards[1], false)
	cards[1].pressed.emit()                    # el botón emite pressed al soltar
	await get_tree().process_frame
	_check(get_tree().paused and ui.visible and not is_instance_valid(ui._detail), "al soltar se cierra el detalle y NO se elige")

	# Toque corto = elige (arma nueva: hacha → Filo 2)
	_press(cards[0], true)
	_press(cards[0], false)
	cards[0].pressed.emit()
	await get_tree().process_frame
	_check(not get_tree().paused and winv.weapon_slots.has(W.SPINNING_AXE), "un toque corto elige la carta")

	# HUD: insignia de Filo activa
	await get_tree().process_frame
	var hud = get_tree().get_first_node_in_group("hud")
	var row = hud._synergy_row if hud else null
	_check(row != null and row.get_child_count() == 1 and hud._synergy_tiers.get("filo", 0) == 1,
		"HUD: insignia de la sinergia Filo (%s)" % [hud._synergy_tiers if hud else "sin HUD"])

	GameState.get_instance().reset_session()
	print("ALL LEVEL UP CARD CHECKS PASSED" if not _fail else "LEVEL UP CARD CHECKS FAILED")
	get_tree().quit(1 if _fail else 0)
