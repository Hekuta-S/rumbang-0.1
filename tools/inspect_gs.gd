extends SceneTree

## Dirección de la hoja en ejes de la mano derecha tal que el tajo vertical (gs1) quede en el plano del personaje.
func _initialize() -> void:
	_run()

func _run() -> void:
	var sc := load("res://assets/models/greatsword/gs_slash.fbx") as PackedScene
	var inst := sc.instantiate()
	root.add_child(inst)
	var ap := inst.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var sk := inst.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var an := ap.get_animation_list()[0]
	var rh := sk.find_bone("mixamorig_RightHand")
	var lh := sk.find_bone("mixamorig_LeftHand")
	ap.play(an)
	ap.pause()
	var m := Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	var rows := []
	var hand_dirs := []
	for f in range(10, 34):
		ap.seek(float(f) / 30.0, true)
		await process_frame
		await process_frame
		var pose := sk.get_bone_global_pose(rh)
		var b := pose.basis.orthonormalized()
		var rx: Vector3 = b.inverse() * Vector3(1, 0, 0)    # eje lateral del personaje en ejes de la mano
		rows.append(rx)
		var d := b.inverse() * (sk.get_bone_global_pose(lh).origin - pose.origin).normalized()
		hand_dirs.append(d)
	# matriz de covarianza sum r r^T
	var c := [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
	for r in rows:
		for i in 3:
			for j in 3:
				c[i][j] += r[i] * r[j]
	# autovector de menor autovalor por iteración inversa (potencia sobre (traza*I - C))
	var tr: float = c[0][0] + c[1][1] + c[2][2]
	var v := Vector3(0.6, 0.0, -0.8)
	for it in 200:
		var nv := Vector3(
			(tr - c[0][0]) * v.x - c[0][1] * v.y - c[0][2] * v.z,
			-c[1][0] * v.x + (tr - c[1][1]) * v.y - c[1][2] * v.z,
			-c[2][0] * v.x - c[2][1] * v.y + (tr - c[2][2]) * v.z)
		v = nv.normalized()
	var err := 0.0
	for r in rows:
		err += pow(r.dot(v), 2)
	var mean_hand := Vector3.ZERO
	for d in hand_dirs:
		mean_hand += d
	mean_hand = mean_hand.normalized()
	print("FITDIR lateral-free dir (hand axes) = ", v, " rms lateral=", sqrt(err / rows.size()), "   mean LH dir=", mean_hand, "   angle between =", rad_to_deg(v.angle_to(-mean_hand)), " / ", rad_to_deg(v.angle_to(mean_hand)))
	quit()
