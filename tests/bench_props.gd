extends Node

## Coste de las estructuras rompibles (necesita ventana): res://tests/bench_props.tscn -- [carpeta_antiguos]
## Pone un campamento (3 chozas y 2 tótems) delante de la cámara en la sala inicial y mide, sin vsync,
## el tiempo de fotograma (CPU) y de GPU durante 4 s: modelos actuales, modelos de <carpeta_antiguos>
## (res://..., mismos nombres de archivo; opcional) y los actuales justo después de romperlos todos.

const KINDS := ["hut", "hut", "hut", "totem", "totem"]
const SPOTS := [Vector3(-5.5, 0, -2.0), Vector3(0.5, 0, -5.0), Vector3(6.0, 0, -1.5), Vector3(-2.0, 0, 3.0), Vector3(3.0, 0, 2.5)]

var _main: Node
var _map: DungeonMap

func _ready() -> void:
	GameData.game_mode = "dungeon"
	_main = (load(Net.game_scene()) as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(_main)
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	await get_tree().process_frame
	get_tree().current_scene = _main
	await get_tree().create_timer(3.0).timeout
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_map = _main.get_node("ProceduralMap")
	var enc = _main.get_node_or_null("DungeonEncounter")
	if enc:
		enc.process_mode = Node.PROCESS_MODE_DISABLED
	for e in get_tree().get_nodes_in_group("enemies"):
		(e as Node).queue_free()
	var c := _map.room_center(0)
	var player: Node3D = _main.get_node("Player")
	player.global_position = c + Vector3(0.0, 0.3, 40.0)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	for d in _map.destructibles:
		if is_instance_valid(d) and d.global_position.distance_to(c) < 12.0:
			d.queue_free()
	var cam := Camera3D.new()
	cam.fov = 60.0
	_main.add_child(cam)
	cam.current = true
	cam.global_position = c + Vector3(0.0, 9.0, 12.0)
	cam.look_at(c + Vector3(0, 0.5, 0))
	await _measure("vacio")
	var props := _spawn(c, "")
	await _measure("actuales")
	if args.size() > 0:
		for d in props:
			d.visible = false
		var old := _spawn(c, args[0])
		await _measure("antiguos")
		for d in old:
			d.queue_free()
		for d in props:
			d.visible = true
	for d in props:
		d.take_damage(100000.0, Vector3(1, 0, 0))
	await _measure("rotos")
	get_tree().quit(0)

func _spawn(c: Vector3, dir: String) -> Array:
	var out := []
	for i in KINDS.size():
		var kind: String = KINDS[i]
		var mesh: Mesh
		var xf := Transform3D.IDENTITY
		if dir == "":
			mesh = _map._load_kind(kind)
			xf = _map._mesh_xf[kind]
		else:
			var root := (load(dir + String(_map._prop_def(kind)["file"]) + ".glb") as PackedScene).instantiate()
			var mi := root.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
			mesh = ProceduralMap.flatten_with(mi.mesh, DungeonMap.detail_material(kind))
			root.free()
		var d := DestructibleProp.new()
		d.setup(kind, mesh, xf, _map._prop_def(kind), Transform3D(Basis().rotated(Vector3.UP, i * 1.3), c + SPOTS[i]), DestructibleProp.hp_for(kind))
		_map.add_child(d)
		out.append(d)
	return out

func _measure(tag: String) -> void:
	await get_tree().create_timer(1.0).timeout
	var frames := 0
	var gpu := 0.0
	var t0 := Time.get_ticks_usec()
	while Time.get_ticks_usec() - t0 < 4000000:
		await get_tree().process_frame
		frames += 1
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0 / frames
	print("BENCH %-9s %6.1f fps  %5.2f ms/fotograma  gpu %5.2f ms" % [tag, 1000.0 / ms, ms, gpu / frames])
