class_name EnemyRegistry
extends RefCounted

## Lista única de enemigos vivos. Sustituye a get_nodes_in_group("enemies") en los
## bucles por frame (armas, orbes, proyectiles): no crea un Array nuevo en cada llamada.
## Los enemigos se registran en _ready() y se dan de baja al salir del árbol (o al morir).
## all() devuelve la lista interna: se puede recorrer, pero NO modificar.

static var _enemies: Array = []
## Posición de cada objeto dentro de _enemies (objeto -> índice): alta/baja en O(1) con swap-remove.
static var _index: Dictionary = {}

## Rejilla espacial (celdas de CELL m en XZ) para consultar "enemigos cerca de X" sin recorrerlos todos.
## Se reconstruye como mucho una vez por frame de física, la primera vez que alguien consulta.
## Los Arrays de las celdas se reutilizan entre reconstrucciones (no se reserva memoria cada frame).
const CELL := 6.0
static var _grid: Dictionary = {}
static var _grid_frame: int = -1
static var _query_buf: Array = []

## Clave entera de una celda (más rápida que un Vector2i como clave de Dictionary: la rejilla se
## reconstruye con todos los enemigos en cada tick de física).
static func _key(cx: int, cz: int) -> int:
	return (cx + 32768) * 65536 + (cz + 32768)

static func _cell_of(x: float, z: float) -> Vector2i:
	return Vector2i(int(floor(x / CELL)), int(floor(z / CELL)))

static func _rebuild_grid() -> void:
	for cell in _grid.values():
		(cell as Array).clear()
	var inv := 1.0 / CELL
	for e in _enemies:
		var p: Vector3 = e.global_position
		var k := (int(floor(p.x * inv)) + 32768) * 65536 + (int(floor(p.z * inv)) + 32768)
		var cell = _grid.get(k)
		if cell == null:
			_grid[k] = [e]
		else:
			(cell as Array).append(e)

## Enemigos a distancia <= radius de `pos` (distancia 3D). Devuelve un Array nuevo, se puede modificar.
static func query_radius(pos: Vector3, radius: float) -> Array:
	var out: Array = []
	query_radius_into(pos, radius, out)
	return out

## Igual que query_radius pero rellena `out` (que se vacía antes): permite reutilizar el Array en bucles calientes.
static func query_radius_into(pos: Vector3, radius: float, out: Array) -> void:
	out.clear()
	var frame := Engine.get_physics_frames()
	if frame != _grid_frame:
		_grid_frame = frame
		_rebuild_grid()
	var r2 := radius * radius
	var c0 := _cell_of(pos.x - radius, pos.z - radius)
	var c1 := _cell_of(pos.x + radius, pos.z + radius)
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			var cell = _grid.get(_key(cx, cz))
			if cell == null:
				continue
			for e in cell:
				if e.global_position.distance_squared_to(pos) <= r2:
					out.append(e)

## Empuje de separación horizontal sobre `me` respecto a los vecinos a menos de `radius` (sin Arrays ni
## Vector3 intermedios: es el bucle más caliente de la IA). Cada vecino empuja con (1 - d/radius).
## En un enjambre denso basta con los SEP_MAX_NEIGHBORS primeros vecinos que tocan (si no, el coste
## crece con el cuadrado de la multitud).
const SEP_MAX_NEIGHBORS := 6

static func separation_push(me: Object, radius: float) -> Vector3:
	var frame := Engine.get_physics_frames()
	if frame != _grid_frame:
		_grid_frame = frame
		_rebuild_grid()
	var p: Vector3 = me.global_position
	var px := p.x
	var pz := p.z
	var r2 := radius * radius
	var pushx := 0.0
	var pushz := 0.0
	var found := 0
	var c0 := _cell_of(px - radius, pz - radius)
	var c1 := _cell_of(px + radius, pz + radius)
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			var cell = _grid.get(_key(cx, cz))
			if cell == null:
				continue
			for o in cell:
				if o == me:
					continue
				var q: Vector3 = o.global_position
				var ax := px - q.x
				var az := pz - q.z
				var d2 := ax * ax + az * az
				if d2 > r2 or absf(p.y - q.y) > radius:
					continue
				if d2 < 0.0001:
					ax = randf() - 0.5
					az = randf() - 0.5
					d2 = 0.25
				var d := sqrt(d2)
				var w := (1.0 - d / radius) / d
				pushx += ax * w
				pushz += az * w
				found += 1
				if found >= SEP_MAX_NEIGHBORS:
					return Vector3(pushx, 0.0, pushz)
	return Vector3(pushx, 0.0, pushz)

static func register(e: Object) -> void:
	if not _index.has(e):
		_index[e] = _enemies.size()
		_enemies.append(e)
	# Solo los enemigos-nodo (jefes) avisan al salir del árbol; los enemigos de datos se dan de baja a mano
	if e is Node:
		var cb := unregister.bind(e)
		if not (e as Node).tree_exiting.is_connected(cb):
			(e as Node).tree_exiting.connect(cb, CONNECT_ONE_SHOT)

## Baja en O(1): el último ocupa el hueco (el orden de all() no está garantizado).
static func unregister(e: Object) -> void:
	var idx: int = _index.get(e, -1)
	if idx < 0:
		return
	var last = _enemies.pop_back()
	if last != e:
		_enemies[idx] = last
		_index[last] = idx
	_index.erase(e)
	# La rejilla de este tick aún lo contiene: se rehace en la próxima consulta (si no, un enemigo dado de
	# baja y liberado en el mismo tick se leería ya liberado)
	_grid_frame = -1

static func all() -> Array:
	return _enemies

static func count() -> int:
	return _enemies.size()

static func clear() -> void:
	_enemies.clear()
	_index.clear()
	_grid.clear()
	_grid_frame = -1
	AttackTokens.clear()
