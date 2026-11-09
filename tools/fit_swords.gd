extends SceneTree
## Mide cada modelo de espadón: eje pommel->punta, ancho de hoja y largo (para la tabla de GreatswordModels).
func _initialize() -> void:
	_run()

func _run() -> void:
	for f in ["great_sword", "dragonslayer", "great_wave_katana", "obsidian"]:
		var inst := (load("res://assets/models/weapons/espadones/%s.glb" % f) as PackedScene).instantiate() as Node3D
		root.add_child(inst)
		await process_frame
		await process_frame
		var pts: Array[Vector3] = []
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			var xf := inst.global_transform.affine_inverse() * m.global_transform
			for s in m.mesh.get_surface_count():
				var vs: PackedVector3Array = m.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
				var step := maxi(vs.size() / 3000, 1)
				for i in range(0, vs.size(), step):
					pts.append(xf * vs[i])
		var c := Vector3.ZERO
		for p in pts:
			c += p
		c /= pts.size()
		var a := pts[0]
		for p in pts:
			if p.distance_to(c) > a.distance_to(c):
				a = p
		var b := a
		for p in pts:
			if p.distance_to(a) > b.distance_to(a):
				b = p
		var axis := (b - a).normalized()
		# radio medio de los extremos (el mango es fino, la hoja ancha)
		var len := a.distance_to(b)
		var ra := 0.0; var na := 0
		var rb := 0.0; var nb := 0
		for p in pts:
			var t := (p - a).dot(axis) / len
			var r := ((p - a) - axis * (p - a).dot(axis)).length()
			if t < 0.3:
				ra += r; na += 1
			elif t > 0.7:
				rb += r; nb += 1
		ra /= maxi(na, 1); rb /= maxi(nb, 1)
		var pommel := a if ra < rb else b
		var tip := b if ra < rb else a
		axis = (tip - pommel).normalized()
		# ancho de la hoja: dirección perpendicular con más extensión (PCA 2D simple por barrido de ángulos)
		var u := axis.cross(Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT).normalized()
		var v := axis.cross(u).normalized()
		var best_ang := 0.0
		var best_ext := 0.0
		for k in 36:
			var ang := PI * k / 36.0
			var d := u * cos(ang) + v * sin(ang)
			var mn := INF; var mx := -INF
			for p in pts:
				var e := (p - c).dot(d)
				mn = minf(mn, e); mx = maxf(mx, e)
			if mx - mn > best_ext:
				best_ext = mx - mn
				best_ang = ang
		var wide := (u * cos(best_ang) + v * sin(best_ang)).normalized()
		# perfil de ancho a lo largo del eje (10 tramos) para localizar la guarda
		var prof := []
		for k in 10:
			var w := 0.0
			for p in pts:
				var t := (p - pommel).dot(axis) / len
				if int(clampf(t, 0.0, 0.9999) * 10.0) == k:
					w = maxf(w, absf((p - c).dot(wide)))
			prof.append(snappedf(w * 2.0 / len, 0.001))
		print("FIT ", f, " len=", snappedf(len, 0.0001), " pommel=", pommel, " tip=", tip, " up=", axis, " wide=", wide, " widthprof(frac of len)=", prof)
		inst.queue_free()
	quit()
