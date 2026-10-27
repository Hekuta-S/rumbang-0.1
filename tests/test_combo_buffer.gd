extends Node

func _ready() -> void:
	print("--- TEST TASK 3: COMBO BUFFER & LINK WINDOW ---")
	GameData.game_mode = "dungeon"
	var player_scene = load("res://scenes/entities/player.tscn")
	var player = player_scene.instantiate()
	add_child(player)
	
	var combat = player.combat_controller
	var anim = player.animation_controller
	assert(combat != null, "Player debe tener combat_controller")
	assert(anim != null, "Player debe tener animation_controller")
	
	# 1. Simular buffer de ataque mientras el arma esta en cooldown
	assert(combat.has_method("buffer_attack"), "combat_controller debe tener buffer_attack")
	assert(combat.has_method("is_attack_buffered"), "combat_controller debe tener is_attack_buffered")
	combat.attack_cooldown = 0.5
	combat.buffer_attack()
	assert(combat.is_attack_buffered(), "El ataque debe permanecer en el buffer si no se puede ejecutar de inmediato")
	print("CHECK 1 PASSED: Buffer de ataque almacena la intencion durante cooldown/ataque")
	
	# 2. Verificar ventana de enlace en animation_controller
	assert(anim.has_method("is_in_link_window"), "animation_controller debe tener is_in_link_window")
	assert(anim.has_method("advance_combo"), "animation_controller debe tener advance_combo")
	print("CHECK 2 PASSED: Metodos de enlace de combo presentes")
	
	player.queue_free()
	print("ALL TASK 3 CHECKS PASSED")
	get_tree().quit(0)
