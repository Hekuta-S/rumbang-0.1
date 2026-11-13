extends Node

## Pantalla de carga de la mazmorra: la barra avanza sin saltos, termina en 100 y cambia a la escena de juego.
## También mide los frames largos durante la carga (solo CPU).

var _last := 0
var _worst := 0.0
var _worst_at := ""
var _bar := 0.0
var _jumps := 0
var _loading: Control
var _t0 := 0

func _ready() -> void:
	print("--- TEST: PANTALLA DE CARGA DE MAZMORRA ---")
	GameData.game_mode = "dungeon"
	SceneLoader.next_scene_path = OS.get_environment("LS_TARGET") if OS.get_environment("LS_TARGET") != "" else "res://scenes/core/main_dungeon.tscn"
	_loading = (load("res://scenes/ui/loading_screen.tscn") as PackedScene).instantiate()
	_t0 = Time.get_ticks_msec()
	_start.call_deferred()

## La pantalla de carga pasa a ser la escena actual (como en el juego): al cambiar de escena se libera ella
## y este nodo, que sigue en la raíz, puede seguir midiendo.
func _start() -> void:
	get_tree().root.add_child(_loading)
	get_tree().current_scene = _loading

func _process(_d: float) -> void:
	var now := Time.get_ticks_usec()
	if _last != 0:
		var ms := (now - _last) / 1000.0
		if ms > _worst:
			_worst = ms
			var l := _loading.get_node_or_null("VBoxContainer/Label") as Label if is_instance_valid(_loading) else null
			_worst_at = l.text if l else "?"
	_last = now
	if is_instance_valid(_loading):
		var pb := _loading.get_node_or_null("VBoxContainer/ProgressBar") as ProgressBar
		if pb:
			if pb.value - _bar > 25.0:
				_jumps += 1
			_bar = pb.value
	elif get_tree().current_scene != null and get_tree().current_scene != _loading and not _done:
		_finish()

var _done := false

func _finish() -> void:
	_done = true
	var secs := (Time.get_ticks_msec() - _t0) / 1000.0
	print("carga completa en %.1f s; frame más largo %.0f ms (en '%s'); saltos de barra >25: %d" % [secs, _worst, _worst_at, _jumps])
	assert(_jumps == 0, "La barra no da saltos grandes")
	# La tapa de SceneLoader cubre el montaje de la escena y se quita sola cuando el mundo está listo
	assert(SceneLoader.has_cover(), "La tapa sigue puesta al entrar la escena nueva")
	var shot := OS.get_environment("LS_SHOT")
	if shot != "":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(shot)
	var t := Time.get_ticks_msec()
	while SceneLoader.has_cover() and Time.get_ticks_msec() - t < 15000:
		await get_tree().process_frame
	assert(not SceneLoader.has_cover(), "La tapa se quita cuando la escena está lista")
	print("tapa retirada a los %.1f s de entrar la escena" % ((Time.get_ticks_msec() - t) / 1000.0))
	print("ALL LOADING CHECKS PASSED")
	get_tree().quit(0)
