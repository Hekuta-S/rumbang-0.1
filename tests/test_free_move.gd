extends Node

## Supervivencia: movimiento libre (el personaje mira hacia donde camina) y cámara más alta.
var _fail := false
func _check(ok: bool, msg: String) -> void:
	print("%s: %s" % ["PASSED" if ok else "FAILED", msg])
	if not ok:
		_fail = true

func _src_len(path: String) -> float:
	var inst := (load(path) as PackedScene).instantiate()
	var ap := inst.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var l := ap.get_animation(ap.get_animation_list()[0]).length
	inst.free()
	return l

func _facing(p) -> Vector3:
	var f: Vector3 = -p.mesh.global_transform.basis.z
	f.y = 0.0
	return f.normalized()

func _wish(p, inp: Vector2) -> Vector3:
	var b: Basis = p.spring_arm.global_transform.basis
	var w: Vector3 = -b.z * -inp.y + b.x * inp.x
	w.y = 0.0
	return w.normalized()

func _hold(p, inp: Vector2, frames: int) -> float:
	VirtualInput.movement_vector = inp
	var speed := 0.0
	for i in frames:
		await get_tree().physics_frame
		speed = Vector2(p.velocity.x, p.velocity.z).length()
	VirtualInput.movement_vector = Vector2.ZERO
	return speed

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.game_mode = "survival"
	SaveManager.save_path = "user://test_save.json"
	GameData.selected_index = GameData.custom_index()    # selección de la mazmorra (Riva): la escena de supervivencia la cambia a Mikeura
	var m = load("res://scenes/core/main_procedural.tscn").instantiate()
	get_tree().root.add_child.call_deferred(m)
	await get_tree().process_frame
	get_tree().current_scene = m
	var p = null
	for i in 900:
		await get_tree().process_frame
		p = m.get_node_or_null("Player")
		if p and p.weapon_inventory and not p.weapon_inventory.weapon_slots.is_empty():
			break
	m.facade.wave_manager.stop_run()      # sin enemigos molestando
	for e in EnemyRegistry.all().duplicate():
		if e is EnemyData:
			e.recycle()
	p.health_comp.max_hp = 99999.0
	p.health_comp.hp = 99999.0
	for i in 40:
		await get_tree().physics_frame

	# Cámara más alta que antes (inclinación -0,35 y 5,2 m daban ~2,8 m de altura)
	var arm: SpringArm3D = p.spring_arm
	_check(arm.rotation.x < -0.6 and arm.spring_length > 5.9, "cámara más alta (inclinación %.2f, brazo %.1f)" % [arm.rotation.x, arm.spring_length])

	# Movimiento libre: al ir a la derecha el cuerpo gira hacia la derecha, no se queda mirando a la cámara
	var spd_fwd := await _hold(p, Vector2(0, -1), 40)
	var spd_back := 0.0
	var turned := false
	VirtualInput.movement_vector = Vector2(1, 0)
	for i in 40:
		await get_tree().physics_frame
	turned = _facing(p).dot(_wish(p, Vector2(1, 0))) > 0.9
	VirtualInput.movement_vector = Vector2.ZERO
	_check(turned, "al caminar a un lado el personaje mira hacia donde camina")
	# Hacia atrás: se gira de espaldas a la cámara y va a la misma velocidad que hacia delante
	VirtualInput.movement_vector = Vector2(0, 1)
	for i in 40:
		await get_tree().physics_frame
		spd_back = Vector2(p.velocity.x, p.velocity.z).length()
	var back_ok := _facing(p).dot(_wish(p, Vector2(0, 1))) > 0.9
	VirtualInput.movement_vector = Vector2.ZERO
	_check(back_ok, "hacia atrás también mira hacia donde camina")
	_check(absf(spd_back - spd_fwd) < 0.2 * maxf(spd_fwd, 0.01) and spd_fwd > 0.5, "misma velocidad en todas direcciones (%.2f / %.2f)" % [spd_fwd, spd_back])

	# Parado conserva su orientación
	await get_tree().physics_frame
	var keep := _facing(p)
	for i in 30:
		await get_tree().physics_frame
	_check(_facing(p).dot(keep) > 0.99, "parado no gira")

	# Al atacar se gira hacia la mira de la cámara
	p.combat_controller._face_soft_aim()
	var cam_f: Vector3 = -p.spring_arm.global_transform.basis.z
	cam_f.y = 0.0
	_check(_facing(p).dot(cam_f.normalized()) > 0.99, "al atacar el cuerpo mira hacia la cámara")
	# Mikeura usa sus propias animaciones de reposo, andar, correr y saltar (las únicas de supervivencia)
	var ac = p.animation_controller
	var lib: AnimationLibrary = ac.anim_player.get_animation_library("")
	_check(ac._char_id() == "mikeura" and ac.model.scene_file_path.ends_with("mikeura_idle.fbx"), "el personaje de supervivencia es Mikeura aunque se venga de la selección de Riva")
	var want := {"idle": "mikeura_idle", "walk": "mikeura_caminar", "run": "mikeura-correr", "jump": "mikeura-saltar"}
	for clip in want:
		var src_len := _src_len("res://assets/models/mikeura/%s.fbx" % want[clip])
		_check(lib.has_animation(clip) and absf(lib.get_animation(clip).length - src_len) < 0.01, "clip '%s' es el de Mikeura (%.2f s)" % [clip, src_len])
	var hud_cross: Control = p.get_parent().find_child("Crosshair", true, false)
	_check(hud_cross != null and not hud_cross.visible, "sin crosshair en supervivencia")
	print("ALL PASSED" if not _fail else "SOME FAILED")
	get_tree().quit(1 if _fail else 0)
