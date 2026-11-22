extends Node

## Sonda de llamadas de dibujo del HUD de supervivencia (necesita ventana: en headless no se dibuja).
## Oculta cada nodo visible del HUD de uno en uno y mide cuántas llamadas de dibujo quita.
##   RUMBANG_FORCE_MOBILE=1 godot --path . --resolution 1280x720 res://tests/probe_hud_draws.tscn
## DEPTH (2): hasta qué profundidad bajo HUD/Control se listan nodos.

const SETTLE := 6

var _main: Node

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.game_mode = "survival"
	SaveManager.save_path = "user://test_save.json"
	_main = load("res://scenes/core/main_procedural.tscn").instantiate()
	get_tree().root.add_child.call_deferred(_main)
	await get_tree().process_frame
	get_tree().current_scene = _main
	var p = null
	var waves: WaveManager = null
	for i in 900:
		await get_tree().process_frame
		p = _main.get_node_or_null("Player")
		waves = _main.find_child("WaveManager", true, false)
		if p and waves and waves._running:
			break
	waves.set_process(false)
	for e in EnemyRegistry.all().duplicate():
		if e is EnemyData:
			e.take_damage(1e9, Vector3.ZERO)
	p.health_comp.max_hp = 99999.0
	p.health_comp.hp = 99999.0
	await get_tree().create_timer(1.5).timeout
	var hud := _main.find_child("HUD", true, false) as CanvasLayer
	if hud == null:
		print("PROBE no HUD")
		get_tree().quit(1)
		return
	var shot := OS.get_environment("SHOT")
	if shot != "":
		await _draws()
		get_viewport().get_texture().get_image().save_png(shot)
		if OS.get_environment("SHOT_ONLY") == "1":
			get_tree().quit(0)
			return
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	var total := await _draws()
	var g_on := await _gpu_ms()
	hud.visible = false
	var without := await _draws()
	var g_off := await _gpu_ms()
	hud.visible = true
	print("PROBE total=%d sin_hud=%d hud=%d" % [total, without, total - without])
	print("PROBE gpu con_hud=%.3fms sin_hud=%.3fms hud=%.3fms" % [g_on, g_off, g_on - g_off])
	var strip := hud.get_node_or_null("Control/HubImage") as CanvasItem
	if strip:
		strip.visible = false
		var g_strip := await _gpu_ms()
		strip.visible = true
		print("PROBE gpu tira_armas=%.3fms" % (g_on - g_strip))
	var depth := int(OS.get_environment("DEPTH")) if OS.get_environment("DEPTH") != "" else 2
	var nodes: Array = []
	_collect(hud, 0, depth, nodes)
	var rows: Array = []
	for n in nodes:
		var ci := n as CanvasItem
		if not ci.is_visible_in_tree():
			continue
		var base := await _draws()
		ci.visible = false
		var off := await _draws()
		ci.visible = true
		rows.append([base - off, str(hud.get_path_to(ci)), ci.get_class()])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	for r in rows:
		if r[0] != 0:
			print("PROBE %3d  %s (%s)" % r)
	get_tree().quit(0)

func _collect(n: Node, d: int, max_d: int, out: Array) -> void:
	for c in n.get_children():
		if c is CanvasItem:
			out.append(c)
		if d < max_d:
			_collect(c, d + 1, max_d, out)

## GPU media de 120 frames (ms) del viewport principal.
func _gpu_ms() -> float:
	for i in SETTLE:
		await RenderingServer.frame_post_draw
	var acc := 0.0
	for i in 120:
		await RenderingServer.frame_post_draw
		acc += RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
	return acc / 120.0

func _draws() -> int:
	for i in SETTLE:
		await RenderingServer.frame_post_draw
	return int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
