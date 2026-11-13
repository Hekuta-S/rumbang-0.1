extends Node

## Fase 4 del plan de loot: forja de Tatán (mejorar, re-tirar, desguazar), garantía de botín y números de daño.

var enc: DungeonEncounter
var player: Node3D
var eq: PlayerEquipment
var arena: Vector3

func _ready() -> void:
	print("--- TEST: DUNGEON ECONOMY (FASE 4) ---")
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
	eq = player.get("equipment")
	eq.persist = false
	arena = enc.map.room_center(enc.map.arena_index)
	player.global_position = arena + Vector3(0, 0.3, 14)
	var gs := GameState.get_instance()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5

	# 1. Mejorar y re-tirar (funciones puras)
	var t := EquipmentDB.roll("talisman", 1, rng)
	t.erase("legendary")
	assert(EquipmentForge.can_upgrade(t), "Una poco común se puede mejorar")
	assert(EquipmentForge.upgrade_price(t, 1) < EquipmentForge.upgrade_price({"rarity": 2}, 1), "Mejorar cuesta más cuanto más rara")
	assert(EquipmentForge.upgrade(t, rng) and int(t["rarity"]) == 2, "Sube a rara")
	assert(not (t["stats"] as Dictionary).is_empty(), "Stats nuevos")
	var leg := EquipmentDB.legendary_item("corona_rey")
	assert(not EquipmentForge.can_upgrade(leg) and not EquipmentForge.reroll(leg), "Las legendarias fijas no se tocan")
	assert(not EquipmentForge.can_upgrade({"slot": "casco", "rarity": EquipmentForge.MAX_RARITY}), "Tope de rareza")
	var c := {"slot": "talisman", "rarity": 2, "stats": {}, "cond": "verdugo", "uid": "c1", "name": "T"}
	EquipmentForge.reroll(c, rng)
	var first_cond := String(c["cond"])
	var changed := false
	for i in 10:
		var before: Dictionary = (c["stats"] as Dictionary).duplicate()
		EquipmentForge.reroll(c, rng)
		changed = changed or c["stats"] != before
	assert(changed and first_cond != "verdugo" and EquipmentDB.CONDITIONALS.has(first_cond), "Re-tirar cambia stats y rasgo (%s)" % first_cond)
	print("CHECK 1 PASSED: mejorar y re-tirar")

	# 2. La forja en la tienda: submenú, mejorar una pieza equipada y desguazar la mochila
	var shop := DungeonShop.spawn(enc.get_parent(), player.global_position + Vector3(20, 0, 0), player, 2)
	eq.equipped.clear()
	eq.bag.clear()
	eq.equipped["talisman_1"] = {"slot": "talisman", "rarity": 1, "stats": {"damage": 0.05}, "uid": "f1", "name": "Forjable"}
	gs.gold = 1000
	shop.open()
	shop._buy("mode:menu")
	var ids: Array = shop._ui._options.map(func(o): return o["id"])
	assert(ids.has("mode:upgrade") and ids.has("mode:reroll") and ids.has("mode:scrap") and ids.has("back"), "Submenú de la forja")
	shop._buy("mode:upgrade")
	ids = shop._ui._options.map(func(o): return o["id"])
	assert(ids.has("up:talisman_1") and ids.has("up:arma"), "Lista de piezas equipadas (%s)" % str(ids))
	var price := EquipmentForge.upgrade_price(eq.equipped["talisman_1"], 2)
	shop._buy("up:talisman_1")
	assert(int(eq.equipped["talisman_1"]["rarity"]) == 2 and gs.gold == 1000 - price, "Mejorada y cobrada (oro %d)" % gs.gold)
	var junk := {"slot": "casco", "rarity": 2, "stats": {}, "uid": "junk", "name": "Chatarra", "base": "x"}
	eq.bag.append(junk)
	var g0 := gs.gold
	shop._buy("back")
	shop._buy("mode:scrap")
	shop._buy("scrap:junk")
	assert(eq.bag.is_empty() and gs.gold == g0 + EquipmentForge.scrap_value(junk), "Desguazada por %d de oro" % EquipmentForge.scrap_value(junk))
	shop._buy("back")
	shop._buy("back")
	assert(shop._mode == "" and shop._ui._options.any(func(o): return o["id"] == "mode:menu"), "Volver a la tienda")
	shop._ui._close()
	shop.queue_free()
	print("CHECK 2 PASSED: forja en la tienda")

	# 3. Garantía de botín
	gs.pity_kills = 0
	gs.pity_since_rare = 0
	for i in DungeonRun.PITY_KILLS - 1:
		assert(not DungeonRun.note_kill_for_loot(), "Aún no toca")
	assert(DungeonRun.note_kill_for_loot(), "A las %d bajas toca pieza" % DungeonRun.PITY_KILLS)
	gs.pity_kills = DungeonRun.PITY_KILLS - 1
	var g := enc._spawn_at(enc.map.arena_index, arena + Vector3(3, 0, 0), "goblin")
	g.set_physics_process(false)
	var drop := EquipmentPickup.drop_for_enemy(enc.get_parent(), g)
	assert(drop != null and gs.pity_kills == 0, "La baja garantizada suelta pieza y reinicia")
	gs.pity_since_rare = DungeonRun.PITY_RARE_DROPS
	var rare := EquipmentPickup.try_drop(enc.get_parent(), arena, 1.0)
	assert(rare != null and int(rare.item["rarity"]) >= ItemDB.Rarity.RARE and gs.pity_since_rare == 0, "Tras %d sin rara, sale rara" % DungeonRun.PITY_RARE_DROPS)
	print("CHECK 3 PASSED: garantía de botín")

	# 4. Números de daño
	assert(DamageNumbers.classify(10, 10, 10, false, false, false, false) == "normal", "normal")
	assert(DamageNumbers.classify(10, 15, 15, false, false, false, false) == "bonus", "potenciado")
	assert(DamageNumbers.classify(10, 10, 5, false, false, false, false) == "resisted", "resistido")
	assert(DamageNumbers.classify(10, 10, 10, false, true, false, false) == "stunned", "aturdido")
	assert(DamageNumbers.classify(10, 10, 10, true, true, true, true) == "dot", "tick")
	assert(DamageNumbers.classify(10, 10, 10, false, false, true, true) == "kill", "baja")
	assert(DamageNumbers.text_for(2.5) == "2.5" and DamageNumbers.text_for(12.4) == "12" and DamageNumbers.text_for(3.0) == "3", "Decimales solo en daños pequeños")
	var g2 := enc._spawn_at(enc.map.arena_index, arena + Vector3(-3, 0, 0), "goblin")
	g2.set_physics_process(false)
	eq.equipped.clear()
	g2.add_stun_fraction(1.0)
	g2.take_damage(1.5)
	var lbl := _find_label(get_tree().root, "1.5!")
	assert(lbl != null and lbl.modulate.is_equal_approx(DamageNumbers.STYLES["stunned"]["color"]), "Golpe a aturdido: número cian con decimal")
	print("CHECK 4 PASSED: números de daño")

	print("ALL ECONOMY CHECKS PASSED")
	get_tree().quit(0)

func _find_label(n: Node, text: String) -> Label3D:
	if n is Label3D and (n as Label3D).text == text and (n as Label3D).visible:
		return n
	for ch in n.get_children():
		var r := _find_label(ch, text)
		if r:
			return r
	return null
