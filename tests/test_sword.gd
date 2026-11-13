extends Node

## Espada de una mano: clips (combo cortado en el fotograma 40), root motion, locomoción propia (reposo = guardia),
## andar -> correr sin combate, ataque corriendo, combo de cuatro golpes, daño y los cuatro modelos.

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
	print("--- TEST: ESPADA ---")
	await _boot()
	var W := WeaponData.WeaponType.SWORD
	var cc: PlayerCombatController = _player.combat_controller
	var ac: PlayerAnimationController = _player.animation_controller
	var mc: PlayerMovementController = _player.movement_controller
	var res: PlayerResources = _player.resources
	assert(_player.add_weapon(W), "Se añade la espada")
	_player.select_slot(_player.weapon_slots.find(W))
	await _wait(0.4)
	assert(_player.current_weapon() == W)

	# 1. Clips: ataque1, ataque2, el combo cortado en el fotograma 40 y el ataque corriendo, con root motion
	var lib: AnimationLibrary = ac.anim_player.get_animation_library("")
	var want := {"sw1": 61.0 / 30.0, "sw2": 50.0 / 30.0, "sw3": 40.0 / 30.0, "sw4": 66.0 / 30.0, "sw_run": 39.0 / 30.0}
	for a in want:
		assert(lib.has_animation(a), "Animación %s cargada" % a)
		var anim := lib.get_animation(a)
		assert(absf(anim.length - float(want[a])) < 0.04, "%s dura %.3f (esperado %.3f)" % [a, anim.length, want[a]])
		assert(anim.has_meta("root_motion"), "%s lleva root motion" % a)
	for a in ["loco_walk_18", "loco_run_18", "loco_strafe_18"]:
		assert(lib.has_animation(a), "Locomoción %s cargada" % a)
		assert(lib.get_animation(a).loop_mode == Animation.LOOP_LINEAR, "%s en bucle" % a)
	# Reposo: la guardia del inicio de ataque1, en ida y vuelta
	assert(lib.has_animation("loco_idle_18"), "Reposo de la espada cargado")
	assert(lib.get_animation("loco_idle_18").loop_mode == Animation.LOOP_PINGPONG, "El reposo va en ida y vuelta")
	assert(ac._gs_loco, "Con la espada se usa su locomoción")
	assert((ac.sm.get_node("walk") as AnimationNodeAnimation).animation == "loco_walk_18", "Andar usa el clip de la espada")
	assert((ac.sm.get_node("idle") as AnimationNodeAnimation).animation == "loco_idle_18", "El reposo es la guardia de la espada")
	print("CHECK 1 PASSED: clips, root motion y locomoción")

	# 2. La espada se ve en la mano con su estela; los cuatro modelos del glb
	var vis = _player.weapon_visuals
	assert(vis.weapon_models.has(W) and vis.weapon_models[W].visible, "La espada se ve en la mano")
	assert(is_instance_valid(vis.sword_trail), "Tiene estela")
	for s in SwordModels.count():
		vis.set_sword_skin(s)
		await get_tree().process_frame
		var meshes: Array = vis.sword_holder().find_children("*", "MeshInstance3D", true, false).filter(
			func(m): return not m is BladeTrail and not m.is_queued_for_deletion() and not m.get_parent() is BladeTrail)
		assert(meshes.size() >= 1, "Skin %d con malla" % s)
		# Largo real del modelo normalizado ~ world_len
		var aabb := AABB()
		var first := true
		for m in meshes:
			var mi := m as MeshInstance3D
			var bb: AABB = vis.sword_holder().global_transform.affine_inverse() * mi.global_transform * mi.get_aabb()
			aabb = bb if first else aabb.merge(bb)
			first = false
		var wl := float(SwordModels.skin(s)["world_len"])
		assert(absf(aabb.size.y - wl) < wl * 0.15, "Skin %d mide %.2f m a lo largo de la hoja (esperado %.2f)" % [s, aabb.size.y, wl])
	vis.set_sword_skin(0)
	print("CHECK 2 PASSED: %d modelos de espada" % SwordModels.count())

	# 3. Andar -> correr: antes que el espadón (GAITS "delay" s sin combate)
	var sw_delay := float(PlayerMovementController.GAITS[WeaponData.WeaponType.SWORD]["delay"])
	assert(sw_delay < PlayerMovementController.GS_RUN_DELAY, "La espada arranca a correr antes que el espadón")
	mc.note_combat()
	assert(not mc.gs_running(), "Recién hecho un golpe: anda")
	for i in int(sw_delay * 10.0) + 3:
		mc._update_gs_gait(0.1, true)
	assert(mc.gs_running(), "Tras %.1f s sin combate corre" % sw_delay)
	_player.take_damage(1.0)
	assert(not mc.gs_running(), "Recibir daño lo devuelve a andar")
	print("CHECK 3 PASSED: andar/correr según el combate")
	await _wait(0.8)

	# 4. Combo de cuatro golpes: sw1 -> sw2 -> sw3 -> sw4
	var d := _dummy(1.8)
	await get_tree().physics_frame
	cc.attack_cooldown = 0.0
	res.energy = PlayerResources.ENERGY_MAX
	var start: Vector3 = _player.global_position
	_player.attack()
	assert(ac._current_action_name == "sw1", "El primer clic lanza sw1 (%s)" % ac._current_action_name)
	var dmg := []
	var last := d.hp
	for a in ["sw2", "sw3", "sw4"]:
		assert(await _chain_to(a), "Encadena %s (%s)" % [a, ac._current_action_name])
		dmg.append(last - d.hp)
		last = d.hp
	await _wait(1.4)
	dmg.append(last - d.hp)
	for i in dmg.size():
		assert(float(dmg[i]) > 0.0, "El golpe %d del combo hace daño (%s)" % [i + 1, str(dmg)])
	var moved: Vector3 = _player.global_position - start
	moved.y = 0.0
	print("CHECK 4 PASSED: combo sw1 -> sw2 -> sw3 -> sw4 (daño %s, avance %.2f m)" % [str(dmg), moved.length()])
	await _clear_enemies()
	await _wait(1.5)

	# 5. Ataque corriendo y continuación con sw2
	var g: Dictionary = PlayerMovementController.GAITS[W]
	mc.gs_calm = 5.0
	mc._gs_mult = float(g["run"])
	assert(mc.gs_running(), "Preparado para correr")
	ac._combo_timer = 0.0
	var d2 := _dummy(2.6)
	await get_tree().physics_frame
	cc.attack_cooldown = 0.0
	res.energy = PlayerResources.ENERGY_MAX
	start = _player.global_position
	_player.attack()
	assert(ac._current_action_name == "sw_run", "Corriendo el clic lanza sw_run (%s)" % ac._current_action_name)
	await _wait(1.0)
	assert(d2.hp < 5000.0, "La embestida golpea (hp %.1f)" % d2.hp)
	moved = _player.global_position - start
	moved.y = 0.0
	assert(await _chain_to("sw2"), "Tras el ataque corriendo sigue sw2 (%s)" % ac._current_action_name)
	print("CHECK 5 PASSED: ataque corriendo (%.1f de daño, %.2f m) y continuación del combo" % [5000.0 - d2.hp, moved.length()])
	await _clear_enemies()

	# 6. Cambiar de arma restablece la locomoción
	_player.add_weapon(WeaponData.WeaponType.SPEAR_LANCE)
	_player.select_slot(_player.weapon_slots.find(WeaponData.WeaponType.SPEAR_LANCE))
	await _wait(0.3)
	assert(not ac._gs_loco, "Sin espada vuelve la locomoción normal")
	assert((ac.sm.get_node("walk") as AnimationNodeAnimation).animation == "walk", "El estado andar vuelve a su clip")
	print("CHECK 6 PASSED: restablece la locomoción")

	print("ALL SWORD CHECKS PASSED")
	get_tree().quit(0)
