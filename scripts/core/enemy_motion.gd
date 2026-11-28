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
## Movimiento en C++ (bin/rumbang_native.gdextension, código en native/src/enemy_motion_native.cpp): mismo
## algoritmo que move() de aquí, unas 10-20 veces más rápido. Si la extensión no está (Web, falta la
## biblioteca) se usa el GDScript. RUMBANG_NATIVE=0 lo desactiva (comparar).
static var native_enabled: bool = OS.get_environment("RUMBANG_NATIVE") != "0"
static var _native: Object = null

## true si el movimiento va por C++ ahora mismo (pruebas / banco).
static func using_native() -> bool:
	return _native != null

## EnemyMotionNative del mapa actual (construye los datos si hace falta) o null. Lo usa EnemySimNative.
static func native_motion() -> Object:
	if not available():
		return null
	if not _built:
		_build()
	return _native

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
	_mesas.clear()
	_player_mesa = -1
	_climb_half = 0.0
	_bridges.clear()
	_bpk = PackedFloat32Array()
	_native = null

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

	# Mesetas (ProceduralMap): copia empaquetada para el enrutado hacia las rampas
	_mesas.clear()
	if _map.has_method("get_mesas"):
		for m in _map.get_mesas():
			var dirs: Array = []
			for rp in m["ramps"]:
				dirs.append([rp["dir"], float(rp["len"])])
			_mesas.append([m["c"], float(m["r"]), float(m["top"]), int(m["parent"]), dirs, float(m["base"])])
	_route_frame = -1
	_player_mesa = -1
	_climb_half = float(_map.get("play_half")) - 1.0 if not _mesas.is_empty() and _map.get("play_half") != null else 0.0
	_bridges.clear()
	if _map.has_method("get_bridges"):
		for br in _map.get_bridges():
			_bridges.append([br["a"], br["b"], float(br["ya"]), float(br["yb"]), float(br["half"])])
	_pack_bridges()
	_setup_native()

## Pasa al C++ los mismos datos empaquetados (relieve, obstáculos, puentes). Solo con malla de alturas local.
static func _setup_native() -> void:
	_native = null
	if not native_enabled or _hside == 0 or not ClassDB.class_exists(&"EnemyMotionNative"):
		return
	_native = ClassDB.instantiate(&"EnemyMotionNative")
	_native.set_heights(_hs, _hside, _hhalf, _hcell, _climb_half)
	_native.set_obstacles(_obs, _ocell_start, _ocell_count, _ox0, _oz0, _ow, _oh)
	_native.set_bridges(_bpk)

# ───────────────────────────── Puentes ─────────────────────────────
## Otra capa de suelo sobre el relieve: quien entra desde la cima (a la altura de la tabla) camina por
## la tabla, sin salirse por las barandillas, hasta el otro extremo. Por debajo se pasa como siempre.
## [a: Vector2, b: Vector2, altura en a, altura en b, media anchura]
static var _bridges: Array = []
## Copia plana de _bridges para el bucle caliente de step_layers (cada enemigo en cada paso la recorre):
## sin Arrays sin tipo ni normalized() por enemigo, y con descarte por caja. BSTRIDE floats por puente:
## ax, az, abx, abz, 1/|ab|², perp_x, perp_z (unitario), lim lateral, ya, yb, min_x, max_x, min_z, max_z
const BSTRIDE := 14
static var _bpk := PackedFloat32Array()

static func _pack_bridges() -> void:
	_bpk = PackedFloat32Array()
	for br: Array in _bridges:
		var a: Vector2 = br[0]
		var bb: Vector2 = br[1]
		var ab := bb - a
		var perp := Vector2(-ab.y, ab.x).normalized()
		var lim := float(br[4]) - ENEMY_RADIUS
		var pad := absf(lim)
		_bpk.append_array(PackedFloat32Array([a.x, a.y, ab.x, ab.y, 1.0 / ab.length_squared(), perp.x, perp.y, lim,
				float(br[2]), float(br[3]),
				minf(a.x, bb.x) - pad, maxf(a.x, bb.x) + pad, minf(a.y, bb.y) - pad, maxf(a.y, bb.y) + pad]))
const BRIDGE_ENTER_TOL := 0.7          ## diferencia de altura con la tabla para subirse

## Un paso con puentes: Vector4(x, z, altura, puente en que queda o -1).
static func step_layers(np: Vector2, step: Vector2, h_now: float, bridge_i: int) -> Vector4:
	if not _built:
		_build()
	if bridge_i >= 0 and bridge_i < _bridges.size():
		var br: Array = _bridges[bridge_i]
		var a: Vector2 = br[0]
		var ab: Vector2 = (br[1] as Vector2) - a
		var blen := ab.length()
		var d := ab / blen
		var side := Vector2(-d.y, d.x)
		var target := np + step
		var rel := target - a
		var lim := float(br[4]) - ENEMY_RADIUS
		var lat := clampf(rel.dot(side), -lim, lim)          # las barandillas no dejan salir
		var along := rel.dot(d)
		target = a + d * along + side * lat
		var t := along / blen
		if t < 0.0 or t > 1.0:
			return Vector4(target.x, target.y, height_at(target.x, target.y), -1)   # baja en la cima
		return Vector4(target.x, target.y, lerpf(float(br[2]), float(br[3]), t), bridge_i)
	var r := resolve_step(np, step, h_now)
	var qx := r.x
	var qz := r.y
	var bp := _bpk
	var n := bp.size()
	var o := 0
	while o < n:
		if qx < bp[o + 10] or qx > bp[o + 11] or qz < bp[o + 12] or qz > bp[o + 13]:
			o += BSTRIDE
			continue
		var rx := qx - bp[o]
		var rz := qz - bp[o + 1]
		var t := (rx * bp[o + 2] + rz * bp[o + 3]) * bp[o + 4]
		if t >= 0.0 and t <= 1.0 and absf(rx * bp[o + 5] + rz * bp[o + 6]) <= bp[o + 7]:
			var deck := lerpf(bp[o + 8], bp[o + 9], t)
			if absf(deck - h_now) < BRIDGE_ENTER_TOL:
				return Vector4(qx, qz, deck, o / BSTRIDE)
		o += BSTRIDE
	return Vector4(r.x, r.y, r.z, -1)

# ───────────────────────────── Mesetas ─────────────────────────────
## Los enemigos van en línea recta y trepan las paredes (CLIMB_MULT). Aquí solo se sabe si el jugador
## está arriba de una meseta (ventaja de altura, aviso de RunEvents).

## [centro: Vector2, radio, altura de la cima, piso de abajo (-1), [[dir: Vector2, largo], ...], altura del pie]
static var _mesas: Array = []
static var _route_frame: int = -1
static var _player_mesa: int = -1
## Dentro del radio + esto y a la altura de la cima = está arriba (el borde real es irregular, ±7 %:
## lo que decide es la altura)
const MESA_ON_MARGIN := 2.0
const MESA_TOP_TOL := 1.4              ## m por debajo de la cima que aún cuentan como "arriba"
const RAMP_HALF := 2.6                 ## = ProceduralMap.RAMP_HALF_W

## ¿Está arriba de la meseta i? Para el jugador (`ramp_top`) también cuenta la mitad alta de una rampa:
## desde ahí ya domina a los de abajo. Para los enemigos solo la cima, así terminan de subir la rampa.
static func _on_mesa(i: int, p: Vector2, y: float, ramp_top: bool = false) -> bool:
	var m: Array = _mesas[i]
	if y < float(m[2]) - MESA_TOP_TOL:
		return false
	if p.distance_to(m[0]) < float(m[1]) + MESA_ON_MARGIN:
		return true
	if not ramp_top:
		return false
	var ramp := _ramp_at(i, p, y)
	return ramp >= 0 and (p - (m[0] as Vector2)).dot(m[4][ramp][0]) < float(m[1]) + float(m[4][ramp][1]) * 0.5

## Rampa de la meseta i en cuyo pasillo está p, a la altura y de su superficie (índice en m[4]); -1 si
## en ninguna. Quien va pegado al lateral, por debajo, no cuenta: tiene que ir al pie.
static func _ramp_at(i: int, p: Vector2, y: float) -> int:
	var m: Array = _mesas[i]
	var rel: Vector2 = p - (m[0] as Vector2)
	var r: float = m[1]
	var ramps: Array = m[4]
	for k in ramps.size():
		var d: Vector2 = ramps[k][0]
		var u := rel.dot(d)
		var rlen: float = ramps[k][1]
		# Solo la parte llana del pasillo: en el borde, el lateral cae en pendiente
		if u > r - 3.0 and u < r + rlen + 1.5 and absf(rel.cross(d)) < RAMP_HALF - 0.3:
			var mid: Vector2 = (m[0] as Vector2) + d * u          # superficie: línea central a la misma altura de rampa
			if y >= height_at(mid.x, mid.y) - 0.45:
				return k
	return -1

## Meseta en la que está el jugador (la más alta), calculada una vez por tick de física.
static func _update_player_mesa(player_pos: Vector3) -> void:
	var f := Engine.get_physics_frames()
	if f == _route_frame:
		return
	_route_frame = f
	_player_mesa = -1
	var pp := Vector2(player_pos.x, player_pos.z)
	var best := -INF
	for i in _mesas.size():
		if float(_mesas[i][2]) > best and _on_mesa(i, pp, player_pos.y, true):
			best = float(_mesas[i][2])
			_player_mesa = i

## Altura de la tabla del puente i a la altura de p.
static func bridge_deck(i: int, p: Vector2) -> float:
	var br: Array = _bridges[i]
	var a: Vector2 = br[0]
	var ab: Vector2 = (br[1] as Vector2) - a
	return lerpf(float(br[2]), float(br[3]), clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0))

## true si el mapa tiene mesetas (relieve jugable).
static func has_relief() -> bool:
	if not _built and available():
		_build()
	return not _mesas.is_empty()

## Índice de la meseta en la que está el jugador (-1 = abajo). Barato: se calcula una vez por tick.
static func player_mesa(player_pos: Vector3) -> int:
	if not has_relief():
		return -1
	_update_player_mesa(player_pos)
	return _player_mesa

## Quita los obstáculos cuyo centro está a menos de `radius` de `center` (un muro o una tubería rotos abren paso).
## Se marcan lejos y sin alcance en su sitio (la rejilla no se rehace) y se pasan otra vez al C++. Devuelve cuántas
## copias quitó (un obstáculo grande está copiado en cada celda que toca).
static func remove_obstacles_near(center: Vector2, radius: float) -> int:
	if not _built:
		_build()
	var n := 0
	var r2 := radius * radius
	var i := 0
	while i < _obs.size():
		var dx := _obs[i] - center.x
		var dz := _obs[i + 1] - center.y
		if dx * dx + dz * dz <= r2 and _obs[i + 2] > 0.0:
			_obs[i] = 1.0e9
			_obs[i + 1] = 1.0e9
			_obs[i + 2] = 0.0
			n += 1
		i += OBS_STRIDE
	if n > 0 and _native != null:
		_native.set_obstacles(_obs, _ocell_start, _ocell_count, _ox0, _oz0, _ow, _oh)
	return n

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

## Paredes de meseta: los enemigos las trepan, a esta fracción de su velocidad (en las rampas van normal).
## Los acantilados del borde del mapa (fuera de _climb_half) siguen sin poder subirse.
const CLIMB_MULT := 0.4
static var _climb_half: float = 0.0     ## 0 = no se trepa (mapa sin mesetas)

## Un paso `step` desde `np` (altura `h_now`) contra el relieve: Vector3(x, z, altura nueva).
## Pendiente suave: avanza. Pared de meseta: trepa a CLIMB_MULT. Acantilado del borde: desliza por un eje.
static func resolve_step(np: Vector2, step: Vector2, h_now: float) -> Vector3:
	if not _built:
		_build()
	var max_rise := maxf(step.length() * 1.3, 0.03)   # pendiente máx. ~50°
	var target := np + step
	var h_t := height_at(target.x, target.y)
	if h_t - h_now <= max_rise:
		return Vector3(target.x, target.y, h_t)
	if absf(target.x) < _climb_half and absf(target.y) < _climb_half:
		var c := np + step * CLIMB_MULT                  # pared de meseta: trepa, más despacio
		return Vector3(c.x, c.y, height_at(c.x, c.y))
	# Pendiente demasiado dura: se intenta deslizar por un eje
	var tx := Vector2(np.x + step.x, np.y)
	var h_x := height_at(tx.x, tx.y)
	if h_x - h_now <= max_rise:
		return Vector3(tx.x, tx.y, h_x)
	var tz := Vector2(np.x, np.y + step.y)
	var h_z := height_at(tz.x, tz.y)
	if h_z - h_now <= max_rise:
		return Vector3(tz.x, tz.y, h_z)
	return Vector3(np.x, np.y, h_now)

## Mueve al enemigo con su velocidad actual durante `delta` segundos (horizontal; la altura la da el mapa).
static func move(e: EnemyData, vel: Vector3, delta: float, player_pos: Vector3) -> void:
	if not _built:
		_build()
	var p: Vector3 = e.global_position
	if _native != null:
		var r: Vector4 = _native.move(p.x, p.z, vel.x, vel.z, delta, e.ground_y, e.bridge_i, player_pos.x, player_pos.z)
		e.global_position = Vector3(r.x, r.z, r.y)
		e.ground_y = r.z
		e.bridge_i = int(r.w)
		return
	var step := Vector2(vel.x, vel.z) * delta
	var np := Vector2(p.x, p.z)
	var h_new: float = e.ground_y            # altura donde está ahora (se guarda para no recalcularla)
	if step.length_squared() > 0.0000001:
		var r := step_layers(np, step, h_new, e.bridge_i)
		np = Vector2(r.x, r.y)
		h_new = r.z
		e.bridge_i = int(r.w)
		var before := np
		if e.bridge_i < 0:
			np = _push_out_of_obstacles(np)              # en la tabla no hay props (los pilotes quedan debajo)
		np = _push_out_of_player(np, player_pos)
		if np != before:
			h_new = height_at(np.x, np.y) if e.bridge_i < 0 else bridge_deck(e.bridge_i, np)
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
