extends Node

## Vista previa de los modelos de espadón (necesita ventana): res://tests/shot_swords.tscn -- <carpeta>
## Cada espada se normaliza a 2 m en su eje largo; un cubo rojo marca el extremo +eje y uno azul el origen del modelo.
const FILES := ["great_sword", "dragonslayer", "great_wave_katana", "obsidian"]
const FLIP := []

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var dir := args[0] if args.size() > 0 else "user://swords"
	DirAccess.make_dir_recursive_absolute(dir)
	var vp := get_viewport()
	vp.size = Vector2i(1600, 700)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.25, 0.27, 0.3)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.8, 0.8)
	add_child(env)
	var dl := DirectionalLight3D.new()
	dl.rotation_degrees = Vector3(-40, 30, 0)
	add_child(dl)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 3.2
	add_child(cam)
	cam.current = true
	for i in FILES.size():
		var m := (load("res://assets/models/weapons/espadones/%s.glb" % FILES[i]) as PackedScene).instantiate() as Node3D
		var holder := Node3D.new()
		holder.position = Vector3(i * 2.4 - 3.6, 0, 0)
		add_child(holder)
		holder.add_child(m)
		var aabb := _aabb(holder)
		var ax := 0
		for k in 3:
			if aabb.size[k] > aabb.size[ax]:
				ax = k
		if ax == 0:
			m.rotation_degrees.z = 90.0
		elif ax == 2:
			m.rotation_degrees.x = -90.0
		if FLIP.has(FILES[i]):
			holder.rotation_degrees.z = 180.0
		aabb = _aabb(holder)
		var s := 2.0 / aabb.size[1]
		m.scale = Vector3.ONE * s
		aabb = _aabb(holder)
		m.position = -aabb.get_center()
		_cube(holder, Vector3.ZERO, Color(0.2, 0.4, 1))
		print("SWORD ", FILES[i], " long axis=", ax, " scale=", s, " aabb=", aabb, " rot=", m.rotation_degrees)
	cam.position = Vector3(0, 0, 8)
	cam.look_at(Vector3.ZERO, Vector3.UP)
	for view in ["xy", "zy"]:
		if view == "zy":
			for h in get_children():
				if h is Node3D and h.get_child_count() > 0 and not (h is Camera3D) and not (h is DirectionalLight3D):
					h.rotation.y = PI / 2
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().create_timer(0.3).timeout
		vp.get_texture().get_image().save_png(ProjectSettings.globalize_path(dir).path_join("swords_%s.png" % view))
	get_tree().quit()

func _cube(parent: Node3D, pos: Vector3, c: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * 0.08
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)

func _aabb(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (n.global_transform.affine_inverse() * (mi as MeshInstance3D).global_transform) * (mi as MeshInstance3D).get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out
