extends Node

## Fase 3 del plan de loot: pergaminos de enfoque, planos, calor y cofre maldito (DungeonRun).

var enc: DungeonEncounter
var player: Node3D
var arena: Vector3

func _ready() -> void:
	print("--- TEST: DUNGEON RUN (FASE 3) ---")
	GameData.game_mode = "dungeon"
	SaveManager.save_path = "user://test_save.json"
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
	(player.get("equipment") as PlayerEquipment).persist = false
	arena = enc.map.room_center(enc.map.arena_index)
	player.global_position = arena + Vector3(0, 0.3, 14)
	var gs := GameState.get_instance()
	gs.focus.clear()
	gs.heat = 0
	gs.curse_kills = 0
	var hc: Node = player.get("health_comp")

	# 1. Enfoques: daño del arma según categoría, vida y armadura de Supervivencia
	var w: int = player.weapon_inventory.weapon_slots[player.weapon_inventory.current_slot]
	var melee := String(WeaponData.get_weapon_data(w).category) == "melee"
	var d0 := float(player.get_weapon_modifiers(w).get("damage", 0.0))
	DungeonRun.add_focus("brutalidad" if melee else "tactica", player)
	var d1 := float(player.get_weapon_modifiers(w).get("damage", 0.0))
	assert(absf(d1 - d0 - 0.08) < 0.001, "El enfoque de su categoría suma +8%% (%.3f -> %.3f)" % [d0, d1])
	DungeonRun.add_focus("tactica" if melee else "brutalidad", player)
	assert(absf(float(player.get_weapon_modifiers(w).get("damage", 0.0)) - d1) < 0.001, "El otro enfoque no toca el daño de esta arma")
	var mhp := float(hc.max_hp)
	var armor0: float = player.stat_block.armor()
	DungeonRun.add_focus("supervivencia", player)
	assert(is_equal_approx(float(hc.max_hp), mhp + DungeonRun.SURV_HP), "Supervivencia: +12 vida máxima (%.1f -> %.1f)" % [mhp, hc.max_hp])
	assert(absf(player.stat_block.armor() - armor0 - DungeonRun.SURV_ARMOR) < 0.001, "Supervivencia: +2% armadura")
	assert(DungeonRun.focus_option("supervivencia")["desc"].contains("Nivel 1 → 2"), "La opción muestra el nivel")
	print("CHECK 1 PASSED: enfoques")

	# 2. Ventajas al nivel 3: Carnicería y Segundo aliento
	gs.focus = {"brutalidad": 3, "supervivencia": 3}
	DungeonRun.on_kill()
	DungeonRun.on_kill()
	assert(DungeonRun.carnage_stacks() == 2 and absf(DungeonRun.perk_bonus(null) - 0.1) < 0.001, "Carnicería x2 = +10%")
	player.stat_block._recalculate()
	hc.invincibility_time = 0.0
	player.take_damage(float(hc.hp) * 50.0)
	assert(is_equal_approx(float(hc.hp), 1.0), "Segundo aliento deja a 1 de vida (%.2f)" % hc.hp)
	assert(not DungeonRun.second_wind_ready(), "Solo una vez por nivel")
	player.heal(float(hc.max_hp))
	gs.focus.clear()
	player.stat_block._recalculate()
	print("CHECK 2 PASSED: ventajas")

	# 3. Maldición: más daño recibido hasta lograr las bajas
	player.heal(float(hc.max_hp))
	hc.invincibility_time = 0.0
	var h0 := float(hc.hp)
	player.take_damage(2.0)
	var normal := h0 - float(hc.hp)
	DungeonRun.curse()
	player.heal(float(hc.max_hp))
	hc.invincibility_time = 0.0
	h0 = float(hc.hp)
	player.take_damage(2.0)
	var cursed := h0 - float(hc.hp)
	assert(normal > 0.0 and absf(cursed / normal - DungeonRun.CURSE_DAMAGE_MULT) < 0.05, "Maldito: x2.5 (%.2f vs %.2f)" % [cursed, normal])
	for i in DungeonRun.CURSE_KILLS:
		DungeonRun.on_kill()
	assert(not DungeonRun.cursed(), "Las bajas rompen la maldición")
	player.heal(float(hc.max_hp))
	print("CHECK 3 PASSED: maldicion")

	# 4. Calor: enemigos más duros, más élites, botín mejor
	var plain := enc._spawn_at(enc.map.arena_index, arena + Vector3(3, 0, 0), "goblin")
	plain.set_physics_process(false)
	gs.heat = 2
	var hot := enc._spawn_at(enc.map.arena_index, arena + Vector3(-3, 0, 0), "goblin")
	hot.set_physics_process(false)
	assert(is_equal_approx(hot.max_hp, plain.max_hp * 1.4), "Calor 2: +40%% vida (%.1f vs %.1f)" % [hot.max_hp, plain.max_hp])
	assert(is_equal_approx(hot.damage_mult, plain.damage_mult * 1.3), "Calor 2: +30% daño")
	assert(is_equal_approx(DungeonRun.elite_bonus(), 0.2) and DungeonRun.min_rarity() == 1, "Calor 2: élites y rareza mínima")
	var opt := DungeonRun.heat_option()
	assert(String(opt["title"]).contains("2 → 3"), "La opción del portal muestra el calor")
	gs.heat = 0
	print("CHECK 4 PASSED: calor")

	# 5. Planos: lo bloqueado no sale hasta encontrar su plano
	SaveManager.meta["blueprints"] = []
	assert(not DungeonRun.known("mohan") and DungeonRun.known("tatan"), "Mohán bloqueado, Tatán libre")
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 2500:
		var it := EquipmentDB.roll("", -1, rng)
		for k in ["cond", "maker", "legendary"]:
			if it.has(k):
				assert(DungeonRun.known(String(it[k])), "Salió %s bloqueado: %s" % [k, it[k]])
	var bp := DungeonRun.maybe_blueprint(enc.get_parent(), arena, 1.0)
	assert(bp != null, "Con contenido bloqueado sale un plano")
	var before := DungeonRun.locked().size()
	bp.collect(player)
	assert(DungeonRun.locked().size() == before - 1, "Recoger el plano lo desbloquea")
	for id in DungeonRun.BLUEPRINTS:
		DungeonRun.unlock(id)
	assert(DungeonRun.maybe_blueprint(enc.get_parent(), arena, 1.0) == null, "Sin nada bloqueado no sale plano")
	var seen_mohan := false
	for i in 1500:
		var it := EquipmentDB.roll("arma", 3, rng)
		seen_mohan = seen_mohan or it.get("maker", "") == "mohan"
	assert(seen_mohan, "Desbloqueado, Mohán ya sale")
	print("CHECK 5 PASSED: planos")

	# 6. Cofre maldito: no se abre solo; al aceptarlo maldice y da botín
	var chest := enc.spawn_cursed_chest(player.global_position + Vector3(1.0, 0, 0))
	for i in 5:
		await get_tree().process_frame
	assert(not chest.is_open, "No se abre al acercarse")
	var ui := _find_choice(enc.get_parent())
	assert(ui != null, "Pregunta si abrirlo")
	var eqc: PlayerEquipment = player.get("equipment")
	var picks_before := get_tree().get_nodes_in_group("equipment_pickups").size() + eqc.bag.size() + eqc.equipped.size() + eqc.weapon_items.size()
	ui._pick("abrir")
	await get_tree().create_timer(1.2).timeout
	assert(chest.is_open and DungeonRun.cursed(), "Abierto y maldito")
	assert(get_tree().get_nodes_in_group("equipment_pickups").size() + eqc.bag.size() + eqc.equipped.size() + eqc.weapon_items.size() > picks_before, "Suelta una pieza")
	print("CHECK 6 PASSED: cofre maldito")

	# 7. Pergamino: recogerlo abre la elección de enfoque y la aplica
	gs.focus.clear()
	var scroll := enc.spawn_scroll(player.global_position + Vector3(5, 0, 0))
	scroll.collect(player)
	await get_tree().process_frame
	var fui := _find_choice(enc.get_parent())
	assert(fui != null, "El pergamino abre la elección")
	fui._pick("tactica")
	assert(DungeonRun.focus_level("tactica") == 1, "El pergamino sube el enfoque")
	print("CHECK 7 PASSED: pergamino")

	print("ALL RUN CHECKS PASSED")
	get_tree().quit(0)

func _find_choice(root: Node) -> DungeonChoiceUI:
	for n in root.get_children():
		if n is DungeonChoiceUI and not n.is_queued_for_deletion():
			return n
	return null
