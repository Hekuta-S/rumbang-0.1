extends Node

## Ranura de AMULETO de la mazmorra (EquipmentDB "amuleto", PlayerEquipment, AmuletActives): sorteo, guardado JSON,
## equipar, tecla E (Player.activate_skill) y las cuatro activas: Pata de Conejo, Botella de Aguardiente,
## Espejo del Mohán y Pluma de Gallinazo. Carga la mazmorra real.

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

func _amulet(base: String, rarity: int = 0) -> Dictionary:
	var it := EquipmentDB.roll("amuleto", rarity, null, 0, false)
	it["base"] = base
	it["name"] = String(EquipmentDB.BASES["amuleto"][base]["name"])
	it["stats"] = {}
	return it

func _ready() -> void:
	print("--- TEST: AMULETOS ---")
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveManager.save_path = "user://test_amulets_save.json"
	SaveManager.meta = {}
	GameData.armory_path = "user://test_amulets_armeria.cfg"
	GameData.dungeon_weapon = WeaponData.WeaponType.SPEAR_LANCE
	GameData.game_mode = "dungeon"
	GameData.selected_index = GameData.custom_index()

	# 1. Datos: cada base tiene activa, el sorteo da amuletos con 0-1 stats y sin efectos, sobreviven al JSON
	for id in EquipmentDB.BASES["amuleto"]:
		_check(AmuletActives.ACTIVES.has(id), "La base %s tiene activa" % id)
		_check(AmuletActives.icon(_amulet(id)) != null, "La base %s tiene icono" % id)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var seen := 0
	for i in 400:
		var any := EquipmentDB.roll("", -1, rng)
		if any["slot"] == "amuleto":
			seen += 1
	_check(seen > 20, "Los amuletos salen en el botín normal (%d de 400)" % seen)
	for r in 5:
		var a := EquipmentDB.roll("amuleto", r, rng, 0, false)
		_check(a["stats"].size() == (0 if r == 0 else 1), "Rareza %d: %d stat" % [r, a["stats"].size()])
		_check(not a.has("perk") and not a.has("cond"), "Sin efecto ni rasgo")
		_check(AmuletActives.id_of(a) != "", "Su base es una activa")
		_check(EquipmentDB.slots_for(a) == ["amuleto"], "Va en la ranura de amuleto")
	_check(AmuletActives.cooldown(_amulet("pata_conejo", 4)) < AmuletActives.cooldown(_amulet("pata_conejo", 0)),
		"La rareza acorta el enfriamiento")
	var back := EquipmentDB.sanitize(JSON.parse_string(JSON.stringify(_amulet("espejo_mohan", 2))))
	_check(AmuletActives.id_of(back) == "espejo_mohan", "Sobrevive al JSON")
	_check(EquipmentDB.sanitize({"slot": "amuleto", "base": "nada"}).is_empty(), "Rechaza amuletos sin activa")
	_check(EquipmentDB.describe(_amulet("pluma_gallinazo")).contains("(E)"), "La descripción explica la activa")
	if not _done(1, "datos y sorteo"): return

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
	eq.persist = false
	_check(PlayerEquipment.SLOTS.has("amuleto"), "PlayerEquipment tiene la ranura")
	_check(not eq.has_amulet(), "Empieza sin amuleto")
	# Sin amuleto la E sigue siendo el Berserk
	p.interact_target = null
	p.skill_cd_timer = 0.0
	p.activate_skill()
	_check(p.is_berserk, "Sin amuleto: Berserk")
	p.is_berserk = false
	var hud := scene.get_node_or_null("EquipmentHud") as EquipmentHud
	_check(hud != null and EquipmentHud.SLOTS.has("amuleto"), "El HUD muestra la ranura")
	if not _done(2, "ranura en el jugador"): return

	# 3. Pata de Conejo: la E arma el golpe; el siguiente golpe hace ×3 y aturde; luego enfriamiento
	_check(eq.receive(_amulet("pata_conejo")) == "equipped", "Se equipa al recogerlo (ranura libre)")
	_check(eq.has_amulet(), "Lleva amuleto")
	var gob = enc._spawn_at(enc.map.arena_index, enc.map.room_center(enc.map.arena_index) + Vector3(4, 0, 0))
	await get_tree().process_frame
	gob.max_hp = 1000.0
	gob.hp = 1000.0
	gob.take_damage(10.0, Vector3.ZERO)
	var normal: float = 1000.0 - gob.hp
	p.activate_skill()
	_check(eq.rabbit_armed and not p.is_berserk, "La E usa el amuleto, no el Berserk")
	_check(eq.amulet_cooldown_left() > 19.0, "Enfriamiento de 20 s")
	var hp1: float = gob.hp
	gob.take_damage(10.0, Vector3.ZERO)
	await get_tree().process_frame
	var lucky: float = hp1 - gob.hp
	_check(normal > 0.0 and is_equal_approx(lucky / normal, 3.0), "Golpe de suerte ×3 (%.1f vs %.1f)" % [lucky, normal])
	_check(not eq.rabbit_armed, "Se gasta en un golpe")
	_check(gob.state == DungeonGoblin.State.STUNNED, "Aturde")
	p.activate_skill()
	_check(not eq.rabbit_armed, "En enfriamiento no vuelve a salir")
	if not _done(3, "Pata de Conejo"): return

	# 4. Botella de Aguardiente: cura y da velocidad de ataque temporal
	eq.equip(_amulet("botella_aguardiente"))
	eq.amulet_ready_t = 0.0
	p.hp = p.max_hp * 0.4
	var hp0: float = p.hp
	var cd0: float = p.stat_block.cooldown_mult()
	p.activate_skill()
	_check(p.hp >= hp0 + p.max_hp * 0.29, "Cura un 30%")
	_check(p.stat_block.cooldown_mult() < cd0, "Ataca más rápido")
	_check(eq.active_buffs().any(func(b): return String(b["name"]) == "Trago Valiente"), "El bonus sale en el HUD")
	eq._buffs[AmuletActives.BUFF_UID]["until"] = 0.0
	_check(is_equal_approx(p.stat_block.cooldown_mult(), cd0), "El bonus se acaba")
	if not _done(4, "Botella de Aguardiente"): return

	# 5. Espejo del Mohán: menos daño recibido y lo devuelve a los cercanos
	eq.equip(_amulet("espejo_mohan"))
	eq.amulet_ready_t = 0.0
	gob.state = DungeonGoblin.State.IDLE if "IDLE" in DungeonGoblin.State else gob.state
	gob.global_position = p.global_position + Vector3(2, 0, 0)
	gob.hp = 1000.0
	p.hp = p.max_hp
	p.health_comp.invincibility_time = 0.0
	p.activate_skill()
	_check(eq.mirror_active(), "Espejo activo")
	var php: float = p.hp
	p.take_damage(10.0, Vector3.ZERO)
	_check(is_equal_approx(php - p.hp, 3.0), "Recibe un 30%% del daño (%.1f)" % (php - p.hp))
	_check(gob.hp < 1000.0, "Devuelve el daño al goblin cercano")
	eq.mirror_until = 0.0
	_check(not eq.mirror_active(), "El espejo se acaba")
	if not _done(5, "Espejo del Mohán"): return

	# 6. Pluma de Gallinazo: teletransporte hacia delante e invulnerable
	eq.equip(_amulet("pluma_gallinazo"))
	eq.amulet_ready_t = 0.0
	gob.queue_free()
	p.health_comp.invincibility_time = 0.0
	var from: Vector3 = p.global_position
	p.activate_skill()
	_check(p.global_position.distance_to(from) > 0.5, "Se mueve (%.1f m)" % p.global_position.distance_to(from))
	_check(p.global_position.distance_to(from) <= AmuletActives.PLUMA_DIST + 0.1, "No pasa del alcance")
	_check(p.health_comp.invincibility_time > 0.0, "Invulnerable un instante")
	if not _done(6, "Pluma de Gallinazo"): return

	# 7. Inventario: el panel enseña la ranura con su nombre
	_check(EquipmentPanel.PLATE_SLOTS.has("amuleto") and EquipmentPanel.SLOT_LABELS.has("amuleto"), "Panel con ranura de amuleto")
	if not _done(7, "UI"): return

	print("ALL AMULET CHECKS PASSED")
	get_tree().quit(0)
