extends Node

## Objetos de supervivencia con pasivas únicas y activas (ItemEffects, ActiveItemSlot) e iconos de ItemDB.
var _main: Node
var _fail := false
func _check(ok: bool, msg: String) -> void:
	print("%s: %s" % ["PASSED" if ok else "FAILED", msg])
	if not ok:
		_fail = true

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.game_mode = "survival"
	SaveManager.save_path = "user://test_save.json"
	SaveManager.meta = {}
	_main = load("res://scenes/core/main_procedural.tscn").instantiate()
	get_tree().root.add_child.call_deferred(_main)
	await get_tree().process_frame
	get_tree().current_scene = _main
	var p = null
	var waves: WaveManager = null
	for i in 900:
		await get_tree().process_frame
		p = _main.get_node_or_null("Player")
		waves = _main.find_child("WaveManager", true, false)
		if p and waves and waves._running:
			break
	_check(waves != null and waves._running, "arranca la partida")
	waves.stop_run()
	waves._running = true
	p.health_comp.max_hp = 1000.0
	p.health_comp.hp = 1000.0
	var fx: ItemEffects = p.item_effects
	var inv: InventoryComponent = p.inventory
	_check(fx != null, "el jugador de supervivencia tiene ItemEffects")

	# 0. Iconos: todos los objetos del pool tienen dibujo
	var missing: Array = []
	for it in ItemDB.get_all_items():
		if not ResourceLoader.exists("res://assets/ui/icons/items/%s.png" % it["id"]):
			missing.append(it["id"])
	_check(missing.is_empty(), "todos los objetos tienen icono %s" % str(missing))

	var pos: Vector3 = p.global_position + Vector3(8, 0, 0)

	# 1. Mecha de Tejo: al 8.º golpe estalla y daña a otro enemigo cercano
	inv.add_item("mecha_tejo")
	var a: EnemyData = waves._spawn_single_enemy(pos, EnemyData.EnemyType.NORMAL_GOBLIN)[0]
	var b: EnemyData = waves._spawn_single_enemy(pos + Vector3(1.5, 0, 0), EnemyData.EnemyType.NORMAL_GOBLIN)[0]
	a.max_hp = 100000.0
	a.hp = a.max_hp
	b.max_hp = 100000.0
	b.hp = b.max_hp
	for i in ItemEffects.TEJO_EVERY - 1:
		a.take_damage(5.0)
	_check(is_equal_approx(b.hp, b.max_hp), "el tejo no estalla antes de tiempo")
	a.take_damage(5.0)
	_check(b.hp < b.max_hp, "el tejo estalla al %d.º golpe (b perdió %.0f)" % [ItemEffects.TEJO_EVERY, b.max_hp - b.hp])
	_check(fx._tejo_hits == 0, "la explosión no cuenta como golpe")

	# 2. Totuma de Chicha: cura y da invulnerabilidad al subir de nivel
	inv.add_item("totuma_chicha")
	p.health_comp.hp = 100.0
	fx._on_level_up()
	_check(p.health_comp.hp >= 100.0 + 1000.0 * ItemEffects.TOTUMA_HEAL - 1.0, "la totuma cura al subir de nivel")
	_check(p.health_comp.invincibility_time >= ItemEffects.TOTUMA_INVULN - 0.1, "la totuma da invulnerabilidad")
	p.health_comp.invincibility_time = 0.0

	# 3. Ruana de la Llorona: aturde a los cercanos al recibir daño, con enfriamiento
	inv.add_item("ruana_llorona")
	var c: EnemyData = waves._spawn_single_enemy(p.global_position + Vector3(2, 0, 0), EnemyData.EnemyType.NORMAL_GOBLIN)[0]
	fx.on_hurt()
	_check(c.slow_multiplier == 0.0 and c.slow_timer >= ItemEffects.LLORONA_STUN - 0.1, "la ruana aturde a los cercanos")
	var ready_at := fx._llorona_ready
	fx.on_hurt()
	_check(is_equal_approx(fx._llorona_ready, ready_at), "la ruana respeta su enfriamiento")

	# 4. Sangre de Mohán: robo de vida por copia
	_check(is_zero_approx(fx.lifesteal()), "sin sangre no hay robo de vida")
	inv.add_item("sangre_mohan")
	inv.add_item("sangre_mohan")
	_check(is_equal_approx(fx.lifesteal(), 0.04), "dos copias = 4% de robo de vida")

	# 5. Activas: hueco único, la nueva sustituye a la anterior
	_check(not fx.has_active(), "sin activa al principio")
	inv.add_item("tamal_emergencia")
	_check(fx.active_id() == "tamal_emergencia", "el tamal ocupa el hueco activo")
	p.health_comp.hp = 100.0
	p.activate_skill()
	_check(p.health_comp.hp >= 100.0 + 1000.0 * ItemEffects.TAMAL_HEAL - 1.0, "E usa el tamal y cura")
	_check(not p.is_berserk, "E no activa el Berserk si hay activa")
	_check(fx.cooldown_left() > 59.0 and not fx.use_active(), "el tamal queda recargando")
	inv.add_item("totumo_polvora")
	_check(fx.active_id() == "totumo_polvora" and not inv.has_item("tamal_emergencia"), "el totumo sustituye al tamal")
	_check(fx.cooldown_left() == 0.0, "la activa nueva llega lista")
	var d: EnemyData = waves._spawn_single_enemy(p.global_position + Vector3(0, 0, -4), EnemyData.EnemyType.NORMAL_GOBLIN)[0]
	d.max_hp = 100000.0
	d.hp = d.max_hp
	var target := d.global_position
	var at := fx._aim_ground()
	# Bomba directa sobre el enemigo (el apuntado depende de la cámara)
	var hits := fx._blast(target, ItemEffects.POLVORA_RADIUS, 50.0, 0.0, Color.WHITE)
	_check(hits >= 1 and d.hp < d.max_hp, "la bomba del totumo daña (%d enemigos)" % hits)
	_check(Vector2(at.x - p.global_position.x, at.z - p.global_position.z).length() <= ItemEffects.POLVORA_RANGE + 0.01, "la bomba cae a su alcance")
	_check(fx.use_active() and fx.cooldown_left() > 9.0, "el totumo se usa y recarga")

	# 6. HUD: el hueco activo se muestra con su icono
	await get_tree().process_frame
	await get_tree().process_frame
	var slot: ActiveItemSlot = _main.find_child("ActiveItemSlot", true, false)
	_check(slot != null and slot.visible and slot._icon.texture != null, "el HUD muestra la activa con icono")
	inv.remove_item("totumo_polvora")
	await get_tree().process_frame
	_check(slot != null and not slot.visible, "sin activa el hueco se oculta")
	p.activate_skill()
	_check(p.is_berserk, "sin activa la E vuelve al Berserk")

	p.is_berserk = false

	# 8. Segunda tanda de pasivas
	# Sombrero Vueltiao: a las 15 bajas, remolino que daña a los cercanos
	inv.add_item("sombrero_vueltiao")
	var tank: EnemyData = waves._spawn_single_enemy(p.global_position + Vector3(2, 0, 0), EnemyData.EnemyType.NORMAL_GOBLIN)[0]
	tank.max_hp = 100000.0
	tank.hp = tank.max_hp
	for i in ItemEffects.VUELTIAO_EVERY:
		var victim: EnemyData = waves._spawn_single_enemy(p.global_position + Vector3(30, 0, 0), EnemyData.EnemyType.NORMAL_GOBLIN)[0]
		victim.take_damage(victim.hp + 1.0)
	await get_tree().process_frame
	_check(tank.hp < tank.max_hp and fx._kills < ItemEffects.VUELTIAO_EVERY, "el vueltiao suelta el remolino a las %d bajas" % ItemEffects.VUELTIAO_EVERY)

	# Collar de la Madremonte: las bajas dejan enredaderas que ralentizan (con tope)
	inv.add_item("collar_madremonte")
	for i in 60:
		var v2: EnemyData = waves._spawn_single_enemy(p.global_position + Vector3(30, 0, 5), EnemyData.EnemyType.NORMAL_GOBLIN)[0]
		v2.take_damage(v2.hp + 1.0)
	var vines := get_tree().get_nodes_in_group("vine_patches")
	_check(vines.size() > 0 and vines.size() <= ItemEffects.VINE_MAX, "la madremonte deja enredaderas (%d, tope %d)" % [vines.size(), ItemEffects.VINE_MAX])
	var slowed: EnemyData = waves._spawn_single_enemy(vines[0].global_position if vines.size() > 0 else p.global_position, EnemyData.EnemyType.NORMAL_GOBLIN)[0]
	await get_tree().create_timer(VinePatch.TICK + 0.1, true, false, true).timeout
	_check(slowed.slow_multiplier <= VinePatch.SLOW + 0.01, "la enredadera ralentiza")

	# Ojo de Candileja: quema a los pegados
	inv.add_item("ojo_candileja")
	var burnt: EnemyData = waves._spawn_single_enemy(p.global_position + Vector3(1.2, 0, 0), EnemyData.EnemyType.NORMAL_GOBLIN)[0]
	burnt.max_hp = 100000.0
	burnt.hp = burnt.max_hp
	await get_tree().create_timer(ItemEffects.CANDILEJA_TICK * 3.0, true, false, true).timeout
	_check(burnt.hp < burnt.max_hp, "la candileja quema a los cercanos (%.1f)" % (burnt.max_hp - burnt.hp))

	# Hamaca del Abuelo: quieto, armadura extra y cura
	var armor0: float = p.stat_block.armor()
	inv.add_item("hamaca_abuelo")
	p.velocity = Vector3.ZERO
	fx._still_t = ItemEffects.HAMACA_STILL + 0.1
	_check(fx.hamaca_on() and p.stat_block.armor() >= armor0 + ItemEffects.HAMACA_ARMOR - 0.001, "la hamaca da armadura estando quieto")
	fx.on_hurt()
	_check(not fx.hamaca_on(), "un golpe te saca de la hamaca")
	fx._still_t = 0.0

	# Pacto de la Patasola: el golpe mortal te deja a media vida, una vez
	inv.add_item("pacto_patasola")
	p.health_comp.invincibility_time = 0.0
	p.health_comp.hp = 50.0
	p.health_comp.take_damage(5000.0)
	_check(is_equal_approx(p.health_comp.hp, 1000.0 * ItemEffects.PATASOLA_HP), "el pacto te salva a media vida (%.0f)" % p.health_comp.hp)
	_check(not inv.has_item("pacto_patasola"), "el pacto se rompe")

	# Moneda del Duende: a veces la gema vale el doble
	_check(ItemEffects.xp_roll() == 1.0 or inv.has_item("moneda_duende"), "sin moneda la gema vale lo normal")
	inv.add_item("moneda_duende")
	var doubles := 0
	for i in 2000:
		if ItemEffects.xp_roll() > 1.0:
			doubles += 1
	_check(doubles > 150 and doubles < 900, "la moneda duplica algunas gemas (%d de 2000)" % doubles)

	# 9. Segunda tanda de activas
	p.health_comp.hp = 1000.0
	inv.add_item("campana_iglesia")
	var bell: EnemyData = waves._spawn_single_enemy(p.global_position + Vector3(6, 0, 0), EnemyData.EnemyType.NORMAL_GOBLIN)[0]
	_check(fx.use_active() and bell.slow_multiplier == 0.0, "la campana congela")
	inv.add_item("garrafon_aguardiente")
	var cd0: float = p.stat_block.cooldown_mult()
	_check(fx.use_active() and fx.furia_on() and p.stat_block.cooldown_mult() < cd0, "el garrafón acelera los ataques")
	fx._furia_until = 0.0
	inv.add_item("trompo_guerra")
	_check(fx.use_active(), "se lanza el trompo")
	await get_tree().process_frame
	var top: WarTop = _main.find_child("*WarTop*", true, false)
	if top == null:
		for n in get_tree().current_scene.get_children():
			if n is WarTop:
				top = n
	_check(top != null, "el trompo aparece")
	inv.add_item("machete_relampago")
	var start: Vector3 = p.global_position
	_check(fx.use_active(), "se usa el machete")
	_check(p.global_position.distance_to(start) <= ItemEffects.MACHETE_DIST + 0.05, "el machete avanza como mucho %d m" % int(ItemEffects.MACHETE_DIST))

	# 7. Mazmorra: no se ofrecen pasivas ni activas
	GameData.game_mode = "dungeon"
	var leaked := ItemDB.get_available_items().filter(func(it): return it.has("kind"))
	GameData.game_mode = "survival"
	_check(leaked.is_empty(), "en la mazmorra no salen pasivas ni activas")

	print("ALL PASSED" if not _fail else "SOME FAILED")
	get_tree().quit(1 if _fail else 0)
