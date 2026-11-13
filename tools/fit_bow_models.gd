extends SceneTree
## Mide cada arco de assets/models/weapons/arcos (en el espacio de la raíz del glb): caja, puntas de las palas y
## centro de la empuñadura (para la tabla de BowModels). Uso: Godot --headless -s res://tools/fit_bow_models.gd
func _initialize() -> void:
	for f in ["cool_bow", "fantasy_bow", "bow"]:
		var g := (load("res://assets/models/weapons/arcos/%s.glb" % f) as PackedScene).instantiate() as Node3D
		var root := Node3D.new()
		root.add_child(g)
		var pts: Array[Vector3] = []
		for mi in g.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			var xf := Transform3D.IDENTITY
			var n: Node = m
			while n != root:
				xf = (n as Node3D).transform * xf
				n = n.get_parent()
			for s in m.mesh.get_surface_count():
				var vs: PackedVector3Array = m.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
				for i in range(0, vs.size(), maxi(vs.size() / 6000, 1)):
					pts.append(xf * vs[i])
			print("  mesh ", m.name, " skin=", m.skin != null, " aabb=", xf * m.get_aabb())
		var aabb := AABB(pts[0], Vector3.ZERO)
		for p in pts:
			aabb = aabb.expand(p)
		print("FIT ", f, " aabb=", aabb)
		# perfil a lo largo del eje mayor: posición media en los otros dos ejes por décima
		var ax := 0
		for k in 3:
			if aabb.size[k] > aabb.size[ax]:
				ax = k
		var prof := []
		for k in 10:
			var acc := Vector3.ZERO; var cnt := 0
			for p in pts:
				var t := (p[ax] - aabb.position[ax]) / aabb.size[ax]
				if int(clampf(t, 0.0, 0.9999) * 10.0) == k:
					acc += p; cnt += 1
			prof.append((acc / maxf(cnt, 1)).snappedf(0.001))
		print("  axis=", ax, " mean per tenth=", prof)
		root.free()
	quit()
