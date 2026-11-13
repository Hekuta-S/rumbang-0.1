extends Node

## Banco de CPU de los enemigos de la mazmorra (headless): BENCH_N enemigos (14 por defecto, el tope de una
## caverna) persiguen y rodean al jugador, que no recibe daño. Mide el tiempo de física por frame durante
## BENCH_SECONDS (10). Lanzar con RUMBANG_FORCE_MOBILE=1 para la configuración de móvil (física a 30 Hz).
##   godot --headless --path . res://tests/bench_dungeon_enemies.tscn

const KINDS := ["goblin", "goblin", "brute", "zombie", "mage", "goblin", "zombie"]

var _player: Node3D
var _health: Node

func _ready() -> void:
	GameData.game_mode = "dungeon"
	GameData.preload_assets()
	var main: Node = (load("res://scenes/core/main_dungeon.tscn") as PackedScene).instantiate()
	add_child(main)
	await get_tree().create_timer(2.0).timeout
	var enc := main.get_node_or_null("DungeonEncounter") as DungeonEncounter
	_player = main.get_node("Player") as Node3D
	_health = _player.get("health_comp") as Node
	var n := int(OS.get_environment("BENCH_N")) if OS.get_environment("BENCH_N") != "" else 14
	var secs := float(OS.get_environment("BENCH_SECONDS")) if OS.get_environment("BENCH_SECONDS") != "" else 10.0
	var room := 0
	for i in enc.map.rooms.size():
		if enc.map.rooms[i]["type"] == "start":
			room = i
	var c: Vector3 = enc.map.room_center(room)
	_player.global_position = c
	for i in n:
		var a := TAU * float(i) / float(n)
		enc._spawn_at(room, c + Vector3(cos(a), 0.0, sin(a)) * 7.0, KINDS[i % KINDS.size()])
	await get_tree().create_timer(2.0).timeout
	PerfProbe.report()          # descarta lo medido durante la aparición
	var samples: Array[float] = []
	var t0 := Time.get_ticks_usec()
	while Time.get_ticks_usec() - t0 < int(secs * 1000000.0):
		await get_tree().physics_frame
		samples.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		PerfProbe.frame()
	samples.sort()
	var avg := 0.0
	for s in samples:
		avg += s
	avg /= maxf(samples.size(), 1.0)
	print("enemigos vivos: %d · ticks: %d" % [EnemyRegistry.all().size(), samples.size()])
	print("BENCH fisica ms/tick: media %.2f, mediana %.2f, max %.2f" % [avg, samples[samples.size() / 2], samples[-1]])
	if PerfProbe.enabled:       # RUMBANG_PROFILE=1: desglose por tick
		print("PERF por tick: ", PerfProbe.report())
	get_tree().quit(0)

func _physics_process(_d: float) -> void:
	if _health:
		_health.set("invincibility_time", 999.0)
		_health.set("hp", _health.get("max_hp"))
