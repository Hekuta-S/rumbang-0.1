extends Node

## Arco y bazuca de esporas (mazmorra): el proyectil sale hacia el objetivo fijado y, sin objetivo, hacia el
## centro de la pantalla (la mira), aunque el objetivo esté desplazado a un lado y el personaje mire a otro sitio.

var _player: CharacterBody3D
var _enc: DungeonEncounter
const MAX_ERR_DEG := 4.0

func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _boot() -> void:
	GameData.game_mode = "dungeon"
	SaveManager.save_path = "user://test_save.json"
	# Personaje: el del juego (personalizado) o el id pasado tras "--" (p. ej. mikeura)
	var args := OS.get_cmdline_user_args()
	GameData.selected_index = GameData.custom_index()
	for i in GameData.CHARACTERS.size():
		if args.size() > 0 and GameData.CHARACTERS[i]["id"] == args[0]:
			GameData.selected_index = i
	print("  personaje: ", GameData.CHARACTERS[GameData.selected_index]["id"])
	var scene: Node = load("res://scenes/core/main_dungeon.tscn").instantiate()
	get_tree().root.add_child.call_deferred(scene)
	await get_tree().process_frame
	get_tree().current_scene = scene
	for i in 600:
		await get_tree().process_frame
		_enc = scene.get_node_or_null("DungeonEncounter")
		if _enc and _enc.map and is_instance_valid(_enc.player):
			break
	_enc._pending.clear()
	_player = _enc.player
	_player.health_comp.max_hp = 9999.0
	_player.health_comp.hp = 9999.0
	_player.global_position = _enc.map.room_center(_enc.map.arena_index) + Vector3(0, 0.3, 0)
	await _wait(0.5)

func _dummy(at: Vector3) -> Node3D:
	var g := _enc._spawn_at(_enc.map.arena_index, at)
	g.global_position = at
	g.max_hp = 5000.0
	g.hp = 5000.0
	g.set_physics_process(false)
	return g

func _clear() -> void:
	var tl = _player.get("target_lock")
	if tl and tl.has_target():
		tl._set_target(null)
	for e in EnemyRegistry.all():
		if is_instance_valid(e) and e is Node:
			EnemyRegistry.unregister(e)
			e.queue_free()
	for n in _projectiles():
		n.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame

func _projectiles() -> Array:
	return get_tree().root.find_children("*", "", true, false).filter(func(n):
		return not n.is_queued_for_deletion() and (n is BowArrow or (n.get_script() != null \
			and String(n.get_script().resource_path).ends_with("spore_projectile.gd"))))

func _equip(w: int) -> void:
	if not _player.weapon_slots.has(w):
		assert(_player.add_weapon(w), "Se añade el arma %d" % w)
	_player.select_slot(_player.weapon_slots.find(w))
	await _wait(0.5)
	assert(_player.current_weapon() == w)

## Dispara y devuelve [origen, dirección] del primer proyectil nuevo.
func _shoot() -> Array:
	var before := _projectiles()
	_player.resources.energy = PlayerResources.ENERGY_MAX
	_player.combat_controller.attack_cooldown = 0.0
	_player.attack()
	for i in 120:
		await get_tree().physics_frame
		for p in _projectiles():
			if not p in before:
				var d: Vector3 = p.velocity if p is BowArrow else p.direction
				var o: Vector3 = p.global_position - d.normalized() * 0.01
				return [o, d.normalized()]
	return []

## Gira la cámara `deg` grados (yaw) respecto a hacia donde mira el personaje.
func _turn_camera(deg: float) -> void:
	var cam_ctrl = _player.get("camera_controller")
	var yaw: float = _player.mesh.rotation.y + deg_to_rad(deg)
	if cam_ctrl and "target_yaw" in cam_ctrl:
		cam_ctrl.target_yaw = yaw
		if "yaw" in cam_ctrl:
			cam_ctrl.yaw = yaw
	else:
		_player.spring_arm.global_rotation.y = yaw
	for i in 30:
		await get_tree().process_frame

func _flat_angle(a: Vector3, b: Vector3) -> float:
	return rad_to_deg(Vector2(a.x, a.z).angle_to(Vector2(b.x, b.z)))

func _check(label: String, w: int) -> void:
	await _equip(w)
	# 1) Objetivo fijado a un lado (no delante del personaje ni de la cámara)
	await _clear()
	var c0: Vector3 = _player.global_position
	var f: Vector3 = -_player.mesh.global_transform.basis.z
	f.y = 0.0
	f = f.normalized()
	var right := Vector3(-f.z, 0, f.x)
	var g := _dummy(c0 + f * 7.0 + right * 5.0)
	await _wait(0.2)
	_player.get("target_lock")._set_target(g)
	await _wait(0.2)
	var shot := await _shoot()
	assert(not shot.is_empty(), "%s: sale el proyectil (fijado)" % label)
	var chest: Vector3 = g.global_position + Vector3(0, EnemyQuery.height_of(g) * 0.55, 0)
	var want: Vector3 = (chest - shot[0]).normalized()
	var err := _flat_angle(shot[1], want)
	print("  %s fijado: error %.1f° (dir %s, quiere %s)" % [label, err, shot[1], want])
	assert(absf(err) < MAX_ERR_DEG, "%s va al objetivo fijado (error %.1f°)" % [label, err])
	print("CHECK PASSED: %s dispara al objetivo fijado" % label)
	# 2) Sin objetivo: cámara girada 40° a un lado; el proyectil va hacia la mira
	await _clear()
	await _wait(0.3)
	await _turn_camera(40.0)
	var cam: Camera3D = _player.get_viewport().get_camera_3d()
	var center := _player.get_viewport().get_visible_rect().size * 0.5
	var cam_dir := cam.project_ray_normal(center)
	shot = await _shoot()
	assert(not shot.is_empty(), "%s: sale el proyectil (mira)" % label)
	err = _flat_angle(shot[1], cam_dir)
	print("  %s mira: error %.1f° (dir %s, cámara %s)" % [label, err, shot[1], cam_dir])
	assert(absf(err) < MAX_ERR_DEG, "%s va hacia la mira (error %.1f°)" % [label, err])
	print("CHECK PASSED: %s dispara hacia la mira" % label)
	# 3) Andando de lado con la cámara girada 70°: varios disparos seguidos, todos hacia la mira
	await _clear()
	await _turn_camera(-70.0)
	var mover := FixedMove.new()
	mover.v = Vector2(1, 0)
	_player.input_controller._direct_sources.append(mover)
	await _wait(0.6)
	for k in 3:
		shot = await _shoot()
		assert(not shot.is_empty(), "%s: sale el proyectil %d andando" % [label, k])
		# Hacia el punto de la mira en el instante del disparo (andando, el origen se aparta del rayo de la cámara)
		var aim_info: Dictionary = _player.camera_aim_controller.get_dungeon_aim()
		var aim_pt: Vector3 = aim_info["point"]
		var want_dir: Vector3 = aim_pt - shot[0]
		var near := Vector2(aim_pt.x - _player.global_position.x, aim_pt.z - _player.global_position.z).length() < WeaponStrategy.AIM_NEAR
		if near:   # la mira chocó con algo pegado al jugador: se dispara hacia la cámara
			want_dir = -_player.get_viewport().get_camera_3d().global_transform.basis.z
		err = _flat_angle(shot[1], want_dir)
		print("  %s andando %d: error %.1f°" % [label, k, err])
		assert(absf(err) < MAX_ERR_DEG, "%s andando va hacia la mira (error %.1f°)" % [label, err])
		await _wait(1.2 if label == "bazuca" else 0.5)
	_player.input_controller._direct_sources.erase(mover)
	print("CHECK PASSED: %s andando dispara hacia la mira" % label)
	# 4) Fijar con toggle() (la tecla C) a un enemigo vivo delante de la cámara (desde el centro de la arena: andando
	# puede haber quedado junto a una pared)
	await _clear()
	_player.global_position = _enc.map.room_center(_enc.map.arena_index) + Vector3(0, 0.3, 0)
	_player.velocity = Vector3.ZERO
	await _wait(0.3)
	var cf: Vector3 = Vector3(cam_dir.x, 0, cam_dir.z).normalized()
	var g2 := _dummy(_player.global_position + cf * 8.0 + Vector3(-cf.z, 0, cf.x) * 2.0)
	g2.set_physics_process(true)
	await _wait(0.3)
	_player.get("target_lock").toggle()
	await _wait(0.3)
	assert(_player.get("target_lock").has_target(), "%s: toggle fija un objetivo" % label)
	var tgt: Node3D = _player.get("target_lock").target
	shot = await _shoot()
	assert(not shot.is_empty(), "%s: sale el proyectil (toggle)" % label)
	want = (tgt.global_position + Vector3(0, 1.0, 0) - shot[0]).normalized()
	err = _flat_angle(shot[1], want)
	print("  %s toggle: error %.1f°" % [label, err])
	assert(absf(err) < MAX_ERR_DEG, "%s va al objetivo fijado con C (error %.1f°)" % [label, err])
	print("CHECK PASSED: %s dispara al objetivo fijado con C" % label)

## 5) La mira choca con algo pegado al jugador (caja, prop, pared al lado): antes el disparo salía en horizontal
## hacia ese punto, es decir, hacia donde mira el cuerpo. Debe seguir la dirección de la cámara.
func _check_near_hit() -> void:
	await _equip(WeaponData.WeaponType.SPORE_BAZOOKA)
	await _clear()
	await _turn_camera(60.0)
	var cam: Camera3D = _player.get_viewport().get_camera_3d()
	var cam_dir := cam.project_ray_normal(_player.get_viewport().get_visible_rect().size * 0.5)
	var cf := Vector3(cam_dir.x, 0, cam_dir.z).normalized()
	# Punto de la mira a 1 m del jugador, a un lado (lo que daría el rayo al chocar con una caja junto a él)
	var near_pt: Vector3 = _player.global_position + Vector3(-cf.z, 0, cf.x) * 1.0 + Vector3(0, 1.0, 0)
	var aim = _player.camera_aim_controller
	var plant := func():
		aim._aim_frame = Engine.get_physics_frames() * 100000 + Engine.get_process_frames()
		aim._aim_cache = {"point": near_pt, "enemy": null, "locked": false}
	# Bazuca: el proyectil sale en el mismo fotograma del ataque
	var before := _projectiles()
	_player.resources.energy = PlayerResources.ENERGY_MAX
	_player.combat_controller.attack_cooldown = 0.0
	plant.call()
	_player.combat_controller.attack()
	var spore = null
	for p in _projectiles():
		if not p in before:
			spore = p
	assert(spore != null, "bazuca: sale el proyectil (mira cerca)")
	var err := _flat_angle(spore.direction, cf)
	print("  bazuca mira pegada: error %.1f°" % err)
	assert(absf(err) < 10.0, "bazuca con la mira pegada al jugador va hacia la cámara (error %.1f°)" % err)
	# Arco: dirección de la flecha con la misma mira
	await _equip(WeaponData.WeaponType.BOW)
	var bow = _player.combat_controller._strategies[WeaponData.WeaponType.BOW]
	plant.call()
	var d: Vector3 = bow._aim_dir(bow._origin())
	err = _flat_angle(d, cf)
	print("  arco mira pegada: error %.1f°" % err)
	assert(absf(err) < 10.0, "arco con la mira pegada al jugador va hacia la cámara (error %.1f°)" % err)
	print("CHECK PASSED: con la mira pegada al jugador se dispara hacia la cámara")

class FixedMove extends MovementSource:
	var v := Vector2(0, -1)
	func get_movement_vector() -> Vector2:
		return v

func _ready() -> void:
	print("--- TEST: APUNTADO DEL ARCO Y LA BAZUCA ---")
	await _boot()
	await _check("arco", WeaponData.WeaponType.BOW)
	await _check("bazuca", WeaponData.WeaponType.SPORE_BAZOOKA)
	await _check_near_hit()
	print("ALL RANGED AIM CHECKS PASSED")
	get_tree().quit(0)
