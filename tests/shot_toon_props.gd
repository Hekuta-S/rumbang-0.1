extends Node3D

## Hoja de contacto de los props cartoon de supervivencia (necesita ventana):
##   res://tests/shot_toon_props.tscn -- <archivo.png> [tipo1,tipo2...]
## Carga cada tipo con ProceduralMap._load_kind (mismo material y malla que en la partida) y los pone en fila
## sobre un suelo gris con una luz parecida a la del mapa.

const KINDS := ["rock_a", "rock_b", "tree_a", "tree_b", "grave_a", "grave_b", "pillar", "wall", "altar",
	"brazier", "bones", "fence", "mushroom"]

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://toon_props.png"
	var kinds: Array = Array(args[1].split(",")) if args.size() > 1 else KINDS
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.32, 0.36, 0.45)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.24, 0.26, 0.38)
	env.ambient_light_energy = 1.9
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.9
	sun.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200.0, 200.0)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.2, 0.22, 0.2)
	floor_mi.material_override = fm
	add_child(floor_mi)
	var map := ProceduralMap.new()
	var x := 0.0
	var tris := 0
	for kind in kinds:
		var mesh: Mesh = map._load_kind(kind)
		if mesh == null:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		var aabb := mesh.get_aabb()
		var xf: Transform3D = map._mesh_xf[kind]
		x += aabb.size.x * 0.5 + 0.6
		mi.transform = Transform3D(Basis(Vector3.UP, 0.6), Vector3(x, 0.0, 0.0)) * xf
		x += aabb.size.x * 0.5 + 0.6
		add_child(mi)
		var n: int = (mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		tris += n
		print("%s: %d tris" % [kind, n])
	print("total tris: ", tris)
	var cam := Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	var dist := x * 0.5 / tan(deg_to_rad(20.0)) / (16.0 / 9.0) * 1.05 + 3.0
	cam.look_at_from_position(Vector3(x * 0.5, dist * 0.35 + 1.5, dist), Vector3(x * 0.5, 1.6, 0.0))
	cam.current = true
	await get_tree().create_timer(1.0).timeout
	get_viewport().get_texture().get_image().save_png(out)
	print("captura guardada: ", ProjectSettings.globalize_path(out))
	map.free()
	get_tree().quit(0)
