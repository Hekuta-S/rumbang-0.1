extends Node

## Sonda: juega la mazmorra unos segundos con entradas reales (andar, correr con esquivar mantenido,
## atacar, rodar) y vigila que el jugador se mueva, no atraviese el suelo y no se atasque.
##   res://tests/probe_dungeon_play.tscn  (headless vale; con ventana guarda user://probe_dungeon_*.png)

var _main: Node

func _ready() -> void:
	GameData.game_mode = "dungeon"
	SaveManager.save_path = "user://test_save.json"
	_main = load("res://scenes/core/main_dungeon.tscn").instantiate()
	get_tree().root.add_child.call_deferred(_main)
	_run.call_deferred()

func _log(tag: String, p) -> void:
	var res = p.get("resources")
	print("PROBE %s pos=%s floor=%s hp=%.0f en=%s sprint=%s atk=%s" % [tag, p.global_position.snapped(Vector3.ONE * 0.1),
		p.is_on_floor(), p.health_comp.hp, ("%.0f" % res.energy) if res else "-",
		p.movement_controller.get("sprinting"), p.animation_controller.is_attacking() if p.animation_controller else "-"])

func _key(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = down
	Input.parse_input_event(e)

func _diag(tag: String, p) -> void:
	var b: Vector3 = p.global_position
	_key(KEY_W, true)
	await get_tree().create_timer(0.6).timeout
	var mc = p.movement_controller
	var parry = p.get("parry_controller")
	print("PROBE diag[%s] moved=%.2f vel=%s atk=%s parry=%s slow=%s/%.2f now=%.2f dodge=%s pp=%s mpp=%s" % [tag,
		Vector2(p.global_position.x - b.x, p.global_position.z - b.z).length(), p.velocity.snapped(Vector3.ONE * 0.01),
		p.animation_controller.is_attacking(), parry.is_active() if parry else "-", mc.slow_until, mc.slow_mult,
		Time.get_ticks_msec() / 1000.0, mc.is_dodging(), p.is_physics_processing(), mc.is_physics_processing()])
	print("PROBE   camfwd=", -p.spring_arm.global_transform.basis.z, " arm_rot=", p.spring_arm.rotation_degrees, " inp=", p.input_controller.get_movement_vector())
	print("PROBE   weapon=%s ms=%.2f mm=%.2f launch=%s slide=%s spear=%.2f gs=%.2f rm=%s dash=%s ts=%.2f" % [p.current_weapon(), p.move_speed,
		p.stat_block.move_mult() if p.stat_block else -1.0, mc._launch_vel, mc._sliding, p.combat_controller.spear_charge,
		mc._gs_mult, mc.root_motion_velocity, mc.dash_velocity, Engine.time_scale])
	_key(KEY_W, false)
	await get_tree().create_timer(0.2).timeout

func _shot(name: String) -> void:
	if DisplayServer.get_name() != "headless":
		get_viewport().get_texture().get_image().save_png("user://probe_dungeon_%s.png" % name)

func _run() -> void:
	await get_tree().process_frame
	get_tree().current_scene = _main
	var enc: DungeonEncounter = null
	for i in 900:
		await get_tree().process_frame
		enc = _main.get_node_or_null("DungeonEncounter")
		if enc and enc.map and is_instance_valid(enc.player):
			break
	var p = enc.player
	(p.get("equipment") as PlayerEquipment).persist = false
	await get_tree().create_timer(1.5).timeout
	var start: Vector3 = p.global_position
	_log("inicio", p)
	_shot("0_inicio")
	# 1. andar hacia delante 2 s
	_key(KEY_W, true)
	await get_tree().create_timer(0.5).timeout
	print("PROBE inp=", p.input_controller.get_movement_vector(), " vel=", p.velocity, " pp=", p.is_physics_processing())
	await get_tree().create_timer(1.5).timeout
	_log("andar", p)
	var walked := Vector2(p.global_position.x - start.x, p.global_position.z - start.z).length()
	# 2. correr: mantener esquivar
	var before: Vector3 = p.global_position
	_key(KEY_W, true)
	_key(KEY_SHIFT, true)
	await get_tree().create_timer(2.0).timeout
	_log("correr", p)
	_key(KEY_SHIFT, false)
	var ran := Vector2(p.global_position.x - before.x, p.global_position.z - before.z).length()
	_key(KEY_W, false)
	# 3. atacar varias veces
	for i in 6:
		Input.action_press("attack")
		await get_tree().create_timer(0.12).timeout
		Input.action_release("attack")
		await get_tree().create_timer(0.3).timeout
	_log("atacar", p)
	await _diag("tras_ataque", p)
	_shot("1_ataque")
	# 4. rodar a un lado
	_key(KEY_A, true)
	Input.action_press("dodge_roll")
	await get_tree().create_timer(0.1).timeout
	Input.action_release("dodge_roll")
	await get_tree().create_timer(1.0).timeout
	_key(KEY_A, false)
	_log("rodar", p)
	await _diag("tras_rodar", p)
	# 5. alt attack
	Input.action_press("alt_attack")
	await get_tree().create_timer(0.8).timeout
	Input.action_release("alt_attack")
	await get_tree().create_timer(1.0).timeout
	_log("alt", p)
	await _diag("tras_alt", p)
	_shot("2_fin")
	# 6. volver a andar al final, hacia atrás (alejándose de la pared de delante)
	_key(KEY_S, true)
	await get_tree().create_timer(1.0).timeout
	_key(KEY_S, false)
	_log("atras", p)
	var b2: Vector3 = p.global_position
	_key(KEY_W, true)
	await get_tree().create_timer(0.5).timeout
	print("PROBE inp=", p.input_controller.get_movement_vector(), " vel=", p.velocity)
	await get_tree().create_timer(1.5).timeout
	_key(KEY_W, false)
	print("PROBE walk2=%.2f" % Vector2(p.global_position.x - b2.x, p.global_position.z - b2.z).length())
	print("PROBE walked=%.2f ran=%.2f y=%.2f enemies=%d" % [walked, ran, p.global_position.y, EnemyRegistry.count()])
	get_tree().quit(0)
