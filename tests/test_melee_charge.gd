extends Node

## Ataques cargados cuerpo a cuerpo (mantener clic izquierdo, mazmorra): espada, espadón, dagas, maza, katana y
## puños. Cada arma carga (pose sostenida, potencia 0..1), suelta y su golpe cargado daña al muñeco; las dagas marcan
## enemigos al cargar y los apuñalan al soltar; un toque corto sigue siendo un golpe normal.

var _player: CharacterBody3D
var _enc: DungeonEncounter

func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _boot() -> void:
	GameData.game_mode = "dungeon"
	SaveManager.save_path = "user://test_save.json"
	for i in GameData.CHARACTERS.size():
		if GameData.CHARACTERS[i]["id"] == "mikeura":
			GameData.selected_index = i
	var scene: Node = load("res://scenes/core/main_dungeon.tscn").instantiate()
	get_tree().root.add_child.call_deferred(scene)
	await get_tree().process_frame
	get_tree().current_scene = scene
	for i in 600:
		await get_tree().process_frame
		_enc = scene.get_node_or_null("DungeonEncounter")
		if _enc and _enc.map and is_instance_valid(_enc.player):
			break
	_enc._pending.clear()
	_player = _enc.player
	_player.health_comp.max_hp = 9999.0
	_player.health_comp.hp = 9999.0
	await _wait(0.5)

func _home() -> void:
	_player.velocity = Vector3.ZERO
	_player.global_position = _enc.map.room_center(_enc.map.arena_index) + Vector3(0, 0.3, 0)
	await _wait(0.2)

func _fwd() -> Vector3:
	var f: Vector3 = -_player.mesh.global_transform.basis.z
	f.y = 0.0
	return f.normalized()

func _dummy(dist: float, side := 0.0) -> DungeonGoblin:
	var f := _fwd()
	var at: Vector3 = _player.global_position + f * dist + Vector3(-f.z, 0, f.x) * side
	var g := _enc._spawn_at(_enc.map.arena_index, at)
	g.global_position = at
	g.max_hp = 5000.0
	g.hp = 5000.0
	g.set_physics_process(false)
	return g

func _clear_enemies() -> void:
	var tl = _player.get("target_lock")
	if tl and tl.has_method("_set_target"):
		tl._set_target(null)
	for e in EnemyRegistry.all():
		if is_instance_valid(e) and e is Node:
			EnemyRegistry.unregister(e)
			e.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame

func _lock(g: Node3D) -> void:
	var tl = _player.get("target_lock")
	if tl:
		tl._set_target(g)

func _equip(w: int) -> void:
	if not _player.weapon_slots.has(w):
		# Huecos llenos: el arma nueva sustituye a la del último hueco que no esté en uso
		var slots: Array = _player.weapon_inventory.weapon_slots
		var cur: int = _player.weapon_inventory.current_slot
		var free := slots.find(null)
		var idx := free if free >= 0 else (slots.size() - 1 if cur != slots.size() - 1 else 0)
		if free < 0 and slots.size() >= PlayerCombatController.MAX_WEAPON_SLOTS:
			slots[idx] = w
		elif free >= 0:
			slots[idx] = w
		else:
			assert(_player.add_weapon(w), "Se añade el arma %d" % w)
		_player.combat_controller.weapon_slots = slots
	_player.select_slot(_player.weapon_slots.find(w))
	await _wait(0.4)
	assert(_player.current_weapon() == w)

func _refill() -> void:
	var res = _player.get("resources")
	if res:
		res.energy = res.energy_max() if res.has_method("energy_max") else 100.0

## Carga a tope `w`, suelta y devuelve cuánta vida le quitó al muñeco `g`.
func _charge_and_release(w: int, g: DungeonGoblin, hold: float = 1.15) -> float:
	var cc = _player.combat_controller
	_refill()
	cc.request_melee_charge()
	await _wait(0.1)
	assert(cc.is_melee_charging(), "Arma %d: empieza a cargar" % w)
	var ac = _player.animation_controller
	var s = cc._strategies[w]
	assert(ac._current_action_name in [s.charge_clip + "_charge", s.charge_prefix + "_charge"], "Arma %d: pose de carga (%s)" % [w, ac._current_action_name])
	await _wait(hold)
	assert(cc.melee_charge_power() >= 1.0, "Arma %d: carga completa" % w)
	if s.charge_prefix != "":
		assert(s._has_charge_clips(), "Arma %d: clips propios de cargado (%s_charge_*)" % [w, s.charge_prefix])
		assert(ac._current_action_name == s.charge_prefix + "_charge", "Arma %d: carga con su bucle propio" % w)
	cc.release_melee_charge()
	assert(not cc.is_melee_charging(), "Arma %d: al soltar deja de cargar" % w)
	if s.charge_prefix != "" and not s._marks.size() if "_marks" in s else s.charge_prefix != "":
		assert(ac._current_action_name == s.charge_prefix + "_charge_release", "Arma %d: suelta con su golpe propio (%s)" % [w, ac._current_action_name])
	# La cadera no sale volando ni se hunde (reposo de las FBX exportadas: WeaponAnimSets._retarget_bones)
	var skel := ac._find_first_node_of_type(ac.model, "Skeleton3D") as Skeleton3D
	var hb := skel.find_bone("mixamorig_Hips")
	var hy_min := 99.0
	var hy_max := -99.0
	for i in 12:
		await get_tree().process_frame
		var hy: float = (skel.global_transform * skel.get_bone_global_pose(hb)).origin.y - _player.global_position.y
		hy_min = minf(hy_min, hy)
		hy_max = maxf(hy_max, hy)
	print("  arma %d: cadera %.2f..%.2f m" % [w, hy_min, hy_max])
	assert(hy_min > 0.35 and hy_max < 1.4, "Arma %d: cadera a altura razonable (%.2f..%.2f)" % [w, hy_min, hy_max])
	if OS.has_environment("MC_DEBUG"):
		var last := ""
		for i in 100:
			var line := "%s t=%.2f hit=%s hp=%.0f d=%.2f" % [ac._current_action_name, ac._action_elapsed, ac.active_attack_name, g.hp, (g.global_position - _player.global_position).length()]
			if i % 4 == 0 or ac.active_attack_name != last:
				print("   ", line, " shot=", ac.anim_tree.get("parameters/shot/active"), " sup=", ac._suppress_hit_window)
				last = ac.active_attack_name
			await get_tree().create_timer(0.02).timeout
	await _wait(1.8)
	return 5000.0 - g.hp

func _ready() -> void:
	print("--- TEST: ATAQUES CARGADOS CUERPO A CUERPO ---")
	get_tree().create_timer(150.0).timeout.connect(func():
		print("TIMEOUT")
		get_tree().quit(1))
	await _boot()
	var W := WeaponData.WeaponType
	var cc = _player.combat_controller

	# 1. Las seis armas tienen carga; el arco y la espalanza no pasan por aquí
	for w in [W.SWORD, W.GREATSWORD, W.DAGGERS, W.MACE, W.KATANA, W.FISTS]:
		await _equip(w)
		assert(cc.has_melee_charge(), "Arma %d con ataque cargado" % w)
	await _equip(W.BOW)
	assert(not cc.has_melee_charge(), "El arco usa su propia carga")
	print("CHECK 1 PASSED: seis armas cuerpo a cuerpo con ataque cargado")

	# 2. Cada arma: cargar, soltar, el golpe cargado daña (más que un golpe normal del arma)
	var dist := {W.SWORD: 2.5, W.GREATSWORD: 3.5, W.MACE: 2.5, W.KATANA: 3.0, W.FISTS: 1.4}
	for w in [W.SWORD, W.GREATSWORD, W.MACE, W.KATANA, W.FISTS]:
		await _clear_enemies()
		await _equip(w)
		await _home()
		var g := _dummy(dist[w])
		_lock(g)
		await _wait(0.2)
		var dealt := await _charge_and_release(w, g)
		var normal: float = _player._weapon_damage(w)
		print("  arma %d: cargado quitó %.1f (golpe base %.1f)" % [w, dealt, normal])
		assert(dealt > normal * 1.2, "Arma %d: el cargado daña más que un golpe base (%.1f)" % [w, dealt])
	print("CHECK 2 PASSED: espada, espadón, maza, katana y puños: golpe cargado")

	# 3. Dagas: marcas al cargar (hasta 3) y apuñalamiento de cada marcado al soltar
	await _clear_enemies()
	await _equip(W.DAGGERS)
	await _home()
	var a := _dummy(4.0, -2.0)
	var b := _dummy(5.0, 2.0)
	var d = cc._strategies[W.DAGGERS]
	_refill()
	cc.request_melee_charge()
	await _wait(1.2)
	assert(d._marks.size() == 2, "Dagas: marca a los dos enemigos cercanos (%d)" % d._marks.size())
	cc.release_melee_charge()
	await _wait(1.0)
	assert(a.hp < 5000.0 and b.hp < 5000.0, "Dagas: apuñala a los dos marcados (%.0f, %.0f)" % [a.hp, b.hp])
	assert(d._marks.is_empty() and d._mark_icons.is_empty(), "Dagas: las marcas se limpian")
	print("CHECK 3 PASSED: dagas marcan y apuñalan")

	# 4. Un toque corto (soltar antes de que empiece la carga) es un golpe normal; esquivar cancela la carga
	await _clear_enemies()
	await _equip(W.SWORD)
	await _home()
	await _wait(0.8)
	cc._melee_charge_wanted = true
	cc.release_melee_charge()
	await _wait(0.05)
	var ac = _player.animation_controller
	assert(ac.is_attacking(), "Toque corto: sale el golpe del combo (%s)" % ac._current_action_name)
	await _wait(1.5)
	_refill()
	cc.request_melee_charge()
	await _wait(0.2)
	assert(cc.is_melee_charging())
	_player.movement_controller.perform_dodge()
	await _wait(0.1)
	assert(not cc.is_melee_charging(), "Esquivar cancela la carga")
	print("CHECK 4 PASSED: toque = golpe normal, esquivar cancela")

	print("ALL MELEE CHARGE CHECKS PASSED")
	get_tree().quit(0)
