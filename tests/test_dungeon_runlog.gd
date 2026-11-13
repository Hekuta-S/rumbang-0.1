extends Node

## Fase 5 del plan de loot: RunLog registra la partida de la mazmorra, saca los indicadores de
## repetición, rellena el resumen y guarda el historial.

var enc: DungeonEncounter
var player: Node3D
var eq: PlayerEquipment

func _ready() -> void:
	print("--- TEST: DUNGEON RUN LOG (FASE 5) ---")
	GameData.game_mode = "dungeon"
	SaveManager.save_path = "user://test_save.json"
	RunLog.history_path = "user://test_dungeon_runs.json"
	if FileAccess.file_exists(RunLog.history_path):
		DirAccess.remove_absolute(RunLog.history_path)
	var scene: Node = load("res://scenes/core/main_dungeon.tscn").instantiate()
	get_tree().root.add_child.call_deferred(scene)
	await get_tree().process_frame
	get_tree().current_scene = scene
	for i in 600:
		await get_tree().process_frame
		enc = scene.get_node_or_null("DungeonEncounter")
		if enc and enc.map and is_instance_valid(enc.player):
			break
	assert(enc != null, "La mazmorra debe crear DungeonEncounter")
	enc._pending.clear()
	player = enc.player
	player.set_physics_process(false)
	eq = player.get("equipment")
	eq.persist = false
	assert(RunLog.world != "", "La partida empieza a contarse al montar el nivel 1 (%s)" % RunLog.world)

	# 1. Una caverna de verdad: receta, tipos, daño por arma, bajas y tiempo
	RunLog.begin("Prueba")
	var room := -1
	for i in enc.map.rooms.size():
		if enc.map.rooms[i]["type"] == "normal" and i != enc.map.arena_index:
			room = i
			break
	assert(room >= 0, "Hay una caverna normal")
	eq.equipped.clear()
	eq.equipped["talisman_1"] = {"slot": "talisman", "rarity": 2, "stats": {}, "uid": "rl1", "name": "T", "cond": "primer_golpe"}
	player.global_position = enc.map.room_center(room) + Vector3(0, 0.3, 3)
	enc._spawn_group(room, 4, player)
	assert(RunLog.recipes.size() == 1 and not RunLog.kinds.is_empty(), "Receta y tipos registrados (%s / %s)" % [RunLog.recipes, RunLog.kinds])
	HitFeedback.weapon_tag = WeaponData.WeaponType.SWORD
	var guard := 0
	while enc._alive.get(room, 0) > 0 and guard < 400:
		guard += 1
		for e in EnemyRegistry.all():
			if e is DungeonGoblin and is_instance_valid(e) and not e.is_dead():
				e.take_damage(e.hp + 1.0)
		await get_tree().process_frame
	assert(enc._alive.get(room, 0) <= 0, "Caverna limpia")
	assert(RunLog.kills >= 4, "Bajas contadas (%d)" % RunLog.kills)
	assert(RunLog.room_times.size() == 1, "Tiempo de la caverna")
	assert(float(RunLog.damage_by_weapon.get(WeaponData.WeaponType.SWORD, 0.0)) > 0.0, "Daño por arma")
	assert(int(RunLog.procs.get("cond:primer_golpe", 0)) > 0, "Activaciones del rasgo contadas")
	assert(int(RunLog.worn.get("cond:primer_golpe", 0)) == 1, "Rasgo llevado durante la caverna")
	print("CHECK 1 PASSED: caverna registrada")

	# 2. Indicadores: arma única, rasgo muerto, combates clonados, botín sin usar
	RunLog.begin("Prueba")
	RunLog.damage_by_weapon = {WeaponData.WeaponType.SWORD: 900.0, WeaponData.WeaponType.MACE: 100.0}
	eq.equipped["talisman_1"]["cond"] = "verdugo"
	for i in RunLog.DEAD_TRAIT_ROOMS:
		RunLog.room_started(100 + i, "patrulla" if i < 2 else "muro", [])
		RunLog.room_cleared(100 + i, eq)
	RunLog.recipes = {"patrulla": 4, "muro": 1}
	for i in 5:
		RunLog.received({"uid": "p%d" % i, "rarity": 1})
	RunLog.equipped({"uid": "p0"})
	var a := RunLog.analyze()
	assert(a["one_weapon"] and is_equal_approx(float(a["top_share"]), 0.9), "90% con una arma")
	assert((a["dead_traits"] as Array).has("cond:verdugo"), "Verdugo llevado 3 cavernas sin activarse")
	assert(a["clones"] and a["top_recipe"] == "patrulla", "Receta repetida")
	assert(a["unused_flag"] and int(a["unused_loot"]) == 4, "4 de 5 piezas sin usar")
	var warns := RunLog.warnings(a)
	assert(warns.size() == 4 and String(warns[0]).contains("90%"), "Cuatro avisos (%s)" % str(warns))
	RunLog.damage_by_weapon[WeaponData.WeaponType.MACE] = 800.0
	assert(not RunLog.analyze()["one_weapon"], "Repartido entre armas: sin aviso")
	print("CHECK 2 PASSED: indicadores")

	# 3. Causa de la muerte, resumen e historial
	var g := enc._spawn_at(enc.map.arena_index, enc.map.room_center(enc.map.arena_index), "goblin")
	g.set_physics_process(false)
	RunLog.hit_by(g)
	assert(RunLog.last_hit_by == "Goblin", "Causa legible (%s)" % RunLog.last_hit_by)
	RunLog.level = 3
	RunLog.finish()
	RunLog.finish()   # solo se guarda una vez
	var runs := RunLog.load_history()
	assert(runs.size() == 1 and runs[0]["death"] == "Goblin" and int(runs[0]["level"]) == 3, "Partida guardada (%d)" % runs.size())
	assert((runs[0]["warnings"] as Array).size() == 3 and (runs[0]["damage"] as Dictionary).size() == 2, "Historial con avisos y daño (%s)" % str(runs[0]["warnings"]))
	var lines := RunLog.summary_lines()
	assert(String(lines[0]).begins_with("NIVEL 3") and lines.any(func(l): return String(l).begins_with("Te derrotó: Goblin")), "Resumen con nivel y causa")
	assert(lines.any(func(l): return String(l).begins_with("⚠")), "Resumen con avisos")
	for i in RunLog.HISTORY_MAX + 3:
		RunLog.begin("Relleno")
		RunLog.finish("x")
	assert(RunLog.load_history().size() == RunLog.HISTORY_MAX, "Solo las últimas %d" % RunLog.HISTORY_MAX)
	DirAccess.remove_absolute(RunLog.history_path)
	print("CHECK 3 PASSED: resumen e historial")

	print("ALL RUNLOG CHECKS PASSED")
	get_tree().quit(0)
