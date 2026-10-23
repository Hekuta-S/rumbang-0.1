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
static func from_env() -> EnemyBenchmark:
	var n := OS.get_environment("RUMBANG_BENCH")
	if n == "":
		return null
	var b := EnemyBenchmark.new()
	b.name = "EnemyBenchmark"
	b.target = int(n) if int(n) > 0 else DEFAULT_TARGET
	b.duration = float(OS.get_environment("RUMBANG_BENCH_SECONDS")) if OS.get_environment("RUMBANG_BENCH_SECONDS") != "" else 0.0
	return b

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	print("[BENCH] objetivo=%d enemigos, móvil=%s, impostores=%s" % [target, Quality.is_mobile(), Quality.use_impostors()])

func _process(delta: float) -> void:
	if EnemyManager.instance == null:
		return
	_topup()
	_elapsed += delta
	_timer += delta
	_frames += 1
	_worst_ms = maxf(_worst_ms, delta * 1000.0)
	if _timer >= REPORT_EVERY:
		_report()
	if duration > 0.0 and _elapsed >= duration:
		_summary()
		get_tree().quit()

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
			e.is_alerted = true

func _report() -> void:
	var fps := float(_frames) / _timer
	var phys := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var proc := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var draws := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var vis := EnemyVisuals.instance
	var drawn := vis.drawn_count() if vis != null else -1
	print("[BENCH] t=%5.1fs enemigos=%d fps=%5.1f peor_frame=%5.1fms física=%5.2fms proceso=%5.2fms draws=%d dibujados=%d mem=%.0fMB" % [
		_elapsed, EnemyManager.active_count(), fps, _worst_ms, phys, proc, int(draws), drawn,
		float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0])
	_fps_samples.append(fps)
	_phys_samples.append(phys)
	_draw_samples.append(draws)
	_timer = 0.0
	_frames = 0
	_worst_ms = 0.0

func _summary() -> void:
	print("[BENCH] RESUMEN fps_medio=%.1f fps_min=%.1f física_media=%.2fms física_max=%.2fms draws_medio=%.0f" % [
		_avg(_fps_samples), _min(_fps_samples), _avg(_phys_samples), _max(_phys_samples), _avg(_draw_samples)])

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
