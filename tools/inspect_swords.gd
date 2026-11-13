extends SceneTree
func _initialize() -> void:
	for f in ["great_sword","dragonslayer","great_wave_katana","obsidian"]:
		var sc := load("res://assets/models/weapons/espadones/%s.glb" % f) as PackedScene
		var inst := sc.instantiate() as Node3D
		root.add_child(inst)
		var tot := AABB()
		var first := true
		var meshes := inst.find_children("*", "MeshInstance3D", true, false)
		var tris := 0
		for m in meshes:
			var mi := m as MeshInstance3D
			var bb := mi.global_transform * mi.get_aabb()
			tot = bb if first else tot.merge(bb)
			first = false
			for s in mi.mesh.get_surface_count():
				var arr := mi.mesh.surface_get_arrays(s)
				tris += (arr[Mesh.ARRAY_INDEX].size() / 3) if arr[Mesh.ARRAY_INDEX] != null else 0
		print("SWORD ", f, " meshes=", meshes.size(), " tris=", tris, " aabb pos=", tot.position, " size=", tot.size, " anims=", inst.find_children("*", "AnimationPlayer", true, false).size())
		# width profile along the longest axis
		var ax := 0
		if tot.size.y > tot.size[ax]: ax = 1
		if tot.size.z > tot.size[ax]: ax = 2
		var prof := []
		var bins := 10
		var widths := []
		for i in bins: widths.append(0.0)
		for m in meshes:
			var mi := m as MeshInstance3D
			for s in mi.mesh.get_surface_count():
				var arr := mi.mesh.surface_get_arrays(s)
				var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var step := maxi(vs.size() / 4000, 1)
				for vi in range(0, vs.size(), step):
					var w: Vector3 = mi.global_transform * vs[vi]
					var t := clampf((w[ax] - tot.position[ax]) / maxf(tot.size[ax], 0.0001), 0.0, 0.9999)
					var b := int(t * bins)
					var o1 := (ax + 1) % 3
					var o2 := (ax + 2) % 3
					widths[b] = maxf(widths[b], maxf(absf(w[o1]), absf(w[o2])))
		print("  longest axis=", ax, " widthprofile(bins from min to max)=", widths)
		inst.queue_free()
	quit()
