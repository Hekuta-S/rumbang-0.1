extends Node

## Dado del destino (FateDice) en supervivencia y en la mazmorra: aparece con su modelo, la tirada deja arriba
## la cara del valor y cada resultado hace lo suyo. Headless:
##   godot --headless --path . res://tests/test_fate_dice.tscn

var _fails := 0

func _check(ok: bool, msg: String) -> void:
	print(("PASSED: " if ok else "FAILED: ") + msg)
	if not ok:
		_fails += 1

func _ready() -> void:
	print("--- TEST: DADO DEL DESTINO ---")
	SaveManager.save_path = "user://test_save.json"
	# Mazmorra primero: los enemigos de supervivencia siguen registrados (EnemyRegistry) tras liberar la escena
	await _dungeon()
	await _survival()
	FateDice.clear_mods()
	print("ALL FATE DICE CHECKS PASSED" if _fails == 0 else "FAILS: %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _survival() -> void:
	GameData.game_mode = "survival"
	SaveManager.meta = {}
	var main: Node = load("res://scenes/core/main_procedural.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	get_tree().current_scene = main
	var p: Node3D = null
	var waves: WaveManager = null
	for i in 900:
		await get_tree().process_frame
		p = main.get_node_or_null("Player")
		waves = main.find_child("WaveManager", true, false)
		if p and waves and waves._running:
			break
	waves.stop_run()
	waves._running = true
	waves.set_process(false)
	p.health_comp.max_hp = 9999.0
	p.health_comp.hp = 9999.0
	var events: RunEvents = waves.events
	events.set_process(false)
	# Aparece con su modelo
	var dice := events.spawn_dice()
	await _frames(2)
	_check(dice._die.mesh != null and dice._die.mesh is ArrayMesh, "el dado sale con su modelo cartoon")
	_check(MapPickup.toon_mesh("pickup_bomb") != null and MapPickup.toon_mesh("pickup_magnet") != null, "bomba e imán con su modelo cartoon")
	_check(dice.faces == 12, "en supervivencia el dado tiene 12 caras")
	# La tirada deja arriba la cara del valor
	for v in [1, 4, 7, 12]:
		var d := FateDice.spawn(main, p.global_position + Vector3(30, 0, 0))
		await _frames(1)
		d.roll(v)
		_check(d._value == v, "tirada forzada %d" % v)
		for i in 200:
			await get_tree().process_frame
			if d._done:
				break
		var up: Vector3 = d._holder.global_transform.basis.orthonormalized() * FateDice.face_up(12, v)
		_check(up.dot(Vector3.UP) > 0.95, "la cara %d queda arriba (%.2f)" % [v, up.dot(Vector3.UP)])
	await _frames(5)
	# Geometría del dodecaedro: 12 caras distintas, cada una con 5 esquinas
	var ns := FateDice.d12_normals()
	_check(ns.size() == 12 and FateDice.d12_face_corners(ns[3]).size() == 5, "dodecaedro: 12 caras de 5 esquinas")
	var ok_pairs := true
	for i in 12:
		for j in range(i + 1, 12):
			if (ns[i] as Vector3).dot(ns[j]) > 0.999:
				ok_pairs = false
	_check(ok_pairs, "las 12 caras apuntan a direcciones distintas")
	# Cada cara es un pentágono plano perpendicular a su normal: sus 5 esquinas a la misma altura sobre ella
	# (con las normales del dodecaedro girado las esquinas salían a 0,98/0,80/0,61: dado deforme y con agujeros)
	var flat := true
	for n: Vector3 in ns:
		for c: Vector3 in FateDice.d12_face_corners(n):
			if absf(c.dot(n) - 0.795) > 0.01:
				flat = false
	_check(flat, "las caras del dodecaedro son pentágonos planos")
	await get_tree().create_timer(3.0).timeout   # botín escalonado de las tiradas de arriba
	FateDice.clear_mods()                   # y sus efectos
	var sb: PlayerStatBlock = p.stat_block
	var dmg0 := sb.damage_mult()
	var spd0 := sb.move_mult()
	var gold0 := GameState.get_instance().gold
	# 7 FURIA
	FateDice.clear_mods()
	FateDice.apply12(7, p, main, p.global_position)
	await _frames(2)
	_check(is_equal_approx(sb.damage_mult(), dmg0 + 0.5) and sb.move_mult() > spd0, "7 FURIA: +50 %% daño (%.2f -> %.2f)" % [dmg0, sb.damage_mult()])
	# Regresión (FPS en móvil con FURIA): el indicador no debe reaplicar su estilo cada frame
	# ni llevar glifos que PressStart2P no tiene (cada rehecho buscaba la fuente emoji del sistema).
	var st_label: Label = FateDice._status._label
	var restyles := [0]
	st_label.theme_changed.connect(func(): restyles[0] += 1)
	await _frames(20)
	_check(restyles[0] <= 1, "FURIA: el indicador no se re-estiliza cada frame (%d en 20 frames)" % restyles[0])
	var font: Font = RumbangStyle.FONT
	var missing := ""
	for ch in st_label.text:
		if not font.has_char(ch.unicode_at(0)):
			missing += ch
	_check(missing == "", "FURIA: el indicador solo usa glifos de la fuente (faltan: %s)" % missing)
	FateDice._clock += FateDice.FURY_TIME + 1.0
	_check(is_equal_approx(sb.damage_mult(), dmg0), "la furia se acaba sola")
	# 3 MALDICIÓN
	FateDice.clear_mods()
	FateDice.apply12(3, p, main, p.global_position)
	await _frames(2)
	_check(sb.damage_mult() < dmg0 and sb.move_mult() < spd0, "3 MALDICIÓN: menos daño y velocidad")
	# 11 BENDICIÓN: más que la furia
	FateDice.clear_mods()
	FateDice.apply12(11, p, main, p.global_position)
	await _frames(2)
	_check(is_equal_approx(sb.damage_mult(), dmg0 + 1.0), "11 BENDICIÓN: +100 %% daño (%.2f)" % sb.damage_mult())
	FateDice.clear_mods()
	# 5 BOLSA
	FateDice.apply12(5, p, main, p.global_position)
	_check(GameState.get_instance().gold == gold0 + FateDice.GOLD_SURVIVAL, "5 BOLSA: +%d oro" % FateDice.GOLD_SURVIVAL)
	# 6 REGALO
	var pk0 := get_tree().get_nodes_in_group("map_pickups").size()
	FateDice.apply12(6, p, main, p.global_position + Vector3(5, 0, 0))
	await _frames(2)
	_check(get_tree().get_nodes_in_group("map_pickups").size() == pk0 + 2, "6 REGALO: dos objetos del mapa")
	# 2 EMBOSCADA
	var e0 := EnemyRegistry.all().size()
	FateDice.apply12(2, p, main, p.global_position)
	await _frames(3)
	_check(EnemyRegistry.all().size() >= e0 + FateDice.AMBUSH_SURVIVAL, "2 EMBOSCADA: %d enemigos más" % (EnemyRegistry.all().size() - e0))
	# 1 CATÁSTROFE: encola un élite y maldice
	FateDice.clear_mods()
	var q0 := events._queue.size()
	FateDice.apply12(1, p, main, p.global_position)
	_check(events._queue.size() > q0 and sb.damage_mult() < dmg0, "1 CATÁSTROFE: élite en cola y maldición")
	FateDice.clear_mods()
	# 4 HERIDA: pierde vida pero nunca muere por ella
	p.health_comp.hp = 5000.0
	FateDice.apply12(4, p, main, p.global_position)
	_check(is_equal_approx(p.health_comp.hp, 3000.0), "4 HERIDA: -40 %% de la vida actual (%.0f)" % p.health_comp.hp)
	p.health_comp.hp = 5.0
	FateDice.apply12(4, p, main, p.global_position)
	_check(p.health_comp.hp >= p.health_comp.max_hp * FateDice.WOUND_MIN_HP_FRACTION - 0.5, "4 HERIDA: deja un mínimo de vida")
	# 8 CURA / 12 JACKPOT
	p.health_comp.hp = 100.0
	FateDice.apply12(8, p, main, p.global_position)
	_check(p.health_comp.hp >= p.health_comp.max_hp - 0.5, "8 CURA: vida completa")
	p.health_comp.hp = 100.0
	var g1 := GameState.get_instance().gold
	FateDice.apply12(12, p, main, p.global_position)
	_check(p.health_comp.hp >= p.health_comp.max_hp - 0.5 and GameState.get_instance().gold == g1 + FateDice.GOLD_JACKPOT and sb.damage_mult() > dmg0, "12 JACKPOT: vida, oro y furia")
	FateDice.clear_mods()
	main.queue_free()
	await _frames(5)

func _dungeon() -> void:
	GameData.game_mode = "dungeon"
	var main: Node = load(Net.game_scene()).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	get_tree().current_scene = main
	var enc: DungeonEncounter = null
	for i in 600:
		await get_tree().process_frame
		enc = main.get_node_or_null("DungeonEncounter") as DungeonEncounter
		if enc and enc.map and is_instance_valid(enc.player):
			break
	await _frames(10)
	var p: Node3D = enc.player
	p.health_comp.max_hp = 9999.0
	p.health_comp.hp = 9999.0
	# Varios niveles: alguno trae dado (70 %)
	var seen := enc._dice.size()
	for i in 6:
		enc._spawn_level_dice([1, 2, 3])
		seen += enc._dice.size()
	_check(seen > 0, "la mazmorra pone dados en las cavernas (%d en 7 sorteos)" % seen)
	var c := enc.map.room_center(enc._start_room())
	p.global_position = c + Vector3(0, 0.3, 0)
	await _frames(3)
	# 1 EMBOSCADA: goblins en la caverna
	var g0 := get_tree().get_nodes_in_group("enemies").size()
	FateDice.apply(1, p, main, c)
	await _frames(3)
	_check(get_tree().get_nodes_in_group("enemies").size() > g0, "1 EMBOSCADA en la mazmorra: aparecen goblins")
	# 5 REGALO: pieza de equipo
	var eq0 := get_tree().root.find_children("*", "EquipmentPickup", true, false).size()
	FateDice.apply(5, p, main, c)
	await _frames(2)
	_check(get_tree().root.find_children("*", "EquipmentPickup", true, false).size() > eq0, "5 REGALO en la mazmorra: pieza de equipo")
	main.queue_free()
	await _frames(5)
