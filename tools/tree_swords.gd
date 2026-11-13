extends SceneTree

func _initialize() -> void:
	for f in ["great_sword", "dragonslayer", "great_wave_katana", "obsidian"]:
		var inst := (load("res://assets/models/weapons/espadones/%s.glb" % f) as PackedScene).instantiate() as Node3D
		root.add_child(inst)
		print("TREE ", f)
		_dump(inst, 1)
		inst.queue_free()
	quit()

func _dump(n: Node, d: int) -> void:
	var extra := ""
	if n is Node3D:
		extra = " pos=%s scale=%s" % [(n as Node3D).position, (n as Node3D).scale]
	if n is MeshInstance3D:
		var m := n as MeshInstance3D
		extra += " skin=%s skel=%s mats=%d vis_end=%s" % [m.skin != null, m.skeleton, m.mesh.get_surface_count(), m.visibility_range_end]
		for i in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(i)
			extra += " [%s %s]" % [mat.get_class() if mat else "null", (mat as BaseMaterial3D).transparency if mat is BaseMaterial3D else ""]
	print("TREE ", "  ".repeat(d), n.name, " (", n.get_class(), ")", extra)
	for c in n.get_children():
		_dump(c, d + 1)
