extends Node

## Deslizamiento de supervivencia (PlayerMovementController): física por pendiente y velocidad, empujón
## lateral a los enemigos según la fuerza, solo en supervivencia, y animación mikeura_slide en Mikeura.
var _main: Node
var _fail := false
func _check(ok: bool, msg: String) -> void:
	print("%s: %s" % ["PASSED" if ok else "FAILED", msg])
	if not ok:
		_fail = true

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var PMC := PlayerMovementController
	# 1. Física pura
	var g := 22.0
	var v := Vector3(10, 0, 0)
	var t := 0.0
	while v.length() > PMC.SLIDE_END_SPEED and t < 10.0:
		v = PMC.slide_step(v, Vector2.ZERO, g, 1.0 / 60.0)
		t += 1.0 / 60.0
	_check(t > 0.6 and t < 1.6, "en llano el roce lo para (%.2f s desde 10 m/s)" % t)
	var down := PMC.slide_step(Vector3(8, 0, 0), Vector2(-0.4, 0.0), g, 0.5)    # el suelo baja hacia +x
	var up := PMC.slide_step(Vector3(8, 0, 0), Vector2(0.4, 0.0), g, 0.5)
	var flat := PMC.slide_step(Vector3(8, 0, 0), Vector2.ZERO, g, 0.5)
	_check(down.length() > 8.0 and up.length() < flat.length(), "cuesta abajo acelera (%.1f), cuesta arriba frena (%.1f vs %.1f)" % [down.length(), up.length(), flat.length()])
	_check(PMC.slide_step(Vector3(19, 0, 0), Vector2(-2.0, 0.0), g, 1.0).length() <= PMC.SLIDE_MAX_SPEED + 0.01, "tope de velocidad")
	_check(PMC.can_start_slide(Vector3(8, 0, 0), Vector2.ZERO) and not PMC.can_start_slide(Vector3(3, 0, 0), Vector2.ZERO)
		and PMC.can_start_slide(Vector3(3, 0, 0), Vector2(-0.3, 0.0)) and not PMC.can_start_slide(Vector3(3, 0, 0), Vector2(0.3, 0.0)),
		"empieza corriendo, o despacio si es cuesta abajo")
	_check(PMC.slide_push_force(2.0) == 0.0 and PMC.slide_push_force(14.0) > PMC.slide_push_force(7.0), "más rápido, empujón más fuerte")
	var kb_l := PMC.slide_push_vector(Vector3(1, 0, 0), Vector3(1, 0, -0.5), 10.0)
	var kb_r := PMC.slide_push_vector(Vector3(1, 0, 0), Vector3(1, 0, 0.5), 10.0)
	_check(kb_l.z < -5.0 and kb_r.z > 5.0 and kb_l.x > 0.0, "aparta hacia el lado en que está el enemigo")

	_check(PMC.landing_slide_speed(8.0, 14.0) > PMC.landing_slide_speed(8.0, 7.0) and PMC.can_landing_slide(8.0, 7.0)
		and not PMC.can_landing_slide(8.0, 3.0) and not PMC.can_landing_slide(0.0, 8.0) and PMC.can_landing_slide(0.0, 12.0),
		"al aterrizar: la caída suma velocidad; quieto solo con caídas fuertes")

	# 2. En partida (supervivencia con Mikeura)
	GameData.game_mode = "survival"
	SaveManager.save_path = "user://test_save.json"
	SaveManager.meta = {}
	_main = load("res://scenes/core/main_procedural.tscn").instantiate()
	get_tree().root.add_child.call_deferred(_main)
	await get_tree().process_frame
	get_tree().current_scene = _main
	var p = null
	var waves: WaveManager = null
	for i in 900:
		await get_tree().process_frame
		p = _main.get_node_or_null("Player")
		waves = _main.find_child("WaveManager", true, false)
		if p and waves and waves._running:
			break
	_check(waves != null and waves._running, "arranca la partida")
	p.health_comp.max_hp = 100000.0
	p.health_comp.hp = 100000.0
	waves.stop_run()
	waves._running = true
	for e in EnemyRegistry.all().duplicate():
		if e is EnemyData and not e.recycled:
			e.take_damage(e.hp + 1.0)
	var mc: PlayerMovementController = p.movement_controller
	mc.slide_elapsed_override = 999.0       # beta: el deslizamiento empieza nerfeado; aquí se prueba a fuerza completa
	_check(is_equal_approx(PlayerMovementController.slide_power(0.0), PlayerMovementController.SLIDE_NERF_START) and is_equal_approx(PlayerMovementController.slide_power(999.0), 1.0), "beta: el deslizamiento empieza al %d %% y llega al 100 %%" % int(PlayerMovementController.SLIDE_NERF_START * 100.0))
	var anim = p.animation_controller
	var lib: AnimationLibrary = anim.anim_player.get_animation_library("")
	_check(anim._char_id() == "mikeura" and lib.has_animation(PlayerAnimationController.ACTION_SLIDE), "Mikeura tiene la animación de deslizarse")
	for i in 20:
		await get_tree().physics_frame

	# Enemigo delante, un poco a la izquierda, quieto
	var start: Vector3 = p.global_position
	var victim: EnemyData = waves._spawn_single_enemy(start + Vector3(4.0, 0, -0.6), EnemyData.EnemyType.NORMAL_GOBLIN)[0]
	victim.speed = 0.0
	await get_tree().physics_frame
	var vz0 := victim.global_position.z
	var hp0 := victim.hp

	mc.slide_input_override = true
	mc._slide_was_pressed = true
	p.velocity = Vector3(9.0, 0, 0)
	mc._try_start_slide()
	_check(mc.is_sliding(), "corriendo + Ctrl empieza a deslizarse")
	var anim_on := false
	var frames := 0
	for i in 240:
		await get_tree().physics_frame
		anim_on = anim_on or anim.is_sliding_anim()
		if not mc.is_sliding():
			break
		frames += 1
	var dist := Vector2(p.global_position.x - start.x, p.global_position.z - start.z).length()
	_check(dist > 4.0 and frames > 20, "se desliza %.1f m en %.2f s" % [dist, frames / 60.0])
	_check(anim_on and not anim.is_sliding_anim(), "suena la animación y se quita al acabar")
	_check(victim.global_position.z < vz0 - 0.5 and victim.hp == hp0, "aparta al enemigo hacia su lado sin dañarlo (%.1f m)" % (vz0 - victim.global_position.z))

	# Soltar la tecla lo corta
	await get_tree().create_timer(0.5, true, false, true).timeout
	p.velocity = Vector3(-9.0, 0, 0)
	mc._try_start_slide()
	var started := mc.is_sliding()
	mc.slide_input_override = false
	for i in 3:
		await get_tree().physics_frame
	_check(started and not mc.is_sliding(), "soltar la tecla corta el deslizamiento")

	# Botón táctil (Android): VirtualInput.is_sliding hace lo mismo que mantener Ctrl
	await get_tree().create_timer(0.5, true, false, true).timeout
	VirtualInput.is_sliding = true
	mc._slide_was_pressed = true
	p.velocity = Vector3(9.0, 0, 0)
	mc._try_start_slide()
	var touch_started := mc.is_sliding()
	VirtualInput.is_sliding = false
	for i in 3:
		await get_tree().physics_frame
	_check(touch_started and not mc.is_sliding(), "el botón táctil de deslizarse empieza y, al soltarlo, corta")
	var mobile := MobileControls_new_survival()
	_check(mobile._in_mode("slide") and mobile._in_mode("jump"), "en supervivencia hay botón de deslizarse")
	mobile.mode = "dungeon"
	_check(not mobile._in_mode("slide"), "en la mazmorra no sale")
	mobile.free()

	# Saltar y caer con la tecla pulsada: entra deslizando al tocar suelo, más rápido que en llano
	await get_tree().create_timer(0.5, true, false, true).timeout
	var here: Vector3 = p.global_position
	p.velocity = Vector3.ZERO
	p.global_position = here + Vector3(0, 4.0, 0)
	mc.add_dash(Vector3(8.0, 0, 0), 0.0)
	for i in 4:
		await get_tree().physics_frame          # ya en el aire
	mc.slide_input_override = true
	var land_speed := 0.0
	for i in 120:
		await get_tree().physics_frame
		if mc.is_sliding():
			land_speed = mc._slide_vel.length()
			break
	mc.slide_input_override = false
	mc.dash_velocity = Vector3.ZERO
	for i in 3:
		await get_tree().physics_frame
	_check(land_speed > PMC.SLIDE_MIN_START + 1.0, "saltar/caer con Ctrl entra deslizando al aterrizar (%.1f m/s)" % land_speed)
	# Sin la tecla, aterrizar no desliza
	await get_tree().create_timer(0.5, true, false, true).timeout
	p.velocity = Vector3.ZERO
	p.global_position = p.global_position + Vector3(0, 4.0, 0)
	mc.add_dash(Vector3(-8.0, 0, 0), 0.0)
	var slid := false
	for i in 90:
		await get_tree().physics_frame
		slid = slid or mc.is_sliding()
	mc.dash_velocity = Vector3.ZERO
	_check(not slid, "sin Ctrl aterrizar no desliza")

	# Solo en supervivencia
	await get_tree().create_timer(0.5, true, false, true).timeout
	GameData.game_mode = "dungeon"
	p.velocity = Vector3(9.0, 0, 0)
	mc._try_start_slide()
	_check(not mc.is_sliding(), "fuera de supervivencia no hay deslizamiento")
	GameData.game_mode = "survival"
	get_tree().quit(1 if _fail else 0)

## Controles táctiles en modo supervivencia, sin añadirlos al árbol (solo para preguntar por sus botones).
func MobileControls_new_survival() -> Node:
	var mc: Node = load("res://scripts/ui/mobile_controls.gd").new()
	mc.mode = "survival"
	return mc
