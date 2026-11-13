extends Node

## Capturas de props rompibles de cerca (necesita ventana, no headless):
##   res://tests/shot_props.tscn -- <prefijo> [tipo1,tipo2...] [break]
## Pone los tipos pedidos (por defecto choza y tótem) en fila en la sala inicial, con la luz real de la
## mazmorra, y guarda <prefijo>_<tipo>_a.png (vista de juego) y _b.png (de cerca, otro lado).
## Con "break" además rompe cada uno y guarda _break1/_break2/_break3 (al romper, 0.5 s y 2 s después).

var _prefix := "user://props"
var _main: Node

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_prefix = args[0]
	GameData.game_mode = "dungeon"
	_main = (load(Net.game_scene()) as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(_main)
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var kinds: PackedStringArray = (args[1] if args.size() > 1 else "hut,totem").split(",")
	var do_break := args.size() > 2 and args[2] == "break"
	await get_tree().process_frame
	get_tree().current_scene = _main
	await get_tree().create_timer(3.0).timeout
	var map: DungeonMap = _main.get_node("ProceduralMap")
	var player: Node3D = _main.get_node("Player")
	var enc = _main.get_node_or_null("DungeonEncounter")
	if enc:
		enc.process_mode = Node.PROCESS_MODE_DISABLED
	for e in get_tree().get_nodes_in_group("enemies"):
		(e as Node).queue_free()
	var c := map.room_center(0)
	# Fuera de la vista de la cámara del jugador (y su luz) para no tapar
	player.global_position = c + Vector3(0.0, 0.3, 30.0)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	for d in map.destructibles:
		if is_instance_valid(d) and d.global_position.distance_to(c) < 9.0:
			d.queue_free()
	var cam := Camera3D.new()
	cam.fov = 55.0
	_main.add_child(cam)
	cam.current = true
	var props: Array[DestructibleProp] = []
	for i in kinds.size():
		var kind := kinds[i]
		var mesh := map._load_kind(kind)
		var d := DestructibleProp.new()
		var pos := c + Vector3((float(i) - float(kinds.size() - 1) * 0.5) * 8.0, 0.0, 0.0)
		DestructibleProp.prewarm(kind, String(map._prop_def(kind)["file"]), mesh, map._mesh_xf[kind])
		d.setup(kind, mesh, map._mesh_xf[kind], map._prop_def(kind), Transform3D(Basis(), pos), DestructibleProp.hp_for(kind))
		map.add_child(d)
		props.append(d)
	var light := OmniLight3D.new()            # la luz que lleva el jugador, para ver como en partida
	light.omni_range = 14.0
	light.light_energy = 1.2
	light.light_color = Color(1.0, 0.85, 0.65)
	_main.add_child(light)
	await get_tree().create_timer(0.5).timeout
	for d in props:
		var p := d.global_position
		light.global_position = p + Vector3(1.5, 2.5, 4.0)
		cam.global_position = p + Vector3(0.0, 5.5, 7.5)
		cam.look_at(p + Vector3(0, 1.4, 0))
		await _save(d.kind + "_a")
		cam.global_position = p + Vector3(-3.6, 2.4, 3.4)
		cam.look_at(p + Vector3(0, 1.5, 0))
		await _save(d.kind + "_b")
	if do_break:
		for d in props:
			var p := d.global_position
			light.global_position = p + Vector3(1.5, 2.5, 4.0)
			cam.global_position = p + Vector3(0.0, 4.5, 8.5)
			cam.look_at(p + Vector3(0, 1.0, 0))
			await get_tree().create_timer(0.2).timeout
			var kind := d.kind
			d.take_damage(10000.0, Vector3(1.0, 0.0, -0.3))
			await _save(kind + "_break1")
			await get_tree().create_timer(0.5).timeout
			await _save(kind + "_break2")
			await get_tree().create_timer(1.5).timeout
			await _save(kind + "_break3")
	get_tree().quit(0)

func _save(tag: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s_%s.png" % [_prefix, tag]
	img.save_png(path)
	print("captura guardada: ", ProjectSettings.globalize_path(path))
