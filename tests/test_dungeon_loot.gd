extends Node

## Fase 2 del plan de loot: rasgos condicionales, fabricantes de arma, reglas de legendarias y botín de jefe.

var enc: DungeonEncounter
var eq: PlayerEquipment
var arena: Vector3

func _ready() -> void:
	print("--- TEST: DUNGEON LOOT (FASE 2) ---")
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
	var player: Node3D = enc.player
	player.set_physics_process(false)
	eq = player.get("equipment")
	assert(eq != null, "El jugador debe tener PlayerEquipment")
	eq.persist = false
	arena = enc.map.room_center(enc.map.arena_index)
	player.global_position = arena + Vector3(0, 0.3, 14)

	# 1. Datos: dónde salen los rasgos, legendarias de jefe fuera del sorteo normal, sanitize
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var conds := 0
	var makers := 0
	for i in 1500:
		var it := EquipmentDB.roll("", -1, rng)
		if it.has("cond"):
			conds += 1
			assert(EquipmentDB.COND_SLOTS.has(it["slot"]), "Rasgo condicional en %s" % it["slot"])
		if it.has("maker"):
			makers += 1
			assert(it["slot"] == "arma", "Fabricante en %s" % it["slot"])
		if it.has("legendary"):
			assert(not EquipmentDB.LEGENDARIES[it["legendary"]].has("boss"), "La legendaria de jefe %s salió fuera del jefe" % it["legendary"])
	assert(conds > 0 and makers > 0, "Deben salir rasgos (%d) y fabricantes (%d)" % [conds, makers])
	var necro_ids := 0
	for i in 200:
		var d := EquipmentDB.boss_drop("necro", 2, rng)
		assert(int(d["rarity"]) >= 2, "El jefe suelta rara o mejor")
		if d.has("legendary"):
			var owner := String(EquipmentDB.LEGENDARIES[d["legendary"]].get("boss", ""))
			assert(owner == "necro" or owner == "", "Legendaria de otro jefe (%s)" % owner)
			necro_ids += 1 if owner == "necro" else 0
	assert(necro_ids > 40 and necro_ids < 130, "~40% legendarias del jefe (%d/200)" % necro_ids)
	var s := EquipmentDB.sanitize({"slot": "arma", "weapon": 18, "rarity": 2, "cond": "verdugo", "maker": "arriero"})
	assert(s.get("cond") == "verdugo" and s.get("maker") == "arriero", "sanitize conserva rasgo y fabricante")
	var bad := EquipmentDB.sanitize({"slot": "casco", "rarity": 2, "cond": "verdugo", "maker": "arriero"})
	assert(not bad.has("cond") and not bad.has("maker"), "sanitize quita rasgos de piezas que no los admiten")
	assert(EquipmentDB.trait_lines(EquipmentDB.legendary_item("maza_terremoto")).any(func(l): return l.begins_with("★★")), "La legendaria muestra su regla")
	print("CHECK 1 PASSED: datos (%d rasgos, %d fabricantes en 1500 piezas)" % [conds, makers])

	# 2. Condicional Verdugo: +50% a aturdidos, nada a los demás
	await get_tree().process_frame
	_wear({"slot": "talisman", "rarity": 2, "name": "T", "uid": "t1", "stats": {}, "cond": "verdugo"})
	var g := _spawn(Vector3.ZERO)
	var h := g.hp
	g.take_damage(10.0)
	assert(absf((h - g.hp) - 10.0) < 0.01, "Sin aturdir: daño normal (%.2f)" % (h - g.hp))
	g.add_stun_fraction(1.0)
	h = g.hp
	g.take_damage(10.0)
	assert(absf((h - g.hp) - 15.0) < 0.01, "Aturdido: +50%% (%.2f)" % (h - g.hp))
	print("CHECK 2 PASSED: verdugo")

	# 3. Contra: +80% tras un parry
	await get_tree().process_frame
	_wear({"slot": "talisman", "rarity": 2, "name": "T", "uid": "t2", "stats": {}, "cond": "contra"})
	var g2 := _spawn(Vector3(2, 0, 0))
	eq.notify("parry")
	h = g2.hp
	g2.take_damage(5.0)
	assert(absf((h - g2.hp) - 9.0) < 0.01, "Tras parry: +80%% (%.2f)" % (h - g2.hp))
	print("CHECK 3 PASSED: contra")

	# 4. Arriero: la cadena sube con golpes seguidos y se corta al recibir un golpe
	await get_tree().process_frame
	_wear({}, _weapon("arriero"))
	var g3 := _spawn(Vector3(-2, 0, 0))
	for i in 3:
		g3.take_damage(1.0)
		await get_tree().process_frame
	assert(eq.chain_stacks == 3 and absf(eq.chain_bonus() - 0.18) < 0.001, "Cadena x3 = +18%% (%.2f)" % eq.chain_bonus())
	eq.notify("hurt")
	assert(eq.chain_bonus() == 0.0, "Recibir un golpe corta la cadena")
	print("CHECK 4 PASSED: arriero")

	# 5. Conquistador: ejecuta por debajo del 15%
	await get_tree().process_frame
	_wear({}, _weapon("conquistador"))
	var g4 := _spawn(Vector3(0, 0, 2))
	g4.hp = g4.max_hp * 0.12
	g4.take_damage(0.1)
	await get_tree().process_frame
	assert(g4.is_dead(), "Conquistador ejecuta al 12%")
	print("CHECK 5 PASSED: conquistador")

	# 6. Tatán: aturdimiento extra por golpe
	await get_tree().process_frame
	_wear({}, _weapon("tatan"))
	var g5 := _spawn(Vector3(0, 0, -2))
	g5.take_damage(2.0)
	await get_tree().process_frame
	var expect := 2.0 * DungeonGoblin.STUN_HIT_MULT * DungeonRunes.stun_mult() + g5.stun_max() * 0.08
	assert(absf(g5._stun - expect) < 0.05, "Tatán suma 8%% de la barra (%.2f, esperado %.2f)" % [g5._stun, expect])
	print("CHECK 6 PASSED: tatan")

	# 7. Regla terremoto: el remate aturde a los cercanos
	await get_tree().process_frame
	_wear({}, EquipmentDB.legendary_item("maza_terremoto"))
	var a := _spawn(Vector3(4, 0, 4))
	var b := _spawn(Vector3(5, 0, 4))
	a.add_stun_fraction(1.0)
	a.receive_finisher(Vector3.FORWARD)
	assert(b.state == DungeonGoblin.State.STUNNED, "El terremoto aturde al vecino")
	print("CHECK 7 PASSED: terremoto")

	# 8. Regla obsidiana: la baja daña a los cercanos
	await get_tree().process_frame
	_wear({}, EquipmentDB.legendary_item("espadon_obsidiana"))
	var c := _spawn(Vector3(-4, 0, 4))
	var d2 := _spawn(Vector3(-5, 0, 4))
	var hd := d2.hp
	c.take_damage(c.hp + 1.0)   # la baja llega a LootHits.on_kill por DungeonEncounter._track
	assert(absf((hd - d2.hp) - LootHits.OBSIDIANA_DAMAGE) < 0.01, "Onda de sombra (%.2f)" % (hd - d2.hp))
	print("CHECK 8 PASSED: obsidiana")

	# 9. Regla vacío: el primer golpe cada 8 s no hace daño
	var vacio := EquipmentDB.legendary_item("coraza_vacio")
	eq.equipped.clear()
	eq.equipped["pechera"] = vacio
	var hc: Node = player.get("health_comp")
	hc.invincibility_time = 0.0
	var php := float(hc.hp)
	player.take_damage(1.0)
	assert(is_equal_approx(float(hc.hp), php), "Primer golpe absorbido")
	hc.invincibility_time = 0.0
	player.take_damage(5.0)
	assert(float(hc.hp) < php, "El segundo golpe sí entra (vida %.2f -> %.2f, invul %.2f)" % [php, float(hc.hp), hc.invincibility_time])
	print("CHECK 9 PASSED: vacio")

	print("ALL LOOT CHECKS PASSED")
	get_tree().quit(0)

## Viste solo `talisman` (en talisman_1) y/o `weapon` como arma en la mano.
func _wear(talisman: Dictionary, weapon: Dictionary = {}) -> void:
	eq.equipped.clear()
	eq.weapon_items.clear()
	eq.reset_chain()
	eq.last_parry_t = -100.0
	if not talisman.is_empty():
		eq.equipped["talisman_1"] = talisman
	if not weapon.is_empty():
		eq.weapon_items[eq.current_weapon()] = weapon

func _weapon(maker: String) -> Dictionary:
	return {"slot": "arma", "weapon": eq.current_weapon(), "rarity": 2, "name": "W", "uid": "w_" + maker, "stats": {}, "maker": maker}

func _spawn(off: Vector3) -> DungeonGoblin:
	var g := enc._spawn_at(enc.map.arena_index, arena + off, "goblin")
	g.set_physics_process(false)
	return g
