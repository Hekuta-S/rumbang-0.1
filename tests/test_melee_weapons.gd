extends Node

## Espalanza (alcance de los golpes, lanzamiento hacia la mira y apuntado táctil al cargar), Dagas
## Gemelas (combo animado y embestida) y Maza Rúnica (combo y mazazo al suelo que aturde).

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

## Goblin quieto (sin IA) a `dist` m delante del jugador, con mucha vida.
func _dummy(dist: float, side: float = 0.0) -> DungeonGoblin:
	# spawn_goblin() devuelve siempre el mismo goblin si sigue vivo: aquí hacen falta varios
	# Nace ya en su sitio: si nace dentro del jugador, la física lo empuja y el primer golpe lo pilla ahí
	var at: Vector3 = _player.global_position + _fwd() * dist + _fwd().cross(Vector3.UP) * side
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

func _equip(w: int) -> void:
	if not _player.weapon_slots.has(w):
		assert(_player.add_weapon(w), "Se añade el arma %d" % w)
	_player.select_slot(_player.weapon_slots.find(w))
	await get_tree().process_frame
	assert(_player.current_weapon() == w)

func _ready() -> void:
	print("--- TEST: ESPALANZA, DAGAS Y MAZA ---")
	await _boot()
	var W := WeaponData.WeaponType
	var cc: PlayerCombatController = _player.combat_controller
	var ac: PlayerAnimationController = _player.animation_controller
	var res: PlayerResources = _player.resources
	var spear = cc._strategies[W.SPEAR_LANCE]

	# 1. La estocada de la espalanza llega a ~3 m, no a 14 m
	var near := _dummy(2.4)
	var far := _dummy(6.0)
	await get_tree().physics_frame
	spear._on_dungeon_hit_opened(1, "attack1")
	await get_tree().physics_frame
	for i in 4:
		await get_tree().physics_frame
	assert(near.hp < 5000.0, "La estocada alcanza a 2,4 m")
	assert(is_equal_approx(far.hp, 5000.0), "La estocada ya no llega a 6 m (hp %.1f)" % far.hp)
	spear._on_dungeon_hit_closed(1)
	print("CHECK 1 PASSED: alcance de la estocada ajustado (%.1f de daño)" % (5000.0 - near.hp))
	await _clear_enemies()

	# 2. El lanzamiento cargado sale hacia la mira aunque Mikeura mire a otro lado
	var cam: CameraController = _player.camera_controller
	cam.target_yaw += deg_to_rad(70.0)
	await _wait(0.6)
	_player.mesh.rotation.y += deg_to_rad(-80.0)
	cc.attack_cooldown = 0.0
	res.energy = PlayerResources.ENERGY_MAX
	cc.start_spear_charge()
	assert(cc.spear_charge >= 0.0, "Empieza la carga")
	await _wait(0.3)
	assert(VirtualInput.alt_aims, "Cargando, el botón especial apunta (táctil)")
	var aim_flat: Vector3 = spear._dungeon_aim()
	assert(_fwd().dot(aim_flat) > 0.98, "Durante la carga Mikeura sigue a la mira")
	cc.release_spear_charge()
	await get_tree().process_frame
	var proj: Node3D = get_tree().get_nodes_in_group("spear_projectiles").back()
	var pdir: Vector3 = proj.direction
	assert(Vector3(pdir.x, 0, pdir.z).normalized().dot(aim_flat) > 0.98, "El tiro va hacia la mira")
	await get_tree().physics_frame
	assert(not VirtualInput.alt_aims, "Al soltar deja de apuntar")
	print("CHECK 2 PASSED: el lanzamiento va hacia la mira")

	# 3. Táctil: arrastrar el dedo del botón especial mientras se carga mueve la cámara
	var controls: Node = load("res://scripts/ui/mobile_controls.gd").new()
	get_tree().current_scene.add_child(controls)
	await get_tree().process_frame
	var alt_i: int = controls.BUTTONS.find_custom(func(b): return b["key"] == "alt")
	await _wait(1.0)
	cc.attack_cooldown = 0.0
	res.energy = PlayerResources.ENERGY_MAX
	controls._on_press(9, controls._btn_center[alt_i], true)
	await _wait(0.2)
	assert(cc.spear_charge >= 0.0, "Mantener el botón especial carga")
	var yaw0 := cam.target_yaw
	for i in 5:
		controls._on_drag(9, controls._btn_center[alt_i] + Vector2(i * 10, 0), Vector2(20, 0))
		await get_tree().physics_frame
	assert(absf(angle_difference(yaw0, cam.target_yaw)) > 0.01, "El dedo del botón especial mueve la mira")
	controls._on_press(9, controls._btn_center[alt_i], false)
	await _wait(0.3)
	assert(cc.spear_charge < 0.0, "Soltar lanza")
	controls.queue_free()
	print("CHECK 3 PASSED: apuntar con el botón especial en táctil")
	await _wait(1.0)

	# 4. Dagas: modelos en las dos manos, combo animado y golpe en la ventana
	await _equip(W.DAGGERS)
	var lib: AnimationLibrary = ac.anim_player.get_animation_library("")
	for a in ["dagger1", "dagger2", "dagger3", "dagger_dash"]:
		assert(lib.has_animation(a), "Animación %s cargada" % a)
	var vis = _player.weapon_visuals
	assert(vis.weapon_models[W.DAGGERS].has_meta("in_hand") and vis.weapon_models[W.DAGGERS].visible, "La daga se ve en la mano")
	assert(vis.dagger_trails.size() == 2, "Una estela por daga")
	var d1 := _dummy(1.4)
	await get_tree().physics_frame
	cc.attack_cooldown = 0.0
	res.energy = PlayerResources.ENERGY_MAX
	_player.attack()
	await _wait(0.5)
	assert(d1.hp < 5000.0, "El tajo de daga golpea (hp %.1f)" % d1.hp)
	print("CHECK 4 PASSED: combo de dagas (%.1f de daño por tajo)" % (5000.0 - d1.hp))
	await _clear_enemies()
	await _wait(0.6)

	# 5. Embestida: avanza hacia la mira, atraviesa y corta, cobra energía; en enfriamiento no cobra
	var start: Vector3 = _player.global_position
	var aim_d: Vector3 = cc._strategies[W.DAGGERS]._dungeon_aim()
	var in_path := _dummy(0.0)
	in_path.global_position = start + aim_d * 2.0
	await get_tree().physics_frame
	res.energy = PlayerResources.ENERGY_MAX
	assert(cc.dagger_dash(), "Sale la embestida")
	var spent := PlayerResources.ENERGY_MAX - res.energy
	assert(spent > 0.0, "La embestida gasta energía")
	var e_after := res.energy
	assert(not cc.dagger_dash(), "En enfriamiento no sale otra")
	assert(is_equal_approx(res.energy, e_after), "Y no cobra energía")
	await _wait(0.5)
	var moved: Vector3 = _player.global_position - start
	moved.y = 0.0
	assert(moved.length() > 2.5 and moved.normalized().dot(aim_d) > 0.9, "Avanza hacia la mira (%.2f m)" % moved.length())
	assert(in_path.hp < 5000.0, "Corta al enemigo que atraviesa")
	print("CHECK 5 PASSED: embestida (%.2f m, %.1f de daño)" % [moved.length(), 5000.0 - in_path.hp])
	await _clear_enemies()
	await _wait(0.8)

	# 6. Maza: combo animado y mazazo al suelo que daña en área y aturde
	await _equip(W.MACE)
	for a in ["mace1", "mace2", "mace3", "mace4", "mace_slam"]:
		assert(lib.has_animation(a), "Animación %s cargada" % a)
	# Fuera de los golpes la lleva al hombro a dos manos (capa de torso, sin IK de manos)
	await _wait(0.5)
	assert(ac.carry_only and ac.held_equipped, "La maza activa la postura al hombro")
	assert(float(ac.anim_tree.get("parameters/upper/blend_amount")) > 0.9, "La capa de torso está puesta")
	assert(not ac.has_held_layer(), "No cuenta como arma sujeta de disparo")
	var m1 := _dummy(1.8)
	await get_tree().physics_frame
	cc.attack_cooldown = 0.0
	res.energy = PlayerResources.ENERGY_MAX
	_player.attack()
	await _wait(1.2)   # golpes de maza pesados: el barrido llega a ~0,7 s
	assert(m1.hp < 5000.0, "El golpe de maza golpea (hp %.1f)" % m1.hp)
	var mace_hit := 5000.0 - m1.hp
	await _clear_enemies()
	await _wait(0.8)
	var ring: Array = [_dummy(2.0), _dummy(1.5, 2.5), _dummy(1.5, -2.5)]
	var out_of_range := _dummy(9.0)
	await get_tree().physics_frame
	res.energy = PlayerResources.ENERGY_MAX
	assert(cc.mace_slam(), "Sale el mazazo")
	await _wait(0.8)
	for g in ring:
		assert(g.hp < 5000.0, "La onda daña a los cercanos")
		assert(g.stun_fraction() >= 0.5, "Y los aturde (%.2f)" % g.stun_fraction())
	assert(is_equal_approx(out_of_range.hp, 5000.0), "No llega a 9 m")
	assert(not cc.mace_slam(), "El mazazo tiene enfriamiento")
	await _equip(W.DAGGERS)
	assert(ac.carry_only and ac.held_equipped, "Las dagas tienen su guardia al andar")
	await _equip(W.SPEAR_LANCE)
	assert(not ac.carry_only and not ac.held_equipped, "Con la espalanza se quita la postura de transporte")
	print("CHECK 6 PASSED: maza (%.1f por golpe) y mazazo al suelo" % mace_hit)

	# 7. Puntos débiles: la maza no se cancela hasta golpear; la espada para mejor
	await _wait(1.0)
	await _equip(W.MACE)
	await _wait(0.3)
	cc.attack_cooldown = 0.0
	res.energy = PlayerResources.ENERGY_MAX
	_player.attack()
	await _wait(0.1)
	assert(ac.is_attacking() and not ac.can_cancel_for_dodge(), "La anticipación de la maza no se esquiva")
	var cancel_after := false
	for i in 240:      # hasta 4 s: el golpe de maza llega a ~0,7 s
		await get_tree().physics_frame
		if not ac.is_attacking():
			break
		if ac._struck_action == ac._current_action_name and ac.active_attack_name == "":
			cancel_after = ac.can_cancel_for_dodge()
			break
	assert(cancel_after, "Tras golpear, la recuperación de la maza sí se esquiva")
	await _wait(1.5)
	var pc: PlayerParryController = _player.parry_controller
	assert(is_equal_approx(pc.window(), PlayerParryController.WINDOW), "Con la maza, guardia normal")
	await _equip(W.SWORD)
	assert(is_equal_approx(pc.window(), PlayerParryController.SWORD_WINDOW) and pc.bonus_mult() > PlayerParryController.BONUS_MULT,
		"Con la espada, guardia más larga y contraataque mayor")
	print("CHECK 7 PASSED: maza comprometida, espada para mejor")

	print("ALL MELEE WEAPON CHECKS PASSED")
	get_tree().quit(0)
