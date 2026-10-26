class_name AssetPreloader
extends RefCounted

## Carga recursos en segundo plano (ResourceLoader.load_threaded_*) sin congelar la pantalla.
## Uso: add() las rutas -> start() -> consultar progress()/is_done() cada frame -> collect().
## Lo cargado se guarda en `GameData.cache_preloaded` (si no, Godot lo descarta al no tener referencias).

var paths: Array[String] = []
var _started := false

func add(path: String) -> void:
	if path != "" and not paths.has(path) and ResourceLoader.exists(path):
		paths.append(path)

func add_many(list: Array) -> void:
	for p in list:
		add(String(p))

func start() -> void:
	_started = true
	for p in paths:
		if not GameData.cache_preloaded.has(p):
			ResourceLoader.load_threaded_request(p, "", true)

## 0..1 del conjunto.
func progress() -> float:
	if paths.is_empty():
		return 1.0
	var total := 0.0
	var prog: Array = []
	for p in paths:
		if GameData.cache_preloaded.has(p):
			total += 1.0
			continue
		var st := ResourceLoader.load_threaded_get_status(p, prog)
		if st == ResourceLoader.THREAD_LOAD_LOADED or st == ResourceLoader.THREAD_LOAD_FAILED or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			total += 1.0
		elif not prog.is_empty():
			total += float(prog[0])
	return total / float(paths.size())

func is_done() -> bool:
	for p in paths:
		if GameData.cache_preloaded.has(p):
			continue
		if ResourceLoader.load_threaded_get_status(p) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return false
	return true

## Recoge lo ya cargado en GameData.cache_preloaded (llamar cuando is_done()).
func collect() -> void:
	for p in paths:
		if GameData.cache_preloaded.has(p):
			continue
		if ResourceLoader.load_threaded_get_status(p) == ResourceLoader.THREAD_LOAD_LOADED:
			GameData.cache_preloaded[p] = ResourceLoader.load_threaded_get(p)
