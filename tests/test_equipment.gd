extends Node

## Sistema de equipo de la mazmorra (EquipmentDB, PlayerEquipment, EquipmentPickup, forja de Tatan,
## EquipmentPanel): sorteo por rareza, stats sobre PlayerStatBlock, vida máxima, talismanes, sets,
## armas como pieza, guardado de SOLO lo equipado, botín y tienda. Carga la mazmorra real.

var _failed := false

func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failed = true
		push_error("FALLO: " + msg)
		print("FAILED: " + msg)

func _done(n: Variant, msg: String) -> bool:
	if _failed:
		print("TEST FAILED en el check %s" % str(n))
		get_tree().quit(1)
		return false
	print("CHECK %s PASSED: %s" % [str(n), msg])
	return true

func _item(kind: String, stats: Dictionary, rarity: int = 1, set_id: String = "") -> Dictionary:
	var it := EquipmentDB.roll(kind, rarity, null, 0, false)
	it["stats"] = stats
	it.erase("perk")   # los efectos especiales se prueban aparte (check 11)
	if kind != "arma" and kind != "talisman":
		it["base"] = {"casco": "casco_minero", "pechera": "coraza_cuero", "pantalones": "pantalon_dril"}[kind]   # sin elemento de armadura
	if kind == "arma":
		it.erase("element")
		it.erase("wmod")
	it.erase("set")
	if set_id != "":
		it["set"] = set_id
	return it

func _ready() -> void:
	print("--- TEST: EQUIPO ---")
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveManager.save_path = "user://test_equipment_save.json"
	SaveManager.meta = {}
	GameData.armory_path = "user://test_equipment_armeria.cfg"
	GameData.dungeon_weapon = WeaponData.WeaponType.SPEAR_LANCE
	GameData.game_mode = "dungeon"
	GameData.selected_index = GameData.custom_index()

	# 1. Sorteo: nº de stats por rareza, rarezas mínimas y guardado JSON
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for r in EquipmentDB.RARITY_AFFIXES.size():
		var it := EquipmentDB.roll("casco", r, rng, 0, false)
		_check(it["stats"].size() == EquipmentDB.RARITY_AFFIXES[r], "Rareza %d trae %d stats" % [r, EquipmentDB.RARITY_AFFIXES[r]])
		_check(EquipmentDB.slots_for(it) == ["casco"], "El casco va en su ranura")
	for i in 200:
		_check(EquipmentDB.roll_rarity(rng, 2) >= 2, "La rareza mínima se respeta")
		var any := EquipmentDB.roll("", -1, rng)
		_check(EquipmentDB.KINDS.has(any["slot"]), "Tipo válido")
		if any["slot"] == "arma":
			_check(EquipmentDB.WEAPONS.has(any["weapon"]), "Arma de la mazmorra")
	# Botín: solo cascos con modelo 3D y la armadura completa de Sombra (con su set)
	var seen := {"casco": {}, "pechera": {}, "pantalones": {}}
	for i in 600:
		for kind in seen:
			var piece := EquipmentDB.roll(kind, 0, rng)
			seen[kind][piece["base"]] = piece
			if kind == "casco":
				_check(EquipmentDB.helmet_of(piece) != "", "Casco de botín con modelo (%s)" % piece["base"])
			else:
				_check(EquipmentDB.armor_of(piece) != "" and (EquipmentDB.armor_of(piece) != "sombra" or piece.get("set", "") == "sombra"),
					"%s de botín: armadura elemental (%s)" % [kind, piece["base"]])
	_check(seen["casco"].size() == EquipmentDB.lootable_bases("casco").size() and seen["casco"].size() >= 6, "Salen todos los cascos con modelo (%d)" % seen["casco"].size())
	_check(seen["pechera"].size() == 4 and seen["pantalones"].size() == 4, "Salen las 4 armaduras elementales")
	_check(EquipmentDB.SETS.has("sombra") and EquipmentDB.BASES["casco"]["yelmo_coronado"]["set"] == "sombra", "El yelmo coronado es del set Sombra")
	var tal := EquipmentDB.roll("talisman", 4, rng)
	var back := EquipmentDB.sanitize(JSON.parse_string(JSON.stringify(tal)))
	_check(back["rarity"] == 4 and back["stats"].size() == tal["stats"].size(), "Sobrevive al JSON")
	_check(EquipmentDB.sanitize({"slot": "botas"}).is_empty(), "Rechaza piezas rotas")
	if not _done(1, "sorteo por rareza"): return

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
	var eq: PlayerEquipment = p.equipment
	var sb: PlayerStatBlock = p.stat_block
	_check(eq != null, "El jugador de la mazmorra tiene equipo")
	_check(scene.get_node_or_null("EquipmentHud") != null, "Tira del equipo en el HUD")
	if not _done(2, "componente en el jugador"): return

	# 3. Stats: un casco con daño y armadura cambia la stat block; la vida máxima va por diferencia
	var dmg0 := sb.damage_mult()
	var armor0 := sb.armor()
	var hp0: float = p.max_hp
	_check(eq.receive(_item("casco", {"damage": 0.2, "armor": 0.1})) == "equipped", "Ranura libre: se equipa sola")
	_check(is_equal_approx(sb.damage_mult(), dmg0 + 0.2), "El daño sube con el casco")
	_check(is_equal_approx(sb.armor(), armor0 + 0.1), "La armadura sube con el casco")
	eq.receive(_item("pechera", {"max_hp": 4.0}))
	_check(is_equal_approx(p.max_hp, hp0 + 4.0), "La pechera suma vida máxima")
	eq.unequip("pechera")
	_check(is_equal_approx(p.max_hp, hp0), "Al quitarla vuelve la vida máxima")
	_check(eq.bag.size() == 1, "La pechera quitada va a la mochila")
	eq.equip(eq.bag[0])
	_check(is_equal_approx(p.max_hp, hp0 + 4.0) and eq.bag.is_empty(), "Se equipa desde la mochila")
	if not _done(3, "stats y vida máxima"): return

	# 4. Talismanes: dos ranuras; el tercero va a la mochila y al equiparlo cambia por el que había
	var t1 := _item("talisman", {"gold": 0.1})
	var t2 := _item("talisman", {"magnet": 2.0})
	var t3 := _item("talisman", {"attack_speed": 0.1})
	eq.receive(t1)
	eq.receive(t2)
	_check(eq.equipped["talisman_1"]["uid"] == t1["uid"] and eq.equipped["talisman_2"]["uid"] == t2["uid"], "Dos talismanes")
	_check(eq.receive(t3) == "bag", "El tercero va a la mochila")
	var cd0 := sb.cooldown_mult()
	eq.equip(eq.bag[0], "talisman_2")
	_check(eq.equipped["talisman_2"]["uid"] == t3["uid"], "Cambia el talismán 2")
	_check(eq.bag.size() == 1 and eq.bag[0]["uid"] == t2["uid"], "El viejo vuelve a la mochila")
	_check(sb.cooldown_mult() < cd0 and is_zero_approx(sb.magnet_bonus() - eq.get_stat_addition("magnet")), "Stats al día")
	var delta := eq.stat_delta(eq.bag[0], "talisman_2")
	_check(is_equal_approx(delta["magnet"], 2.0) and is_equal_approx(delta["attack_speed"], -0.1), "Comparación de stats")
	if not _done(4, "talismanes y comparación"): return

	# 5. Sets: dos piezas del Arriero dan velocidad
	eq.equipped.erase("casco")
	eq.equipped.erase("pantalones")
	eq._changed()
	var mv0 := sb.move_mult()
	eq.equip(_item("casco", {}, 1, "arriero"))
	eq.equip(_item("pantalones", {}, 1, "arriero"))
	_check(eq.set_counts().get("arriero", 0) == 2, "Dos piezas del set")
	_check(is_equal_approx(sb.move_mult(), mv0 + 0.10), "Bonus de 2 piezas")
	if not _done(5, "sets"): return

	# 5b. Energía y maná: el equipo sube máximos y recarga y abarata la energía; en la mazmorra
	#     el tamaño de ataque y los golpes/proyectiles extra no cuentan (ni salen en el equipo)
	for i in 300:
		for k in EquipmentDB.roll("", 4)["stats"]:
			_check(not (k in PlayerStatBlock.DUNGEON_IGNORED), "El equipo no trae %s" % k)
	var rsc: PlayerResources = p.resources
	var e_max0 := rsc.energy_max()
	var regen0 := sb.energy_regen_mult()
	eq.receive(_item("talisman", {"max_energy": 20.0, "energy_regen": 0.5, "energy_cost": 0.25, "max_mana": 10.0, "melee_size": 0.5, "melee_hits": 1}, 4))
	if eq.bag.size() > 0 and String(eq.bag[eq.bag.size() - 1]["slot"]) == "talisman":
		eq.equip(eq.bag[eq.bag.size() - 1], "talisman_1")
	_check(is_equal_approx(rsc.energy_max(), e_max0 + 20.0), "Más energía máxima")
	_check(is_equal_approx(sb.energy_regen_mult(), regen0 + 0.5), "Recarga más rápido")
	_check(is_equal_approx(rsc.mana_max(), PlayerResources.MANA_MAX + 10.0), "Más maná máximo")
	p.inventory.add_item("mango_hierro")      # objeto de supervivencia con tamaño melee
	p.inventory.add_item("doble_filo")
	_check(is_equal_approx(sb.melee_size(), 1.0) and sb.melee_extra_hits() == 0, "Tamaño y golpes extra no cuentan en la mazmorra")
	p.inventory.clear_items()
	rsc.energy = rsc.energy_max()
	var before_e := rsc.energy
	rsc.spend_energy(20.0)
	_check(is_equal_approx(before_e - rsc.energy, 20.0 * sb.energy_cost_mult()), "Cada gasto cuesta menos energía")
	rsc.energy = 5.0
	var t0 := rsc.energy
	rsc._energy_wait = 0.0
	rsc._process(0.1)
	_check(is_equal_approx(rsc.energy - t0, PlayerResources.ENERGY_REGEN * sb.energy_regen_mult() * 0.1), "Regenera con el multiplicador")
	_check(sb.describe().any(func(l): return l.begins_with("Energía:")), "La ficha muestra la energía")
	if not _done("5b", "energía y maná del equipo"): return

	# 6. Armas: una pieza de arma entra en la lista, se empuña y sus stats solo cuentan en la mano
	var winv: PlayerWeaponInventory = p.weapon_inventory
	var first: int = winv.get_current_weapon()
	var dag := EquipmentDB.weapon_item(WeaponData.WeaponType.DAGGERS, 2)
	dag["stats"] = {"damage": 0.5}
	var dmg_before := sb.damage_mult()
	var res := eq.receive(dag)
	_check(res == "equipped" or winv.weapon_slots.has(WeaponData.WeaponType.DAGGERS), "El arma se equipa")
	_check(winv.get_current_weapon() == WeaponData.WeaponType.DAGGERS, "Se empuña la nueva")
	_check(is_equal_approx(sb.damage_mult(), dmg_before + 0.5), "Sus stats cuentan en la mano")
	var mods: Dictionary = p.get_weapon_modifiers(WeaponData.WeaponType.DAGGERS)
	_check(mods.has("damage") and mods.has("size"), "Modificadores y sinergias intactos")
	p.select_slot(winv.weapon_slots.find(first))
	_check(is_equal_approx(sb.damage_mult(), dmg_before), "Fuera de la mano no cuentan")
	p.select_slot(winv.weapon_slots.find(WeaponData.WeaponType.DAGGERS))
	if not _done(6, "armas en el equipo"): return

	# 7. Guardado: solo lo equipado (y el arma de la mano, que pasa a ser la inicial); la mochila se pierde
	var bag_uid: String = eq.bag[0]["uid"]
	SaveManager.load_save()
	var saved: Dictionary = SaveManager.meta.get("equipment", {})
	_check(saved.has("casco") and saved.has("talisman_1") and saved.has("arma"), "Se guarda lo equipado")
	_check(not JSON.stringify(saved).contains(bag_uid), "La mochila no se guarda")
	_check(int(saved["arma"]["weapon"]) == WeaponData.WeaponType.DAGGERS, "El arma de la mano se guarda")
	_check(GameData.dungeon_weapon == WeaponData.WeaponType.DAGGERS, "Y es el arma inicial de la próxima")
	var hp_eq: float = p.max_hp
	var casco_uid: String = eq.equipped["casco"]["uid"]
	scene.facade._apply_character_data()
	_check(eq.bag.is_empty(), "Partida nueva: mochila vacía")
	_check(eq.equipped["casco"]["uid"] == casco_uid, "Partida nueva: vuelve lo equipado")
	_check(is_equal_approx(p.max_hp, hp_eq), "La vida del equipo se vuelve a sumar a la base")
	_check(PlayerEquipment.saved_loadout().size() == saved.size(), "El Salón lee el equipo guardado")
	if not _done(7, "solo se conserva lo equipado"): return

	# 8. Botín: cajas/enemigos (dado), jefes (siempre, rara+) y recoger del suelo
	var c := enc.map.room_center(enc.map.arena_index)
	p.global_position = c + Vector3(0, 0.3, 0)
	var none := EquipmentPickup.try_drop(scene, c, 0.0)
	_check(none == null, "Sin suerte no cae nada")
	var drop := EquipmentPickup.try_drop(scene, c + Vector3(20, 0, 0), 1.0, 3)
	_check(drop != null and int(drop.item["rarity"]) >= 3, "Cae una pieza con la rareza mínima")
	var n0 := eq.bag.size() + eq.equipped.size()
	var got := drop.collect(p)
	_check(got == "equipped" or got == "bag", "Se recoge")
	_check(eq.bag.size() + eq.equipped.size() == n0 + 1 or got == "equipped", "Entra en el equipo")
	var boss := enc.spawn_necromancer() if enc.has_method("spawn_necromancer") else null
	if boss:
		await get_tree().physics_frame
		var bd := EquipmentPickup.drop_for_enemy(scene, boss)
		_check(bd != null and int(bd.item["rarity"]) >= EquipmentPickup.BOSS_MIN_RARITY, "El jefe suelta rara o mejor")
		boss.queue_free()
	var props := get_tree().get_nodes_in_group("destructibles")
	print("  props en el mapa: %d" % props.size())
	if not _done(8, "botín"): return

	# 9. Forja de Tatan: vende dos piezas y se compran con oro
	var shop := DungeonShop.spawn(scene, c + Vector3(-6, 0, 0), p, 3)
	await get_tree().process_frame
	_check(shop._equip.size() == DungeonShop.EQUIP_OFFERS, "Dos piezas a la venta")
	_check(shop.tatan != null, "Tatan atiende la forja")
	var opts: Array = shop._options()
	var eopts := opts.filter(func(o): return String(o["id"]).begins_with("equip:"))
	_check(eopts.size() == 2, "Las piezas salen en la tienda")
	var gs := GameState.get_instance()
	while eq.bag.size() > 2:
		eq.discard(eq.bag[0])
	var offer: Dictionary = shop._equip[0]
	var price := shop.equip_price(offer)
	gs.gold = price + 5
	shop._buy(String(eopts[0]["id"]))
	_check(gs.gold == 5, "Cobra el precio")
	_check(shop._equip.size() == 1, "La pieza vendida desaparece")
	var owned := JSON.stringify(eq.bag) + JSON.stringify(eq.equipped) + JSON.stringify(eq.weapon_items)
	_check(owned.contains(String(offer["uid"])), "La pieza comprada es tuya")
	gs.gold = 0
	shop._buy(String("equip:" + String(shop._equip[0]["uid"])))
	_check(shop._equip.size() == 1, "Sin oro no se compra")
	shop.queue_free()
	if not _done(9, "forja de Tatan"): return

	# 10. UI: panel EQUIPO con ranuras y mochila; equipar desde él
	eq.receive(_item("pantalones", {"jump_height": 0.3}, 3))
	var panel := EquipmentPanel.create(eq, sb)
	add_child(panel)
	await get_tree().process_frame
	_check(panel._plate.sockets.size() == 5 and panel._weapon_socket != null, "Cinco huecos de armadura y talismanes, más el arma")
	_check(panel._bag_plate.sockets.size() == PlayerEquipment.BAG_MAX, "Un hueco por plaza de mochila")
	_check(panel._bag_plate.sockets.filter(func(sk): return sk.filled).size() == eq.bag.size(), "Un hueco lleno por pieza de la mochila")
	_check(not eq.bag.is_empty(), "Hay una pieza en la mochila para probar")
	panel.select_bag(eq.bag[0])
	var btn := panel._detail.find_child("Equipar", true, false) as Button
	_check(btn != null, "Botón de equipar")
	var bag_before := eq.bag.size()
	if btn:
		btn.pressed.emit()
	await get_tree().process_frame
	_check(eq.bag.size() <= bag_before, "Equipar desde el panel")
	_check(panel._stats_label.text.contains("Daño"), "Resumen de estadísticas")
	panel.close()
	if not _done(10, "panel de equipo"): return

	# 11. Fase 1: stats por tipo de pieza, efectos especiales, legendarias fijas
	for kind in ["casco", "pechera", "pantalones", "talisman", "arma"]:
		var allowed: Array = EquipmentDB.SLOT_STATS[kind]["main"] + EquipmentDB.SLOT_STATS[kind]["extra"]
		var main: Array = EquipmentDB.SLOT_STATS[kind]["main"]
		for i in 120:
			var it := EquipmentDB.roll(kind, i % 5, rng, 0, false)
			var keys: Array = it["stats"].keys()
			_check(keys.size() > 0 and main.has(keys[0]), "%s: el primer stat es protagonista (%s)" % [kind, keys])
			for k in keys:
				_check(allowed.has(k), "%s: stat permitido (%s)" % [kind, k])
			_check(it["rarity"] >= 2 or not it.has("perk"), "Sin efecto por debajo de Rara")
			if it.has("perk"):
				var perk: Dictionary = EquipmentDB.PERKS[it["perk"]]
				_check(perk["slots"].has(kind) and not perk.get("unique", false), "Efecto válido para %s" % kind)
	var with_perk := 0
	for i in 200:
		with_perk += 1 if EquipmentDB.roll("pechera", 4, rng, 0, false).has("perk") else 0
	_check(with_perk == 200, "Mítica: siempre trae efecto")
	var found_legend := false
	for i in 400:
		var m := EquipmentDB.roll("", 4, rng)
		if m.has("legendary"):
			found_legend = true
			_check(EquipmentDB.LEGENDARIES.has(m["legendary"]) and EquipmentDB.perk_of(m).size() > 0, "Legendaria con su efecto")
			_check(EquipmentDB.sanitize(JSON.parse_string(JSON.stringify(m))).get("perk") == m["perk"], "El efecto sobrevive al guardado")
	_check(found_legend, "Salen legendarias fijas")
	for id in EquipmentDB.LEGENDARIES:
		var l := EquipmentDB.legendary_item(id)
		_check(EquipmentDB.PERKS.has(l["perk"]) and not EquipmentDB.sanitize(l).is_empty(), "Legendaria %s válida" % id)

	# Efectos en vivo (sobre el jugador real). Se vacían las ranuras para aislar.
	for s in PlayerEquipment.SLOTS:
		eq.equipped.erase(s)
	eq.bag.clear()
	var perk_item := func(kind: String, perk_id: String) -> Dictionary:
		var x := _item(kind, {}, 2)
		x["perk"] = perk_id
		return x
	var d0 := sb.damage_mult()
	eq.equip(perk_item.call("pantalones", "pies_niebla"))
	_check(is_equal_approx(sb.damage_mult(), d0), "Antes de esquivar no hay bonus")
	p.notify_equipment("dodge")
	_check(is_equal_approx(sb.damage_mult(), d0 + 0.25), "Esquivar activa +25% daño")
	eq._buffs.clear()
	_check(is_equal_approx(sb.damage_mult(), d0), "El bonus caduca/se limpia")
	eq.equip(perk_item.call("talisman", "sed_mana"), "talisman_1")
	p.resources.mana = 0.0
	p.notify_equipment("kill")
	_check(is_equal_approx(p.resources.mana, 6.0), "Una baja da maná (sed_mana)")
	eq.equip(perk_item.call("talisman", "gallardo"), "talisman_2")
	p.resources.energy = 0.0
	p.notify_equipment("dodge")
	_check(is_equal_approx(p.resources.energy, 12.0), "Esquivar da energía (gallardo)")
	p.notify_equipment("dodge")
	_check(is_equal_approx(p.resources.energy, 12.0), "El reposo impide repetirlo al instante")
	eq.equip(perk_item.call("pechera", "ultimo_aliento"))
	var a0 := sb.armor()
	p.hp = p.max_hp
	var d1 := sb.damage_mult()
	p.hp = p.max_hp * 0.2
	_check(is_equal_approx(sb.damage_mult(), d1 + 0.25) and sb.armor() > a0 - 0.0001, "Con poca vida sube el daño (último aliento)")
	p.hp = p.max_hp
	_check(is_equal_approx(sb.damage_mult(), d1), "Con la vida llena se apaga")
	var pc = p.parry_controller
	eq.equip(perk_item.call("casco", "contragolpe"))
	var d2 := sb.damage_mult()
	if pc:
		pc.parried.emit(null)
		_check(is_equal_approx(sb.damage_mult(), d2 + 0.40), "Un parry activa +40% daño (contragolpe)")
	eq._buffs.clear()
	if not _done(11, "stats por tipo, efectos especiales y legendarias"): return

	# 12. Fase 2: elementos y modificadores de arma
	for i in 100:
		var w := EquipmentDB.roll("arma", 4, rng, 0, false)
		_check(EquipmentDB.ELEMENTS.has(w.get("element", "")) and w["name"].ends_with(EquipmentDB.ELEMENTS[w["element"]]["label"]),
			"Arma mítica con elemento y nombre (%s)" % w["name"])
		_check(EquipmentDB.WEAPON_MODS.get(w["weapon"], {}).is_empty() or not EquipmentDB.wmod_of(w).is_empty(), "Arma mítica con modificador")
		var rt := EquipmentDB.sanitize(JSON.parse_string(JSON.stringify(w)))
		_check(rt.get("element") == w["element"] and rt.get("wmod") == w.get("wmod"), "Elemento y modificador sobreviven al guardado")
		_check(EquipmentDB.roll("arma", 0, rng, 0, false).get("element", "") == "", "Arma común sin elemento")
	var armor_fire := EquipmentDB.roll("pechera", 0, rng, 0, false)
	armor_fire["base"] = "coraza_fuego"
	armor_fire.erase("set")
	armor_fire["stats"] = {}
	_check(EquipmentDB.element_of(armor_fire) == "fuego", "La coraza de fuego es de fuego")
	_check(EquipmentDB.sanitize(armor_fire.merged({"element": "fuego"})).has("element") == false, "Solo las armas guardan elemento propio")

	var wt: int = eq.current_weapon()
	for s in PlayerEquipment.SLOTS:
		eq.equipped.erase(s)
	eq.weapon_items[wt] = {"uid": "w_test", "slot": "arma", "weapon": wt, "rarity": 2, "stats": {}, "element": "fuego", "wmod": "larga"}
	var ae := eq.active_element()
	_check(ae.get("id") == "fuego" and is_equal_approx(float(ae["power"]), 1.0), "Elemento del arma en la mano")
	var d3 := sb.damage_mult()
	eq.equip(armor_fire)
	_check(is_equal_approx(float(eq.active_element()["power"]), 1.25), "Una pieza del mismo elemento: resonancia +25%")
	_check(is_equal_approx(sb.damage_mult(), d3 + 0.05), "La armadura de fuego suma daño")
	eq.weapon_items[wt]["element"] = ""
	_check(eq.active_element().is_empty(), "Sin elemento en el arma y una sola pieza: nada")
	var armor_fire2 := armor_fire.duplicate(true)
	armor_fire2["slot"] = "pantalones"
	armor_fire2["base"] = "grebas_fuego"
	armor_fire2["uid"] = "pf2"
	eq.equip(armor_fire2)
	_check(eq.active_element().get("id") == "fuego" and is_equal_approx(float(eq.active_element()["power"]), 0.5), "Dos piezas prestan el elemento a media fuerza")
	eq.weapon_items[wt]["element"] = "fuego"
	var sp := WeaponData.WeaponType.SPEAR_LANCE
	eq.weapon_items[sp] = {"uid": "w_sp", "slot": "arma", "weapon": sp, "rarity": 2, "stats": {}, "wmod": ""}
	var mods_base: Dictionary = p.get_weapon_modifiers(sp)
	eq.weapon_items[sp]["wmod"] = "larga"
	_check(is_equal_approx(float(p.get_weapon_modifiers(sp).get("size", 1.0)) - float(mods_base.get("size", 1.0)), 0.25), "Asta larga: +25% alcance")
	eq.weapon_items[sp]["wmod"] = "punta"
	_check(is_equal_approx(float(p.get_weapon_modifiers(sp).get("damage", 1.0)) - float(mods_base.get("damage", 1.0)), 0.15), "Punta afilada: +15% daño")
	eq.weapon_items.erase(sp)

	# Efecto de cada elemento sobre un enemigo de prueba
	var stub_script := GDScript.new()
	stub_script.source_code = "extends Node3D\nvar hp := 100.0\nvar _force_dot := false\nvar chill := 1.0\nfunc take_damage(a, _d = Vector3.ZERO):\n\thp -= a\nfunc apply_chill(f, _t):\n\tchill = f\n"
	stub_script.reload()
	var stub := Node3D.new()
	stub.set_script(stub_script)
	add_child(stub)
	for id in ["fuego", "natural"]:
		for i in 80:
			ElementalHits.apply(id, 1.0, stub, 20.0, p, wt)
		var fx := StatusEffects.get_for(stub)
		_check(fx != null and fx.has("burn" if id == "fuego" else "poison"), "%s aplica su estado" % id)
	for i in 80:
		ElementalHits.apply("frio", 1.0, stub, 20.0, p, wt)
	_check(stub.chill < 1.0, "La escarcha ralentiza")
	p.hp = p.max_hp * 0.5
	var hp_before: float = p.hp
	ElementalHits.apply("sombra", 1.0, stub, 20.0, p, wt)
	_check(p.hp > hp_before, "La sombra roba vida")

	# Golpe real contra un goblin: el elemento del arma lo quema (y el tick de quemadura no vuelve a provocarlo)
	eq.equipped.erase("pechera")
	eq.equipped.erase("pantalones")
	eq.weapon_items[wt]["element"] = "fuego"
	enc._pending.clear()
	var gob = enc._spawn_at(enc.map.arena_index, enc.map.room_center(enc.map.arena_index) + Vector3(4, 0, 0))
	var burned := false
	for i in 60:
		gob.take_damage(2.0, Vector3.ZERO)
		var gfx := StatusEffects.get_for(gob)
		if gfx != null and gfx.has("burn"):
			burned = true
			break
	_check(burned, "Un golpe con arma de fuego quema al goblin")
	var hp_g: float = gob.hp
	gob._force_dot = true
	gob.take_damage(1.0, Vector3.ZERO)
	gob._force_dot = false
	_check(is_equal_approx(gob.hp, hp_g - 1.0), "El tick de quemadura solo resta vida")
	if not _done(12, "elementos y modificadores de arma"): return

	# 13. Fase 4: sensación de botín (columna de luz, avisos de efectos, comparación de rasgos)
	var pk_common := EquipmentPickup.spawn(scene, enc.player.global_position + Vector3(6, 0, 0), _item("casco", {"damage": 0.1}, 0))
	var pk_rare := EquipmentPickup.spawn(scene, enc.player.global_position + Vector3(8, 0, 0), _item("casco", {"damage": 0.1}, 2))
	var pk_myth := EquipmentPickup.spawn(scene, enc.player.global_position + Vector3(10, 0, 0), _item("casco", {"damage": 0.1}, 4))
	await get_tree().process_frame
	_check(pk_common.beam == null, "Una pieza común no lleva columna de luz")
	_check(pk_rare.beam != null and pk_myth.beam != null, "Rara y mítica sí")
	_check((pk_myth.beam.mesh as CylinderMesh).height > (pk_rare.beam.mesh as CylinderMesh).height, "La mítica es más alta")
	for pk in [pk_common, pk_rare, pk_myth]:
		pk.queue_free()

	var hud: EquipmentHud = scene.get_node("EquipmentHud")
	for s in PlayerEquipment.SLOTS:
		eq.equipped.erase(s)
	eq.equip(perk_item.call("pantalones", "pies_niebla"))
	p.notify_equipment("dodge")
	_check(is_instance_valid(hud.last_popup) and hud.last_popup.text.contains("Pies de Niebla"), "El HUD avisa del efecto activado")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(hud._buffs.text.contains("Pies de Niebla"), "El HUD lista el bonus temporal con su tiempo")
	eq._buffs.clear()

	var pop_target := Node3D.new()
	add_child(pop_target)
	ElementalHits._pop(pop_target, "QUEMADO", Color.ORANGE)
	_check(pop_target.get_child_count() == 1 and pop_target.get_child(0) is Label3D, "Aviso flotante del elemento")
	ElementalHits._pop(pop_target, "QUEMADO", Color.ORANGE)
	_check(pop_target.get_child_count() == 1, "No se repite el aviso al instante")

	eq.equip(perk_item.call("casco", "sed_mana"))
	eq.bag.clear()
	var better: Dictionary = perk_item.call("casco", "contragolpe")
	better["perk"] = "contragolpe"
	eq.bag.append(better)
	var panel2 := EquipmentPanel.create(eq, sb)
	add_child(panel2)
	await get_tree().process_frame
	var found_cmp := false
	panel2.select_bag(better)
	for l in panel2._detail.find_children("*", "Label", true, false):
		if (l as Label).text.begins_with("Ahora llevas") and (l as Label).text.contains("Sed de Maná"):
			found_cmp = true
	_check(found_cmp, "La mochila compara el efecto con el que llevas")
	panel2.close()
	if not _done(13, "sensación de botín"): return

	# 14. Fase 3: sets de 4-5 piezas con mecánica (armadura + talismán + arma del mismo elemento)
	for i in 60:
		var w2 := EquipmentDB.roll("arma", 4, rng, 0, false)
		_check(w2.get("set") == w2.get("element"), "El arma con elemento es pieza de su set")
	for id in ["totem_ardiente", "colmillo_helado", "semilla_viva", "sello_sombra"]:
		_check(EquipmentDB.SETS.has(EquipmentDB.BASES["talisman"][id]["set"]), "Talismán de set %s" % id)
	var old_w := {"slot": "arma", "weapon": WeaponData.WeaponType.MACE, "rarity": 2, "element": "frio", "stats": {}}
	_check(EquipmentDB.sanitize(old_w).get("set") == "frio", "Un arma guardada antes de la Fase 3 recibe su set")
	for s2 in PlayerEquipment.SLOTS:
		eq.equipped.erase(s2)
	var mk := func(kind: String, base: String, set_id: String) -> Dictionary:
		var x := EquipmentDB.roll(kind, 1, rng, 0, false)
		x["base"] = base
		x["set"] = set_id
		x["stats"] = {}
		x.erase("perk")
		return x
	eq.equip(mk.call("pechera", "coraza_fuego", "fuego"))
	eq.equip(mk.call("pantalones", "grebas_fuego", "fuego"))
	eq.equip(mk.call("talisman", "totem_ardiente", "fuego"), "talisman_1")
	eq.weapon_items[wt] = {"uid": "w_fire", "slot": "arma", "weapon": wt, "rarity": 2, "stats": {}, "element": "fuego", "set": "fuego"}
	eq.equipment_changed.emit()
	_check(eq.set_counts().get("fuego", 0) == 4, "Cuatro piezas del set de fuego")
	_check(is_equal_approx(eq.set_special("element_power"), 0.4), "El nivel 4 refuerza el elemento")
	_check(is_equal_approx(float(eq.active_element()["power"]), 1.0 + 0.25 * 2 + 0.4), "Resonancia + set")
	_check(not eq.set_bonus().has("perk") and not eq.set_bonus().has("element_power"), "Las claves especiales no se cuelan como stats")
	var sum := eq.set_summary()
	_check(sum.any(func(l): return l.begins_with("Brasa Viva  4/4")) and sum.any(func(l): return l.begins_with("✓ [4]")), "Resumen del set")
	StatusEffects.get_for(stub).clear_all()
	stub.global_position = p.global_position + Vector3(2, 0, 0)
	stub.add_to_group("enemies")
	var dd := sb.damage_mult()
	p.notify_equipment("kill")
	_check(StatusEffects.get_for(stub).has("burn"), "La baja lanza una onda de fuego que quema a los cercanos")
	_check(is_equal_approx(sb.damage_mult(), dd + 0.15), "Y da +15% daño")
	eq._buffs.clear()
	stub.global_position = p.global_position + Vector3(30, 0, 0)
	StatusEffects.get_for(stub).clear_all()
	eq._perk_ready.clear()
	p.notify_equipment("kill")
	_check(not StatusEffects.get_for(stub).has("burn"), "Los lejanos no se queman")
	stub.remove_from_group("enemies")
	eq.weapon_items[wt]["element"] = ""
	eq.weapon_items[wt].erase("set")
	eq.equipment_changed.emit()
	_check(eq.set_counts().get("fuego", 0) == 3 and not eq.perk_sources().any(func(sr): return String(sr["uid"]).begins_with("set:")), "Sin el arma son 3 piezas: la mecánica se apaga")
	var panel3 := EquipmentPanel.create(eq, sb)
	add_child(panel3)
	await get_tree().process_frame
	_check(panel3._stats_label.text.contains("Brasa Viva"), "El panel muestra los niveles del set")
	panel3.close()
	if not _done(14, "sets con mecánica"): return

	# 15. Tarjeta de información: ratón encima (PC) y pulsación larga (táctil)
	for s3 in PlayerEquipment.SLOTS:
		eq.equipped.erase(s3)
	eq.bag.clear()
	var named := EquipmentDB.roll("casco", 3, rng, 0, false)
	named["name"] = "Yelmo de Prueba"
	eq.equip(named)
	var cand := EquipmentDB.roll("casco", 2, rng, 0, false)
	cand["name"] = "Candidato de Prueba"
	eq.bag.append(cand)
	eq.equipment_changed.emit()
	var panel4 := EquipmentPanel.create(eq, sb)
	add_child(panel4)
	await get_tree().process_frame
	var sk: StoneUI.Socket = panel4._plate.sockets[0]
	var card_text := func() -> String:
		var t := ""
		if StoneUI.card_visible():
			for lb in StoneUI._card.find_children("*", "Label", true, false):
				t += (lb as Label).text + "
"
		return t
	sk.mouse_entered.emit()
	await get_tree().create_timer(0.4).timeout
	_check(StoneUI.card_visible() and card_text.call().contains("Yelmo de Prueba"), "Ratón encima: sale la tarjeta de la pieza")
	sk.mouse_exited.emit()
	await get_tree().process_frame
	_check(not StoneUI.card_visible(), "Al quitar el ratón se oculta")
	var empty_sk: StoneUI.Socket = panel4._plate.sockets[4]
	empty_sk.mouse_entered.emit()
	await get_tree().create_timer(0.4).timeout
	_check(not StoneUI.card_visible(), "Un hueco vacío no muestra tarjeta")
	var press := InputEventScreenTouch.new()
	press.pressed = true
	var release := InputEventScreenTouch.new()
	release.pressed = false
	sk._gui_input(press)
	await get_tree().create_timer(0.15).timeout
	sk._gui_input(release)
	await get_tree().create_timer(0.5).timeout
	_check(not StoneUI.card_visible() and not sk.take_long_press(), "Un toque corto no muestra la tarjeta")
	sk._gui_input(press)
	await get_tree().create_timer(0.6).timeout
	_check(StoneUI.card_visible() and card_text.call().contains("Yelmo de Prueba"), "Pulsación larga: sale la tarjeta")
	sk._gui_input(release)
	await get_tree().process_frame
	_check(not StoneUI.card_visible(), "Al soltar el dedo se oculta")
	_check(sk.take_long_press() and not sk.take_long_press(), "La pulsación larga no cuenta como clic (una sola vez)")
	var bag_sk: StoneUI.Socket = panel4._bag_plate.sockets[0]
	bag_sk.mouse_entered.emit()
	await get_tree().create_timer(0.4).timeout
	_check(card_text.call().contains("Candidato de Prueba") and card_text.call().contains("Ahora llevas") or card_text.call().contains("Candidato de Prueba"), "La tarjeta de la mochila trae la comparación")
	bag_sk.mouse_exited.emit()
	panel4.close()
	await get_tree().process_frame
	_check(not StoneUI.card_visible(), "Cerrar el panel no deja tarjetas sueltas")
	if not _done(15, "tarjeta de información"): return

	# 16. Tocar una ranura abre el menú de objetos de la mochila que caben en ella
	for s4 in PlayerEquipment.SLOTS:
		eq.equipped.erase(s4)
	eq.bag.clear()
	var h1 := EquipmentDB.roll("casco", 2, rng, 0, false)
	h1["name"] = "Casco Uno"
	var h2 := EquipmentDB.roll("casco", 1, rng, 0, false)
	h2["name"] = "Casco Dos"
	var ch := EquipmentDB.roll("pechera", 2, rng, 0, false)
	ch["name"] = "Pechera Uno"
	var tl1 := EquipmentDB.roll("talisman", 2, rng, 0, false)
	tl1["name"] = "Talisman Uno"
	eq.bag.append_array([h1, ch, h2, tl1])
	eq.equipment_changed.emit()
	var panel5 := EquipmentPanel.create(eq, sb)
	add_child(panel5)
	await get_tree().process_frame
	panel5.select_slot("casco")
	await get_tree().process_frame
	var rows := panel5._detail.find_children("Equipar", "Button", true, false)
	_check(rows.size() == 2, "El menú del casco lista solo los dos cascos de la mochila (%d)" % rows.size())
	var txt := ""
	for lb in panel5._detail.find_children("*", "Label", true, false):
		txt += (lb as Label).text + "|"
	_check(txt.contains("Casco Uno") and txt.contains("Casco Dos") and not txt.contains("Pechera Uno") and not txt.contains("Talisman Uno"), "No salen objetos de otras ranuras")
	(rows[0] as Button).pressed.emit()
	await get_tree().process_frame
	_check(eq.get_item("casco")["name"] == "Casco Uno" and eq.bag.size() == 3, "Elegir uno lo equipa en esa ranura")
	panel5.select_slot("talisman_2")
	await get_tree().process_frame
	var trows := panel5._detail.find_children("Equipar", "Button", true, false)
	_check(trows.size() == 1, "El menú del talismán lista el talismán de la mochila")
	(trows[0] as Button).pressed.emit()
	await get_tree().process_frame
	_check(eq.get_item("talisman_2").get("name", "") == "Talisman Uno" and eq.get_item("talisman_1").is_empty(), "Se equipa en la ranura que tocaste, no en la primera libre")
	panel5.select_slot("pantalones")
	await get_tree().process_frame
	_check(panel5._detail.find_children("Equipar", "Button", true, false).is_empty(), "Sin objetos para la ranura no hay botones")
	panel5.close()
	await get_tree().process_frame
	if not _done(16, "menú de objetos por ranura"): return

	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_equipment_save.json"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_equipment_armeria.cfg"))
	print("ALL EQUIPMENT CHECKS PASSED")
	get_tree().quit(0)
