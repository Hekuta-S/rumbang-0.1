extends Node

## Prueba del editor de ropa (headless): carga de prendas, gizmo (mover / rotar / escalar), deshacer, pose T y brazos,
## y ida y vuelta del JSON.
##   godot --headless --path . res://tests/test_clothing_editor.tscn

var _fails := 0

func _check(ok: bool, what: String) -> void:
	if ok:
		print("CHECK ok: ", what)
	else:
		_fails += 1
		printerr("CHECK FAILED: ", what)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var ids := ClothingFit.garment_ids()
	_check(ids.size() >= 4, "hay al menos 4 prendas (%s)" % str(ids))
	var ed := (load("res://tools/clothing_editor.tscn") as PackedScene).instantiate()
	add_child(ed)
	await get_tree().create_timer(1.0).timeout
	ed.set_view(0.0, 8.0, 3.0, Vector3(0, 1.1, 0))
	await get_tree().process_frame
	await get_tree().process_frame

	ed.select_garment("camiseta")
	var it = ed._selected()
	_check(it != null and it.shown, "camiseta seleccionada y visible")
	_check(ed._ms > 1.0, "escala del modelo calculada (%.1f)" % ed._ms)

	# — Mover en X con la flecha roja —
	ed.set_mode(ed.MODE_MOVE)
	await get_tree().process_frame
	var pos0: Vector3 = it.pos
	var o: Vector3 = it.root.global_position
	var gs: float = ed._gizmo_size()
	var axes: Array = ed._axes()
	var p: Vector2 = ed._screen(o + axes[0] * gs * 0.7)
	_check(ed._pick_handle(p) == 0, "el ratón sobre la flecha X la elige")
	ed._begin_drag(0, p)
	ed._update_drag(p + Vector2(60, 0))
	ed._end_drag()
	var moved: Vector3 = it.pos - pos0
	_check(moved.x > 0.05 and absf(moved.y) < 0.001 and absf(moved.z) < 0.001, "arrastrar la flecha X mueve solo en X (%s)" % str(moved))

	# — Deshacer / rehacer —
	ed._do_undo()
	_check(it.pos.distance_to(pos0) < 0.0001, "deshacer devuelve la posición")
	ed._do_redo()
	_check(it.pos.distance_to(pos0) > 0.05, "rehacer repite el movimiento")
	ed._do_undo()

	# — Rotar con el anillo verde (alrededor de Y) —
	ed.set_mode(ed.MODE_ROTATE)
	await get_tree().process_frame
	var basis0: Basis = it.root.global_transform.basis.orthonormalized()
	o = it.root.global_position
	gs = ed._gizmo_size()
	axes = ed._axes()
	var start_dir: Vector3 = (axes[2] + axes[0] * 0.3).normalized()   # evita el cruce con el anillo X
	var a0: Vector2 = ed._screen(o + start_dir * gs)
	_check(ed._pick_handle(a0) == 1, "el ratón sobre el anillo Y lo elige")
	ed._begin_drag(1, a0)
	var dir30: Vector3 = Basis(axes[1], deg_to_rad(30.0)) * start_dir
	ed._update_drag(ed._screen(o + dir30 * gs))
	ed._end_drag()
	var delta: Quaternion = (it.root.global_transform.basis.orthonormalized() * basis0.inverse()).get_rotation_quaternion()
	_check(absf(rad_to_deg(delta.get_angle()) - 30.0) < 1.5, "arrastrar el anillo gira ~30° (%.1f°)" % rad_to_deg(delta.get_angle()))
	_check(absf(delta.get_axis().dot(Vector3.UP)) > 0.99, "el giro es alrededor de Y")
	ed._do_undo()

	# — Escalar en un eje —
	ed.set_mode(ed.MODE_SCALE)
	await get_tree().process_frame
	var scl0: Vector3 = it.scl
	o = it.root.global_position
	gs = ed._gizmo_size()
	axes = ed._axes()
	var tip: Vector2 = ed._screen(o + axes[0] * gs)
	_check(ed._pick_handle(tip) == 0, "el ratón sobre el cubo X lo elige")
	ed._begin_drag(0, tip)
	ed._update_drag(ed._screen(o + axes[0] * gs * 1.5))
	ed._end_drag()
	var changed := 0
	for i in 3:
		if absf(it.scl[i] - scl0[i]) > 0.001:
			changed += 1
	var rat: Vector3 = it.scl / scl0
	_check(changed == 1 and rat[rat.max_axis_index()] > 1.3,
		"arrastrar el cubo escala un solo eje (%s → %s)" % [str(scl0), str(it.scl)])
	ed._do_undo()

	# — Escalado uniforme del centro —
	var s1: Vector3 = it.scl
	o = it.root.global_position
	var c: Vector2 = ed._screen(o)
	_check(ed._pick_handle(c) == 3, "el centro elige el escalado uniforme")
	ed._begin_drag(3, c + Vector2(40, 0))
	ed._update_drag(c + Vector2(80, 0))
	ed._end_drag()
	var uni: Vector3 = it.scl / s1
	_check(absf(uni.x - uni.y) < 0.001 and absf(uni.y - uni.z) < 0.001 and uni.x > 1.5, "el centro escala por igual (×%.2f)" % uni.x)
	ed._do_undo()

	# — Pose T y brazos —
	ed.set_arms(0.0, 0.0)
	var skel: Skeleton3D = ed._skel
	var arm := skel.get_bone_global_pose(skel.find_bone("mixamorig_LeftArm")).origin
	var hand := skel.get_bone_global_pose(skel.find_bone("mixamorig_LeftHand")).origin
	_check(absf(hand.y - arm.y) < absf(hand.x - arm.x) * 0.02, "pose T: la mano está a la altura del hombro (%s %s)" % [str(arm), str(hand)])
	ed.set_arms(60.0, 60.0)
	hand = skel.get_bone_global_pose(skel.find_bone("mixamorig_LeftHand")).origin
	arm = skel.get_bone_global_pose(skel.find_bone("mixamorig_LeftArm")).origin
	_check(hand.y > arm.y + absf(hand.x - arm.x) * 0.8, "brazos arriba: la mano sube")
	ed.set_arms(-60.0, -60.0)
	hand = skel.get_bone_global_pose(skel.find_bone("mixamorig_RightHand")).origin
	arm = skel.get_bone_global_pose(skel.find_bone("mixamorig_RightArm")).origin
	_check(hand.y < arm.y - absf(hand.x - arm.x) * 0.8, "brazos abajo (derecho): la mano baja")
	ed.set_arms(0.0, 0.0)

	# — Asas: arrastrar la mano y el codo —
	ed.set_arms(0.0, 0.0)
	await get_tree().process_frame
	await get_tree().process_frame
	var hand_pt: Vector3 = ed._arm_points("Left", 1)[0]
	var hp: Vector2 = ed._screen(hand_pt)
	_check(ed._pick_arm_handle(hp) == "Left_1", "el ratón sobre la mano elige su asa")
	ed._begin_arm_drag("Left_1")
	ed._update_arm_drag(hp + Vector2(-30, -120))
	ed._arm_drag = ""
	var new_hand: Vector3 = ed._arm_points("Left", 1)[0]
	_check(new_hand.y > hand_pt.y + 0.1, "arrastrar la mano hacia arriba sube el antebrazo (%.2f → %.2f)" % [hand_pt.y, new_hand.y])
	var elbow0: Vector3 = ed._arm_points("Left", 0)[0]
	var right_hand: Vector3 = ed._arm_points("Right", 1)[0]
	_check(absf(right_hand.y - new_hand.y) < 0.05, "con 'los dos brazos' el otro lado se refleja")
	var ep: Vector2 = ed._screen(elbow0)
	ed._begin_arm_drag("Left_0")
	ed._update_arm_drag(ep + Vector2(0, 150))
	ed._arm_drag = ""
	_check(ed._arm_points("Left", 0)[0].y < elbow0.y - 0.1, "arrastrar el codo hacia abajo baja el brazo")
	ed.set_arms(0.0, 0.0)

	# — Una prenda pegada a un brazo lo sigue —
	var bone_idx: int = ed._bone_names.find("mixamorig_LeftArm")
	ed._on_bone_selected(bone_idx)
	var before: Vector3 = it.root.global_position
	ed.set_arms(60.0, 60.0)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(it.root.global_position.distance_to(before) > 0.1, "una prenda en el brazo sube con él")
	ed.set_arms(0.0, 0.0)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(it.root.global_position.distance_to(before) < 0.01, "y vuelve a su sitio con la pose T")

	# — La pose, las prendas visibles y la selección sobreviven a cerrar y reabrir —
	var backup := FileAccess.get_file_as_string(ed.STATE_PATH)
	ed.set_arms(0.0, 0.0)
	ed._arm_sync.button_pressed = false
	ed._arm_dir["Left"] = [Vector3(0.3, 0.8, 0.5).normalized(), Vector3(0.1, 0.5, 0.9).normalized()]
	ed._apply_pose()
	ed.show_garment("camiseta_basica", true)
	ed.select_garment("camiseta")
	var left_hand: Vector3 = ed._arm_points("Left", 1)[0]
	ed._save_state()
	var ed2 := (load("res://tools/clothing_editor.tscn") as PackedScene).instantiate()
	add_child(ed2)
	await get_tree().create_timer(1.0).timeout
	_check(ed2._arm_points("Left", 1)[0].distance_to(left_hand) < 0.01, "la pose de los brazos se recupera al reabrir")
	_check(ed2._items.has("camiseta_basica") and ed2._items["camiseta_basica"].shown, "las prendas visibles se recuperan")
	_check(ed2._sel == "camiseta", "la prenda seleccionada se recupera")
	var f := FileAccess.open(ed.STATE_PATH, FileAccess.WRITE)
	f.store_string(backup)
	f.close()
	if backup == "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(ed.STATE_PATH))

	# — Cada prenda guarda su propia pose de brazos —
	ed.select_garment("camiseta")
	ed.set_arms(70.0, 70.0)
	ed.select_garment("camiseta_basica")
	ed.set_arms(-50.0, -50.0)
	var hand_basica: Vector3 = ed._arm_points("Left", 1)[0]
	ed.select_garment("camiseta")
	_check(ed._arm_points("Left", 1)[0].y > hand_basica.y + 0.3, "al elegir otra prenda vuelve SU pose de brazos")
	var json_arms: Dictionary = ed._items["camiseta"].arms
	var rt := ClothingFit.parse_entry(JSON.parse_string(JSON.stringify(ClothingFit.entry_to_json("mixamorig_Spine2", Vector3.ZERO, Basis.IDENTITY, Vector3.ONE, json_arms))))
	_check(not (rt["arms"] as Dictionary).is_empty() and absf(float(rt["arms"]["Left"]["angle"]) - 70.0) < 0.01, "la pose de brazos va en el JSON de la prenda")

	# — JSON —
	var json := ClothingFit.entry_to_json("mixamorig_Hips", Vector3(0.1, 0.9, 0.02), Basis.from_euler(Vector3(0.3, -0.4, 0.2)), Vector3(0.5, 0.6, 0.7))
	var back := ClothingFit.parse_entry(JSON.parse_string(JSON.stringify(json)))
	_check(back["bone"] == "mixamorig_Hips" and (back["pos"] as Vector3).is_equal_approx(Vector3(0.1, 0.9, 0.02)), "JSON: hueso y posición")
	_check((back["rot"] as Basis).get_euler().is_equal_approx(Vector3(0.3, -0.4, 0.2)) or ((back["rot"] as Basis).get_euler() - Vector3(0.3, -0.4, 0.2)).length() < 0.001, "JSON: rotación")

	if _fails == 0:
		print("CHECK test_clothing_editor PASSED")
	get_tree().quit(1 if _fails > 0 else 0)
