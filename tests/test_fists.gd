extends Node

## Puños: clips (fs2 = fs1 en espejo, fs5 = fs4 en espejo), reposo normal que pasa a la guardia de pelea al golpear
## y vuelve tras un rato, combo de seis golpes con daño y ataque corriendo.

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

## Encadena golpes (buffer cada fotograma) hasta que la acción en curso sea `want`.
func _chain_to(want: String) -> bool:
	var cc: PlayerCombatController = _player.combat_controller
	var ac: PlayerAnimationController = _player.animation_controller
	for i in 300:
		if ac._current_action_name == want:
			return true
		_player.resources.energy = PlayerResources.ENERGY_MAX
		cc.buffer_attack()
		await get_tree().process_frame
	return ac._current_action_name == want

## kt2-style: la mano derecha de `b` hace lo que la izquierda de `a`, reflejado (x -> -x).
func _mirror_error(lib: AnimationLibrary, sk: Skeleton3D, a_name: String, b_name: String) -> float:
	var a_anim := lib.get_animation(a_name)
	var b_anim := lib.get_animation(b_name)
	var tr1 := WeaponAnimSets._bone_tracks(a_anim, sk)
	var tr2 := WeaponAnimSets._bone_tracks(b_anim, sk)
	var lh := sk.find_bone("mixamorig_LeftHand")
	var rh := sk.find_bone("mixamorig_RightHand")
	var hips := sk.find_bone("mixamorig_Hips")
	var worst := 0.0
	for t in [0.0, 0.3, 0.6, 0.9, 1.1]:
		var c1 := {}
		var c2 := {}
		var a: Vector3 = WeaponAnimSets._global_pose(sk, rh, a_anim, tr1, t, c1).origin - WeaponAnimSets._global_pose(sk, hips, a_anim, tr1, t, c1).origin
		var b: Vector3 = WeaponAnimSets._global_pose(sk, lh, b_anim, tr2, t, c2).origin - WeaponAnimSets._global_pose(sk, hips, b_anim, tr2, t, c2).origin
		worst = maxf(worst, Vector3(-a.x, a.y, a.z).distance_to(b) / maxf(a.length(), 0.001))
	return worst

func _ready() -> void:
	print("--- TEST: PUÑOS ---")
	await _boot()
	var W := WeaponData.WeaponType.FISTS
	var cc: PlayerCombatController = _player.combat_controller
	var ac: PlayerAnimationController = _player.animation_controller
	var res: PlayerResources = _player.resources
	assert(_player.add_weapon(W), "Se añaden los puños")
	_player.select_slot(_player.weapon_slots.find(W))
	await _wait(0.4)
	assert(_player.current_weapon() == W)

	# 1. Clips, espejos y reposo normal
	var lib: AnimationLibrary = ac.anim_player.get_animation_library("")
	var want := {"fs1": 47.0 / 30.0, "fs2": 47.0 / 30.0, "fs3": 44.0 / 30.0, "fs4": 37.0 / 30.0, "fs5": 37.0 / 30.0,
		"fs6": 79.0 / 30.0, "fs_run": 43.0 / 30.0}
	for a in want:
		assert(lib.has_animation(a), "Animación %s cargada" % a)
		var anim := lib.get_animation(a)
		assert(absf(anim.length - float(want[a])) < 0.04, "%s dura %.3f (esperado %.3f)" % [a, anim.length, want[a]])
	assert(lib.has_animation("guard_%d" % W), "Guardia de pelea cargada")
	assert(not ac._gs_loco, "Los puños no cambian la locomoción")
	assert((ac.sm.get_node("idle") as AnimationNodeAnimation).animation == "idle", "Reposo normal del personaje")
	var sk: Skeleton3D = _player.find_children("*", "Skeleton3D", true, false)[0]
	var e2 := _mirror_error(lib, sk, "fs1", "fs2")
	var e5 := _mirror_error(lib, sk, "fs4", "fs5")
	assert(e2 < 0.15, "fs2 refleja fs1 (error %.3f)" % e2)
	assert(e5 < 0.15, "fs5 refleja fs4 (error %.3f)" % e5)
	print("CHECK 1 PASSED: clips, espejos (%.3f, %.3f) y reposo normal" % [e2, e5])

	# 2. Sin pelear no hay guardia
	assert(ac._guard < 0.01, "En reposo no está en guardia (%.2f)" % ac._guard)
	assert(float(ac.anim_tree.get(ac.GUARD_FULL_PARAM)) < 0.01, "Mezcla de guardia a 0")
	print("CHECK 2 PASSED: reposo normal sin guardia")

	# 3. Combo fs1 -> ... -> fs6 con daño; tras golpear entra la guardia
	var d := _dummy(1.3)
	await get_tree().physics_frame
	cc.attack_cooldown = 0.0
	res.energy = PlayerResources.ENERGY_MAX
	_player.velocity = Vector3.ZERO
	_player.attack()
	assert(ac._current_action_name == "fs1", "El primer clic lanza fs1 (%s)" % ac._current_action_name)
	var dmg := []
	var last := d.hp
	for a in ["fs2", "fs3", "fs4", "fs5", "fs6"]:
		assert(await _chain_to(a), "Encadena %s (%s)" % [a, ac._current_action_name])
		dmg.append(last - d.hp)
		last = d.hp
	await _wait(2.4)
	dmg.append(last - d.hp)
	for i in dmg.size():
		assert(float(dmg[i]) > 0.0, "El golpe %d del combo hace daño (%s)" % [i + 1, str(dmg)])
	print("CHECK 3 PASSED: combo de seis golpes (daño %s)" % str(dmg))

	# 4. Guardia de pelea tras el combo; vuelve al reposo pasado GUARD_HOLD
	await get_tree().process_frame
	assert(not ac.is_attacking(), "El combo terminó")
	assert(ac.in_combat_guard(), "Tras golpear está en guardia (%.2f)" % ac._guard)
	assert(float(ac.anim_tree.get(ac.GUARD_FULL_PARAM)) > 0.8, "Guardia de cuerpo entero quieto (%.2f)" % float(ac.anim_tree.get(ac.GUARD_FULL_PARAM)))
	await _clear_enemies()
	await _wait(ac.GUARD_HOLD + 0.6)
	assert(ac._guard < 0.01, "Sin pelear vuelve al reposo normal (%.2f)" % ac._guard)
	print("CHECK 4 PASSED: guardia al golpear y vuelta al reposo")

	# 5. Ataque corriendo
	var d2 := _dummy(1.8)
	await get_tree().physics_frame
	ac._combo_timer = 0.0
	cc.attack_cooldown = 0.0
	res.energy = PlayerResources.ENERGY_MAX
	_player.velocity = _fwd() * 4.8
	_player.attack()
	assert(ac._current_action_name == "fs_run", "Corriendo el clic lanza fs_run (%s)" % ac._current_action_name)
	await _wait(1.6)
	assert(d2.hp < 5000.0, "El puñetazo corriendo golpea (hp %.1f)" % d2.hp)
	print("CHECK 5 PASSED: ataque corriendo")
	await _clear_enemies()

	# 6. Especial: lluvia de golpes (el clip dos veces), diez puñetazos, cuesta energía y tiene enfriamiento
	await _wait(1.5)
	var sp := lib.get_animation("fs_special")
	assert(sp != null and absf(sp.length - (30.0 / 30.0 + 0.1 + 40.0 / 30.0)) < 0.04, "fs_special encadena dos pasadas (%.3f s)" % sp.length)
	var d3 := _dummy(1.3)
	await get_tree().physics_frame
	res.energy = PlayerResources.ENERGY_MAX
	var opened := [0]
	var count_open := func(_id: int, anim_name: String) -> void:
		if anim_name == "fs_special":
			opened[0] += 1
	ac.hit_window_opened.connect(count_open)
	_player._on_alt_attack_pressed()
	assert(ac._current_action_name == "fs_special", "Clic derecho lanza fs_special (%s)" % ac._current_action_name)
	assert(absf(res.energy - (PlayerResources.ENERGY_MAX - 30.0)) < 0.5, "Cobra 30 de energía una sola vez (%.1f)" % res.energy)
	assert(not cc.fists_special(), "En enfriamiento no sale otra vez")
	await _wait(sp.length / 1.1 + 0.3)
	ac.hit_window_opened.disconnect(count_open)
	assert(opened[0] == 10, "Diez puñetazos (%d)" % opened[0])
	assert(d3.hp < 5000.0, "La lluvia golpea (hp %.1f)" % d3.hp)
	print("CHECK 6 PASSED: lluvia de golpes (%d puñetazos, %.1f de daño)" % [opened[0], 5000.0 - d3.hp])
	await _clear_enemies()

	# 7. Estelas en las manos: fs1 enciende la derecha antes del golpe; fs2 (espejo), la izquierda
	var vis = _player.weapon_visuals
	assert(vis.fist_trails.size() == 2, "Una estela por mano")
	await _wait(4.5)
	ac._combo_timer = 0.0
	cc.attack_cooldown = 0.0
	res.energy = PlayerResources.ENERGY_MAX
	_player.velocity = Vector3.ZERO
	_player.attack()
	assert(ac._current_action_name == "fs1", "fs1 para las estelas (%s)" % ac._current_action_name)
	var lit_r := false
	var lit_l := false
	for i in 90:
		await get_tree().process_frame
		lit_r = lit_r or vis.fist_trails[0]._emit_left > 0.0
		lit_l = lit_l or vis.fist_trails[1]._emit_left > 0.0
		if ac._action_elapsed > 0.8:
			break
	assert(lit_r and not lit_l, "fs1 enciende solo la estela derecha (R %s, L %s)" % [lit_r, lit_l])
	assert(await _chain_to("fs2"), "Encadena fs2")
	lit_l = false
	for i in 90:
		await get_tree().process_frame
		lit_l = lit_l or vis.fist_trails[1]._emit_left > 0.0
		if ac._action_elapsed > 0.8:
			break
	assert(lit_l, "fs2 (espejo) enciende la estela izquierda")
	print("CHECK 7 PASSED: estelas en las manos")
	await _wait(2.0)

	# 8. Cambiar de arma quita la guardia
	_player.add_weapon(WeaponData.WeaponType.SWORD)
	_player.select_slot(_player.weapon_slots.find(WeaponData.WeaponType.SWORD))
	await _wait(0.2)
	assert(ac._guard_weapon == -1, "La espada no usa la guardia de puños")
	print("CHECK 8 PASSED: otra arma sin guardia")

	print("ALL FISTS CHECKS PASSED")
	get_tree().quit(0)
