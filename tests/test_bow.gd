extends Node

## Arco: clips y locomoción propia (reposo, andar en 4 direcciones, sin carrera), modelos en la mano izquierda,
## combo de tres disparos con su clip cada uno (la flecha sale al soltar la cuerda; el 3.º es una sola flecha
## potente), disparo cargado (tensar, sostener en bucle, soltar) que atraviesa y aturde,
## y remates: el impacto entra en el fotograma en que el golpe abre su ventana (espada) y con la flecha (arco).

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
	_player.global_position = _enc.map.room_center(_enc.map.arena_index) + Vector3(0, 0.3, 0)
	await _wait(0.5)

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
	for e in EnemyRegistry.all():
		if is_instance_valid(e) and e is Node:
			EnemyRegistry.unregister(e)
			e.queue_free()
	for a in get_tree().root.find_children("*", "BowArrow", true, false):
		a.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame

func _arrows() -> Array:
	return get_tree().root.find_children("*", "", true, false).filter(func(n): return n is BowArrow and not n.is_queued_for_deletion())

## La mira apunta a `g` (objetivo fijado), así las flechas van a él sin depender de la cámara.
func _lock(g: Node3D) -> void:
	var tl = _player.get("target_lock")
	if tl:
		tl._set_target(g)

func _equip(w: int) -> void:
	if not _player.weapon_slots.has(w):
		assert(_player.add_weapon(w), "Se añade el arma %d" % w)
	_player.select_slot(_player.weapon_slots.find(w))
	await _wait(0.4)
	assert(_player.current_weapon() == w)

func _ready() -> void:
	print("--- TEST: ARCO Y REMATES ---")
	await _boot()
	var W := WeaponData.WeaponType.BOW
	var cc: PlayerCombatController = _player.combat_controller
	var ac: PlayerAnimationController = _player.animation_controller
	var res: PlayerResources = _player.resources
	await _equip(W)

	# 1. Clips y locomoción del arco
	var lib: AnimationLibrary = ac.anim_player.get_animation_library("")
	assert(lib.has_animation("bow_shot"), "Clip de disparo cargado")
	for a in PlayerAnimationController.BOW_COMBO + [PlayerAnimationController.BOW_CHARGE_DRAW,
			PlayerAnimationController.BOW_CHARGE_HOLD, PlayerAnimationController.BOW_CHARGE_RELEASE]:
		assert(lib.has_animation(a), "Clip nuevo del arco %s" % a)
		var clip := lib.get_animation(a)
		assert(clip.length > 0.3 and clip.length < 2.0, "%s dura %.2f s" % [a, clip.length])
		# Los dedos agarran el arco y la cuerda: sus pistas no se pierden al importar
		var sp := str(ac._skel_path)
		assert(clip.find_track(NodePath(sp + ":mixamorig_LeftHandIndex1"), Animation.TYPE_ROTATION_3D) >= 0, "%s lleva los dedos" % a)
		# La cadera queda a la altura de Riva (no flota ni se hunde: exportado desde el fotograma 1)
		var hips := clip.find_track(NodePath(sp + ":mixamorig_Hips"), Animation.TYPE_POSITION_3D)
		assert(hips >= 0, "%s mueve la cadera" % a)
		var hy: float = clip.position_track_interpolate(hips, 0.0).y
		var ref: float = lib.get_animation("bow_shot").position_track_interpolate(
			lib.get_animation("bow_shot").find_track(NodePath(sp + ":mixamorig_Hips"), Animation.TYPE_POSITION_3D), 0.0).y
		assert(absf(hy - ref) < absf(ref) * 0.15, "%s: cadera a %.3f (bow_shot %.3f)" % [a, hy, ref])
	for a in PlayerAnimationController.BOW_COMBO + [PlayerAnimationController.BOW_CHARGE_RELEASE]:
		var rt := WeaponStrategy.BowStrategy.release_time(a)
		assert(rt > 0.0 and rt < lib.get_animation(a).length, "%s suelta la cuerda dentro del clip (%.3f)" % [a, rt])
	for a in ["loco_idle_19", "loco_walk_19", "loco_strafe_19", "loco_strafe_l_19", "loco_back_19"]:
		assert(lib.has_animation(a), "Locomoción %s cargada" % a)
	assert(not lib.has_animation("loco_run_19"), "El arco no trae carrera propia")
	assert(ac._gs_loco, "Con el arco se usa su locomoción")
	assert((ac.sm.get_node("walk") as AnimationNodeAnimation).animation == "loco_walk_19", "Andar usa el clip del arco")
	assert((ac.sm.get_node("run") as AnimationNodeAnimation).animation == "run", "Correr usa la carrera del personaje")
	if ac.anim_tree.tree_root.has_node("strafe_l"):
		assert((ac.anim_tree.tree_root.get_node("strafe_l") as AnimationNodeAnimation).animation == "loco_strafe_l_19", "Paso a la izquierda propio")
	assert(ac._loco_back == "loco_back_19", "Retroceso propio")
	print("CHECK 1 PASSED: clips y locomoción del arco")

	# 2. Los tres arcos en la mano izquierda, normalizados
	var vis = _player.weapon_visuals
	assert(vis.weapon_models.has(W) and vis.weapon_models[W].visible, "El arco se ve en la mano")
	for s in BowModels.count():
		vis.set_bow_skin(s)
		await get_tree().process_frame
		var meshes: Array = vis.bow_holder().find_children("*", "MeshInstance3D", true, false).filter(
			func(m): return not m.is_queued_for_deletion() and m.is_visible_in_tree() and m.name != "Cuerda" and not m.get_parent() is BladeTrail)
		assert(meshes.size() >= 1, "Arco %d con malla" % s)
		var aabb := AABB()
		var first := true
		for m in meshes:
			var mi := m as MeshInstance3D
			var bb: AABB = vis.bow_holder().global_transform.affine_inverse() * mi.global_transform * mi.get_aabb()
			aabb = bb if first else aabb.merge(bb)
			first = false
		var wl := float(BowModels.skin(s)["world_len"])
		assert(absf(aabb.size.y - wl) < wl * 0.15, "Arco %d mide %.2f m de punta a punta (esperado %.2f)" % [s, aabb.size.y, wl])
		assert(aabb.size.y > aabb.size.x and aabb.size.y > aabb.size.z, "Arco %d con las palas a lo largo de Y (%s)" % [s, aabb.size])
	vis.set_bow_skin(0)
	var hand_bone: String = vis.bow_holder().get_parent().get("bone_name") if vis.bow_holder().get_parent().get("bone_name") != null else ""
	assert(hand_bone == "" or hand_bone == "mixamorig_LeftHand", "En la mano izquierda (%s)" % hand_bone)
	print("CHECK 2 PASSED: %d arcos normalizados en la mano" % BowModels.count())

	# 3. Disparo rápido: la flecha sale al soltar la cuerda, no al hacer clic
	var d := _dummy(7.0)
	await get_tree().physics_frame
	_lock(d)
	cc.attack_cooldown = 0.0
	res.energy = PlayerResources.ENERGY_MAX
	_player.attack()
	await get_tree().process_frame
	assert(ac._current_action_name == "bow_shot_1", "El clic lanza el 1.er disparo del combo (%s)" % ac._current_action_name)
	assert(_arrows().is_empty(), "La flecha no sale en el mismo fotograma del clic")
	var t0 := Time.get_ticks_msec()
	for i in 120:
		await get_tree().process_frame
		if not _arrows().is_empty():
			break
	var release_ms := Time.get_ticks_msec() - t0
	assert(_arrows().size() == 1, "Sale una flecha (%d)" % _arrows().size())
	var expect_ms := WeaponStrategy.BowStrategy.release_time("bow_shot_1") / float(WeaponStrategy.BowStrategy.COMBO_SPEEDS[0]) * 1000.0
	assert(absf(release_ms - expect_ms) < 90.0, "Sale al soltar la cuerda (%d ms, esperado ~%d)" % [release_ms, expect_ms])
	await _wait(0.8)
	var quick_dmg := 5000.0 - d.hp
	assert(quick_dmg > 0.0, "La flecha hace daño (%.1f)" % quick_dmg)
	print("CHECK 3 PASSED: disparo rápido (%.1f de daño, suelta a %d ms)" % [quick_dmg, release_ms])

	# 4. El 2.º y el 3.º del combo con su clip; el 3.º es UNA flecha que pega más fuerte
	var hp_before := d.hp
	for k in 2:
		cc.attack_cooldown = 0.0
		res.energy = PlayerResources.ENERGY_MAX
		var before := _arrows().size()
		_player.attack()
		await get_tree().process_frame
		var clip: String = PlayerAnimationController.BOW_COMBO[k + 1]
		assert(ac._current_action_name == clip, "Disparo %d del combo con %s (%s)" % [k + 2, clip, ac._current_action_name])
		var t1 := Time.get_ticks_msec()
		var got := 0
		for i in 90:
			await get_tree().process_frame
			got = _arrows().size() - before
			if got > 0:
				break
		var ms := Time.get_ticks_msec() - t1
		var exp_ms := WeaponStrategy.BowStrategy.release_time(clip) / float(WeaponStrategy.BowStrategy.COMBO_SPEEDS[k + 1]) * 1000.0
		assert(absf(ms - exp_ms) < 90.0, "%s suelta a %d ms (esperado ~%d)" % [clip, ms, exp_ms])
		if k == 0:
			assert(got == 1, "El 2.º disparo es una flecha (%d)" % got)
			await _wait(0.7)
			hp_before = d.hp
		else:
			assert(got == 1, "El 3.er disparo es UNA sola flecha (%d)" % got)
			await _wait(0.8)
			var heavy_dmg := hp_before - d.hp
			assert(heavy_dmg > quick_dmg * 1.4, "La flecha del 3.º pega más (%.1f vs %.1f)" % [heavy_dmg, quick_dmg])
	print("CHECK 4 PASSED: combo bow_shot_1/2/3, el 3.º una flecha potente")
	await _clear_enemies()
	await _wait(0.5)

	# 5. Disparo cargado: atraviesa a todos y, a tope, aturde
	var a1 := _dummy(5.0)
	var a2 := _dummy(8.0)
	await get_tree().physics_frame
	_lock(a2)
	cc.attack_cooldown = 0.0
	res.energy = PlayerResources.ENERGY_MAX
	assert(cc.start_bow_charge(), "Empieza a tensar")
	assert(ac._current_action_name == PlayerAnimationController.BOW_DRAW, "Pose de tensado (%s)" % ac._current_action_name)
	# La acción de tensado es encajar+tensar y luego el bucle de sostener repetido (no la pose congelada de bow_shot)
	var draw_anim := lib.get_animation(PlayerAnimationController.BOW_DRAW)
	var intro_len := lib.get_animation(PlayerAnimationController.BOW_CHARGE_DRAW).length
	var hold_len := lib.get_animation(PlayerAnimationController.BOW_CHARGE_HOLD).length
	assert(draw_anim.length >= PlayerAnimationController.BOW_DRAW_LENGTH - 0.01, "El tensado se sostiene (%.1f s)" % draw_anim.length)
	var tr := draw_anim.find_track(NodePath(str(ac._skel_path) + ":mixamorig_Spine2"), Animation.TYPE_ROTATION_3D)
	var q_a: Quaternion = draw_anim.rotation_track_interpolate(tr, intro_len + hold_len * 0.33)
	var q_b: Quaternion = draw_anim.rotation_track_interpolate(tr, intro_len + hold_len * 3.33)
	var q_c: Quaternion = draw_anim.rotation_track_interpolate(tr, intro_len + hold_len * 0.66)
	assert(q_a.angle_to(q_b) < 0.01, "El sostener se repite en bucle")
	assert(q_a.angle_to(q_c) > 0.005, "Sosteniendo hay un leve temblor")
	await _wait(1.2)
	var stun0: float = a1._stun
	var arrows0 := _arrows().size()
	cc.release_bow_charge()
	await get_tree().process_frame
	assert(ac._current_action_name == PlayerAnimationController.BOW_CHARGE_RELEASE, "Suelta propia del cargado (%s)" % ac._current_action_name)
	var t2 := Time.get_ticks_msec()
	for i in 60:
		await get_tree().process_frame
		if _arrows().size() > arrows0:
			break
	var rel_ms := Time.get_ticks_msec() - t2
	assert(_arrows().size() > arrows0, "La cargada sale")
	assert(rel_ms < WeaponStrategy.BowStrategy.release_time(PlayerAnimationController.BOW_CHARGE_RELEASE) * 1000.0 + 90.0,
		"La cargada sale al momento de soltar (%d ms)" % rel_ms)
	await _wait(0.9)
	assert(a1.hp < 5000.0 and a2.hp < 5000.0, "La flecha cargada atraviesa (hp %.0f / %.0f)" % [a1.hp, a2.hp])
	assert(5000.0 - a1.hp > quick_dmg * 2.0, "Hace mucho más daño que una normal (%.1f vs %.1f)" % [5000.0 - a1.hp, quick_dmg])
	assert(a1._stun > stun0 or a1.state == DungeonGoblin.State.STUNNED, "A tope aturde")
	print("CHECK 5 PASSED: cargada atraviesa (%.1f de daño)" % (5000.0 - a1.hp))
	await _clear_enemies()
	_lock(null)

	# 6. Remate con espada: el impacto entra cuando el golpe abre su ventana, no antes
	await _equip(WeaponData.WeaponType.SWORD)
	await _finisher_check("sw4")
	# Remate con el arco: flecha a quemarropa
	await _equip(W)
	await _finisher_check("")
	print("ALL BOW CHECKS PASSED")
	get_tree().quit(0)

var _window_at := -1
var _dead_at := -1

func _finisher_check(anim: String) -> void:
	var ac: PlayerAnimationController = _player.animation_controller
	var fin: PlayerFinisherController = _player.finisher_controller
	var g := _dummy(2.5)
	g.set_physics_process(true)
	g.max_hp = 60.0
	g.hp = 60.0
	await get_tree().physics_frame
	g._set_state(DungeonGoblin.State.STUNNED)
	fin._recent.clear()
	_window_at = -1
	_dead_at = -1
	var cb := func(_id: int, n: String) -> void:
		if n == anim and _window_at < 0:
			_window_at = Engine.get_process_frames()
	ac.hit_window_opened.connect(cb)
	_player.resources.energy = PlayerResources.ENERGY_MAX
	_player.attack()
	assert(fin.is_active(), "El ataque lanza el remate")
	if anim != "":
		assert(ac._current_action_name == anim, "El remate usa %s (%s)" % [anim, ac._current_action_name])
	var start := Time.get_ticks_msec()
	for i in 6000:
		await get_tree().process_frame
		if _dead_at < 0 and g.is_dead():
			_dead_at = Engine.get_process_frames()
		if not fin.is_active():
			break
	ac.hit_window_opened.disconnect(cb)
	assert(g.is_dead(), "El remate mata")
	if anim != "":
		assert(_window_at >= 0, "La ventana del golpe se abrió")
		assert(_dead_at >= _window_at and _dead_at - _window_at <= 1,
			"El daño entra con la ventana (muere en el fotograma %d, ventana en %d)" % [_dead_at, _window_at])
	print("CHECK 6 PASSED: remate %s (impacto en el fotograma de la ventana, %d ms)" % [anim if anim != "" else "con arco", Time.get_ticks_msec() - start])
	await _clear_enemies()
	await _wait(0.5)

