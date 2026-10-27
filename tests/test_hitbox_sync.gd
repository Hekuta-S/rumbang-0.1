extends Node

func _ready() -> void:
	print("--- TEST TASK 2: HITBOX SYNC & MESH ATTACHMENT ---")
	GameData.game_mode = "dungeon"
	var player_scene = load("res://scenes/entities/player.tscn")
	var player = player_scene.instantiate()
	add_child(player)
	
	var anim_ctrl = player.animation_controller
	assert(anim_ctrl != null, "Player debe tener animation_controller")
	assert(anim_ctrl.has_signal("hit_window_opened"), "Debe tener senal hit_window_opened")
	assert(anim_ctrl.has_signal("hit_window_closed"), "Debe tener senal hit_window_closed")
	
	# Verificar inyeccion de pistas de metodo en las animaciones de ataque
	var lib = anim_ctrl.anim_player.get_animation_library("")
	for a_name in ["attack1", "attack2", "attack3"]:
		if lib.has_animation(a_name):
			var a = lib.get_animation(a_name)
			var has_method_track := false
			for i in a.get_track_count():
				if a.track_get_type(i) == Animation.TYPE_METHOD:
					has_method_track = true
					break
			assert(has_method_track, "La animacion %s debe tener pista de metodo" % a_name)
	print("CHECK 1 PASSED: Pistas de metodo inyectadas en animaciones de ataque")
	
	# Simular apertura de ventana de golpe
	var hit_opened := [false]
	anim_ctrl.hit_window_opened.connect(func(aid, aname):
		hit_opened[0] = true
		assert(aname == "attack1", "Nombre de animacion correcto")
	)
	anim_ctrl._on_anim_hit_on("attack1")
	assert(hit_opened[0], "hit_window_opened debe emitirse al disparar _on_anim_hit_on")
	print("CHECK 2 PASSED: _on_anim_hit_on emite hit_window_opened")
	
	player.queue_free()
	print("ALL TASK 2 CHECKS PASSED")
	get_tree().quit(0)
