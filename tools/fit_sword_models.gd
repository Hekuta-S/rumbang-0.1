extends SceneTree
## Mide cada espada de finns_swords.glb (en el espacio de GLTF_SceneRootNode): eje pomo->punta, ancho y
## perfil de ancho (para la tabla de SwordModels). Uso: Godot --headless -s res://tools/fit_sword_models.gd
func _initialize() -> void:
	var g := (load("res://assets/models/weapons/espadas/finns_swords.glb") as PackedScene).instantiate() as Node3D
	var sroot := g.find_child("GLTF_SceneRootNode", true, false) as Node3D
	for sw in sroot.get_children():
		var pts: Array[Vector3] = []
		for mi in (sw as Node).find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			var xf := (sw as Node3D).transform * m.transform
			for s in m.mesh.get_surface_count():
				var vs: PackedVector3Array = m.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
				var step := maxi(vs.size() / 4000, 1)
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
		var len := a.distance_to(b)
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
		var prof := []
		for k in 10:
			var w := 0.0
			for p in pts:
				var t := (p - a).dot(axis) / len
				if int(clampf(t, 0.0, 0.9999) * 10.0) == k:
					w = maxf(w, absf((p - c).dot(wide)))
			prof.append(snappedf(w * 2.0 / len, 0.001))
		print("FIT ", sw.name, " len=", snappedf(len, 0.0001), " a=", a, " b=", b, " axis(a->b)=", axis, " wide=", wide, " prof(a->b)=", prof)
	g.free()
	quit()
