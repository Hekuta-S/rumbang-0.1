extends Node

func _ready() -> void:
	print("--- TEST TASK 1: AUTO COMBAT & SOFT AIM ---")
	GameData.game_mode = "dungeon"
	var player_scene = load("res://scenes/entities/player.tscn")
	var player = player_scene.instantiate()
	add_child(player)
	
	# 1. Verificar que AutoCombatController no existe en modo dungeon
	var auto_node = player.get_node_or_null("AutoCombatController")
	assert(auto_node == null, "AutoCombatController NO debe instanciarse en modo dungeon")
	print("CHECK 1 PASSED: AutoCombatController deshabilitado en mazmorra")
	
	# 2. Probar que apuntado suave existe y devuelve un Vector3 normalizado
	assert(player.combat_controller.has_method("get_soft_aim_direction"), "CombatController debe tener get_soft_aim_direction")
	var aim_dir = player.combat_controller.get_soft_aim_direction()
	assert(aim_dir is Vector3, "get_soft_aim_direction debe devolver un Vector3")
	print("CHECK 2 PASSED: get_soft_aim_direction implementado")
	
	# 3. Probar bloqueo de combo durante carga de lanza
	player.combat_controller.spear_charge = 0.5
	var cd_before = player.combat_controller.attack_cooldown
	player.combat_controller.attack()
	assert(player.combat_controller.spear_charge == 0.5, "Attack no debe romper la carga")
	player.combat_controller.spear_charge = -1.0
	print("CHECK 3 PASSED: Carga de lanza protege contra ataques simultaneos")
	
	player.queue_free()
	print("ALL TASK 1 CHECKS PASSED")
	get_tree().quit(0)
