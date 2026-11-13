extends Node

## Cambios de escena con pantalla de carga, y la "tapa" que queda por encima mientras la escena nueva se
## monta. Instanciar una escena y generar su mundo congela uno o varios frames: la tapa (idéntica a la
## pantalla de carga) sobrevive al cambio y se funde cuando la escena ya está lista, así que el jugador
## no ve ni el frame congelado ni la escena a medio construir.

const LOADING := "res://scenes/ui/loading_screen.tscn"
const COVER_TIMEOUT_MS := 20000   ## pase lo que pase, la tapa no se queda puesta para siempre

var next_scene_path: String = ""

var _cover: CanvasLayer
var _claimed := false

func load_scene(path: String) -> void:
	next_scene_path = path
	get_tree().paused = false
	get_tree().change_scene_to_file(LOADING)

func has_cover() -> bool:
	return is_instance_valid(_cover)

## Pone la tapa. Si nadie la reclama (claim_cover), se quita sola unos frames después de cambiar de escena.
func hold_cover(step: String = "Generando mundo...", title: String = "", tip: String = "") -> void:
	if has_cover():
		return
	_claimed = false
	_cover = CanvasLayer.new()
	_cover.layer = 120
	_cover.process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cover.add_child(root)
	add_child(_cover)
	LoadingVisual.build(root, title if title != "" else LoadingVisual.title_for(next_scene_path), tip, step, 100.0)
	_watch(_cover)

## La escena nueva se hace cargo de la tapa: la quitará ella con release_cover() cuando su mundo esté listo.
func claim_cover() -> void:
	_claimed = true

func release_cover(fade: float = 0.45) -> void:
	if not has_cover():
		return
	var c := _cover
	_cover = null
	_claimed = false
	var root := c.get_child(0) as Control
	for n in root.get_children():
		if n is Control:
			(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := c.create_tween()
	tw.tween_property(root, "modulate:a", 0.0, fade)
	tw.tween_callback(c.queue_free)

func _watch(c: CanvasLayer) -> void:
	var tree := get_tree()
	var from_id := tree.current_scene.get_instance_id() if tree.current_scene else 0
	var t0 := Time.get_ticks_msec()
	# Sin reclamar: espera a que entre la escena nueva
	while _cover == c and not _claimed and Time.get_ticks_msec() - t0 < COVER_TIMEOUT_MS:
		var cur := tree.current_scene
		if cur != null and cur.get_instance_id() != from_id:
			break
		await tree.process_frame
	if _cover == c and not _claimed:
		# Unos frames para que la escena nueva se dibuje (y compile sus sombreadores) bajo la tapa
		for i in 4:
			await tree.process_frame
	while _cover == c and _claimed and Time.get_ticks_msec() - t0 < COVER_TIMEOUT_MS:
		await tree.process_frame
	if _cover == c:
		release_cover()
