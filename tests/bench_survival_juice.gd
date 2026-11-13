extends Node

## Banco del perfil "light" de supervivencia (fase 5 del juice; necesita ventana para medir el dibujo):
## cada CYCLE s aparecen BENCH_N enemigos alrededor del jugador y mueren todos a la vez (lo peor: muchas
## bajas en un frame). Mide el tiempo de frame medio y el peor durante BENCH_SECONDS.
##   godot --path . res://tests/bench_survival_juice.tscn            (juice "light")
##   JUICE_OFF=1 godot --path . res://tests/bench_survival_juice.tscn (sin juice, para comparar)
## BENCH_N (60) · BENCH_SECONDS (12) · SHOT=<png> guarda una captura justo tras una matanza.

const CYCLE := 0.8

var _frames: Array[float] = []
var _worst := 0.0
var _measuring := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.game_mode = "survival"
	SaveManager.save_path = "user://test_save.json"
	if OS.get_environment("JUICE_OFF") == "1":
		HitFeedback.profile_override = "off"
	var main: Node = load("res://scenes/core/main_procedural.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	get_tree().current_scene = main
	var p = null
	var waves: WaveManager = null
	for i in 900:
		await get_tree().process_frame
		p = main.get_node_or_null("Player")
		waves = main.find_child("WaveManager", true, false)
		if p and waves and waves._running:
			break
	p.health_comp.max_hp = 99999.0
	p.health_comp.hp = 99999.0
	waves.set_process(false)          # solo los enemigos del banco
	var xpc = p.get_node_or_null("ExperienceComponent")
	if xpc:
		xpc.experience_required = 1e12   # sin subidas de nivel: pausarían el juego a mitad de medida
	var n := int(OS.get_environment("BENCH_N")) if OS.get_environment("BENCH_N") != "" else 60
	var secs := float(OS.get_environment("BENCH_SECONDS")) if OS.get_environment("BENCH_SECONDS") != "" else 12.0
	var shot := OS.get_environment("SHOT")
	await get_tree().create_timer(1.0).timeout
	_measuring = true
	var t := 0.0
	var cycles := 0
	while t < secs:
		var spawned: Array = []
		for i in n:
			var a := TAU * float(i) / float(n)
			var pos: Vector3 = p.global_position + Vector3(cos(a), 0.0, sin(a)) * randf_range(3.0, 7.0)
			spawned.append_array(waves._spawn_single_enemy(pos))
		await get_tree().create_timer(CYCLE * 0.5).timeout
		HitFeedback.weapon_tag = WeaponData.WeaponType.SPINNING_AXE
		for en in spawned:
			if en is EnemyData and not en.recycled:
				en.take_damage(99999.0, (en.global_position - p.global_position).normalized() * 6.0)
		cycles += 1
		if shot != "" and cycles == 2:
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(shot)
		await get_tree().create_timer(CYCLE * 0.5).timeout
		t += CYCLE
	_measuring = false
	var avg := 0.0
	for f in _frames:
		avg += f
	avg /= maxf(float(_frames.size()), 1.0)
	_frames.sort()
	var p99: float = _frames[int(_frames.size() * 0.99)] if not _frames.is_empty() else 0.0
	print("BENCH profile=%s n=%d cycles=%d frames=%d avg=%.2fms p99=%.2fms worst=%.2fms paused=%s" % [
		HitFeedback.profile(), n, cycles, _frames.size(), avg, p99, _worst, get_tree().paused])
	HitFeedback.profile_override = ""
	get_tree().quit(0)

func _process(delta: float) -> void:
	if _measuring:
		var ms := delta * 1000.0 / maxf(Engine.time_scale, 0.001)
		_frames.append(ms)
		_worst = maxf(_worst, ms)
