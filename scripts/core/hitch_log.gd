class_name HitchLog
extends Node

## Registro de tirones para medir en un dispositivo real. Solo existe si hay un archivo user://hitch.txt
## (en Android: adb shell run-as <paquete> sh -c 'touch files/hitch.txt'); el contenido opcional es el
## umbral en ms (por defecto 80). Cada frame más lento imprime "[HITCH]" con lo que cambió en ese frame:
## escena, nodos y objetos creados, memoria y draws, para saber qué lo provocó. Borrar el archivo al terminar.

const DEFAULT_THRESHOLD_MS := 80.0

var threshold_ms := DEFAULT_THRESHOLD_MS
var _last_us := 0
var _nodes := 0
var _objects := 0
var _mem := 0.0
var _scene := ""
var _count := 0
var _worst := 0.0

## Lo añade GameData al arrancar si existe user://hitch.txt.
static func install(parent: Node) -> void:
	if not FileAccess.file_exists("user://hitch.txt"):
		return
	var h := HitchLog.new()
	h.name = "HitchLog"
	var txt := FileAccess.get_file_as_string("user://hitch.txt").strip_edges()
	if txt.is_valid_float():
		h.threshold_ms = float(txt)
	parent.add_child.call_deferred(h)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -100000          # primero del frame: mide el frame anterior completo
	_last_us = Time.get_ticks_usec()
	_sample()
	print("[HITCH] registro activo, umbral %.0f ms" % threshold_ms)

func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var ms := float(now - _last_us) / 1000.0
	_last_us = now
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var objects := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var mem := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	var cs := get_tree().current_scene
	var scene := cs.scene_file_path.get_file() if cs else "-"
	if ms >= threshold_ms:
		_count += 1
		_worst = maxf(_worst, ms)
		print("[HITCH] %.0f ms t=%.1fs escena=%s%s nodos%+d objetos%+d mem%+.1fMB draws=%d pausa=%s" % [
			ms, Time.get_ticks_msec() / 1000.0, scene, (" (antes " + _scene + ")") if scene != _scene else "",
			nodes - _nodes, objects - _objects, mem - _mem,
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), get_tree().paused])
	_nodes = nodes
	_objects = objects
	_mem = mem
	_scene = scene

func _sample() -> void:
	_nodes = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	_objects = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	_mem = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0

func _exit_tree() -> void:
	print("[HITCH] total=%d peor=%.0f ms" % [_count, _worst])
