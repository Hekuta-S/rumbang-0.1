extends Node

## Katana de Sangre (mítica): clips (kt2 = kt1 en espejo, combo cortado en el 28), locomoción del espadón, combo de
## cuatro golpes, ataque corriendo, especial con clic derecho, modelo en la mano y la legendaria mítica.

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
	for i in 240:
		if ac._current_action_name == want:
			return true
		_player.resources.energy = PlayerResources.ENERGY_MAX
		cc.buffer_attack()
		await get_tree().process_frame
	return ac._current_action_name == want

func _ready() -> void:
	print("--- TEST: KATANA ---")
	await _boot()
	var W := WeaponData.WeaponType.KATANA
	var cc: PlayerCombatController = _player.combat_controller
	var ac: PlayerAnimationController = _player.animation_controller
	var mc: PlayerMovementController = _player.movement_controller
	var res: PlayerResources = _player.resources
	assert(_player.add_weapon(W), "Se añade la katana")
	_player.select_slot(_player.weapon_slots.find(W))
	await _wait(0.4)
	assert(_player.current_weapon() == W)

	# 1. Clips y locomoción del espadón
	var lib: AnimationLibrary = ac.anim_player.get_animation_library("")
	var want := {"kt1": 38.0 / 30.0, "kt2": 38.0 / 30.0, "kt3": 28.0 / 30.0, "kt4": 70.0 / 30.0, "kt_run": 65.0 / 30.0, "kt_special": 65.0 / 30.0}
	for a in want:
		assert(lib.has_animation(a), "Animación %s cargada" % a)
		var anim := lib.get_animation(a)
		assert(absf(anim.length - float(want[a])) < 0.04, "%s dura %.3f (esperado %.3f)" % [a, anim.length, want[a]])
	for a in ["loco_idle_20", "loco_walk_20", "loco_run_20", "loco_strafe_20"]:
		assert(lib.has_animation(a), "Locomoción %s cargada" % a)
	assert(ac._gs_loco, "Con la katana se usa locomoción de arma")
	assert((ac.sm.get_node("idle") as AnimationNodeAnimation).animation == "loco_idle_20")
	# kt2 es kt1 en espejo: la mano derecha de kt2 hace lo que la izquierda de kt1, reflejado (x -> -x)
	var sk: Skeleton3D = _player.find_children("*", "Skeleton3D", true, false)[0]
	var tr1 := WeaponAnimSets._bone_tracks(lib.get_animation("kt1"), sk)
	var tr2 := WeaponAnimSets._bone_tracks(lib.get_animation("kt2"), sk)
	var lh := sk.find_bone("mixamorig_LeftHand")
	var rh := sk.find_bone("mixamorig_RightHand")
	var hips := sk.find_bone("mixamorig_Hips")
	var worst := 0.0
	for t in [0.0, 0.3, 0.5, 0.7, 1.0]:
		var c1 := {}
		var c2 := {}
		var a: Vector3 = WeaponAnimSets._global_pose(sk, lh, lib.get_animation("kt1"), tr1, t, c1).origin - WeaponAnimSets._global_pose(sk, hips, lib.get_animation("kt1"), tr1, t, c1).origin
		var b: Vector3 = WeaponAnimSets._global_pose(sk, rh, lib.get_animation("kt2"), tr2, t, c2).origin - WeaponAnimSets._global_pose(sk, hips, lib.get_animation("kt2"), tr2, t, c2).origin
		worst = maxf(worst, Vector3(-a.x, a.y, a.z).distance_to(b) / maxf(a.length(), 0.001))
	assert(worst < 0.15, "kt2 refleja kt1 (error relativo %.3f)" % worst)
	print("CHECK 1 PASSED: clips, kt2 en espejo y locomoción del espadón")

	# 2. Katana en la mano con estela, ~world_len de largo
	var vis = _player.weapon_visuals
	assert(vis.weapon_models.has(W) and vis.weapon_models[W].visible, "La katana se ve en la mano")
	assert(is_instance_valid(vis.katana_trail), "Tiene estela")
	var meshes: Array = vis.katana_holder().find_children("*", "MeshInstance3D", true, false).filter(
		func(m): return not m is BladeTrail and not m.get_parent() is BladeTrail)
	var aabb := AABB()
	var first := true
	for m in meshes:
		var mi := m as MeshInstance3D
		var bb: AABB = vis.katana_holder().global_transform.affine_inverse() * mi.global_transform * mi.get_aabb()
		aabb = bb if first else aabb.merge(bb)
		first = false
	var wl := float(KatanaModels.skin(0)["world_len"])
	assert(absf(aabb.size.y - wl) < wl * 0.15, "La katana mide %.2f m a lo largo (esperado %.2f, aabb %s)" % [aabb.size.y, wl, aabb])
	print("CHECK 2 PASSED: modelo en la mano (%.2f m)" % aabb.size.y)

	# 3. Combo kt1 -> kt2 -> kt3 -> kt4 con daño
	var d := _dummy(1.8)
	await get_tree().physics_frame
	cc.attack_cooldown = 0.0
	res.energy = PlayerResources.ENERGY_MAX
	_player.attack()
	assert(ac._current_action_name == "kt1", "El primer clic lanza kt1 (%s)" % ac._current_action_name)
	var dmg := []
	var last := d.hp
	for a in ["kt2", "kt3", "kt4"]:
		assert(await _chain_to(a), "Encadena %s (%s)" % [a, ac._current_action_name])
		dmg.append(last - d.hp)
		last = d.hp
	await _wait(1.8)
	dmg.append(last - d.hp)
	for i in dmg.size():
		assert(float(dmg[i]) > 0.0, "El golpe %d del combo hace daño (%s)" % [i + 1, str(dmg)])
	print("CHECK 3 PASSED: combo kt1 -> kt2 -> kt3 -> kt4 (daño %s)" % str(dmg))
	await _clear_enemies()
	await _wait(1.5)

	# 4. Ataque corriendo
	var g: Dictionary = PlayerMovementController.GAITS[W]
	mc.gs_calm = 5.0
	mc._gs_mult = float(g["run"])
	ac._combo_timer = 0.0
	var d2 := _dummy(2.6)
	await get_tree().physics_frame
	cc.attack_cooldown = 0.0
	res.energy = PlayerResources.ENERGY_MAX
	_player.attack()
	assert(ac._current_action_name == "kt_run", "Corriendo el clic lanza kt_run (%s)" % ac._current_action_name)
	await _wait(1.4)
	assert(d2.hp < 5000.0, "El ataque corriendo golpea (hp %.1f)" % d2.hp)
	print("CHECK 4 PASSED: ataque corriendo")
	await _clear_enemies()
	await _wait(2.0)

	# 5. Especial (clic derecho): cobra energía, golpea y tiene enfriamiento
	var d3 := _dummy(2.2)
	await get_tree().physics_frame
	res.energy = PlayerResources.ENERGY_MAX
	assert(cc.katana_special(), "Sale el especial")
	assert(ac._current_action_name == "kt_special", "Suena kt_special (%s)" % ac._current_action_name)
	assert(res.energy < PlayerResources.ENERGY_MAX, "El especial cuesta energía")
	assert(not cc.katana_special(), "En enfriamiento no sale otra vez")
	await _wait(1.6)
	assert(d3.hp < 5000.0, "El especial golpea (hp %.1f)" % d3.hp)
	print("CHECK 5 PASSED: especial (%.1f de daño)" % (5000.0 - d3.hp))
	await _clear_enemies()

	# 6. Legendaria mítica
	var item := EquipmentDB.legendary_item("katana_sangre")
	assert(int(item["rarity"]) == 4 and EquipmentDB.rarity_name(item) == "Mítica", "Rareza mítica")
	assert(int(item["weapon"]) == W, "Es una katana")
	assert(not EquipmentDB.WEAPONS.has(W), "No sale en el sorteo normal de armas")
	print("CHECK 6 PASSED: legendaria mítica %s" % item["name"])

	print("ALL KATANA CHECKS PASSED")
	get_tree().quit(0)
