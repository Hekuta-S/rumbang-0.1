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

func _ready() -> void:
	instance = self
	process_mode = Node.PROCESS_MODE_PAUSABLE
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

func _exit_tree() -> void:
	if instance == self:
		instance = null
	_free.clear()
	_active.clear()

## Un solo bucle para todos los enemigos de datos.
func _physics_process(delta: float) -> void:
	tick += 1
	var vis := EnemyVisuals.instance
	var tick_f := float(tick)
	var i := 0
	while i < _active.size():
		var e: EnemyData = _active[i]
		e.tick_age += 1
		if e.tick_age >= e.tick_span:
			# Actualiza con el tiempo acumulado de los ticks que se saltó
			var dt := delta * float(e.tick_age)
			e.tick_age = 0
			e.update(dt)
			if vis != null:
				vis.write(e, tick_f)
		# Si e (u otro anterior) se recicló durante su update, la lista se desplazó: no se avanza
		if i < _active.size() and _active[i] == e:
			i += 1

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

static func active_count() -> int:
	return instance._active.size() if instance != null else 0
