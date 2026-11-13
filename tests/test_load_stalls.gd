extends Node

## Mide los tirones (frames largos) al cargar la mazmorra y al bajar de nivel. Solo CPU (headless).

var _last := 0
var _stalls: Array = []
var _label := "carga"

func _process(_d: float) -> void:
	var now := Time.get_ticks_usec()
	if _last != 0:
		var ms := (now - _last) / 1000.0
		if ms > 35.0:
			_stalls.append("%s: %.0f ms" % [_label, ms])
	_last = now

func _ready() -> void:
	print("--- TEST: TIRONES DE CARGA ---")
	GameData.game_mode = "dungeon"
	var t0 := Time.get_ticks_usec()
	GameData.preload_assets()
	print("preload_assets: %.0f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	# Lo mismo que la pantalla de carga: datos de la partida en caché y un modelo de cada enemigo calentado
	t0 = Time.get_ticks_usec()
	var LoadingScreen := load("res://scripts/ui/loading_screen.gd")
	if OS.get_environment("STALLS_BASELINE") != "1":     # =1: como antes en móvil (sin caché de partida)
		LoadingScreen.cache_run_data_sync()
	for m in DungeonGoblin.warm_models():
		(m as Node).free()
	print("pantalla de carga (datos + calentar enemigos): %.0f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	t0 = Time.get_ticks_usec()
	var ps := load("res://scenes/core/main_dungeon.tscn") as PackedScene
	print("load escena: %.0f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	t0 = Time.get_ticks_usec()
	var main := ps.instantiate()
	print("instantiate: %.0f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	t0 = Time.get_ticks_usec()
	add_child(main)
	print("add_child (_ready de todo): %.0f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	await get_tree().create_timer(3.0).timeout
	_label = "juego"
	await get_tree().create_timer(1.0).timeout
	var enc := main.get_node_or_null("DungeonEncounter") as DungeonEncounter
	print("encuentro: ", enc != null, " mapa: ", main.get_node_or_null("ProceduralMap"))
	if enc:
		_label = "nivel"
		enc.next_level()
		await get_tree().create_timer(3.5).timeout
		# Primer spawn de cada tipo de enemigo (carga de modelo, animaciones y materiales)
		_label = "enemigos"
		var room := 0
		for i in enc.map.rooms.size():
			if enc.map.rooms[i]["type"] != "start":
				room = i
				break
		var c: Vector3 = enc.map.room_center(room)
		for k in ["goblin", "zombie", "mage", "brute", "necro"]:
			var t1 := Time.get_ticks_usec()
			enc._spawn_at(room, c, k)
			print("primer spawn %s: %.0f ms" % [k, (Time.get_ticks_usec() - t1) / 1000.0])
			await get_tree().create_timer(0.3).timeout
		var t2 := Time.get_ticks_usec()
		enc._spawn_at(room, c + Vector3(3, 0, 0), "goblin")
		print("segundo spawn goblin: %.0f ms" % ((Time.get_ticks_usec() - t2) / 1000.0))
	print("tirones (>35 ms): ", _stalls.size())
	for s in _stalls:
		print("  ", s)
	get_tree().quit(0)
