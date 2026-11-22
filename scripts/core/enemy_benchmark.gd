class_name EnemyBenchmark
extends Node

## Banco de pruebas de rendimiento: mantiene N enemigos vivos alrededor del jugador y escribe en consola
## métricas cada REPORT_EVERY s (FPS, tiempo de frame/física, draw calls, enemigos dibujados).
##
## Uso (PC simulando móvil):
##   RUMBANG_FORCE_MOBILE=1 RUMBANG_BENCH=300 RUMBANG_BENCH_SECONDS=60 godot --path .
## Con RUMBANG_BENCH_SECONDS el juego se cierra al terminar e imprime un resumen. En partida, F9 alterna
## el banco (300 enemigos).

const REPORT_EVERY := 2.0
const RING_MIN := 6.0
const RING_MAX := 32.0
const TOPUP_PER_FRAME := 20
const DEFAULT_TARGET := 300

var target: int = DEFAULT_TARGET
var duration: float = 0.0          ## 0 = sin límite
var _elapsed := 0.0
var _timer := 0.0
var _frames := 0
var _worst_ms := 0.0
var _fps_samples: PackedFloat32Array = PackedFloat32Array()
var _phys_samples: PackedFloat32Array = PackedFloat32Array()
var _draw_samples: PackedFloat32Array = PackedFloat32Array()

## Crea el banco si la variable de entorno RUMBANG_BENCH está definida (devuelve null si no).
static var fixed_scale := 0.0
static var mailbox := false                 ## vsync "mailbox" en vez de desactivado (prueba)
static var uncapped := false               ## sin tope de FPS ni vsync (medir margen real)
static var hide: PackedStringArray = []      ## bisección de GPU: qué partes de la escena apagar

static func from_env() -> EnemyBenchmark:
	var n := OS.get_environment("RUMBANG_BENCH")
	var secs := OS.get_environment("RUMBANG_BENCH_SECONDS")
	# Android: sin variables de entorno. Un archivo user://bench.txt con "enemigos segundos" activa el banco.
	if n == "" and FileAccess.file_exists("user://bench.txt"):
		var parts := FileAccess.get_file_as_string("user://bench.txt").strip_edges().split(" ", false)
		if parts.size() > 0:
			n = parts[0]
		if parts.size() > 1:
			secs = parts[1]
		for i in range(2, parts.size()):       # opciones: "p" = perfilador, "s=0.5" = escala 3D fija (sin gobernador)
			if parts[i] == "p":
				PerfProbe.enabled = true
			elif parts[i] == "pc":
				PerfProbe.enabled = true
				PerfProbe.detail = false
			elif parts[i].begins_with("s="):
				fixed_scale = float(parts[i].substr(2))
			elif parts[i].begins_with("cr="):
				HiveMind.crowd_ref = float(parts[i].substr(3))
			elif parts[i] == "nn":
				EnemyMotion.native_enabled = false   # sin C++ (comparar)
			elif parts[i] == "ns":
				EnemyManager.native_sim_enabled = false   # solo el movimiento en C++, el bucle en GDScript
			elif parts[i] == "u":
				uncapped = true
			elif parts[i] in ["r1", "r2", "r3", "r4", "r5"]:
				# r1 reducida; r2-r5 fija a 1080p/900p/720p/540p (Quality.RES_*), para comparar
				Quality.apply_resolution(int(parts[i].substr(1)))
			elif parts[i] == "mb":
				uncapped = true
				mailbox = true
			elif parts[i].begins_with("h="):
				hide = parts[i].substr(2).split(",", false)
	if n == "":
		return null
	var b := EnemyBenchmark.new()
	b.name = "EnemyBenchmark"
	b.target = int(n) if int(n) > 0 else DEFAULT_TARGET
	b.duration = float(secs) if secs != "" else 0.0
	return b

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	if fixed_scale > 0.0:
		var gov := get_tree().root.find_child("PerformanceGovernor", true, false)
		if gov:
			gov.set_process(false)
			gov.set_physics_process(false)
		get_viewport().scaling_3d_scale = fixed_scale
		print("[BENCH] escala 3D fija=%.2f" % fixed_scale)
	if uncapped:
		Engine.max_fps = 0
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_MAILBOX if mailbox else DisplayServer.VSYNC_DISABLED)
		print("[BENCH] vsync pedido=%s activo=%d" % ["mailbox" if mailbox else "off", DisplayServer.window_get_vsync_mode()])
	_add_edges.call_deferred()
	if not hide.is_empty():
		_apply_hide.call_deferred()
		print("[BENCH] ocultar=%s" % ",".join(hide))
	print("[BENCH] objetivo=%d enemigos, móvil=%s, impostores=%s" % [target, Quality.is_mobile(), Quality.use_impostors()])

func _process(delta: float) -> void:
	if EnemyManager.instance == null:
		return
	_keep_player_alive()
	_topup()
	_elapsed += delta
	_timer += delta
	_frames += 1
	PerfProbe.frame()
	_worst_ms = maxf(_worst_ms, delta * 1000.0)
	if _timer >= REPORT_EVERY:
		_report()
	if duration > 0.0 and _elapsed >= duration:
		_summary()
		get_tree().quit()

## Mide siempre lo mismo: si el jugador muere a mitad, la partida cambia (pantalla de fin, sin combate).
func _keep_player_alive() -> void:
	var player := EnemyManager.player_node()
	var hc = player.get("health_comp") if player else null
	if hc:
		hc.max_hp = 1.0e9
		hc.hp = 1.0e9

## Rellena hasta `target` enemigos vivos en un anillo alrededor del jugador (reparte el coste entre frames).
func _topup() -> void:
	var player := EnemyManager.player_node()
	if player == null:
		return
	var missing := target - EnemyManager.active_count()
	var n := mini(missing, TOPUP_PER_FRAME)
	for i in range(n):
		var a := randf() * TAU
		var r := randf_range(RING_MIN, RING_MAX)
		var p := player.global_position + Vector3(cos(a) * r, 0.0, sin(a) * r)
		p.y = EnemyManager.floor_y(p.x, p.z)
		var type_val := randi() % 5
		var e := EnemyManager.spawn(type_val, p)
		if e != null:
			e.alert()

## Reparto del frame en el dispositivo: cuánto tardan TODOS los _physics_process y _process de scripts
## (dos nodos con prioridad mínima y máxima los encierran) frente al resto (motor de física, render, espera).
var _edges: Array = []
var _ph_t0 := 0
var _ph_acc := 0
var _ph_n := 0
var _pr_t0 := 0
var _pr_acc := 0
var _pr_n := 0

class _Edge extends Node:
	var bench
	var first := false
	func _physics_process(_d: float) -> void:
		var t := Time.get_ticks_usec()
		if first:
			bench._ph_t0 = t
		elif bench._ph_t0 > 0:
			bench._ph_acc += t - bench._ph_t0
			bench._ph_n += 1
	func _process(_d: float) -> void:
		var t := Time.get_ticks_usec()
		if first:
			bench._pr_t0 = t
		elif bench._pr_t0 > 0:
			bench._pr_acc += t - bench._pr_t0
			bench._pr_n += 1

func _add_edges() -> void:
	for first in [true, false]:
		var e := _Edge.new()
		e.bench = self
		e.first = first
		e.process_mode = Node.PROCESS_MODE_PAUSABLE
		e.process_priority = -1000000 if first else 1000000
		e.process_physics_priority = -1000000 if first else 1000000
		get_tree().root.add_child(e)
		_edges.append(e)

func _exit_tree() -> void:
	for e in _edges:
		if is_instance_valid(e):
			e.queue_free()

func _report() -> void:
	var fps := float(_frames) / _timer
	if _ph_n > 0 or _pr_n > 0:
		var frame_ms := 1000.0 / maxf(fps, 0.001)
		var ph := float(_ph_acc) / 1000.0 / maxf(float(_ph_n), 1.0)
		var pr := float(_pr_acc) / 1000.0 / maxf(float(_pr_n), 1.0)
		var ticks_per_frame := float(_ph_n) / maxf(float(_pr_n), 1.0)
		print("[FRAME] frame=%.1fms scripts_física=%.2fms/tick (%.2f ticks/frame) scripts_proceso=%.2fms resto=%.1fms" % [
			frame_ms, ph, ticks_per_frame, pr, frame_ms - pr - ph * ticks_per_frame])
		_ph_acc = 0; _ph_n = 0; _pr_acc = 0; _pr_n = 0
	var phys := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var proc := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var draws := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var vis := EnemyVisuals.instance
	var drawn := vis.drawn_count() if vis != null else -1
	print("[BENCH] t=%5.1fs enemigos=%d fps=%5.1f peor_frame=%5.1fms física=%5.2fms proceso=%5.2fms draws=%d dibujados=%d mem=%.0fMB nodos=%d cuerpos=%d pares=%d" % [
		_elapsed, EnemyManager.active_count(), fps, _worst_ms, phys, proc, int(draws), drawn,
		float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0,
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)),
		int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS))])
	if PerfProbe.enabled:
		# Cuántos enemigos se actualizan por tick de física (con el reparto por distancia y multitud)
		var per_tick := 0.0
		for e in EnemyManager.instance._active:
			per_tick += 1.0 / float(maxi(e.tick_span, 1))
		print("[PERF] actualizados/tick=%.0f multitud=%.2f | %s" % [per_tick, HiveMind.crowd_scale, PerfProbe.report()])
	_fps_samples.append(fps)
	_phys_samples.append(phys)
	_draw_samples.append(draws)
	_timer = 0.0
	_frames = 0
	_worst_ms = 0.0

func _summary() -> void:
	print("[BENCH] RESUMEN fps_medio=%.1f fps_min=%.1f física_media=%.2fms física_max=%.2fms draws_medio=%.0f nativo=%s" % [
		_avg(_fps_samples), _min(_fps_samples), _avg(_phys_samples), _max(_phys_samples), _avg(_draw_samples), EnemyMotion.using_native()])

static func _avg(a: PackedFloat32Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += v
	return s / a.size()

static func _min(a: PackedFloat32Array) -> float:
	var m := INF
	for v in a:
		m = minf(m, v)
	return m if not a.is_empty() else 0.0

static func _max(a: PackedFloat32Array) -> float:
	var m := 0.0
	for v in a:
		m = maxf(m, v)
	return m

## Bisección de GPU (solo banco): apaga partes de la escena para ver cuánto cuesta cada una.
func _apply_hide() -> void:
	var scene := get_tree().current_scene
	for what in hide:
		match what:
			"env":
				var we := scene.find_child("WorldEnvironment", false, false) as WorldEnvironment
				if we and we.environment:
					var env := we.environment
					env.fog_enabled = false
					env.adjustment_enabled = false
					env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
					env.background_mode = Environment.BG_COLOR
			"env_fog", "env_adj", "env_tone", "env_sky":
				var we2 := scene.find_child("WorldEnvironment", false, false) as WorldEnvironment
				if we2 and we2.environment:
					var e2 := we2.environment
					if what == "env_fog": e2.fog_enabled = false
					elif what == "env_adj": e2.adjustment_enabled = false
					elif what == "env_tone": e2.tonemap_mode = Environment.TONE_MAPPER_LINEAR
					else: e2.background_mode = Environment.BG_COLOR
			"aa":
				get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
				get_viewport().use_debanding = false
			"lights":
				for l in scene.find_children("*", "OmniLight3D", true, false):
					l.visible = false
				for l in scene.find_children("*", "SpotLight3D", true, false):
					l.visible = false
			"sun":
				var sun := scene.find_child("DirectionalLight3D", false, false)
				if sun:
					sun.visible = false
			"ground":
				var g := scene.get_node_or_null("ProceduralMap/Ground")
				if g:
					g.visible = false
			"props":
				var pr := scene.get_node_or_null("ProceduralMap/Props")
				if pr:
					pr.visible = false
			"enemies":
				var ev := scene.find_child("EnemyVisuals", true, false)
				if ev:
					ev.visible = false
			"player":
				var pl := scene.get_node_or_null("Player/KnightMesh")
				if pl:
					pl.visible = false
			"hud":
				for c in scene.find_children("*", "CanvasLayer", true, false):
					c.visible = false
			"critters":
				var ac := scene.find_child("AmbientCritters", false, false)
				if ac:
					ac.visible = false
