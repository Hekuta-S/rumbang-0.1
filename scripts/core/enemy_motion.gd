class_name EnemyMotion
extends RefCounted

## Movimiento de enemigos SIN move_and_slide: se integra la posición a mano y se resuelve contra
##  - el relieve del mapa procedural (altura bilineal, sin colisión de malla),
##  - sus pendientes (no suben acantilados),
##  - los props con colisión (cilindros y cajas) vía una rejilla de obstáculos, y
##  - el jugador (no se meten dentro de él).
## El CharacterBody3D del enemigo sigue existiendo como objetivo de golpes; solo se mueve por asignación.

const CELL := 4.0                      ## celdas pequeñas: menos obstáculos que mirar por enemigo
const ENEMY_RADIUS := 0.45
const PLAYER_RADIUS := 0.5

static var _map: Node = null
## Obstáculos por celda, empaquetados (es el bucle más caliente del movimiento: sin diccionarios ni
## Arrays nuevos). Cada obstáculo son OBS_STRIDE floats:
##   centro x, centro z, alcance (radio que lo envuelve), tipo (0 cilindro / 1 caja), yaw, mitad x, mitad z
## (en un cilindro "mitad x" es su radio).
## Rejilla densa sobre el rectángulo que cubren los obstáculos: la celda (cx, cz) es el índice
## (cz - _oz0) * _ow + (cx - _ox0); sus obstáculos están seguidos en _obs desde _ocell_start, y son
## _ocell_count. Así cada paso de cada enemigo es aritmética + lecturas de arrays (sin hash de Vector2i).
const OBS_STRIDE := 7
static var _obs: PackedFloat32Array = PackedFloat32Array()
static var _ocell_start: PackedInt32Array = PackedInt32Array()
static var _ocell_count: PackedInt32Array = PackedInt32Array()
static var _ox0: int = 0
static var _oz0: int = 0
static var _ow: int = 0                 ## ancho de la rejilla en celdas (0 = sin obstáculos)
static var _oh: int = 0
static var _built: bool = false
## Copia local de la malla de alturas del mapa: se evita una llamada a método del nodo por cada consulta.
static var _hs: PackedFloat32Array = PackedFloat32Array()
static var _hside: int = 0
static var _hhalf: float = 0.0
static var _hcell: float = 1.0

## true si hay mapa procedural con altura (si no, el enemigo usa move_and_slide como antes).
static func available() -> bool:
	if _map != null and is_instance_valid(_map):
		return true                       # camino rápido: se llama en cada paso de cada enemigo
	_map = null
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		var m := tree.get_first_node_in_group("procedural_map")
		if m and m.has_method("get_height_at") and m.has_method("get_colliders"):
			_map = m
			_built = false
	return _map != null

## Olvida el mapa y los obstáculos (cambio de escena / reinicio).
static func reset() -> void:
	_map = null
	_clear_obstacles()
	_hs = PackedFloat32Array()
	_hside = 0
	_built = false

static func _build() -> void:
	_built = true
	var hs = _map.get("_heights")
	var side = _map.get("_side")
	if hs is PackedFloat32Array and side != null and int(side) > 1 and (hs as PackedFloat32Array).size() >= int(side) * int(side):
		_hs = hs
		_hside = int(side)
		_hhalf = float(_map.get("half_size"))
		_hcell = float(_map.get("cell_size"))
	else:
		_hside = 0
	# Primero por celdas en un diccionario temporal (solo al construir), luego se aplana a la rejilla densa
	var grid: Dictionary = {}             # Vector2i -> PackedFloat32Array
	for o in _map.get_colliders():
		var c: Vector2 = o["pos"]
		var reach: float = o["r"]
		var is_cyl: bool = o["shape"] == "cyl"
		var half: Vector2 = o.get("half", Vector2.ZERO)
		var packed := PackedFloat32Array([c.x, c.y, reach, 0.0 if is_cyl else 1.0, float(o.get("yaw", 0.0)),
			reach if is_cyl else half.x, 0.0 if is_cyl else half.y])
		var c0 := Vector2i(int(floor((c.x - reach) / CELL)), int(floor((c.y - reach) / CELL)))
		var c1 := Vector2i(int(floor((c.x + reach) / CELL)), int(floor((c.y + reach) / CELL)))
		for cx in range(c0.x, c1.x + 1):
			for cz in range(c0.y, c1.y + 1):
				var k := Vector2i(cx, cz)
				# Se vuelve a guardar: `(grid[k] as PackedFloat32Array).append_array()` trabajaría
				# sobre una copia y la celda se quedaría solo con su primer obstáculo.
				var cur: PackedFloat32Array = grid.get(k, PackedFloat32Array())
				cur.append_array(packed)
				grid[k] = cur
	_flatten_obstacles(grid)

static func _clear_obstacles() -> void:
	_obs = PackedFloat32Array()
	_ocell_start = PackedInt32Array()
	_ocell_count = PackedInt32Array()
	_ow = 0
	_oh = 0

## Pasa los obstáculos por celda a la rejilla densa (mismo orden de obstáculos dentro de cada celda).
static func _flatten_obstacles(grid: Dictionary) -> void:
	_clear_obstacles()
	if grid.is_empty():
		return
	var x0 := 1 << 30
	var z0 := 1 << 30
	var x1 := -(1 << 30)
	var z1 := -(1 << 30)
	for k: Vector2i in grid:
		x0 = mini(x0, k.x)
		z0 = mini(z0, k.y)
		x1 = maxi(x1, k.x)
		z1 = maxi(z1, k.y)
	_ox0 = x0
	_oz0 = z0
	_ow = x1 - x0 + 1
	_oh = z1 - z0 + 1
	_ocell_start.resize(_ow * _oh)
	_ocell_count.resize(_ow * _oh)
	_ocell_start.fill(0)
	_ocell_count.fill(0)
	for k: Vector2i in grid:
		var cell: PackedFloat32Array = grid[k]
		var ci := (k.y - _oz0) * _ow + (k.x - _ox0)
		_ocell_start[ci] = _obs.size()
		_ocell_count[ci] = cell.size() / OBS_STRIDE
		_obs.append_array(cell)

static func height_at(x: float, z: float) -> float:
	if not _built:
		_build()
	if _hside == 0:
		return _map.get_height_at(x, z)
	# Misma interpolación bilineal que ProceduralMap.get_height_at, sobre la copia local
	var lim := float(_hside - 1) - 0.001
	var fx := clampf((x + _hhalf) / _hcell, 0.0, lim)
	var fz := clampf((z + _hhalf) / _hcell, 0.0, lim)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - float(ix)
	var tz := fz - float(iz)
	var i0 := iz * _hside + ix
	var i1 := i0 + _hside
	var a := _hs[i0] + (_hs[i0 + 1] - _hs[i0]) * tx
	var b := _hs[i1] + (_hs[i1 + 1] - _hs[i1]) * tx
	return a + (b - a) * tz

## Mueve al enemigo con su velocidad actual durante `delta` segundos (horizontal; la altura la da el mapa).
static func move(e, vel: Vector3, delta: float, player_pos: Vector3) -> void:
	if not _built:
		_build()
	var p: Vector3 = e.global_position
	var step := Vector2(vel.x, vel.z) * delta
	var np := Vector2(p.x, p.z)
	var h_new: float = e.ground_y            # altura donde está ahora (se guarda para no recalcularla)
	if step.length_squared() > 0.0000001:
		var h_now: float = h_new
		var max_rise := maxf(step.length() * 1.3, 0.03)   # pendiente máx. ~50°
		var target := np + step
		var h_t := height_at(target.x, target.y)
		if h_t - h_now <= max_rise:
			np = target
			h_new = h_t
		else:
			# Pendiente demasiado dura: se intenta deslizar por un eje
			var tx := Vector2(np.x + step.x, np.y)
			var tz := Vector2(np.x, np.y + step.y)
			var h_x := height_at(tx.x, tx.y)
			if h_x - h_now <= max_rise:
				np = tx
				h_new = h_x
			else:
				var h_z := height_at(tz.x, tz.y)
				if h_z - h_now <= max_rise:
					np = tz
					h_new = h_z
		var before := np
		np = _push_out_of_obstacles(np)
		np = _push_out_of_player(np, player_pos)
		if np != before:
			h_new = height_at(np.x, np.y)
	e.global_position = Vector3(np.x, h_new, np.y)
	e.ground_y = h_new

static func _push_out_of_obstacles(p: Vector2) -> Vector2:
	var gx := int(floor(p.x / CELL)) - _ox0
	var gz := int(floor(p.y / CELL)) - _oz0
	if gx < 0 or gz < 0 or gx >= _ow or gz >= _oh:
		return p
	var ci := gz * _ow + gx
	var cnt := _ocell_count[ci]
	if cnt == 0:
		return p                              # la mayoría de celdas no tienen obstáculos
	var obs := _obs
	var i := _ocell_start[ci]
	var n := i + cnt * OBS_STRIDE
	while i < n:
		var cx := obs[i]
		var cz := obs[i + 1]
		var dx := p.x - cx
		var dz := p.y - cz
		var reach := obs[i + 2] + ENEMY_RADIUS
		var kind := obs[i + 3]
		var yaw := obs[i + 4]
		var hx := obs[i + 5]
		var hz := obs[i + 6]
		i += OBS_STRIDE
		# Descarte rápido: fuera del círculo que envuelve al obstáculo
		if dx * dx + dz * dz >= reach * reach:
			continue
		var c := Vector2(cx, cz)
		if kind == 0.0:
			var r := hx + ENEMY_RADIUS
			var d := p - c
			var dist := d.length()
			if dist < r:
				p = c + (d / dist if dist > 0.0001 else Vector2.RIGHT) * r
		else:
			# Caja orientada: se pasa al marco local, se calcula el punto más cercano y se empuja hacia fuera
			var half := Vector2(hx, hz)
			var local := (p - c).rotated(-yaw)
			var closest := Vector2(clampf(local.x, -half.x, half.x), clampf(local.y, -half.y, half.y))
			var delta := local - closest
			var dist := delta.length()
			if dist < ENEMY_RADIUS:
				if dist > 0.0001:
					local = closest + delta / dist * ENEMY_RADIUS
				else:
					# Dentro de la caja: sale por el lado más cercano
					var gap_x := half.x - absf(local.x)
					var gap_z := half.y - absf(local.y)
					if gap_x < gap_z:
						local.x = signf(local.x if local.x != 0.0 else 1.0) * (half.x + ENEMY_RADIUS)
					else:
						local.y = signf(local.y if local.y != 0.0 else 1.0) * (half.y + ENEMY_RADIUS)
				p = c + local.rotated(yaw)
	return p

static func _push_out_of_player(p: Vector2, player_pos: Vector3) -> Vector2:
	var pc := Vector2(player_pos.x, player_pos.z)
	var d := p - pc
	var r := ENEMY_RADIUS + PLAYER_RADIUS
	var dist := d.length()
	if dist < r and dist > 0.0001:
		return pc + d / dist * r
	return p
