class_name EnemyManager
extends Node

## Gestiona a todos los enemigos normales (EnemyData): los crea/recicla por tipo (pool) y ejecuta la IA de
## todos en un único bucle de física. Vive como hijo del WaveManager.

static var instance: EnemyManager = null
static var _free: Dictionary = {}    # tipo (int) -> Array[EnemyData]
## Nº de tick de física del bucle de enemigos: es el reloj con el que el shader de impostores interpola.
static var tick: int = 0

var _active: Array = []              # EnemyData vivos
var _player: Node3D = null

## Simulación completa en C++ (EnemySimNative, native/src/enemy_sim_native.cpp): todo el bucle de abajo
## (temporizadores, frecuencia de actualización, IA, tokens, separación, movimiento y dibujo impostor) en una
## sola llamada por tick. Se decide al primer spawn (hace falta el mapa con relieve en C++) y no cambia
## hasta salir de la escena. RUMBANG_NATIVE_SIM=0 (o RUMBANG_NATIVE=0) vuelve al GDScript.
static var native_sim_enabled: bool = OS.get_environment("RUMBANG_NATIVE_SIM") != "0"
static var sim: Object = null
var _sim_decided: bool = false
## Enemigos cuyos atributos cambió el juego (vida, velocidad, escala...): el C++ los relee antes del tick.
var _dirty: Array = []
const EV_STRIDE := 6

func _ready() -> void:
	instance = self
	process_mode = Node.PROCESS_MODE_PAUSABLE
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

func _exit_tree() -> void:
	if instance == self:
		instance = null
	if sim != null and _sim_decided:
		sim = null
	_free.clear()
	_active.clear()
	HiveMind.reset()

## Un solo bucle para todos los enemigos de datos.
func _physics_process(delta: float) -> void:
	tick += 1
	var t0 := PerfProbe.begin()
	# Mente colmena: datos compartidos de la multitud, calculados una vez antes de actualizar a nadie
	HiveMind.begin_tick(get_tree(), _active.size())
	if sim != null:
		_step_native(delta)
		PerfProbe.end("enemigos.bucle", t0)
		return
	var vis := EnemyVisuals.instance
	var tick_f := float(tick)
	var prof := PerfProbe.enabled and PerfProbe.detail
	var i := 0
	while i < _active.size():
		var e: EnemyData = _active[i]
		e.tick_age += 1
		if e.tick_age >= e.tick_span:
			# Actualiza con el tiempo acumulado de los ticks que se saltó
			var dt := delta * float(e.tick_age)
			e.tick_age = 0
			e.update(dt)
			var ev: EnemyVisuals = e.visuals()
			if ev != null:
				if prof:
					var tv := PerfProbe.begin()
					ev.write(e, tick_f)
					PerfProbe.end("enemigos.dibujo", tv)
				else:
					ev.write(e, tick_f)
		# Si e (u otro anterior) se recicló durante su update, la lista se desplazó: no se avanza
		if i < _active.size() and _active[i] == e:
			i += 1
	PerfProbe.end("enemigos.bucle", t0)

## Un tick de la simulación en C++ y después los eventos que necesitan el juego (disparos, golpes).
func _step_native(delta: float) -> void:
	for e in _dirty:
		e._sim_dirty = false
		if e.active_idx >= 0:
			sim.load_stats(e.active_idx)
	_dirty.clear()
	var pl := HiveMind.local_player
	if pl == null or not is_instance_valid(pl):
		return
	var pv = pl.get("velocity")
	var pvel: Vector3 = pv if pv is Vector3 else Vector3.ZERO
	var gs := GameState.get_instance()
	var elapsed: float = gs.elapsed_time if gs != null else 0.0
	var ev: PackedFloat32Array = sim.step(EnemyMotion.native_motion(), delta, tick, HiveMind.local_player_pos, pvel,
			HiveMind.crowd_scale, elapsed, Time.get_ticks_msec(), Engine.get_physics_frames(),
			HiveMind.use_tokens, HiveMind.use_density)
	HiveMind.tokens_used = sim.get_tokens_used()
	if not ev.is_empty():
		_run_events(ev)

## Ejecuta los eventos del C++. Primero se resuelven todos los enemigos (un golpe puede matar a alguno y
## mover los índices de _active), luego se ejecutan.
func _run_events(ev: PackedFloat32Array) -> void:
	var n := ev.size() / EV_STRIDE
	var who: Array = []
	for k in range(n):
		var idx := int(ev[k * EV_STRIDE + 1])
		who.append(_active[idx] if idx >= 0 and idx < _active.size() else null)
	for k in range(n):
		var e: EnemyData = who[k]
		if e == null or e.recycled:
			continue
		var b := k * EV_STRIDE
		var a := Vector3(ev[b + 2], ev[b + 3], ev[b + 4])
		match int(ev[b]):
			1:
				EnemyBehavior.fire_ranged(e, a, ev[b + 5])
			2:
				EnemyBehavior.fire_ranged(e, a, ev[b + 5])
			3:
				EnemyBehavior.fire_mortar(e)
			4:
				EnemyBehavior.hit_player(e, ev[b + 2])
			5:
				EnemyBehavior.fire_slam(e)
			6:
				EnemyBehavior.fire_burst(e)

## El juego cambió atributos de `e` (vida, velocidad, escala, alerta, posición): el C++ los relee.
static func mark_dirty(e: EnemyData) -> void:
	if sim == null or e._sim_dirty or instance == null:
		return
	e._sim_dirty = true
	instance._dirty.append(e)

static func _decide_sim() -> void:
	instance._sim_decided = true
	sim = null
	if not native_sim_enabled or not EnemyMotion.native_enabled or not ClassDB.class_exists(&"EnemySimNative"):
		return
	if EnemyMotion.native_motion() == null:
		return
	sim = ClassDB.instantiate(&"EnemySimNative")
	if not sim.has_method(&"supports_creatures"):
		sim = null          # biblioteca nativa antigua (sin ratas ni babosas): vale el GDScript
		return
	sim.vis_setup(EnemyVisuals.KEYS.size() + EnemyVisuals.CREATURE_KEYS.size(), EnemyVisuals.CAPACITY, EnemyVisuals.STRIDE)
	# Modo malla (sin impostores): EnemyVisuals lee del objeto tick_age, vat_walking, vat_flash... cada frame
	sim.set_full_writeback(EnemyVisuals.instance == null)

## true si los enemigos van por la simulación en C++ (pruebas / banco).
static func using_native_sim() -> bool:
	return sim != null

# ───────────────────────────── Acceso estático ─────────────────────────────

static func player_node() -> Node3D:
	if instance == null:
		return null
	if instance._player == null or not is_instance_valid(instance._player):
		instance._player = instance.get_tree().get_first_node_in_group("player")
	return instance._player

static func scene_root() -> Node:
	return instance.get_tree().current_scene if instance != null and instance.is_inside_tree() else null

static func floor_y(x: float, z: float) -> float:
	var root := scene_root()
	if root != null and root.has_method("get_floor_y"):
		return root.get_floor_y(x, z)
	return 0.0

# ───────────────────────────── Creación / pool ─────────────────────────────

## Enemigo del tipo pedido, activo en `pos` (reutiliza uno del pool si lo hay).
static func spawn(type_val: int, pos: Vector3) -> EnemyData:
	if instance == null:
		return null
	if not instance._sim_decided:
		_decide_sim()
	var list: Array = _free.get(type_val, [])
	var e: EnemyData
	if list.is_empty():
		e = EnemyData.new(type_val)
	else:
		e = list.pop_back()
	e.reactivate(pos)
	e.player = player_node()
	e.active_idx = instance._active.size()
	instance._active.append(e)
	if sim != null:
		sim.add(e)
		e._sim_dirty = false
		mark_dirty(e)          # quien lo crea suele cambiarle vida/velocidad/escala justo después
	return e

## Prellena el pool con enemigos ya construidos (durante la carga): evita crear objetos en plena partida.
## `counts`: tipo (EnemyData.EnemyType) -> cantidad.
static func prefill(counts: Dictionary) -> void:
	for type_val in counts:
		if not _free.has(type_val):
			_free[type_val] = []
		var list: Array = _free[type_val]
		for i in range(int(counts[type_val]) - list.size()):
			var e := EnemyData.new(type_val)
			e.recycled = true
			list.append(e)

## Lo llama EnemyData.recycle(): vuelve al pool de su tipo.
static func release(e: EnemyData) -> void:
	if sim != null and instance != null and e.active_idx >= 0:
		sim.remove(e.active_idx)        # suelta su token y su casilla de dibujo
	else:
		HiveMind.release_token(e)
	if instance != null and e.active_idx >= 0:
		# Swap-remove O(1): el último ocupa el hueco (el bucle de física lo procesa al no avanzar el índice)
		var act: Array = instance._active
		var last: EnemyData = act.pop_back()
		if last != e:
			act[e.active_idx] = last
			last.active_idx = e.active_idx
	e.active_idx = -1
	if not _free.has(e.type):
		_free[e.type] = []
	(_free[e.type] as Array).append(e)

## Devuelve al pool a TODOS los enemigos vivos (reinicio de partida).
static func recycle_all() -> void:
	if instance == null:
		return
	for e in instance._active.duplicate():
		e.recycle()
	instance._active.clear()
	if sim != null:
		sim.clear()

static func active_count() -> int:
	return instance._active.size() if instance != null else 0
