extends Node

## Fase 2 del plan de mejora (supervivencia): etiquetas y sinergias de arma, evoluciones y las
## cartas de mejora con volver a tirar / bloquear / descartar. Carga la partida real.

const W := WeaponData.WeaponType

func _ready() -> void:
	print("--- TEST: SINERGIAS Y EVOLUCIONES ---")
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
	assert(p != null, "La partida crea al jugador")
	p.health_comp.max_hp = 99999.0
	p.health_comp.hp = 99999.0
	var winv: PlayerWeaponInventory = p.weapon_inventory
	GameState.get_instance().reset_session()
	# Mano controlada: solo la espalanza
	winv.weapon_slots.clear()
	winv.reset_progress()
	p.add_weapon(W.SPEAR_LANCE)

	# 1. Etiquetas y sinergias
	var base: float = p.get_weapon_modifiers(W.SPEAR_LANCE)["damage"]
	assert(WeaponSynergies.active(winv.weapon_slots).is_empty(), "Con un arma no hay sinergias")
	p.add_weapon(W.SPINNING_AXE)                       # 2 de filo
	var two: Dictionary = p.get_weapon_modifiers(W.SPEAR_LANCE)
	assert(absf(float(two["damage"]) - base - 0.15) < 0.001, "Filo ×2: +15%% daño (%.2f → %.2f)" % [base, two["damage"]])
	var flame: float = p.get_weapon_modifiers(W.FLAME_THROWER)["damage"]
	p.add_weapon(W.ZOMBIE_ARM)                         # 3 de filo
	var three: Dictionary = p.get_weapon_modifiers(W.SPEAR_LANCE)
	assert(int(three["quantity_bonus"]) == int(two["quantity_bonus"]) + 1, "Filo ×3: +1 golpe")
	assert(float(three["size"]) > float(two["size"]), "Filo ×3: más tamaño")
	assert(is_equal_approx(float(p.get_weapon_modifiers(W.FLAME_THROWER)["damage"]), flame), "La sinergia no toca armas de otra etiqueta")
	var act := WeaponSynergies.active(winv.weapon_slots)
	assert(act[0]["tag"] == "filo" and act[0]["tier"] == 2, "Filo activa en su segundo nivel")
	print("CHECK 1 PASSED: %s" % WeaponSynergies.describe(act[0]))

	# 2. Vista previa en la carta de arma nueva
	var prev := WeaponSynergies.preview_new_weapon([W.FLAME_THROWER], W.ELEMENTS_CYCLE)
	assert(prev.size() == 1 and prev[0].contains("Fuego"), "Coger el ciclo elemental con el lanzallamas activa Fuego (%s)" % [prev])
	print("CHECK 2 PASSED: vista previa \"%s\"" % prev[0])

	# 3. Evolución: nivel + catalizador → carta EVOLUCIÓN primero; al elegirla, mods y nombre nuevos
	assert(not WeaponSynergies.can_evolve(winv, p.inventory, W.SPEAR_LANCE), "Sin nivel ni catalizador no evoluciona")
	for i in WeaponSynergies.EVOLVE_LEVEL:
		winv.upgrade_weapon(W.SPEAR_LANCE)
	assert(not WeaponSynergies.can_evolve(winv, p.inventory, W.SPEAR_LANCE), "Sin su tomo no evoluciona")
	p.stat_block.add_tome("zancada", TomeDB.Rarity.COMMON)
	assert(WeaponSynergies.can_evolve(winv, p.inventory, W.SPEAR_LANCE), "Nivel %d + Tomo de Zancada → puede evolucionar" % winv.get_weapon_level(W.SPEAR_LANCE))
	var hand := UpgradeChoiceUI_build(p)
	assert(hand[0]["type"] == "evolution" and hand[0]["weapon"] == W.SPEAR_LANCE, "La evolución sale la primera (%s)" % [hand[0]])
	var before: Dictionary = p.get_weapon_modifiers(W.SPEAR_LANCE)
	var ui_mgr = scene.find_child("UIManager", true, false)
	if ui_mgr and ui_mgr.has_method("_on_upgrade_choice_made"):
		ui_mgr._on_upgrade_choice_made("evolution", str(W.SPEAR_LANCE))
	else:
		WeaponSynergies.evolve(winv, W.SPEAR_LANCE)
	var after: Dictionary = p.get_weapon_modifiers(W.SPEAR_LANCE)
	assert(absf(float(after["damage"]) - float(before["damage"]) - 0.6) < 0.001, "Evolucionada: +60%% daño")
	assert(int(after["quantity_bonus"]) == int(before["quantity_bonus"]) + 2, "Evolucionada: +2 cortes")
	assert(WeaponSynergies.weapon_name(winv, W.SPEAR_LANCE) == "Lanza del Trueno", "Cambia de nombre")
	assert(not UpgradeChoiceUI_build(p).any(func(c): return c["type"] == "evolution"), "No vuelve a ofrecer la evolución")
	print("CHECK 3 PASSED: evolución a %s" % WeaponSynergies.weapon_name(winv, W.SPEAR_LANCE))

	# 4. Bloquear y descartar (lógica del sorteo)
	var ui_script := load("res://scripts/ui/upgrade_choice_ui.gd")
	for i in 20:
		var h := UpgradeChoiceUI_build(p)
		var locked: Dictionary = h[h.size() - 1]
		var next: Array = ui_script.build_choices(p, [], locked)
		assert(ui_script.choice_key(next[0]) == ui_script.choice_key(locked), "La carta bloqueada vuelve la primera")
		var banned := [ui_script.choice_key(locked)]
		for j in 5:
			assert(not ui_script.build_choices(p, banned, {}).any(func(c): return ui_script.choice_key(c) == banned[0]), "La descartada no vuelve")
	print("CHECK 4 PASSED: bloquear y descartar")

	# 5. La UI: volver a tirar gasta un uso; descartar cambia solo esa carta
	var ui = load("res://scenes/ui/upgrade_choice_ui.tscn").instantiate()
	scene.add_child(ui)
	await get_tree().process_frame
	ui.present_choices(p)
	await get_tree().process_frame
	var gs := GameState.get_instance()
	var rerolls := gs.card_rerolls
	ui._on_reroll()
	assert(gs.card_rerolls == rerolls - 1, "Volver a tirar gasta un uso (%d → %d)" % [rerolls, gs.card_rerolls])
	var keep: Array = ui._choices.slice(1).map(func(c): return ui_script.choice_key(c))
	var gone: String = ui_script.choice_key(ui._choices[0])
	ui._on_banish(ui._choices[0])
	var now: Array = ui._choices.map(func(c): return ui_script.choice_key(c))
	assert(not now.has(gone) and gs.banished_cards.has(gone), "La descartada desaparece")
	for k in keep:
		assert(now.has(k), "Las otras cartas se quedan")
	assert(gs.card_banishes == GameState.CARD_BANISHES + MetaProgress.bonus_banishes() - 1, "Descartar gasta un uso")
	ui._on_card_pressed(ui._choices[0])
	assert(not get_tree().paused, "Elegir carta reanuda la partida")
	GameState.get_instance().reset_session()
	assert(gs.card_rerolls == GameState.CARD_REROLLS + MetaProgress.bonus_rerolls() and gs.banished_cards.is_empty(), "Nueva partida: usos y descartes reiniciados")
	print("CHECK 5 PASSED: volver a tirar, descartar y reinicio por partida")

	# 6. Tomos: salen como carta, se aplican con su rareza y respetan los 4 huecos
	GameState.get_instance().reset_session()
	var saw_tome := false
	for i in 40:
		if UpgradeChoiceUI_build(p).any(func(c): return c["type"] == "tome"):
			saw_tome = true
			break
	assert(saw_tome, "Las cartas de tomo salen en el sorteo")
	var dmg0: float = p.stat_block.damage_mult()
	ui_mgr._on_upgrade_choice_made("tome", "poder:%d" % TomeDB.Rarity.EPIC)
	assert(is_equal_approx(p.stat_block.damage_mult(), dmg0 + 0.08 * 2.0), "Tomo de Poder épico: +16%% daño (%.3f → %.3f)" % [dmg0, p.stat_block.damage_mult()])
	var hp0: float = p.max_hp
	ui_mgr._on_upgrade_choice_made("tome", "vitalidad:%d" % TomeDB.Rarity.RARE)
	assert(is_equal_approx(p.max_hp, hp0 + 15.0 * 1.5), "Vitalidad rara: +22,5 vida máxima")
	for id in ["celeridad", "area", "iman"]:
		ui_mgr._on_upgrade_choice_made("tome", "%s:0" % id)
	assert(TomeDB.owned().size() == TomeDB.SLOTS, "Cuatro tomos ocupan los huecos")
	for i in 20:
		for c in UpgradeChoiceUI_build(p):
			if c["type"] == "tome":
				assert(TomeDB.level(c["upgrade_id"]) > 0, "Con los huecos llenos solo salen tomos que ya tienes")
	print("CHECK 6 PASSED: tomos")

	print("ALL SYNERGY CHECKS PASSED")
	get_tree().quit(0)

func UpgradeChoiceUI_build(p) -> Array:
	return load("res://scripts/ui/upgrade_choice_ui.gd").build_choices(p)
