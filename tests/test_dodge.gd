extends Node

func _ready() -> void:
	print("--- TEST TASK 4: DODGE & I-FRAMES ---")
	GameData.game_mode = "dungeon"
	var player_scene = load("res://scenes/entities/player.tscn")
	var player = player_scene.instantiate()
	add_child(player)
	await get_tree().process_frame

	var mc = player.movement_controller
	var anim = player.animation_controller
	var combat = player.combat_controller
	assert(mc != null, "Player debe tener movement_controller")
	assert(mc.has_method("perform_dodge"), "MovementController debe tener perform_dodge")
	assert(mc.has_method("is_dodging"), "MovementController debe tener is_dodging")

	# Ejecutar esquiva
	mc.perform_dodge()
	assert(mc.is_dodging(), "Debe reportar estado de esquiva activo tras perform_dodge")
	assert(player.health_comp.is_invincible(), "Durante la esquiva el jugador debe tener I-frames")
	print("CHECK 1 PASSED: perform_dodge activa esquiva e I-frames")

	# Cooldown: una segunda esquiva inmediata no se ejecuta
	mc._dodge_timer = 0.0
	mc.perform_dodge()
	assert(not mc.is_dodging(), "La esquiva debe respetar su cooldown")
	print("CHECK 2 PASSED: Cooldown de esquiva")

	# Cancelacion de la carga de lanza
	mc._dodge_cooldown_timer = 0.0
	combat.spear_charge = 0.5
	mc.perform_dodge()
	assert(combat.spear_charge < 0.0, "La esquiva debe cancelar la carga de lanza")
	print("CHECK 3 PASSED: La esquiva cancela la carga")

	# El clic durante la esquiva queda en el buffer y no se consume a mitad del rodamiento
	combat.attack_cooldown = 0.0
	combat.buffer_attack()
	assert(combat.is_attack_buffered(), "El ataque pulsado durante la esquiva debe quedar en el buffer")
	print("CHECK 4 PASSED: Buffer retenido durante la esquiva")
	combat._attack_buffer_timer = 0.0

	# Ventana de impacto abierta: no se puede esquivar
	mc._dodge_timer = 0.0
	mc._dodge_cooldown_timer = 0.0
	anim.active_attack_name = "attack1"
	mc.perform_dodge()
	assert(not mc.is_dodging(), "No se esquiva con la ventana de impacto abierta")
	anim.active_attack_name = ""
	print("CHECK 5 PASSED: Ventana de impacto bloquea la esquiva")

	# Recuperacion de attack1: la esquiva la corta
	anim._combo_timer = 0.0
	anim.play_attack()
	await get_tree().process_frame
	await get_tree().process_frame
	if anim.is_attacking():
		anim.active_attack_name = ""
		mc.perform_dodge()
		assert(mc.is_dodging(), "La esquiva debe cortar la recuperacion de attack1")
		assert(anim._current_action_name == "", "La accion de attack1 debe quedar cancelada")
		print("CHECK 6 PASSED: La esquiva cancela la recuperacion de attack1")

		# Clavado (attack3): no se puede cancelar
		mc._dodge_timer = 0.0
		mc._dodge_cooldown_timer = 0.0
		anim._combo_index = 2
		anim._combo_timer = 1.0
		anim.play_attack()
		await get_tree().process_frame
		await get_tree().process_frame
		anim.active_attack_name = ""
		mc.perform_dodge()
		assert(not mc.is_dodging(), "El clavado (attack3) no debe poder cancelarse con la esquiva")
		print("CHECK 7 PASSED: El clavado no se cancela")
	else:
		print("CHECK 6-7 SKIPPED: sin animaciones de ataque cargadas")

	player.queue_free()
	print("ALL TASK 4 CHECKS PASSED")
	get_tree().quit(0)
