extends Node

## Captura de los orbes elementales dibujados (necesita ventana): res://tests/shot_elemental_orbs.tscn -- <archivo.png>
## Supervivencia, da el Ciclo Elemental y 4 orbes extra (8 en total, elementos al azar con repetición),
## comprueba que todos usan uno de los 5 elementos y guarda una vista cercana.

var _out := "user://orbes.png"
var _main: Node

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	GameData.game_mode = "survival"
	SaveManager.save_path = "user://test_save.json"
	_main = load("res://scenes/core/main_procedural.tscn").instantiate()
	get_tree().root.add_child.call_deferred(_main)
	_run.call_deferred()

func _run() -> void:
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
	waves.stop_run()
	waves._running = true
	waves.set_process(false)
	p.health_comp.max_hp = 9999.0
	p.health_comp.hp = 9999.0
	p.add_weapon(WeaponData.WeaponType.ELEMENTS_CYCLE)
	await get_tree().create_timer(0.6).timeout
	var orbs: ElementalOrbs = p.combat_controller.elemental_orbs
	assert(orbs != null and orbs.orbs.size() == ElementalOrbs.INITIAL_ORBS, "Empieza con 4 orbes")
	for i in 4:
		orbs.add_orb()
	for o in orbs.orbs:
		assert(int(o.element_idx) >= 0 and int(o.element_idx) < 5, "Solo hay 5 elementos")
		assert(o.mesh is Sprite3D and (o.mesh as Sprite3D).texture != null, "Orbe = dibujo horneado")
	print("CHECK 1 PASSED orbes=", orbs.orbs.map(func(o): return ElementalOrbs.ELEMENT_NAMES[o.element_idx]))
	var cam := Camera3D.new()
	cam.fov = 50.0
	_main.add_child(cam)
	var c: Vector3 = p.global_position
	cam.look_at_from_position(c + Vector3(0, 3.2, 5.2), c + Vector3(0, 1.0, 0))
	cam.current = true
	await get_tree().create_timer(0.7).timeout
	get_viewport().get_texture().get_image().save_png(_out)
	print("captura guardada: ", _out)
	get_tree().quit(0)
