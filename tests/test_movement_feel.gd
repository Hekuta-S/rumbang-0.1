extends Node

## Fase 3 del plan de juice (docs/PLAN_JUICE.md): esquiva perfecta, fantasmas, aterrizaje y pasos.

func _ready() -> void:
	print("--- TEST: MOVIMIENTO (FASE 3) ---")
	GameData.game_mode = "dungeon"
	var hf := HitFeedback.new()
	add_child(hf)
	HitFeedback._inst = hf
	var player = load("res://scenes/entities/player.tscn").instantiate()
	add_child(player)
	await get_tree().process_frame
	await get_tree().process_frame
	var mc = player.movement_controller
	var hc = player.health_comp

	# 1. Esquiva perfecta: golpe al principio de la voltereta → sin daño, energía de vuelta, una sola vez
	mc.perform_dodge()
	assert(mc.is_dodging())
	var hp_before: float = hc.hp
	var res = player.resources
	var energy_before: float = res.energy
	player.take_damage(5.0, Vector3.FORWARD)
	assert(hc.hp == hp_before, "durante la voltereta no hay daño")
	assert(mc._perfect_used, "golpe al principio de la voltereta = esquiva perfecta")
	assert(res.energy > energy_before, "la esquiva perfecta devuelve energía")
	assert(not mc.try_perfect_dodge(), "solo una esquiva perfecta por voltereta")
	print("CHECK 1 PASSED: esquiva perfecta sin daño, con energía y una sola vez")

	# 2. Fuera de la ventana no es perfecta
	mc._dodge_cooldown_timer = 0.0
	mc._dodge_timer = 0.0
	mc.perform_dodge()
	mc._dodge_timer = mc.DODGE_DURATION - mc.PERFECT_WINDOW - 0.05
	assert(not mc.try_perfect_dodge(), "tarde en la voltereta ya no es perfecta")
	print("CHECK 2 PASSED: ventana de la esquiva perfecta")

	# 3. Fantasmas: siluetas congeladas que se liberan solas (antes, que se apaguen los de las volteretas)
	await get_tree().create_timer(1.0, true, false, true).timeout
	var before := hf.get_child_count()
	var t0 := Time.get_ticks_usec()
	HitFeedback.afterimages(player.mesh, 1, 0.05, Color.CYAN, 0.2)
	print("ghost bake ms: %.2f" % ((Time.get_ticks_usec() - t0) / 1000.0))
	assert(hf.get_child_count() == before + 1, "un fantasma = un contenedor")
	var holder: Node3D = hf.get_child(hf.get_child_count() - 1)
	assert(holder.get_child_count() > 0, "el fantasma lleva las mallas del personaje")
	await get_tree().create_timer(0.5).timeout
	assert(not is_instance_valid(holder), "el fantasma se libera al apagarse")
	print("CHECK 3 PASSED: fantasmas de la esquiva")

	# 4. Aterrizaje: el modelo se aplasta y vuelve a su escala
	var base_scale: Vector3 = player.mesh.scale
	mc._on_land(14.0)
	assert(player.mesh.scale.y < base_scale.y, "al aterrizar se aplasta")
	await get_tree().create_timer(0.5, true, false, true).timeout
	assert(player.mesh.scale.is_equal_approx(base_scale), "y recupera su escala")
	print("CHECK 4 PASSED: squash del aterrizaje")

	# 5. Pasos: cuatro variantes de sonido
	assert(AudioManager.get_stream("step") != null)
	for v in ["step_2", "step_3", "step_4"]:
		assert(ResourceLoader.exists("res://assets/sfx/%s.wav" % v), "falta %s" % v)
	print("CHECK 5 PASSED: sonidos de pasos")

	print("ALL MOVEMENT FEEL CHECKS PASSED")
	get_tree().quit(0)
