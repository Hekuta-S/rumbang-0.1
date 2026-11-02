extends Node

## Opción de marcas de ataque, velocidad de los personajes en mazmorra y ritmo de la espalanza.

func _ready() -> void:
	print("--- TEST: MARCAS, VELOCIDAD Y ESPALANZA ---")
	GameData.game_mode = "dungeon"
	var scene: Node = load("res://scenes/core/main_dungeon.tscn").instantiate()
	get_tree().root.add_child.call_deferred(scene)
	await get_tree().process_frame
	get_tree().current_scene = scene
	var enc: DungeonEncounter = null
	for i in 600:
		await get_tree().process_frame
		enc = scene.get_node_or_null("DungeonEncounter")
		if enc and enc.map and is_instance_valid(enc.player):
			break
	enc._pending.clear()
	var player = enc.player
	var saved_marks: bool = SettingsManager.show_attack_marks

	# 1. Marcas de ataque: se ocultan y vuelven con la opción
	var b := enc.spawn_brute()
	await get_tree().physics_frame
	SettingsManager.show_attack_marks = false
	b._start_attack("smash")
	await get_tree().physics_frame
	assert(b.state == DungeonGoblin.State.WINDUP and not b._telegraph.visible, "Sin marcas, el aviso del suelo no se ve")
	assert(b._flash > 0.0, "Sin marcas, el destello de aviso se mantiene")
	b._set_state(DungeonGoblin.State.APPROACH)
	SettingsManager.show_attack_marks = true
	b._start_attack("smash")
	await get_tree().physics_frame
	assert(b._telegraph.visible, "Con marcas, el aviso del suelo se ve")
	b.queue_free()
	SettingsManager.show_attack_marks = saved_marks
	print("CHECK 1 PASSED: la opción oculta y muestra las marcas")

	# 2. Velocidad: × 0,8 en mazmorra; la de la ficha en supervivencia
	var base := float(GameData.get_selected().get("stats", {}).get("move_speed", 8.5))
	assert(absf(player.move_speed - base * GameData.DUNGEON_MOVE_SPEED_MULT) < 0.01,
		"En mazmorra la velocidad es %.2f × 0,8 (es %.2f)" % [base, player.move_speed])
	GameData.game_mode = "survival"
	GameData.apply_to_player(player)
	assert(absf(player.move_speed - base * GameData.SURVIVAL_PLAYER_SPEED_MULT) < 0.01, "En supervivencia la velocidad es × %.2f (es %.2f)" % [GameData.SURVIVAL_PLAYER_SPEED_MULT, player.move_speed])
	GameData.game_mode = "dungeon"
	player.move_speed = base * GameData.DUNGEON_MOVE_SPEED_MULT
	print("CHECK 2 PASSED: velocidad %.2f → %.2f en mazmorra, %.2f en supervivencia" % [base, base * GameData.DUNGEON_MOVE_SPEED_MULT, base * GameData.SURVIVAL_PLAYER_SPEED_MULT])

	# 3. Espalanza: golpes al 80 % y ventana de impacto más tardía pero sincronizada
	var anim = player.animation_controller
	var opened := [false]
	anim.hit_window_opened.connect(func(_id, _n): opened[0] = true, CONNECT_ONE_SHOT)
	anim._combo_timer = 0.0
	anim.play_attack()
	assert(is_equal_approx(float(anim.anim_tree.get(PlayerAnimationController.ACTION_SCALE_PARAM)), PlayerAnimationController.SPEAR_ATTACK_SPEED), "Los golpes de espalanza deben ir al 80 %")
	# Tiempo de juego (no reloj real: en headless no coinciden)
	var acc := 0.0
	for i in 240:
		await get_tree().process_frame
		acc += get_process_delta_time()
		if opened[0]:
			break
	var clip_t: float = anim._action_elapsed
	print("  ventana de attack1 abierta a %.2f s de juego, %.2f s de clip" % [acc, clip_t])
	assert(opened[0], "La ventana de attack1 debe abrirse")
	assert(acc >= 0.2 / PlayerAnimationController.SPEAR_ATTACK_SPEED, "Al 80 %% la ventana (0,20 s de clip) abre a 0,25 s o más de juego (abrió a %.2f)" % acc)
	assert(absf(clip_t - acc * PlayerAnimationController.SPEAR_ATTACK_SPEED) < 0.02, "El reloj del clip avanza al 80 % del de juego")
	var link_end: float = PlayerAnimationController.LINK_WINDOWS["attack1"][1]
	assert(anim._action_elapsed < link_end, "El tiempo de enlace va en tiempo del clip")
	anim._fire_action(PlayerAnimationController.ACTION_CHARGE)
	assert(is_equal_approx(float(anim.anim_tree.get(PlayerAnimationController.ACTION_SCALE_PARAM)), 1.0), "Las demás acciones van a velocidad normal")
	print("CHECK 3 PASSED: espalanza al 80 %, ventana sincronizada")

	print("ALL SETTINGS/SPEED CHECKS PASSED")
	get_tree().quit(0)
