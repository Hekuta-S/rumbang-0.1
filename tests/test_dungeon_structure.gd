extends Node

## Fase 4 del plan de mejora (mazmorra): oro, cavernas de desafío, runas, camino tras el portal y
## la forja. Carga la mazmorra real.

func _ready() -> void:
	print("--- TEST: ESTRUCTURA DE LA MAZMORRA ---")
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.game_mode = "dungeon"
	SaveManager.save_path = "user://test_save.json"   # no tocar la partida guardada real
	SaveManager.meta = {}
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
	var p = enc.player
	p.health_comp.max_hp = 99999.0
	p.health_comp.hp = 99999.0
	var gs := GameState.get_instance()

	# 1. Nivel 1: una caverna de desafío marcada y sin forja
	assert(enc._challenge_rooms.size() == 1, "Una caverna de desafío (%d)" % enc._challenge_rooms.size())
	assert(enc.shop == null, "En el nivel 1 no hay forja")
	print("CHECK 1 PASSED: desafío marcado, sin forja")

	# 2. Desafío: entrar lo arranca, despejarlo a tiempo da oro y una runa
	var room: int = enc._challenge_rooms.keys()[0]
	var c := enc.map.room_center(room)
	p.global_position = Vector3(c.x, 0.3, c.z)
	for i in 30:
		await get_tree().physics_frame
		if not enc._challenge.is_empty():
			break
	assert(not enc._challenge.is_empty() and int(enc._challenge["room"]) == room, "Entrar arranca el desafío")
	assert(enc._challenge_label != null, "Se ve la cuenta atrás")
	var gold0 := gs.gold
	for i in 200:
		var alive: Array = EnemyRegistry.all().filter(func(e): return e is DungeonGoblin and is_instance_valid(e) and not e.is_dead())
		if alive.is_empty() and enc._alive.get(room, 0) <= 0:
			break
		for e in alive:
			e.take_damage(99999.0, Vector3.ZERO)
		await get_tree().physics_frame
	await get_tree().process_frame
	assert(enc._challenge.is_empty(), "El desafío termina al despejar")
	assert(gs.gold > gold0 + DungeonEncounter.CHALLENGE_GOLD, "Oro de los enemigos y del desafío (%d → %d)" % [gold0, gs.gold])
	var ui := _find_choice(scene)
	assert(ui != null and get_tree().paused, "Se abre la elección de runa")
	var rune: String = ui._options[0]["id"]
	ui._pick(rune)
	assert(DungeonRunes.level(rune) == 1 and not get_tree().paused, "Runa %s conseguida" % rune)
	print("CHECK 2 PASSED: desafío superado, %d de oro, runa %s" % [gs.gold - gold0, rune])

	# 3. Las runas se notan en el arma
	var dmg0: float = p.get_weapon_modifiers(p.current_weapon())["damage"]
	gs.runes["poder"] = int(gs.runes.get("poder", 0)) + 1
	assert(absf(float(p.get_weapon_modifiers(p.current_weapon())["damage"]) - dmg0 - 0.15) < 0.001, "Tomo de Poder (mazmorra): +15% daño")
	var stun0 := DungeonRunes.stun_mult()
	gs.runes["quebranto"] = int(gs.runes.get("quebranto", 0)) + 1   # la runa del desafío pudo ser esta
	assert(DungeonRunes.stun_mult() > stun0, "Runa del Quebranto: más aguante")
	print("CHECK 3 PASSED: runas aplicadas")

	# 4. Desafío fallido: se acaba el tiempo
	enc._challenge = {"room": room, "until": 0.0}
	enc._update_challenge()
	assert(enc._challenge.is_empty() and _find_choice(scene) == null, "Sin tiempo: desafío fallido y sin premio")
	print("CHECK 4 PASSED: desafío fallido")

	# 5. Camino tras el portal: 3 opciones al azar + Calor (riesgo opcional, DungeonRun); "descanso" cura y baja de nivel (con forja)
	enc._choose_path()
	var pui := _find_choice(scene)
	assert(pui != null and pui._options.size() == 4 and pui._options.back()["id"] == "calor", "Tres caminos y Calor")
	pui.queue_free()
	get_tree().paused = false
	p.health_comp.hp = 100.0
	enc._on_path_chosen("descanso")
	for i in 240:
		await get_tree().process_frame
		if enc.level == 2 and not enc._changing_level:
			break
	assert(enc.level == 2 and p.health_comp.hp >= p.health_comp.max_hp - 1.0, "Descanso: vida llena y nivel 2")
	assert(is_instance_valid(enc.shop), "Desde el nivel 2 hay forja")
	print("CHECK 5 PASSED: camino de descanso y forja en el nivel 2")

	# 6. Forja: comprar cuesta oro y da lo comprado
	gs.gold = 1000
	enc.shop.open()
	var prices: Dictionary = enc.shop.prices()
	p.health_comp.hp = 100.0
	enc.shop._buy("potion")
	assert(gs.gold == 1000 - prices["potion"] and p.health_comp.hp > 100.0, "Poción comprada")
	var sr: String = enc.shop._runes[0] if not enc.shop._runes.is_empty() else ""
	if sr != "":
		var lv := DungeonRunes.level(sr)
		enc.shop._buy(sr)
		assert(DungeonRunes.level(sr) == lv + 1, "Runa comprada en la forja")
	enc.shop._ui._close()
	assert(not get_tree().paused, "Salir de la forja reanuda")
	print("CHECK 6 PASSED: forja")

	# 7. Camino de tesoro: cofre de runas en la caverna inicial
	var chests := enc._chests.size()
	enc.path = "tesoro"
	enc._setup_level_extras()
	assert(enc._chests.size() == chests + 1, "El camino de tesoro pone un cofre")
	enc._chests.back().opened.emit(enc._chests.back())
	var cui := _find_choice(scene)
	assert(cui != null, "El cofre de tesoro ofrece runas")
	cui._pick(cui._options[0]["id"])
	print("CHECK 7 PASSED: cofre de runas")

	print("ALL DUNGEON STRUCTURE CHECKS PASSED")
	get_tree().quit(0)

func _find_choice(scene: Node) -> DungeonChoiceUI:
	for n in scene.get_children():
		if n is DungeonChoiceUI and not n.is_queued_for_deletion():
			return n
	return null
