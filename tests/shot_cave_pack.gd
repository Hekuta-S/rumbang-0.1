extends Node3D

## Hoja de contacto de las piezas del pack de cueva con su material (cave_rock + tinte):
## res://tests/shot_cave_pack.tscn -- <archivo.png>   (necesita ventana, no headless)

const KINDS := ["stalactite_a", "stalactite_b", "stalactite_c", "stalagmite_d", "cave_pillar", "cave_rock_01",
	"cave_rock_04", "cave_cliff_a", "cave_cliff_b", "cave_cliff_c", "cave_cliff_d"]

func _ready() -> void:
	var out := "user://shot_cave_pack.png"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.15, 0.15, 0.18)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.6, 0.65)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	# SHOT_OMNI=1: solo luces omni (como en la cueva) en vez de sol
	if OS.get_environment("SHOT_OMNI") == "1":
		env.ambient_light_color = Color(0.1, 0.1, 0.12)
		for i in 7:
			var l := OmniLight3D.new()
			l.position = Vector3(i * 6.0, 3.0, 4.0)
			l.omni_range = 9.0
			l.light_energy = 2.5
			add_child(l)
	else:
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-45, 30, 0)
		add_child(sun)
	var mat := DungeonMap.pack_rock_material()
	mat.set_shader_parameter("tint", Color(0.21, 0.18, 0.17))
	var x := 0.0
	for k in KINDS:
		var file: String = DungeonMap.CAVE_PROPS[k]["file"]
		var scene := load(DungeonMap.PROP_DIR + file + ".glb") as PackedScene
		var root := scene.instantiate() as Node3D
		add_child(root)
		root.position = Vector3(x, 5.0 if k.begins_with("stalactite") else 0.0, 0)
		if k == "stalagmite_d":
			root.scale = Vector3.ONE * 0.4
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_override = mat
		x += 3.2
	# Fila 2: MultiMesh de cave_rock_01 a varias escalas (como en el mapa)
	var rock_scene := load(DungeonMap.PROP_DIR + "cave_rock_01.glb") as PackedScene
	var rr := rock_scene.instantiate()
	var rmesh: Mesh = (rr.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh.duplicate()
	rr.free()
	rmesh.surface_set_material(0, mat)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = rmesh
	var scales := [0.4, 0.7, 1.0, 1.3, 1.6]
	mm.instance_count = scales.size()
	for i in scales.size():
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * scales[i]), Vector3(6.0 + i * 4.0, 0, 6.0)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)
	var cam := Camera3D.new()
	add_child(cam)
	cam.look_at_from_position(Vector3(x * 0.5, 4.0, 22.0), Vector3(x * 0.5, 1.8, 0))
	cam.current = true
	await get_tree().create_timer(1.0).timeout
	get_viewport().get_texture().get_image().save_png(out)
	print("captura guardada: ", ProjectSettings.globalize_path(out))
	get_tree().quit(0)
