extends Node

## Captura de pantalla de la mazmorra (necesita ventana, no headless): res://tests/shot_dungeon.tscn -- <archivo.png> [sala]
## Coloca al jugador en la sala indicada (índice; por defecto la inicial) y guarda varias vistas.
## SHOT_WORLD=sewers (variable de entorno) captura otro mundo (ver WorldDefs).
## SHOT_CAM="ox,oy,oz,tx,ty,tz" usa una cámara libre (offsets desde el centro de la sala);
## SHOT_AMBIENT=<energía> pone luz ambiente blanca y quita la niebla; SHOT_PROP=<tipo> encuadra ese prop;
## SHOT_QUALITY=0|1|2 fuerza la calidad sin guardarla.

var _out := "user://shot.png"
var _main: Node

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	GameData.game_mode = "dungeon"
	# SHOT_QUALITY=0|1|2: calidad solo para esta captura (no se guarda en los ajustes)
	if OS.get_environment("SHOT_QUALITY") != "":
		Quality._level = OS.get_environment("SHOT_QUALITY").to_int()
	if WorldDefs.has(OS.get_environment("SHOT_WORLD")):
		GameData.world = OS.get_environment("SHOT_WORLD")
	_main = (load(Net.game_scene()) as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(_main)
	_run.call_deferred()

func _run() -> void:
	await get_tree().process_frame
	get_tree().current_scene = _main
	await get_tree().create_timer(4.0).timeout
	var enc = _main.get_node_or_null("DungeonEncounter")
	var map: DungeonMap = _main.get_node("ProceduralMap")
	var player = _main.get_node("Player")
	var want: String = args_room()
	var idx := 0
	for i in map.rooms.size():
		if want != "" and (str(map.rooms[i]["type"]) == want or str(map.rooms[i]["theme"]) == want or str(map.rooms[i]["shape"]) == want):
			idx = i
			break
	var c := map.room_center(idx)
	player.global_position = Vector3(c.x + 4.0, 0.3, c.z + 4.0)
	await get_tree().create_timer(2.5).timeout
	# SHOT_CAM="ox,oy,oz,tx,ty,tz": cámara libre (offsets desde el centro de la sala) mirando a un punto
	# SHOT_AMBIENT=<energía>: luz ambiente blanca fuerte y sin niebla (revisar geometría a oscuras)
	if OS.get_environment("SHOT_AMBIENT") != "":
		var we := _main.find_children("*", "WorldEnvironment", true, false)
		if not we.is_empty():
			var env: Environment = (we[0] as WorldEnvironment).environment
			env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			env.ambient_light_color = Color(1, 1, 1)
			env.ambient_light_energy = OS.get_environment("SHOT_AMBIENT").to_float()
			env.fog_enabled = false
	# SHOT_PROP=<tipo>: encuadra de cerca la instancia de ese prop más cercana a la sala (p. ej. torch_wall)
	if OS.get_environment("SHOT_DEBUG") == "1":
		for mmi in map.get_node("Props").get_children():
			var mesh: Mesh = (mmi as MultiMeshInstance3D).multimesh.mesh
			var mat = mesh.surface_get_material(0)
			print("DBG ", mmi.name, " surf=", mesh.get_surface_count(), " mat=", mat, " ovr=", (mmi as GeometryInstance3D).material_override, " shader=", mat.shader.resource_path if mat is ShaderMaterial else "-")
	var prop_env := OS.get_environment("SHOT_PROP")
	var prop_xfs: Array = map._instances.get(prop_env, []).duplicate()
	if map.has_node("PackProps"):           # piezas del pack como mallas sueltas (nombre = tipo)
		for mi in map.get_node("PackProps").get_children():
			if String(mi.name).begins_with(prop_env):
				prop_xfs.append((mi as Node3D).transform)
	if prop_env == "rock_art" and map.has_node("RockArt"):    # decals: el frente es su +Y
		for dcl in map.get_node("RockArt").get_children():
			var t: Transform3D = (dcl as Node3D).transform
			prop_xfs.append(Transform3D(Basis(t.basis.x, Vector3.UP, t.basis.y), t.origin + Vector3(0, -0.8, 0)))
	if prop_env != "" and not prop_xfs.is_empty():
		var best: Transform3D = prop_xfs[0]
		for t in prop_xfs:
			if (t as Transform3D).origin.distance_to(c) < best.origin.distance_to(c):
				best = t
		var front := best.basis.z.normalized()
		var cam2 := Camera3D.new()
		cam2.fov = 60.0
		_main.add_child(cam2)
		# objetivo: a media altura si el prop está en el suelo (brasero), a su altura si cuelga (antorcha)
		var target := best.origin + Vector3(0, 0.2 if best.origin.y > 0.5 else 1.0, 0)
		var dist := 2.2 if best.origin.y > 0.5 else 4.0
		cam2.look_at_from_position(target + front * dist + best.basis.x.normalized() * 1.0 + Vector3(0, 0.6, 0), target)
		cam2.current = true
		player.global_position = best.origin + front * 3.0 + Vector3(0, -best.origin.y + 0.3, 0)
		await get_tree().create_timer(0.6).timeout
	var cam_env := OS.get_environment("SHOT_CAM")
	if cam_env != "":
		var v := cam_env.split_floats(",")
		var cam := Camera3D.new()
		cam.fov = 70.0
		_main.add_child(cam)
		cam.look_at_from_position(c + Vector3(v[0], v[1], v[2]), c + Vector3(v[3], v[4], v[5]))
		cam.current = true
		await get_tree().create_timer(0.3).timeout
	if OS.get_environment("SHOT_PAUSE") == "1":
		var pm = _main.find_child("PauseMenu", true, false)
		pm.open_menu()
		await get_tree().create_timer(0.5).timeout
	# SHOT_FPS=1: mide los FPS medios durante 4 s antes de la captura (lanzar con --disable-vsync)
	if OS.get_environment("SHOT_FPS") == "1":
		var frames := 0
		var t0 := Time.get_ticks_usec()
		while Time.get_ticks_usec() - t0 < 4000000:
			await get_tree().process_frame
			frames += 1
		print("FPS medio: %.1f (%.2f ms)" % [frames / 4.0, 4000.0 / frames])
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out)
	print("captura guardada: ", ProjectSettings.globalize_path(_out), " sala=", map.rooms[idx]["theme"])
	get_tree().quit(0)

func args_room() -> String:
	var a := OS.get_cmdline_user_args()
	return a[1] if a.size() > 1 else ""
