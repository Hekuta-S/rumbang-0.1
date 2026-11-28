extends Node

## Capturas del mapa de Cloacas de Supervivencia (necesita ventana): res://tests/shot_sewers_map.tscn -- <prefijo>
## <prefijo>_alto.png (vista general), _calle.png (calle y canal), _centro.png (franja de en medio),
## _jugador.png (cámara del juego) y _portal.png (portal abierto, desde el Bosque).

var _prefix := "user://sewers_map"
var _main: Node

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_prefix = args[0]
	GameData.game_mode = "survival"
	GameData.survival_map = "sewers"
	_main = (load("res://scenes/core/main_procedural.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(_main)
	_run.call_deferred()

func _run() -> void:
	await get_tree().process_frame
	get_tree().current_scene = _main
	await get_tree().create_timer(4.0).timeout
	for n in get_tree().root.find_children("*", "", true, false):
		if n is WaveManager:
			n.process_mode = Node.PROCESS_MODE_DISABLED
	var map: ProceduralMap = _main.get_node("ProceduralMap")
	_save("_jugador")
	var d: SewerDistrict = map.districts[0]
	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.far = 500.0
	_main.add_child(cam)
	cam.current = true
	var hi := d.to_world(-30.0, -150.0)
	await _shot(cam, Vector3(hi.x, d.street_y + 90.0, hi.y), Vector3(0.0, d.street_y, 0.0), "_alto")
	var mu: Vector2 = d.local_range(d.canals[0])[0]
	var eye := d.to_world(mu.x - 6.0, -20.0)
	var look := d.to_world(mu.y + 10.0, 10.0)
	await _shot(cam, Vector3(eye.x, d.street_y + 4.0, eye.y), Vector3(look.x, d.street_y, look.y), "_calle")
	var bc := map.get_basin_center()
	await _shot(cam, Vector3(bc.x * 0.2, map.get_height_at(0, 0) + 8.0, bc.z * 0.2 - 6.0), bc, "_centro")
	# Portal (como si se abriera en la partida)
	cam.current = false
	var sw := _main.get_node_or_null("SurvivalMapSwitch") as SurvivalMapSwitch
	var p := _main.get_node("Player") as Node3D
	if sw:
		var portal := sw.open_portal()
		if portal:
			cam.current = true
			var pp := portal.global_position
			await _shot(cam, pp + Vector3(7.0, 4.0, 7.0), pp + Vector3(0, 1.5, 0), "_portal")
	GameData.survival_map = "forest"
	get_tree().quit(0)

func _shot(cam: Camera3D, eye: Vector3, at: Vector3, suffix: String) -> void:
	cam.global_position = eye
	cam.look_at(at, Vector3.UP)
	await get_tree().create_timer(0.6).timeout
	_save(suffix)

func _save(suffix: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_prefix + suffix + ".png")
	print("guardado ", _prefix + suffix + ".png")
