extends Node

## Paso lateral de Riva: clip solo de piernas, capa "legs" en el AnimationTree y peso según el movimiento
## lateral respecto a donde mira el cuerpo (derecha = el mismo clip al revés).

func _ready() -> void:
	print("--- TEST: PASO LATERAL ---")
	GameData.game_mode = "dungeon"
	var scene: Node = load("res://scenes/core/main_dungeon.tscn").instantiate()
	get_tree().root.add_child.call_deferred(scene)
	var player: Node = null
	var ac: PlayerAnimationController = null
	for i in 600:
		await get_tree().process_frame
		player = scene.get_node_or_null("Player")
		if player and player.get_node_or_null("PlayerAnimationController") and player.get_node("PlayerAnimationController").model:
			ac = player.get_node("PlayerAnimationController")
			break
	assert(ac != null and ac._has_strafe, "El controlador tiene la capa de paso lateral")
	var anim: Animation = ac.anim_player.get_animation(PlayerAnimationController.STRAFE_ANIM)
	assert(anim.get_track_count() > 0, "El clip tiene pistas")
	for i in anim.get_track_count():
		var bone := String(anim.track_get_path(i).get_concatenated_subnames()).trim_prefix("mixamorig_")
		assert(bone in PlayerAnimationController.LEG_BONES, "Solo piernas (%s)" % bone)
	print("CHECK 1 PASSED: clip de %d pistas, solo piernas" % anim.get_track_count())
	# El cuerpo mira hacia -Z: moverse a +X es ir a la derecha
	player.mesh.rotation.y = 0.0
	ac._update_strafe(1.0, Vector3(3, 0, 0), true)
	assert(ac._strafe_w > 0.9 and ac._strafe_side > 0.9, "Derecha: peso alto, clip al revés (%f %f)" % [ac._strafe_w, ac._strafe_side])
	ac._update_strafe(1.0, Vector3(-3, 0, 0), true)
	assert(ac._strafe_w > 0.9 and ac._strafe_side < 0.1, "Izquierda: clip normal")
	ac._update_strafe(1.0, Vector3(0, 0, -3), true)
	assert(ac._strafe_w < 0.1, "De frente: sin paso lateral")
	print("CHECK 2 PASSED: peso y lado del paso lateral")
	# La carrera solo va hacia delante: de lado y atrás se anda
	player.mesh.rotation.y = 0.0
	ac._fwd_run = true
	assert(ac._moving_forward(Vector3(0, 0, -5)), "De frente se puede correr")
	assert(not ac._moving_forward(Vector3(5, 0, 0)), "De lado no se corre")
	assert(not ac._moving_forward(Vector3(0, 0, 5)), "Hacia atrás no se corre")
	var mc = player.movement_controller
	assert(mc.SIDE_SPEED_DUNGEON < 0.6 and mc.BACK_SPEED_DUNGEON < 0.6, "En mazmorra de lado/atrás se va a paso de andar")
	mc.gs_calm = 5.0
	mc._gs_mult = 1.1
	mc._update_gs_gait(0.016, true, false)
	assert(not mc.gs_running(), "De lado la espada/espadón deja de correr")
	print("CHECK 3 PASSED: carrera solo hacia delante")
	# Corriendo en diagonal (joystick a 45°) el cuerpo se gira hacia donde corre; andando de lado, no
	var fwd: Vector3 = -player.spring_arm.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var aim_yaw := atan2(-fwd.x, -fwd.z)
	VirtualInput.movement_vector = Vector2(0.7071, -0.7071)
	for i in 150:      # 2,5 s: el espadón/espada/arco tardan en pasar a correr
		mc.face_lock_until = 0.0
		mc.handle_movement(1.0 / 60.0)
	var right: Vector3 = player.spring_arm.global_transform.basis.x
	right.y = 0.0
	var wish := (fwd + right.normalized()).normalized()
	var body := -(player.mesh as Node3D).global_transform.basis.z
	body.y = 0.0
	assert(mc._runs_now(PlayerAnimationController.WALK_TO_RUN + 1.0), "En diagonal va corriendo")
	assert(body.normalized().dot(wish) > 0.97, "Corriendo en diagonal el cuerpo mira hacia donde corre (%.2f)" % body.normalized().dot(wish))
	VirtualInput.movement_vector = Vector2(1.0, 0.0)
	for i in 40:
		mc.face_lock_until = 0.0
		mc.handle_movement(1.0 / 60.0)
	assert(absf(angle_difference(player.mesh.rotation.y, aim_yaw)) < 0.1, "De lado sigue mirando a la mira")
	VirtualInput.movement_vector = Vector2.ZERO
	print("CHECK 4 PASSED: carrera en diagonal mira hacia donde corre")
	print("ALL STRAFE CHECKS PASSED")
	get_tree().quit(0)
