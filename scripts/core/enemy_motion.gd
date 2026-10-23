class_name EnemyMotion
extends RefCounted

## Movimiento de enemigos SIN move_and_slide: se integra la posición a mano y se resuelve contra
##  - el relieve del mapa procedural (altura bilineal, sin colisión de malla),
##  - sus pendientes (no suben acantilados),
##  - los props con colisión (cilindros y cajas) vía una rejilla de obstáculos, y
##  - el jugador (no se meten dentro de él).
## El CharacterBody3D del enemigo sigue existiendo como objetivo de golpes; solo se mueve por asignación.

const CELL := 8.0
const ENEMY_RADIUS := 0.45
const PLAYER_RADIUS := 0.5

static var _map: Node = null
static var _grid: Dictionary = {}       # Vector2i -> Array[Dictionary] de obstáculos
static var _built: bool = false
## Copia local de la malla de alturas del mapa: se evita una llamada a método del nodo por cada consulta.
static var _hs: PackedFloat32Array = PackedFloat32Array()
static var _hside: int = 0
static var _hhalf: float = 0.0
static var _hcell: float = 1.0

## true si hay mapa procedural con altura (si no, el enemigo usa move_and_slide como antes).
static func available() -> bool:
	if _map == null or not is_instance_valid(_map):
		var tree := Engine.get_main_loop() as SceneTree
		if tree:
			var m := tree.get_first_node_in_group("procedural_map")
			if m and m.has_method("get_height_at") and m.has_method("get_colliders"):
				_map = m
				_built = false
	return _map != null and is_instance_valid(_map)

## Olvida el mapa y los obstáculos (cambio de escena / reinicio).
static func reset() -> void:
	_map = null
	_grid.clear()
	_hs = PackedFloat32Array()
	_hside = 0
	_built = false

static func _build() -> void:
	_built = true
	_grid.clear()
	var hs = _map.get("_heights")
	var side = _map.get("_side")
	if hs is PackedFloat32Array and side != null and int(side) > 1 and (hs as PackedFloat32Array).size() >= int(side) * int(side):
		_hs = hs
		_hside = int(side)
		_hhalf = float(_map.get("half_size"))
		_hcell = float(_map.get("cell_size"))
	else:
		_hside = 0
	for o in _map.get_colliders():
		var c: Vector2 = o["pos"]
		var reach: float = o["r"]
		var c0 := Vector2i(int(floor((c.x - reach) / CELL)), int(floor((c.y - reach) / CELL)))
		var c1 := Vector2i(int(floor((c.x + reach) / CELL)), int(floor((c.y + reach) / CELL)))
		for cx in range(c0.x, c1.x + 1):
			for cz in range(c0.y, c1.y + 1):
				var k := Vector2i(cx, cz)
				if _grid.has(k):
					(_grid[k] as Array).append(o)
				else:
					_grid[k] = [o]

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
	var cell: Array = _grid.get(Vector2i(int(floor(p.x / CELL)), int(floor(p.y / CELL))), [])
	for o in cell:
		var c: Vector2 = o["pos"]
		if o["shape"] == "cyl":
			var r: float = float(o["r"]) + ENEMY_RADIUS
			var d := p - c
			var dist := d.length()
			if dist < r:
				p = c + (d / dist if dist > 0.0001 else Vector2.RIGHT) * r
		else:
			# Caja orientada: se pasa al marco local, se calcula el punto más cercano y se empuja hacia fuera
			var yaw: float = o["yaw"]
			var half: Vector2 = o["half"]
			var local := (p - c).rotated(-yaw)
			var closest := Vector2(clampf(local.x, -half.x, half.x), clampf(local.y, -half.y, half.y))
			var delta := local - closest
			var dist := delta.length()
			if dist < ENEMY_RADIUS:
				if dist > 0.0001:
					local = closest + delta / dist * ENEMY_RADIUS
				else:
					# Dentro de la caja: sale por el lado más cercano
					var dx := half.x - absf(local.x)
					var dy := half.y - absf(local.y)
					if dx < dy:
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
