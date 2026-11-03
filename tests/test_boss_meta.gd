extends Node

## Fase 5 del plan de mejora: jefes en tres fases (cataclismo, cambio de fase con cartel y remate
## final de rodillas) y progresión entre partidas (logros, códice y menú). Carga la mazmorra real.

func _ready() -> void:
	print("--- TEST: JEFES Y PROGRESIÓN ---")
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveManager.save_path = "user://test_save.json"   # no tocar la partida guardada real
	SaveManager.meta = {}
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
	var p = enc.player
	p.health_comp.max_hp = 99999.0
	p.health_comp.hp = 99999.0
	var c := enc.map.room_center(enc.map.arena_index)
	p.global_position = c + Vector3(0, 0.3, 0)

	# 1. Cataclismo: solo en la tercera fase
	var n := enc.spawn_necromancer()
	await get_tree().physics_frame
	assert(n.attacks.has("cataclysm"), "El jefe tiene el cataclismo")
	n._clock = 1000.0
	var seen := false
	for i in 300:
		seen = seen or n._choose_attack(3.0) == "cataclysm"
	assert(not seen, "En la fase 1 no hay cataclismo")
	n.phase = 2
	for i in 300:
		seen = seen or n._choose_attack(3.0) == "cataclysm"
		n._atk_ready.clear()
	assert(seen, "En la fase 3 sí")
	assert(DungeonGoblin.guard_kind(n.attacks["cataclysm"]) == "dodge", "El cataclismo solo se esquiva")
	n.phase = 0
	print("CHECK 1 PASSED: cataclismo en la fase 3")

	# 2. Cambio de fase: cartel "FASE 2" y rugido
	n._set_state(DungeonGoblin.State.APPROACH)
	n.take_damage(n.max_hp * 0.4, Vector3.ZERO)
	for i in 3:
		await get_tree().physics_frame
	assert(n.phase == 1 and n._atk_name == "roar", "Al bajar del 66 % ruge (fase %d, %s)" % [n.phase, n._atk_name])
	var banner := false
	for ch in n._bar_layer.get_children():
		banner = banner or (ch is Label and (ch as Label).text == "FASE 2")
	assert(banner, "Cartel FASE 2")
	print("CHECK 2 PASSED: cambio de fase con cartel")

	# 3. Remate final: de rodillas al 6 % y un remate lo mata
	while n.state == DungeonGoblin.State.WINDUP or n.state == DungeonGoblin.State.ATTACK or n.is_immune():
		await get_tree().physics_frame
	n.hp = n.max_hp * 0.1
	n.take_damage(n.max_hp * 0.05, Vector3.ZERO)
	assert(not n.is_dead() and n.state == DungeonGoblin.State.STUNNED and n.can_be_finished(), "De rodillas al 5 %")
	assert(n.finish_damage_frac == 0.0, "El remate final mata")
	n.receive_finisher(Vector3(0, 0, 10))
	assert(n.is_dead(), "Rematado")
	print("CHECK 3 PASSED: remate final del jefe")

	# 4. Logros: contador, recompensa y guardado
	assert(not MetaProgress.unlocked("verdugo") and not MetaProgress.starting_rune(), "Sin remates no hay logro")
	MetaProgress.record("finishers", 50)
	assert(MetaProgress.unlocked("verdugo") and MetaProgress.starting_rune(), "50 remates → Verdugo (runa inicial)")
	MetaProgress.discover_evolution(WeaponData.WeaponType.SPEAR_LANCE)
	MetaProgress.discover_evolution(WeaponData.WeaponType.SPEAR_LANCE)
	assert(MetaProgress.stat("evolutions_found") == 1, "Una evolución cuenta una vez")
	assert(MetaProgress.bonus_rerolls() == 1, "Evolucionista: +1 volver a tirar")
	GameState.get_instance().reset_session()
	assert(GameState.get_instance().card_rerolls == GameState.CARD_REROLLS + 1, "La partida nueva trae el uso extra")
	MetaProgress.record_max("best_endless_s", 100)
	MetaProgress.record_max("best_endless_s", 50)
	assert(MetaProgress.stat("best_endless_s") == 100, "El récord se queda con el máximo")
	SaveManager.load_save()
	assert(MetaProgress.unlocked("verdugo") and MetaProgress.evolution_known(WeaponData.WeaponType.SPEAR_LANCE), "Se guarda y se carga")
	print("CHECK 4 PASSED: logros y códice guardados")

	# 5. Runa inicial en la mazmorra (logro Verdugo)
	GameState.get_instance().runes.clear()
	enc.level = 1
	enc._setup_level_extras()
	assert(not GameState.get_instance().runes.is_empty(), "Con Verdugo la mazmorra empieza con una runa")
	print("CHECK 5 PASSED: runa inicial")

	# 6. Menú: panel de logros y evoluciones
	var menu: Node = load("res://scenes/ui/main_menu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame
	menu._on_codex_menu()
	await get_tree().process_frame
	var texts: Array = menu.codex_list.get_children().map(func(l): return (l as Label).text)
	assert(texts.any(func(t): return t.begins_with("★ Verdugo")), "El logro conseguido sale con estrella")
	assert(texts.any(func(t): return t.begins_with("Lanza del Trueno")), "La evolución descubierta sale con su receta")
	assert(texts.any(func(t): return t.begins_with("???")), "Las no descubiertas salen como ???")
	print("CHECK 6 PASSED: panel de logros (%d líneas)" % texts.size())

	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_save.json"))
	print("ALL BOSS/META CHECKS PASSED")
	get_tree().quit(0)
