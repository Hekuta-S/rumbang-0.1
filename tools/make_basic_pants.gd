extends SceneTree

## Genera assets/models/riva/ropa/pantalon_basico.glb: un pantalón sencillo (cintura + dos piernas) para empezar a
## colocar pantalones en tools/clothing_editor.tscn. Se sustituye por cualquier .glb propio.
## Uso: godot --headless --path . --script tools/make_basic_pants.gd

func _initialize() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Piernas: troncos de cono (m). Cadera a y=0.9, tobillo a y=0.05
	for sx in [-1.0, 1.0]:
		_tube(st, Vector3(sx * 0.095, 0.9, 0.0), Vector3(sx * 0.09, 0.05, 0.0), 0.135, 0.075, 20)
	_tube(st, Vector3(0, 0.9, 0.0), Vector3(0, 0.84, 0.0), 0.20, 0.20, 24)   # cintura
	st.generate_normals()
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.3, 0.55)
	mat.roughness = 0.9
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, mat)
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.name = "Pantalon"
	root.add_child(mi)
	mi.owner = root
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	doc.append_from_scene(root, state)
	var err := doc.write_to_filesystem(state, "res://assets/models/riva/ropa/pantalon_basico.glb")
	print("pantalon_basico.glb -> ", error_string(err))
	quit(0 if err == OK else 1)

func _tube(st: SurfaceTool, a: Vector3, b: Vector3, ra: float, rb: float, seg: int) -> void:
	for i in seg:
		var t0 := TAU * i / seg
		var t1 := TAU * (i + 1) / seg
		var p00 := a + Vector3(cos(t0), 0, sin(t0)) * ra
		var p01 := a + Vector3(cos(t1), 0, sin(t1)) * ra
		var p10 := b + Vector3(cos(t0), 0, sin(t0)) * rb
		var p11 := b + Vector3(cos(t1), 0, sin(t1)) * rb
		for v in [p00, p10, p01, p01, p10, p11]:
			st.add_vertex(v)
