class_name PerfProbe
extends RefCounted

## Perfilador por secciones, solo activo con la variable de entorno RUMBANG_PROFILE (desactivado
## cuesta una comprobación de bool). Lo usa EnemyBenchmark para desglosar el tiempo de cada frame:
##     var t := PerfProbe.begin()
##     ...trabajo...
##     PerfProbe.end("enemigos.ia", t)
## report() devuelve "sección ms/frame (llamadas/frame)" de mayor a menor y reinicia los contadores.

static var enabled: bool = OS.get_environment("RUMBANG_PROFILE") != ""
static var _usec: Dictionary = {}
static var _calls: Dictionary = {}
static var _frames: int = 0

static func begin() -> int:
	return Time.get_ticks_usec() if enabled else 0

static func end(section: String, start: int) -> void:
	if not enabled:
		return
	_usec[section] = int(_usec.get(section, 0)) + Time.get_ticks_usec() - start
	_calls[section] = int(_calls.get(section, 0)) + 1

## Cuenta un frame de dibujo (para dar las medias por frame).
static func frame() -> void:
	if enabled:
		_frames += 1

static func report() -> String:
	if not enabled or _frames == 0:
		return ""
	var keys: Array = _usec.keys()
	keys.sort_custom(func(a, b): return _usec[a] > _usec[b])
	var parts: Array = []
	for k in keys:
		parts.append("%s %.2fms (%d)" % [k, float(_usec[k]) / 1000.0 / _frames, int(_calls[k]) / _frames])
	_usec.clear()
	_calls.clear()
	_frames = 0
	return " | ".join(parts)
