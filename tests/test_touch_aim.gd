extends Node

## Controles táctiles: fijar objetivo (una sola vez por pulsación) y apuntar con el botón de disparo
## (bazuca, polvos y escopeta): mantener = apuntar arrastrando el dedo, soltar = disparar.

var _player: CharacterBody3D
var _enc: DungeonEncounter

func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _boot(char_id: String) -> void:
	GameData.game_mode = "dungeon"
	for i in GameData.CHARACTERS.size():
		if GameData.CHARACTERS[i]["id"] == char_id:
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

func _ready() -> void:
	print("--- TEST: APUNTAR CON EL BOTÓN TÁCTIL ---")
	await _boot("bronch")
	var controls: Node = load("res://scripts/ui/mobile_controls.gd").new()
	get_tree().current_scene.add_child(controls)
	await get_tree().process_frame
	var res: PlayerResources = _player.resources
	var W := WeaponData.WeaponType
	assert(_player.current_weapon() == W.SPORE_BAZOOKA)
	var attack_i := -1
	for i in controls.BUTTONS.size():
		if controls.BUTTONS[i]["key"] == "attack":
			attack_i = i

	# 1. Mantener el botón NO dispara y activa el modo de apuntado
	var ammo0 := res.ammo_of(W.SPORE_BAZOOKA)
	var fired := [0]
	_player.weapon_attacked.connect(func(_w): fired[0] += 1)
	_player.combat_controller.attack_cooldown = 0.0
	controls._on_press(7, controls._btn_center[attack_i], true)
	await _wait(0.5)
	assert(VirtualInput.attack_aims, "Con la bazuca el botón de disparo apunta")
	assert(fired[0] == 0 and res.ammo_of(W.SPORE_BAZOOKA) == ammo0, "Mantener pulsado no dispara")
	print("CHECK 1 PASSED: mantener el botón apunta y no dispara")

	# 2. Arrastrar el dedo desde el botón mueve la cámara
	var cc: CameraController = _player.camera_controller
	var yaw0 := cc.target_yaw
	for i in 5:
		controls._on_drag(7, controls._btn_center[attack_i] + Vector2(i * 10, 0), Vector2(20, 0))
		await get_tree().physics_frame
	assert(absf(angle_difference(yaw0, cc.target_yaw)) > 0.01, "Arrastrar desde el botón mueve la mira (yaw %.3f → %.3f)" % [yaw0, cc.target_yaw])
	print("CHECK 2 PASSED: el dedo del botón mueve la mira")

	# 3. Soltar dispara UNA vez
	controls._on_press(7, controls._btn_center[attack_i], false)
	await _wait(0.5)
	assert(fired[0] == 1, "Soltar dispara una vez (disparos: %d)" % fired[0])
	assert(res.ammo_of(W.SPORE_BAZOOKA) == ammo0 - 1, "Gasta una bala")
	await _wait(0.5)
	assert(fired[0] == 1, "No sigue disparando")
	print("CHECK 3 PASSED: al soltar sale un solo disparo")

	# 4. Fijar objetivo: una pulsación táctil fija una sola vez (aunque el aviso dure varios frames)
	var g := _enc.spawn_goblin()
	g.global_position = _player.global_position + Vector3(0, 0, -6)
	await _wait(1.2)
	var lock: TargetLockController = _player.target_lock
	assert(not lock.has_target())
	controls._on_press(8, controls._btn_center[controls.BUTTONS.find_custom(func(b): return b["key"] == "target")], true)
	controls._on_press(8, Vector2.ZERO, false)
	for i in 6:
		await get_tree().process_frame
	assert(lock.has_target(), "Una pulsación de FIJ fija al enemigo (y no lo suelta al instante)")
	print("CHECK 4 PASSED: FIJ fija una vez")

	# 4c. Mantener FIJ y deslizar cambia al enemigo de ese lado (como el stick derecho); tocar sin
	# arrastrar con un objetivo fijado lo suelta.
	var tgt_i: int = controls.BUTTONS.find_custom(func(b): return b["key"] == "target")
	var cam := get_viewport().get_camera_3d()
	var right: Vector3 = cam.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	lock._set_target(g)
	var g_r: Node3D = _enc.spawn_brute()
	g_r.global_position = g.global_position + right * 4.0
	var g_l: Node3D = _enc.spawn_brute()
	g_l.global_position = g.global_position - right * 4.0
	await _wait(0.6)
	lock._set_target(g)
	await get_tree().physics_frame
	var c0: Vector2 = controls._btn_center[tgt_i]
	controls._on_press(9, c0, true)
	for i in 4:
		controls._on_drag(9, c0 + Vector2(20 * (i + 1), 0), Vector2(20, 0))
	for i in 4:
		await get_tree().physics_frame
	assert(g_r != g and g_l != g and g_r != g_l, "Tres enemigos distintos")
	assert(lock.target == g_r, "Deslizar a la derecha cambia al goblin de la derecha (objetivo: %s)" % lock.target)
	controls._on_press(9, c0 + Vector2(80, 0), false)
	for i in 4:
		await get_tree().physics_frame
	assert(lock.target == g_r, "Soltar tras cambiar no suelta el objetivo")
	controls._on_press(9, c0, true)
	for i in 4:
		controls._on_drag(9, c0 - Vector2(20 * (i + 1), 0), Vector2(-20, 0))
	for i in 4:
		await get_tree().physics_frame
	controls._on_press(9, c0 - Vector2(80, 0), false)
	assert(lock.target == g, "Deslizar a la izquierda vuelve al del centro")
	controls._on_press(9, c0, true)
	controls._on_press(9, c0, false)
	for i in 4:
		await get_tree().physics_frame
	assert(not lock.has_target(), "Tocar FIJ sin arrastrar suelta el objetivo")
	g_r.queue_free()
	g_l.queue_free()
	await _wait(0.2)
	print("CHECK 4c PASSED: deslizar FIJ cambia de objetivo por dirección")

	# 4b. Teclado: C fija y suelta; Tab ya no fija sino que abre/cierra el menú de pausa
	var key := func(code: Key) -> void:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = true
		Input.parse_input_event(ev)
		await get_tree().process_frame
		ev = ev.duplicate()
		ev.pressed = false
		Input.parse_input_event(ev)
		await get_tree().process_frame
	lock._set_target(null)
	await key.call(KEY_C)
	assert(lock.has_target(), "C fija al enemigo")
	await key.call(KEY_C)
	assert(not lock.has_target(), "C vuelve a soltarlo")
	var pm = get_tree().current_scene.find_child("PauseMenu", true, false)
	assert(pm != null and not pm.visible, "Menú de pausa cerrado al empezar")
	await key.call(KEY_TAB)
	assert(pm.visible and not lock.has_target(), "Tab abre el menú y no fija objetivo")
	assert(is_instance_valid(pm._equip_panel) and not pm.get_node("Control/Row").visible, "Tab abre directo la pantalla de equipo")
	await key.call(KEY_TAB)
	assert(not pm.visible and not get_tree().paused and not is_instance_valid(pm._equip_panel), "Tab cierra todo y reanuda")
	print("CHECK 4b PASSED: C fija objetivo, Tab abre y cierra la pantalla de equipo")

	# 5. Los polvos de Tatan y la escopeta de Riva también se apuntan; la espalanza no
	var ic = _player.input_controller
	for w in [W.DUSTS, W.TRI_SHOTGUN, W.SPORE_BAZOOKA]:
		assert(ic.AIM_ON_HOLD.has(w))
	assert(not ic.AIM_ON_HOLD.has(W.SPEAR_LANCE) and not ic.AIM_ON_HOLD.has(W.FLAME_THROWER))
	print("CHECK 5 PASSED: armas que se apuntan al mantener")

	# 6. Pequeña ayuda de apuntado de la espalanza: engancha a un enemigo cercano y casi enfrente
	lock._set_target(null)
	var fwd: Vector3 = -_player.mesh.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	g.global_position = _player.global_position + fwd * 3.0
	_player.mesh.rotation.y += deg_to_rad(20.0)
	var assisted = _player.combat_controller.face_aim_assist_enemy()
	assert(assisted == g, "La ayuda de apuntado engancha al enemigo cercano de enfrente")
	var to_g: Vector3 = g.global_position - _player.global_position
	to_g.y = 0.0
	var yaw_want := atan2(-to_g.x, -to_g.z)
	assert(absf(angle_difference(_player.mesh.rotation.y, yaw_want)) < deg_to_rad(2.0), "La ayuda orienta al enemigo")
	print("CHECK 6 PASSED: ayuda de apuntado de la espalanza")

	print("ALL TOUCH AIM CHECKS PASSED")
	get_tree().quit(0)
