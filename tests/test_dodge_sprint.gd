extends Node

## Mazmorra, esquivar como en Dark Souls: un toque del botón rueda al soltarlo; mantenerlo corre (gastando
## energía) y al soltarlo no rueda. Sin energía deja de correr hasta soltar el botón.

func _ready() -> void:
	print("--- TEST: ESQUIVAR / CORRER ---")
	GameData.game_mode = "dungeon"
	var scene: Node = load("res://scenes/core/main_dungeon.tscn").instantiate()
	get_tree().root.add_child.call_deferred(scene)
	var player: Node = null
	for i in 600:
		await get_tree().process_frame
		player = scene.get_node_or_null("Player")
		if player and player.input_controller and player.movement_controller and player.resources:
			break
	for i in 30:
		await get_tree().physics_frame
	var inp = player.input_controller
	var mc: PlayerMovementController = player.movement_controller
	var res: PlayerResources = player.resources
	inp.set_physics_process(false)          # sin teclado real de por medio
	var rolls := [0]
	inp.dodge_pressed.connect(func(): rolls[0] += 1)
	var dt := 1.0 / 60.0

	# 1. Toque: rueda al soltar, no corre
	for i in 6:
		inp._update_dodge_hold(dt, true)      # 0,1 s pulsado
	assert(rolls[0] == 0, "Al pulsar todavía no rueda")
	assert(not inp.sprint_held, "Un toque no corre")
	inp._update_dodge_hold(dt, false)
	assert(rolls[0] == 1, "Al soltar el toque rueda (%d)" % rolls[0])
	print("CHECK 1 PASSED: toque = rodar al soltar")

	# 2. Mantener: corre y al soltar no rueda
	for i in 30:
		inp._update_dodge_hold(dt, true)      # 0,5 s
	assert(inp.sprint_held, "Mantenido más de %.2f s corre" % inp.SPRINT_HOLD)
	inp._update_dodge_hold(dt, false)
	assert(rolls[0] == 1 and not inp.sprint_held, "Al soltar tras correr no rueda")
	print("CHECK 2 PASSED: mantener = correr, sin rodar al soltar")

	# 3. Correr gasta energía; de lado no se corre
	assert(player.is_on_floor(), "En el suelo")
	res.energy = PlayerResources.ENERGY_MAX
	mc.force_sprint = true
	mc._update_sprint(0.5, true, true, false, false)
	assert(mc.sprinting, "Mantenido y hacia delante corre")
	assert(res.energy < PlayerResources.ENERGY_MAX, "Correr gasta energía (%.1f)" % res.energy)
	mc._update_sprint(dt, true, false, false, false)
	assert(not mc.sprinting, "De lado no se corre")
	mc._update_sprint(dt, true, true, true, false)
	assert(not mc.sprinting, "Atacando no se corre")
	print("CHECK 3 PASSED: carrera con gasto de energía, solo hacia delante")

	# 4. Sin energía para hasta soltar
	res.energy = 0.0
	mc._update_sprint(dt, true, true, false, false)
	assert(not mc.sprinting, "Sin energía no corre")
	res.energy = PlayerResources.ENERGY_MAX
	mc._update_sprint(dt, true, true, false, false)
	assert(not mc.sprinting, "Aunque recupere energía, no vuelve a correr sin soltar")
	mc.force_sprint = false
	mc._update_sprint(dt, true, true, false, false)
	mc.force_sprint = true
	mc._update_sprint(dt, true, true, false, false)
	assert(mc.sprinting, "Al soltar y volver a mantener corre otra vez")
	mc.force_sprint = false
	print("CHECK 4 PASSED: agotado deja de correr hasta soltar")

	# 5. En supervivencia Shift rueda al pulsar (sin cambios)
	GameData.game_mode = "survival"
	mc._update_sprint(dt, true, true, false, false)
	assert(not mc.sprinting, "En supervivencia no hay carrera de esquivar")
	GameData.game_mode = "dungeon"
	print("CHECK 5 PASSED: supervivencia sin carrera")
	print("ALL DODGE SPRINT CHECKS PASSED")
	get_tree().quit(0)
