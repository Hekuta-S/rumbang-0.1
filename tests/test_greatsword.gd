extends Node

## Espadón: clips cortados (fotogramas 33 y 77), root motion, locomoción propia, andar -> correr sin combate,
## ataque corriendo, combo de tres golpes y daño.

var _player: CharacterBody3D
var _enc: DungeonEncounter

func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _boot() -> void:
	GameData.game_mode = "dungeon"
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

func _dummy(dist: float) -> DungeonGoblin:
	var at: Vector3 = _player.global_position + _fwd() * dist
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
	await get_tree().physics_frame
	await get_tree().physics_frame

func _ready() -> void:
	print("--- TEST: ESPADON ---")
	await _boot()
	var W := WeaponData.WeaponType.GREATSWORD
	var cc: PlayerCombatController = _player.combat_controller
	var ac: PlayerAnimationController = _player.animation_controller
	var mc: PlayerMovementController = _player.movement_controller
	var res: PlayerResources = _player.resources
	assert(_player.add_weapon(W), "Se añade el espadón")
	_player.select_slot(_player.weapon_slots.find(W))
	await _wait(0.4)
	assert(_player.current_weapon() == W)

	# 1. Clips: tres golpes cortados en los fotogramas 33 y 77 + ataque corriendo, todos con root motion
	var lib: AnimationLibrary = ac.anim_player.get_animation_library("")
	var want := {"gs1": 33.0 / 30.0, "gs2": 44.0 / 30.0, "gs3": 29.0 / 30.0, "gs_run": 56.0 / 30.0}
	for a in want:
		assert(lib.has_animation(a), "Animación %s cargada" % a)
		var anim := lib.get_animation(a)
		assert(absf(anim.length - float(want[a])) < 0.02, "%s dura %.3f (esperado %.3f)" % [a, anim.length, want[a]])
		assert(anim.has_meta("root_motion"), "%s lleva root motion" % a)
		var pts: PackedVector2Array = (anim.get_meta("root_motion") as Dictionary)["pts"]
		assert(pts[pts.size() - 1].length() > 0.0, "%s avanza" % a)
		# La cadera queda quieta en horizontal
		var t := anim.find_track(NodePath(str(ac._skel_path) + ":mixamorig_Hips"), Animation.TYPE_POSITION_3D)
		assert(t >= 0, "%s tiene pista de cadera" % a)
		var p0: Vector3 = anim.track_get_key_value(t, 0)
		for k in anim.track_get_key_count(t):
			var v: Vector3 = anim.track_get_key_value(t, k)
			assert(absf(v.x - p0.x) < 0.000001 and absf(v.z - p0.z) < 0.000001, "%s: cadera en su sitio (horizontal)" % a)
	# La altura de la cadera retargeteada cae cerca de la del esqueleto del personaje
	var skel := ac._find_first_node_of_type(ac.model, "Skeleton3D") as Skeleton3D
	var hips_rest := skel.get_bone_global_rest(skel.find_bone("mixamorig_Hips")).origin.y
	var an1 := lib.get_animation("gs1")
	var ht := an1.find_track(NodePath(str(ac._skel_path) + ":mixamorig_Hips"), Animation.TYPE_POSITION_3D)
	var hy: float = (an1.track_get_key_value(ht, 0) as Vector3).y
	assert(hy > hips_rest * 0.8 and hy < hips_rest * 1.1, "Altura de cadera del clip (%.5f) vs reposo del personaje (%.5f)" % [hy, hips_rest])
	for a in ["loco_idle_17", "loco_walk_17", "loco_run_17", "loco_strafe_17"]:
		assert(lib.has_animation(a), "Locomoción %s cargada" % a)
		assert(lib.get_animation(a).loop_mode == Animation.LOOP_LINEAR, "%s en bucle" % a)
	assert(ac._gs_loco, "Con el espadón se usa su locomoción")
	assert((ac.sm.get_node("walk") as AnimationNodeAnimation).animation == "loco_walk_17", "El estado andar usa el clip del espadón")
	print("CHECK 1 PASSED: clips cortados, root motion y locomoción (cadera %.5f / reposo %.5f)" % [hy, hips_rest])

	# 2. El espadón se ve en la mano y tiene su estela; cambia de modelo con la skin
	var vis = _player.weapon_visuals
	assert(vis.weapon_models.has(W) and vis.weapon_models[W].visible, "El espadón se ve en la mano")
	assert(is_instance_valid(vis.greatsword_trail), "Tiene estela")
	for s in GreatswordModels.count():
		vis.set_greatsword_skin(s)
		await get_tree().process_frame
		assert(vis._gs_holder.get_child_count() >= 4, "Skin %d colgada (modelo + marcas + estela)" % s)
	print("CHECK 2 PASSED: %d modelos de espadón" % GreatswordModels.count())

	# 3. Andar -> correr: tras GS_RUN_DELAY s moviéndose sin combate; daño, golpe y rodada lo cortan
	mc.note_combat()
	assert(not mc.gs_running(), "Recién hecho un golpe: anda")
	for i in int(PlayerMovementController.GS_RUN_DELAY * 10.0) + 3:
		mc._update_gs_gait(0.1, true)       # GS_RUN_DELAY + 0,3 s caminando
	assert(mc.gs_running(), "Tras %.1f s sin combate corre" % PlayerMovementController.GS_RUN_DELAY)
	_player.take_damage(1.0)
	assert(not mc.gs_running() and mc.gs_calm == 0.0, "Recibir daño lo devuelve a andar")
	for i in int(PlayerMovementController.GS_RUN_DELAY * 10.0) + 3:
		mc._update_gs_gait(0.1, true)
	assert(mc.gs_running(), "Vuelve a correr")
	mc._dodge_cooldown_timer = 0.0
	res.energy = PlayerResources.ENERGY_MAX
	mc.perform_dodge()
	assert(not mc.gs_running(), "Rodar lo devuelve a andar")
	for i in 20:
		mc._update_gs_gait(0.1, false)      # parado no cuenta
	assert(not mc.gs_running(), "Parado no se acumula tiempo de carrera")
	print("CHECK 3 PASSED: andar/correr según el combate")
	await _wait(0.8)

	# 4. Combo de tres golpes distintos encadenados dentro de la ventana de enlace
	var d := _dummy(2.4)
	await get_tree().physics_frame
	cc.attack_cooldown = 0.0
	res.energy = PlayerResources.ENERGY_MAX
	var start: Vector3 = _player.global_position
	_player.attack()
	assert(ac._current_action_name == "gs1", "El primer clic lanza gs1 (%s)" % ac._current_action_name)
	await _wait(0.4)
	assert(not ac.is_in_link_window(), "Aún no se puede encadenar")
	await _wait(0.5)    # ~0,9 s reales = 1,0 s de clip: ya está en la ventana de enlace
	assert(ac.is_in_link_window(), "Ventana de enlace del primer golpe")
	assert(d.hp < 5000.0, "gs1 golpea (hp %.1f)" % d.hp)
	var hp1 := d.hp
	res.energy = PlayerResources.ENERGY_MAX
	cc.buffer_attack()
	assert(ac._current_action_name == "gs2", "Encadena gs2 (%s)" % ac._current_action_name)
	await _wait(1.1)
	assert(d.hp < hp1, "gs2 golpea")
	var hp2 := d.hp
	await _wait(0.2)
	res.energy = PlayerResources.ENERGY_MAX
	cc.buffer_attack()
	for i in 90:
		if ac._current_action_name == "gs3":
			break
		await get_tree().process_frame
		cc.buffer_attack()
	assert(ac._current_action_name == "gs3", "Encadena gs3 (%s)" % ac._current_action_name)
	await _wait(1.0)
	assert(d.hp < hp2, "gs3 golpea (martillazo)")
	var gs3_dmg := hp2 - d.hp
	var moved: Vector3 = _player.global_position - start
	moved.y = 0.0
	assert(moved.length() > 1.0 and moved.normalized().dot(_fwd()) > 0.7, "El root motion avanza hacia delante (%.2f m)" % moved.length())
	print("CHECK 4 PASSED: combo gs1 -> gs2 -> gs3 (%.1f / %.1f / %.1f de daño, avance %.2f m)" % [5000.0 - hp1, hp1 - hp2, gs3_dmg, moved.length()])
	await _clear_enemies()
	await _wait(1.5)

	# 5. Ataque corriendo: embiste (gs_run) y el golpe siguiente continúa con gs2
	mc.gs_calm = 5.0
	mc._gs_mult = PlayerMovementController.GS_RUN_MULT
	assert(mc.gs_running(), "Preparado para correr")
	ac._combo_timer = 0.0
	var d2 := _dummy(3.0)
	await get_tree().physics_frame
	cc.attack_cooldown = 0.0
	res.energy = PlayerResources.ENERGY_MAX
	start = _player.global_position
	_player.attack()
	assert(ac._current_action_name == "gs_run", "Corriendo el clic lanza gs_run (%s)" % ac._current_action_name)
	assert(not mc.gs_running(), "Atacar interrumpe la carrera")
	await _wait(1.4)
	assert(d2.hp < 5000.0, "La estocada con carrerilla golpea (hp %.1f)" % d2.hp)
	moved = _player.global_position - start
	moved.y = 0.0
	assert(moved.length() > 1.2, "Y el cuerpo la recorre (%.2f m)" % moved.length())
	res.energy = PlayerResources.ENERGY_MAX
	await _wait(0.1)
	cc.buffer_attack()
	for i in 90:
		if ac._current_action_name == "gs2":
			break
		await get_tree().process_frame
		cc.buffer_attack()
	assert(ac._current_action_name == "gs2", "Tras el ataque corriendo sigue gs2 (%s)" % ac._current_action_name)
	print("CHECK 5 PASSED: ataque corriendo (%.1f de daño, %.2f m) y continuación del combo" % [5000.0 - d2.hp, moved.length()])
	await _clear_enemies()

	# 6. Cambiar de arma restablece la locomoción del personaje
	_player.add_weapon(WeaponData.WeaponType.SPEAR_LANCE)
	_player.select_slot(_player.weapon_slots.find(WeaponData.WeaponType.SPEAR_LANCE))
	await _wait(0.3)
	assert(not ac._gs_loco, "Sin espadón vuelve la locomoción normal")
	assert((ac.sm.get_node("walk") as AnimationNodeAnimation).animation == "walk", "El estado andar vuelve a su clip")
	assert(not mc.gs_running(), "Sin espadón no hay modo carrera")
	print("CHECK 6 PASSED: restablece la locomoción")

	print("ALL GREATSWORD CHECKS PASSED")
	get_tree().quit(0)
