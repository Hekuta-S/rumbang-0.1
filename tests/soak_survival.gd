extends Node

## Soak de supervivencia (perfil de rendimiento a largo plazo; necesita ventana para medir el dibujo).
## Juega una partida real acelerada: jugador inmortal, sin subidas de nivel, mata cada KILL_EVERY s a los
## enemigos a menos de KILL_RADIUS m, mata al jefe y sigue en modo infinito. Cada minuto de partida imprime
## [SOAK] con frame real, monitores de Performance y los tipos de nodo que más crecen.
##   godot --path . res://tests/soak_survival.tscn
## SOAK_MINUTES (16) · SOAK_SCALE (3) · SOAK_KILL (1 = matar, 0 = dejar que se acumulen)
## SOAK_BISECT=<min>: en ese minuto apaga el _process/_physics_process de cada clase de script por turnos y
## imprime [BISECT] con cuánto baja el frame sin ella (qué clase cuesta).

const KILL_EVERY := 0.5
const KILL_RADIUS := 9.0

var _frames: PackedFloat32Array = PackedFloat32Array()
var _worst := 0.0
var _prev_hist: Dictionary = {}
var _bisecting := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.game_mode = "survival"
	SaveManager.save_path = "user://test_save.json"
	var minutes := float(OS.get_environment("SOAK_MINUTES")) if OS.get_environment("SOAK_MINUTES") != "" else 16.0
	var scale := float(OS.get_environment("SOAK_SCALE")) if OS.get_environment("SOAK_SCALE") != "" else 3.0
	var kill := OS.get_environment("SOAK_KILL") != "0"
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
	p.health_comp.max_hp = 1e9
	p.health_comp.hp = 1e9
	var xpc = p.get_node_or_null("ExperienceComponent")
	if xpc:
		xpc.experience_required = 1e12
	Engine.time_scale = scale
	var gs := GameState.get_instance()
	var next_sample := 60.0
	var kill_t := 0.0
	var endless_started := false
	var bisect_at := float(OS.get_environment("SOAK_BISECT")) * 60.0 if OS.get_environment("SOAK_BISECT") != "" else -1.0
	print("[SOAK] start scale=%.1f minutes=%.0f kill=%s quality=%d" % [scale, minutes, kill, Quality.level()])
	_sample(main, 0.0)
	while gs.elapsed_time < minutes * 60.0 or _bisecting:
		await get_tree().process_frame
		p.health_comp.hp = 1e9
		if get_tree().paused:
			# pantalla de victoria (jefe muerto): seguir en modo infinito
			if not endless_started and main.has_method("_start_endless"):
				endless_started = true
				main._start_endless()
			get_tree().paused = false
			continue
		kill_t += get_process_delta_time()
		if kill and kill_t >= KILL_EVERY:
			kill_t = 0.0
			_kill_near(p, waves)
		if bisect_at > 0.0 and gs.elapsed_time >= bisect_at:
			bisect_at = -1.0
			_bisect(main)
		if gs.elapsed_time >= next_sample and not _bisecting:
			_sample(main, gs.elapsed_time)
			next_sample += 60.0
	Engine.time_scale = 1.0
	print("[SOAK] done")
	get_tree().quit(0)

func _kill_near(p: Node3D, waves: WaveManager) -> void:
	HitFeedback.weapon_tag = WeaponData.WeaponType.SPINNING_AXE
	for en in EnemyRegistry.all().duplicate():
		if en is EnemyData and not en.recycled and en.global_position.distance_to(p.global_position) < KILL_RADIUS:
			en.take_damage(1e7, (en.global_position - p.global_position).normalized() * 6.0)
	if waves._boss_alive() and waves._boss.global_position.distance_to(p.global_position) < 40.0:
		waves._boss.take_damage(1e7)
	for c in get_tree().get_nodes_in_group("flyers"):
		if is_instance_valid(c) and c.has_method("take_damage") and not c.is_dead():
			c.take_damage(1e7)

func _process(delta: float) -> void:
	var ms := delta * 1000.0 / maxf(Engine.time_scale, 0.001)
	_frames.append(ms)
	_worst = maxf(_worst, ms)

func _hist(n: Node, out: Dictionary) -> void:
	var key := n.get_class()
	var s = n.get_script()
	if s != null and s.get_global_name() != &"":
		key = String(s.get_global_name())
	out[key] = int(out.get(key, 0)) + 1
	for c in n.get_children():
		_hist(c, out)

func _sample(main: Node, t: float) -> void:
	var avg := 0.0
	for f in _frames:
		avg += f
	avg /= maxf(float(_frames.size()), 1.0)
	var sorted := _frames.duplicate()
	sorted.sort()
	var p95: float = sorted[int(sorted.size() * 0.95)] if not sorted.is_empty() else 0.0
	var hist := {}
	_hist(get_tree().root, hist)
	var growth: Array = []
	for k in hist:
		var d: int = int(hist[k]) - int(_prev_hist.get(k, 0))
		if d != 0:
			growth.append([d, k, hist[k]])
	growth.sort_custom(func(a, b): return absi(a[0]) > absi(b[0]))
	var gtxt := ""
	for g in growth.slice(0, 8):
		gtxt += " %s=%d(%+d)" % [g[1], g[2], g[0]]
	print("[SOAK] t=%4.1fmin frame_avg=%.2fms p95=%.2fms worst=%.1fms | proc=%.2fms phys=%.2fms | nodes=%d obj=%d orphan=%d mem=%.0fMB | draws=%d objs3d=%d | enemies=%d crows=%d orbs_grp=%d" % [
		t / 60.0, avg, p95, _worst,
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_COUNT),
		Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		EnemyRegistry.count(), get_tree().get_nodes_in_group("flyers").size(),
		get_tree().get_nodes_in_group("xp_orbs").size()])
	print("[SOAK]   growth:%s" % gtxt)
	print("[SOAK]   gpu: %s" % _gpu_state())
	_prev_hist = hist
	_frames.clear()
	_worst = 0.0

func _frame_avg(real_s: float) -> float:
	_frames.clear()
	var end := Time.get_ticks_msec() + int(real_s * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame
	var a := 0.0
	for f in _frames:
		a += f
	return a / maxf(float(_frames.size()), 1.0)

func _collect(n: Node, out: Dictionary) -> void:
	if n != self:
		var s = n.get_script()
		var key := String(s.get_global_name()) if s != null and s.get_global_name() != &"" else (String(s.resource_path.get_file()) if s != null else "")
		if key != "" and (n.is_processing() or n.is_physics_processing()):
			if not out.has(key):
				out[key] = []
			out[key].append(n)
	for c in n.get_children():
		_collect(c, out)

func _bisect(main: Node) -> void:
	_bisecting = true
	var groups := {}
	_collect(get_tree().root, groups)
	var base: float = await _frame_avg(3.0)
	print("[BISECT] base=%.2fms clases=%d" % [base, groups.size()])
	var res: Array = []
	for key in groups:
		var nodes: Array = groups[key]
		var st: Array = []
		for n in nodes:
			if is_instance_valid(n):
				st.append([n, n.is_processing(), n.is_physics_processing()])
				n.set_process(false)
				n.set_physics_process(false)
		var off: float = await _frame_avg(2.0)
		for e in st:
			if is_instance_valid(e[0]):
				e[0].set_process(e[1])
				e[0].set_physics_process(e[2])
		var back: float = await _frame_avg(1.0)
		res.append([(base + back) * 0.5 - off, key, nodes.size(), off, back])
	res.sort_custom(func(a, b): return a[0] > b[0])
	for r in res.slice(0, 15):
		print("[BISECT] %-28s n=%3d  ahorro=%6.2fms (off=%.2f on=%.2f)" % [r[1], r[2], r[0], r[3], r[4]])
	_bisecting = false

## Temperatura, reloj y frenos de la GPU NVIDIA (vacío si no hay nvidia-smi): separa el calor del portátil del coste del juego.
func _gpu_state() -> String:
	var exe := "C:/Program Files/NVIDIA Corporation/NVSMI/nvidia-smi.exe"
	if not FileAccess.file_exists(exe):
		return "n/a"
	var out: Array = []
	OS.execute(exe, ["--query-gpu=temperature.gpu,clocks.gr,utilization.gpu,clocks_throttle_reasons.sw_thermal_slowdown,clocks_throttle_reasons.hw_slowdown,clocks_throttle_reasons.sw_power_cap", "--format=csv,noheader"], out)
	return String(out[0]).strip_edges() if not out.is_empty() else "n/a"
