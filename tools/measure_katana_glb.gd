extends Node
## Mide rengoku_katana.glb: nodos con malla y su AABB en el espacio de la raíz (para KatanaModels).
func _ready() -> void:
	var glb := (load("res://assets/models/katana/rengoku_katana.glb") as PackedScene).instantiate() as Node3D
	add_child(glb)
	var total := AABB()
	var first := true
	for m in glb.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var xf := glb.global_transform.affine_inverse() * mi.global_transform
		var bb := xf * mi.get_aabb()
		print("MESH ", glb.get_path_to(mi), " aabb=", bb)
		total = bb if first else total.merge(bb)
		first = false
	print("TOTAL ", total, " size=", total.size)
	# Perfil a lo largo del eje largo: ancho de la sección en 10 tramos (para hallar el mango)
	var ax := 0 if total.size.x >= total.size.y and total.size.x >= total.size.z else (1 if total.size.y >= total.size.z else 2)
	var bins := []
	for i in 20: bins.append([INF, -INF, INF, -INF])
	for m in glb.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var xf := glb.global_transform.affine_inverse() * mi.global_transform
		for s in mi.mesh.get_surface_count():
			var verts: PackedVector3Array = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			for v in verts:
				var p: Vector3 = xf * v
				var t := clampi(int((p[ax] - total.position[ax]) / total.size[ax] * 20.0), 0, 19)
				var o1 := (ax + 1) % 3
				var o2 := (ax + 2) % 3
				bins[t][0] = minf(bins[t][0], p[o1]); bins[t][1] = maxf(bins[t][1], p[o1])
				bins[t][2] = minf(bins[t][2], p[o2]); bins[t][3] = maxf(bins[t][3], p[o2])
	print("AXIS ", ax)
	for i in 20:
		print("BIN ", i, " w1=", snappedf(bins[i][1] - bins[i][0], 0.001), " w2=", snappedf(bins[i][3] - bins[i][2], 0.001), " c1=", snappedf((bins[i][1] + bins[i][0]) / 2, 0.001), " c2=", snappedf((bins[i][3] + bins[i][2]) / 2, 0.001))
	get_tree().quit()
