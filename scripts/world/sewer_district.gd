class_name SewerDistrict
extends RefCounted

## Barrio del Desagüe: franja de cloacas a cielo abierto en un borde del mapa de Supervivencia
## (ProceduralMap). Historia production/epics/rumbang/story-008.
##
##  - La franja (de DEPTH_START m del centro hasta el acantilado) se allana a nivel de calle.
##  - Un canal principal la recorre a lo largo y varios desagües bajan de él hasta el acantilado, donde
##    salen tuberías gigantes. Los canales son rectos y van alineados con la rejilla del terreno: así su
##    pared ocupa una sola celda y es más empinada (> 52°) de lo que sube nadie andando. Los enemigos la
##    trepan despacio (EnemyMotion.CLIMB_MULT): el canal hace de embudo sin enrutado. El jugador sale por
##    escaleras (rampas cortadas en la orilla), por los puentes o saltando.
##  - Puentes de madera a ras de la orilla (los de ProceduralMap: EnemyMotion los cruza como otra capa).
##  - Agua residual (sewer_water.gdshader, con las ondas de MapReactions) que frena al jugador.
##
## El tallado es una pasada sobre la malla ya calculada (sirve igual con TerrainNative y con el GDScript),
## antes de crear la colisión y de que EnemyMotion copie las alturas.

const DEPTH_START := 100.0            ## m del centro del mapa donde empieza el barrio (eje del barrio); ver depth_start
const BLEND := 10.0                   ## m de transición entre el campo y la calle
const MAIN_CANAL_U := Vector2(118.0, 124.0)   ## suelo del canal principal (u desde el centro); ver main_canal_u
const CROSS_W := 4.0                  ## ancho del suelo de los desagües
const CROSS_COUNT := 3
const STAIR_W := 3.5                  ## ancho de una escalera (a lo largo del canal)
const STAIR_SLOPE := 0.55             ## pendiente de la escalera (~29°)
const WATER_ABOVE_FLOOR := 0.35       ## el agua cubre los tobillos
const WATER_SLOW := 0.72              ## velocidad del jugador dentro del agua
const BRIDGE_HALF := 1.6
const BRIDGE_OVERHANG := 2.5          ## m que entra el puente en cada orilla
const PIPE_R := 1.35                  ## radio de las tuberías gigantes del acantilado
const WATER_SHADER: Shader = preload("res://assets/shaders/sewer_water.gdshader")
const PIPE_COL := Color(0.24, 0.27, 0.22)
const PIPE_RING_COL := Color(0.14, 0.15, 0.12)
const RUST_COL := Color(0.36, 0.2, 0.1)
const GLOW_COL := Color(0.45, 0.95, 0.3)
const PIPE_BARRIERS := 2
const BRICK_WALLS := 2
const WALL_H := 2.6
const WALL_THICK := 0.7
const GATE_THICK := 0.35
const HP_BY_KIND := {"pipe": 80.0, "wall": 110.0, "gate": 45.0}
const FLOOD_TIME := 1.4               ## s que tarda el agua en llenar un desagüe
const FLOOD_KNOCK := 16.0
const FLOOD_FRAC := 0.55              ## fracción de la vida que quita la ola (élites: un tercio)
const FLOOD_MIN_DAMAGE := 30.0
const BRICK_COL := Color(0.55, 0.3, 0.22)
const GATE_WOOD := Color(0.36, 0.24, 0.14)
const IRON_COL := Color(0.2, 0.21, 0.22)
const WATER_TINT := Color(0.45, 0.6, 0.4)
const TEX_DIR := "res://assets/textures/dungeon/"
const BRICK_TINT := Color(0.95, 0.62, 0.5)
const BRICK_UV := 0.5                  ## la textura cubre 2 m (= sewer_brick.gdshader brick_tex_m)

var _map: ProceduralMap
## Mapa de Cloacas (ProceduralMap.theme "sewers"): un barrio a cada lado, más ancho (ProceduralMap._pick_layout).
var depth_start: float = DEPTH_START
var main_canal_u: Vector2 = MAIN_CANAL_U
var cross_count: int = CROSS_COUNT
var _rng := RandomNumberGenerator.new()
## Eje del barrio: 0 = x, 1 = z; signo hacia el que queda (u = side_sign * coordenada del eje).
var axis: int = 0
var side_sign: float = 1.0
var street_y: float = 0.0             ## altura de la calle y las orillas
var floor_y: float = 0.0              ## altura del suelo de los canales
var depth: float = 2.2
## Canales: [{min: Vector2, max: Vector2 (rectángulo del suelo en el mundo, x/z), main: bool, cross_v}]
var canals: Array = []
## Escaleras: [{min, max (rectángulo en el mundo), from: Vector2 (punto del borde del suelo), dir: Vector2 (hacia la orilla), len}]
var stairs: Array = []
## Bocas de tubería: [{pos: Vector3 (centro de la boca), dir: Vector3 (hacia fuera del acantilado)}]
var pipes: Array = []
## Tuberías tumbadas en la orilla: [{a: Vector3, b: Vector3, r}]
var bank_pipes: Array = []
## Piezas rompibles: [{kind: "pipe"|"wall"|"gate", a, b: Vector3, half (media anchura), height, canal (compuerta:
## su desagüe), collider (entrada de _colliders), node (SewerBreakable), broken}]
var breakables: Array = []
var _barrier_v: Array = []
## Desagües inundándose: [{canal, t, hit: {}}]
var _floods: Array = []
var _water_mm: MultiMesh
var _water_full: Array = []           ## transformada completa del agua de cada canal
var _colliders: Array = []

func _init(map: ProceduralMap) -> void:
	_map = map

# ───────────────────────────── Coordenadas ─────────────────────────────

## Del marco del barrio (u: hacia el acantilado, v: a lo largo) al mundo (x, z).
func to_world(u: float, v: float) -> Vector2:
	return Vector2(side_sign * u, v) if axis == 0 else Vector2(v, side_sign * u)

func to_local(p: Vector2) -> Vector2:
	return Vector2(side_sign * p.x, p.y) if axis == 0 else Vector2(side_sign * p.y, p.x)

func dir_out() -> Vector2:
	return to_world(1.0, 0.0)

## Coordenada del mundo ajustada a la línea de vértices más cercana de la malla.
func _snap(c: float) -> float:
	var cell: float = _map.cell_size
	var half: float = _map.half_size
	return -half + roundf((c + half) / cell) * cell

## Rectángulo del mundo (ajustado a la malla) a partir de un rango en u y otro en v.
func _rect(u0: float, u1: float, v0: float, v1: float) -> Dictionary:
	var a := to_world(u0, v0)
	var b := to_world(u1, v1)
	return {"min": Vector2(_snap(minf(a.x, b.x)), _snap(minf(a.y, b.y))),
		"max": Vector2(_snap(maxf(a.x, b.x)), _snap(maxf(a.y, b.y)))}

static func _in_rect(p: Vector2, r: Dictionary, grow: float = 0.0) -> bool:
	var mn: Vector2 = r["min"]
	var mx: Vector2 = r["max"]
	return p.x >= mn.x - grow - 0.001 and p.x <= mx.x + grow + 0.001 and p.y >= mn.y - grow - 0.001 and p.y <= mx.y + grow + 0.001

## ¿p está dentro del barrio (con `margin` m de holgura hacia el centro)?
func contains(p: Vector2, margin: float = 0.0) -> bool:
	return to_local(p).x >= depth_start - BLEND - margin

## ¿p cae sobre el suelo de un canal o en una escalera (con holgura)?
func in_canal(p: Vector2, grow: float = 0.0) -> bool:
	for c in canals:
		if _in_rect(p, c, grow):
			return true
	return false

func _in_stair(p: Vector2, grow: float = 0.0) -> bool:
	for s in stairs:
		if _in_rect(p, s, grow):
			return true
	return false

# ───────────────────────────── Distribución ─────────────────────────────

## Elige el borde del barrio, lejos de la cripta. Va antes de las mesetas (que lo evitan).
## force_axis / force_sign (mapa de Cloacas): borde fijo; `salt` cambia el azar del segundo barrio.
func pick_axis(p_seed: int, force_axis: int = -1, force_sign: float = 0.0, salt: int = 0) -> void:
	_rng.seed = (p_seed ^ 0x5E3E) + salt
	depth = maxf(2.2, _map.cell_size * 1.4)        # pared de una celda: pendiente > 1,3 (EnemyMotion sube hasta ~1,3)
	if force_axis >= 0:
		axis = force_axis
		side_sign = force_sign
		return
	var basin_dir: Vector2 = _map.get("_basin_center").normalized()
	var opts: Array = []
	for ax in 2:
		for sg: float in [-1.0, 1.0]:
			var d := Vector2(sg, 0.0) if ax == 0 else Vector2(0.0, sg)
			if d.dot(basin_dir) < 0.5:
				opts.append([ax, sg])
	var pick: Array = opts[_rng.randi() % opts.size()]
	axis = int(pick[0])
	side_sign = float(pick[1])

## Canales, escaleras, tuberías y puentes. Después de las mesetas y de sus puentes (los de aquí se añaden).
func pick_layout() -> void:
	canals.clear()
	stairs.clear()
	pipes.clear()
	bank_pipes.clear()
	_colliders.clear()
	breakables.clear()
	_barrier_v.clear()
	_floods.clear()
	var ph: float = _map.play_half
	# Nivel de la calle: la media del terreno donde empieza el barrio (la transición queda suave)
	var sum := 0.0
	var n := 0
	var v := -ph + 10.0
	while v <= ph - 10.0:
		var p := to_world(depth_start - BLEND, v)
		sum += _map._terrain(p.x, p.y).x
		n += 1
		v += 6.0
	street_y = sum / float(maxi(n, 1)) + 0.2
	floor_y = street_y - depth
	var vend := ph + 2.0
	var main := _rect(main_canal_u.x, main_canal_u.y, -vend, vend)
	main["main"] = true
	canals.append(main)
	var main_u: Vector2 = local_range(main)[0]
	# Desagües hacia el acantilado, repartidos a lo largo (separados ≥ 40 m)
	var slots := [-95.0, -45.0, 5.0, 55.0, 100.0]
	for i in range(slots.size() - 1, 0, -1):     # barajar con la semilla del mapa (shuffle() usa el azar global)
		var j := _rng.randi_range(0, i)
		var tmp: float = slots[i]
		slots[i] = slots[j]
		slots[j] = tmp
	var cross_v: Array = []
	for s: float in slots:
		if cross_v.size() >= cross_count:
			break
		var sv := s + _rng.randf_range(-8.0, 8.0)
		var ok := true
		for o: float in cross_v:
			if absf(o - sv) < 40.0:
				ok = false
		if ok:
			cross_v.append(sv)
	for sv: float in cross_v:
		var c := _rect(main_u.y, ph + 3.0, sv - CROSS_W * 0.5, sv + CROSS_W * 0.5)
		c["main"] = false
		c["cross_v"] = sv
		canals.append(c)
		var mouth := to_world(ph + 1.2, sv)
		var out3 := Vector3(dir_out().x, 0.0, dir_out().y)
		pipes.append({"pos": Vector3(mouth.x, floor_y + PIPE_R * 0.85, mouth.y), "dir": out3})
	# Escaleras: en el canal principal cada ~45 m, alternando orilla; una por desagüe
	var stair_len := depth / STAIR_SLOPE
	var side := 0
	var sv2 := -ph + 18.0 + _rng.randf_range(0.0, 10.0)
	while sv2 < ph - 12.0:
		if _near_any(sv2, cross_v, 8.0):
			sv2 += 6.0
			continue
		if side == 0:
			_add_stair(Vector2(main_u.x, sv2), Vector2(-1.0, 0.0), stair_len)
		else:
			_add_stair(Vector2(main_u.y, sv2), Vector2(1.0, 0.0), stair_len)
		side = 1 - side
		sv2 += _rng.randf_range(38.0, 50.0)
	for sv: float in cross_v:
		var su := _rng.randf_range(main_u.y + 6.0, ph - 8.0)
		var sd := 1.0 if _rng.randf() < 0.5 else -1.0
		_add_stair(Vector2(su, sv + sd * CROSS_W * 0.5), Vector2(0.0, sd), stair_len)
	# Puentes sobre el canal principal (lejos de los cruces y de las escaleras) y uno por desagüe
	var bridges: Array = _map.get("_bridges")
	var bv := -ph + 14.0 + _rng.randf_range(0.0, 12.0)
	while bv < ph - 10.0:
		if not _near_any(bv, cross_v, 9.0) and not _stair_near_v(bv, 5.0):
			var a := to_world(main_u.x - BRIDGE_OVERHANG, bv)
			var b := to_world(main_u.y + BRIDGE_OVERHANG, bv)
			bridges.append({"a": a, "b": b, "ya": street_y, "yb": street_y, "half": BRIDGE_HALF, "ma": -1, "mb": -1, "canal": true})
		bv += _rng.randf_range(42.0, 58.0)
	for sv: float in cross_v:
		for k in 8:
			var bu := _rng.randf_range(main_u.y + 6.0, ph - 7.0)
			var a := to_world(bu, sv - CROSS_W * 0.5 - BRIDGE_OVERHANG)
			var b := to_world(bu, sv + CROSS_W * 0.5 + BRIDGE_OVERHANG)
			if _in_stair(a, 2.0) or _in_stair(b, 2.0) or _in_stair((a + b) * 0.5, 2.0):
				continue
			bridges.append({"a": a, "b": b, "ya": street_y, "yb": street_y, "half": BRIDGE_HALF, "ma": -1, "mb": -1, "canal": true})
			break
	# Tuberías gigantes tumbadas de través en la calle de dentro: cortan el paso a lo largo (romperlas = atajo)
	var placed := 0
	for tries in 30:
		if placed >= PIPE_BARRIERS:
			break
		var pv := _rng.randf_range(-ph + 25.0, ph - 25.0)
		if _stair_near_v(pv, 6.0) or _near_any(pv, cross_v, 10.0) or _near_any(pv, _barrier_v, 30.0):
			continue
		var a := to_world(depth_start - 1.0, pv)
		var b := to_world(main_u.x - 0.8, pv)
		if _bridge_near(a, b, bridges, 4.0):
			continue
		var r := _rng.randf_range(0.8, 0.95)
		_add_breakable("pipe", Vector3(a.x, street_y + r, a.y), Vector3(b.x, street_y + r, b.y), r, r * 2.0, -1)
		bank_pipes.append({"a": Vector3(a.x, street_y + r, a.y), "b": Vector3(b.x, street_y + r, b.y), "r": r})
		_barrier_v.append(pv)
		placed += 1
	# Muros de ladrillo de través en la calle de fuera, entre desagües (romperlos = atajo)
	var sorted_v := cross_v.duplicate()
	sorted_v.sort()
	var gaps: Array = []
	var prev := -ph
	for cv: float in sorted_v + [ph]:
		if cv - prev > 24.0:
			gaps.append((prev + cv) * 0.5)
		prev = cv
	placed = 0
	for gv: float in gaps:
		if placed >= BRICK_WALLS:
			break
		for tries in 8:                        # en el hueco entre desagües, sin escalera ni puente al lado
			var wv := gv + _rng.randf_range(-8.0, 8.0)
			if _stair_near_v(wv, 5.0):
				continue
			var a := to_world(main_u.y + 0.6, wv)
			var b := to_world(ph + 0.5, wv)
			if _bridge_near(a, b, bridges, 3.0):
				continue
			_add_breakable("wall", Vector3(a.x, street_y, a.y), Vector3(b.x, street_y, b.y), WALL_THICK * 0.5, WALL_H, -1)
			placed += 1
			break
	# Compuertas: cada desagüe empieza seco, cerrado por una compuerta donde sale del canal principal
	for ci in range(1, canals.size()):
		var c: Dictionary = canals[ci]
		c["wet"] = false
		var lv: Vector2 = local_range(c)[1]
		var gu := main_u.y + 0.45
		var a := to_world(gu, lv.x - 0.5)
		var b := to_world(gu, lv.y + 0.5)
		_add_breakable("gate", Vector3(a.x, floor_y, a.y), Vector3(b.x, floor_y, b.y), GATE_THICK * 0.5, depth + 0.5, ci)

## Pieza rompible de a a b (en el suelo, o en el eje si es una tubería), con su obstáculo para EnemyMotion.
func _add_breakable(kind: String, a: Vector3, b: Vector3, half_thick: float, height: float, canal: int) -> void:
	var mid := Vector2((a.x + b.x) * 0.5, (a.z + b.z) * 0.5)
	var along := Vector2(b.x - a.x, b.z - a.z)
	var hl := along.length() * 0.5
	var col := {"pos": mid, "shape": "box", "r": hl + half_thick,
		"half": Vector2(hl, half_thick) if absf(along.x) > absf(along.y) else Vector2(half_thick, hl), "yaw": 0.0}
	_colliders.append(col)
	breakables.append({"kind": kind, "a": a, "b": b, "half": half_thick, "height": height, "canal": canal,
		"collider": col, "node": null, "broken": false})

func _add_stair(edge: Vector2, d: Vector2, length: float) -> void:
	# edge en (u, v); d en (u, v): hacia la orilla
	var u0 := edge.x
	var u1 := edge.x + d.x * length
	var v0 := edge.y - STAIR_W * 0.5 if d.x != 0.0 else edge.y
	var v1 := edge.y + STAIR_W * 0.5 if d.x != 0.0 else edge.y + d.y * length
	var r := _rect(minf(u0, u1), maxf(u0, u1), minf(v0, v1), maxf(v0, v1))
	var from := to_world(edge.x, edge.y)
	var dw := to_world(d.x, d.y) - to_world(0.0, 0.0)
	# El rectángulo empieza en el borde del suelo (ajustado a la malla): la rampa sube desde ahí
	r["from"] = Vector2(_snap(from.x), _snap(from.y))
	r["dir"] = dw.normalized()
	r["len"] = length
	stairs.append(r)

static func _near_any(v: float, list: Array, d: float) -> bool:
	for o: float in list:
		if absf(o - v) < d:
			return true
	return false

func _stair_near_v(v: float, d: float) -> bool:
	for s in stairs:
		var c := to_local(((s["min"] as Vector2) + (s["max"] as Vector2)) * 0.5)
		if absf(c.y - v) < d + STAIR_W * 0.5:
			return true
	return false

static func _bridge_near(a: Vector2, b: Vector2, bridges: Array, d: float) -> bool:
	for br in bridges:
		var ba: Vector2 = br["a"]
		var bb: Vector2 = br["b"]
		for p in [a, b, (a + b) * 0.5]:
			if Geometry2D.get_closest_point_to_segment(p, ba, bb).distance_to(p) < d:
				return true
	return false

# ───────────────────────────── Terreno ─────────────────────────────

## Altura que pide el barrio en p (sin la mezcla con el campo ni el acantilado).
func _target_height(p: Vector2) -> float:
	for c in canals:
		if _in_rect(p, c):
			return floor_y
	for s in stairs:
		if _in_rect(p, s):
			var t := clampf((p - (s["from"] as Vector2)).dot(s["dir"] as Vector2) / float(s["len"]), 0.0, 1.0)
			return lerpf(floor_y, street_y, t)
	return street_y

## Talla el barrio en la malla del terreno: alturas, vértices, colores y normales de la zona.
func carve(arrays: Array) -> void:
	var side: int = _map.get("_side")
	var heights: PackedFloat32Array = _map.get("_heights")
	var cell: float = _map.cell_size
	var half: float = _map.half_size
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var u_start := depth_start - BLEND - cell
	# Solo los vértices de la franja (la cuarta parte del mapa): índices del eje del barrio a partir de u_start
	var k0 := clampi(int(floor((u_start + half) / cell)), 0, side - 1)
	var k1 := clampi(int(ceil((-u_start + half) / cell)), 0, side - 1)
	var i_rng := Vector2i(0, side - 1)
	var j_rng := Vector2i(0, side - 1)
	var band := Vector2i(k0, side - 1) if side_sign > 0.0 else Vector2i(0, k1)
	if axis == 0:
		i_rng = band
	else:
		j_rng = band
	# Altura pedida por vértice: la calle, y encima se rasterizan escaleras y canales (por rangos de índices,
	# sin mirar cada rectángulo en cada vértice: esto tardaba ~0,3 s)
	var target_h := PackedFloat32Array()
	target_h.resize(side * side)
	target_h.fill(street_y)
	for s in stairs:
		var from: Vector2 = s["from"]
		var dir: Vector2 = s["dir"]
		var slen: float = s["len"]
		var ir := _index_range(s, side)
		for j in range(ir.y, ir.w + 1):
			for i in range(ir.x, ir.z + 1):
				var p := Vector2(-half + float(i) * cell, -half + float(j) * cell)
				target_h[j * side + i] = lerpf(floor_y, street_y, clampf((p - from).dot(dir) / slen, 0.0, 1.0))
	for c in canals:
		var ir := _index_range(c, side)
		for j in range(ir.y, ir.w + 1):
			for i in range(ir.x, ir.z + 1):
				target_h[j * side + i] = floor_y
	var imin := side
	var imax := -1
	var jmin := side
	var jmax := -1
	for j in range(j_rng.x, j_rng.y + 1):
		var z := -half + float(j) * cell
		for i in range(i_rng.x, i_rng.y + 1):
			var x := -half + float(i) * cell
			var p := Vector2(x, z)
			var u := to_local(p).x
			if u < u_start:
				continue
			var idx := j * side + i
			var col := colors[idx]
			var ct := col.a
			var m := smoothstep(depth_start - BLEND, depth_start, u) * (1.0 - ct)
			if m <= 0.0:
				continue
			var target := target_h[idx]
			var h := lerpf(heights[idx], target, m)
			heights[idx] = h
			verts[idx].y = h
			# Calle y canales: camino de tierra (canal g del shader del suelo); las paredes salen de roca solas
			col.g = maxf(col.g, m * (1.0 if target < street_y - 0.01 else 0.85))
			colors[idx] = col
			imin = mini(imin, i)
			imax = maxi(imax, i)
			jmin = mini(jmin, j)
			jmax = maxi(jmax, j)
	if imax < 0:
		return
	# Normales de la zona tocada (mismo cálculo que ProceduralMap._build_terrain_arrays)
	for j in range(maxi(jmin - 1, 0), mini(jmax + 2, side)):
		for i in range(maxi(imin - 1, 0), mini(imax + 2, side)):
			var hl := heights[j * side + maxi(i - 1, 0)]
			var hr := heights[j * side + mini(i + 1, side - 1)]
			var hd := heights[maxi(j - 1, 0) * side + i]
			var hu := heights[mini(j + 1, side - 1) * side + i]
			normals[j * side + i] = Vector3(hl - hr, 2.0 * cell, hd - hu).normalized()
	_map.set("_heights", heights)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_NORMAL] = normals

## Vértices de la malla dentro de un rectángulo (con la misma holgura que _in_rect): Vector4i(i0, j0, i1, j1).
func _index_range(r: Dictionary, side: int) -> Vector4i:
	var cell: float = _map.cell_size
	var half: float = _map.half_size
	var mn: Vector2 = r["min"]
	var mx: Vector2 = r["max"]
	return Vector4i(clampi(int(ceil((mn.x - 0.001 + half) / cell)), 0, side - 1), clampi(int(ceil((mn.y - 0.001 + half) / cell)), 0, side - 1),
		clampi(int(floor((mx.x + 0.001 + half) / cell)), 0, side - 1), clampi(int(floor((mx.y + 0.001 + half) / cell)), 0, side - 1))

# ───────────────────────────── Agua ─────────────────────────────

func water_y() -> float:
	return floor_y + WATER_ABOVE_FLOOR

## ¿Hay agua residual en p? (sobre el suelo de un canal y por debajo de la orilla)
func is_water(p: Vector3) -> bool:
	if p.y >= floor_y + 1.2:
		return false
	var q := Vector2(p.x, p.z)
	for c in canals:
		if bool(c.get("wet", true)) and _in_rect(q, c, 0.2):
			return true
	return false

## Frena al jugador local mientras pisa el agua (como SewerMap, sin el veneno: aquí es agua de lluvia sucia).
func tick(delta: float) -> void:
	if not _floods.is_empty():
		_tick_floods(delta)
	if Net.is_dedicated():
		return
	var tree := _map.get_tree()
	if tree == null:
		return
	var p := tree.get_first_node_in_group("player") as Node3D
	if p == null or bool(p.get_meta("downed", false)) or not is_water(p.global_position):
		return
	var mc = p.get("movement_controller")
	if mc != null:
		var now := Time.get_ticks_msec() / 1000.0
		mc.slow_mult = WATER_SLOW if now >= mc.slow_until else minf(mc.slow_mult, WATER_SLOW)
		mc.slow_until = maxf(mc.slow_until, now + 0.15)

# ───────────────────────────── Decoración ─────────────────────────────

## Obstáculos para EnemyMotion (formato de ProceduralMap.get_colliders).
func colliders() -> Array:
	return _colliders

## Props de cloaca en las orillas (basura, válvulas, desagües) y algún resto de muro. Va con los demás props.
func decorate() -> void:
	var ph: float = _map.play_half
	var main_u: Vector2 = local_range(canals[0])[0]
	var u_in := main_u.x
	var u_out := main_u.y
	# Válvulas y desagües junto al borde del canal
	var v := -ph + 8.0
	while v < ph - 8.0:
		for bank: float in [u_in - 1.4, u_out + 1.4]:
			var p := to_world(bank, v + _rng.randf_range(-3.0, 3.0))
			if _free(p, 1.2):
				_map._place("valve" if _rng.randf() < 0.45 else "drain", p, 1.0, -1.0, -1.0, _rng.randf() < 0.45)
		v += _rng.randf_range(9.0, 15.0)
	# Montones de basura repartidos por la calle y entre los desagües
	var piles := int(22.0 * _map.prop_density)
	for k in piles * 10:
		if piles <= 0:
			break
		var p := to_world(_rng.randf_range(depth_start, ph - 4.0), _rng.randf_range(-ph + 5.0, ph - 5.0))
		if not _free(p, 2.2):
			continue
		_map._place("trash_pile", p, 1.4)
		for b in _rng.randi_range(2, 4):
			var q := p + Vector2(_rng.randf_range(-2.0, 2.0), _rng.randf_range(-2.0, 2.0))
			if _free(q, 0.7):
				_map._place("trash_bag", q, 0.6, -1.0, -1.0, false)
		piles -= 1
	# Bidones tóxicos y cajas sueltos
	var loose := int(14.0 * _map.prop_density)
	for k in loose * 10:
		if loose <= 0:
			break
		var p := to_world(_rng.randf_range(depth_start, ph - 4.0), _rng.randf_range(-ph + 5.0, ph - 5.0))
		if not _free(p, 1.2):
			continue
		_map._place("toxic_barrel" if _rng.randf() < 0.5 else "crate", p, 0.9)
		loose -= 1
	# Restos de muro que forman callejones en la calle de dentro
	var walls := 6
	for k in walls * 12:
		if walls <= 0:
			break
		var p := to_world(_rng.randf_range(depth_start + 2.0, u_in - 6.0), _rng.randf_range(-ph + 8.0, ph - 8.0))
		if not _free(p, 3.0):
			continue
		var yaw := 0.0 if axis == 1 else PI * 0.5
		_map._place("wall", p, 2.4, yaw + _rng.randf_range(-0.08, 0.08))
		walls -= 1
	# Luz verdosa en la boca de cada tubería (cuenta en el tope de luces del mapa)
	for pp in pipes:
		var pos: Vector3 = pp["pos"]
		var d: Vector3 = pp["dir"]
		_map._add_light(pos - d * 2.0 + Vector3(0.0, 0.6, 0.0), GLOW_COL, 1.6, 9.0)

## ¿p está libre para un prop del barrio? (en la calle, fuera de canales, escaleras, puentes y tuberías)
func _free(p: Vector2, r: float) -> bool:
	var ph: float = _map.play_half
	if absf(p.x) > ph - 3.0 or absf(p.y) > ph - 3.0:
		return false
	if to_local(p).x < depth_start:
		return false
	if in_canal(p, r + 0.8) or _in_stair(p, r + 1.0) or _map._near_bridge(p, r + 0.8) or _map._occupied(p, r):
		return false
	for bk in breakables:
		var a: Vector3 = bk["a"]
		var b: Vector3 = bk["b"]
		if Geometry2D.get_closest_point_to_segment(p, Vector2(a.x, a.z), Vector2(b.x, b.z)).distance_to(p) < float(bk["half"]) + r + 1.0:
			return false
	return true

## Nodos: agua, tuberías del acantilado y de la orilla (con colisión para el jugador). Las piezas de las
## tuberías van en una MultiMesh por material (cilindro unidad escalado): 4 llamadas de dibujo en total.
func build_nodes() -> void:
	_build_water()
	var root := Node3D.new()
	root.name = "SewerDistrict"
	_map.add_child(root)
	var pipe_mat := StandardMaterial3D.new()
	pipe_mat.albedo_color = PIPE_COL
	pipe_mat.roughness = 0.75
	pipe_mat.metallic = 0.25
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = PIPE_RING_COL
	ring_mat.roughness = 0.8
	var dark_mat := StandardMaterial3D.new()
	dark_mat.albedo_color = Color(0.02, 0.025, 0.02)
	dark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var rust_mat := StandardMaterial3D.new()
	rust_mat.albedo_color = RUST_COL
	var body := StaticBody3D.new()
	body.name = "SewerDistrictBody"
	body.collision_layer = 1
	body.collision_mask = 0
	var tubes: Array[Transform3D] = []
	var rings: Array[Transform3D] = []
	var holes: Array[Transform3D] = []
	var supports: Array[Transform3D] = []
	for pp in pipes:
		var pos: Vector3 = pp["pos"]
		var d: Vector3 = pp["dir"]
		# Tubo que se mete en el acantilado, con un anillo en la boca y el interior negro
		var length := 9.0
		var centre := pos + d * (length * 0.5)
		tubes.append(_cyl_xf(centre, d, PIPE_R, length))
		rings.append(_cyl_xf(pos + d * 0.15, d, PIPE_R + 0.14, 0.5))
		holes.append(_cyl_xf(pos + d * 0.6, d, PIPE_R - 0.12, 0.2))
		rings.append(_cyl_xf(pos + d * 3.0, d, PIPE_R + 0.1, 0.35))
		_add_cyl_shape(body, centre, d, PIPE_R, length)
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 1.0
	cyl.radial_segments = 14
	cyl.rings = 1
	var box := BoxMesh.new()
	_multimesh(root, "Tubes", cyl, pipe_mat, tubes)
	_multimesh(root, "Rings", cyl, ring_mat, rings)
	_multimesh(root, "Holes", cyl, dark_mat, holes)
	_multimesh(root, "Supports", box, rust_mat, supports)
	root.add_child(body)
	for i in breakables.size():
		_build_breakable(root, i, pipe_mat, ring_mat, rust_mat)
	_build_quays(root, rust_mat)

# ───────────────────────────── Muelles, remate y farolas ─────────────────────────────

const QUAY_THICK := 0.08
const COPING_W := 0.5
const COPING_H := 0.16
const LAMP_H := 3.4
const LAMP_GAP := 26.0
const COPING_COL := Color(0.45, 0.43, 0.4)
const LAMP_COL := Color(0.9, 1.0, 0.55)

## Revestimiento de ladrillo pegado a las paredes de los canales (no cubre escaleras ni las bocas de los desagües),
## remate de piedra en el borde de la calle y farolas con cabeza emisiva (sin luces reales: el tope del mapa es 8).
func _build_quays(root: Node3D, iron_mat: Material) -> void:
	var cell: float = _map.cell_size
	var slope_len := sqrt(cell * cell + depth * depth)
	var quay: Array[Transform3D] = []
	var coping: Array[Transform3D] = []
	for seg in _bank_segments():
		var a: Vector2 = seg["a"]
		var b: Vector2 = seg["b"]
		var out: Vector2 = seg["out"]
		var seg_len := a.distance_to(b)
		if seg_len < 0.4:
			continue
		var x := _world_dir(b - a).normalized()
		var hn := -_world_dir(out).normalized()
		var n := (hn * depth + Vector3.UP * cell) / slope_len
		var mid := (a + b) * 0.5 + out * cell * 0.5
		var mw := to_world(mid.x, mid.y)
		var centre := Vector3(mw.x, (floor_y + street_y) * 0.5, mw.y) + n * (QUAY_THICK * 0.55)
		var z := x.cross(n).normalized()
		quay.append(Transform3D(Basis(x, n, z) * Basis.from_scale(Vector3(seg_len, QUAY_THICK, slope_len)), centre))
		var top := (a + b) * 0.5 + out * (cell + COPING_W * 0.4)
		var tw := to_world(top.x, top.y)
		var cz := x.cross(Vector3.UP).normalized()
		coping.append(Transform3D(Basis(x, Vector3.UP, cz) * Basis.from_scale(Vector3(seg_len, COPING_H, COPING_W)),
			Vector3(tw.x, street_y + COPING_H * 0.5, tw.y)))
	var box := BoxMesh.new()
	if not quay.is_empty():
		var qm := _brick_material()
		qm.albedo_color = BRICK_TINT * Color(0.72, 0.74, 0.72)    # ladrillo viejo y mojado
		_multimesh(root, "Quays", box, qm, quay)
	if not coping.is_empty():
		var cm := StandardMaterial3D.new()
		cm.albedo_color = COPING_COL
		cm.roughness = 0.9
		_multimesh(root, "Coping", box, cm, coping)
	_build_lamps(root, iron_mat)

## Tramos de orilla: [{a, b (extremos en (u, v) del borde inferior de la pared), out: dirección horizontal local hacia arriba}].
func _bank_segments() -> Array:
	var segs: Array = []
	if canals.is_empty():
		return segs
	var cell: float = _map.cell_size
	var ph: float = _map.play_half
	var main_rng: Array = local_range(canals[0])
	var mu: Vector2 = main_rng[0]
	var mv: Vector2 = main_rng[1]
	var vlo := maxf(mv.x, -ph - 2.0)
	var vhi := minf(mv.y, ph + 2.0)
	# Escaleras en el marco local: [u0, u1, v0, v1]
	var st: Array = []
	for s in stairs:
		var r := local_range(s)
		st.append([(r[0] as Vector2).x, (r[0] as Vector2).y, (r[1] as Vector2).x, (r[1] as Vector2).y])
	for side in 2:
		var edge := mu.x if side == 0 else mu.y
		var out := Vector2(-1.0, 0.0) if side == 0 else Vector2(1.0, 0.0)
		var lo := edge - cell if side == 0 else edge
		var excl: Array = []
		for s: Array in st:
			if s[1] >= lo - 0.5 and s[0] <= lo + cell + 0.5:
				excl.append(Vector2(s[2] - 0.6, s[3] + 0.6))
		if side == 1:
			for ci in range(1, canals.size()):
				var cv: Vector2 = local_range(canals[ci])[1]
				excl.append(Vector2(cv.x - 0.3, cv.y + 0.3))
		for iv in _subtract(Vector2(vlo, vhi), excl):
			segs.append({"a": Vector2(edge, iv.x), "b": Vector2(edge, iv.y), "out": out})
	for ci in range(1, canals.size()):
		var cr: Array = local_range(canals[ci])
		var cu: Vector2 = cr[0]
		var cv: Vector2 = cr[1]
		var u1 := minf(cu.y, ph + 1.0)
		for side in 2:
			var edge := cv.x if side == 0 else cv.y
			var out := Vector2(0.0, -1.0) if side == 0 else Vector2(0.0, 1.0)
			var lo := edge - cell if side == 0 else edge
			var excl: Array = []
			for s: Array in st:
				if s[3] >= lo - 0.5 and s[2] <= lo + cell + 0.5:
					excl.append(Vector2(s[0] - 0.6, s[1] + 0.6))
			for iv in _subtract(Vector2(cu.x, u1), excl):
				segs.append({"a": Vector2(iv.x, edge), "b": Vector2(iv.y, edge), "out": out})
	return segs

## Intervalo `range` menos los de `cuts`; descarta restos de menos de 0,5 m.
static func _subtract(rng: Vector2, cuts: Array) -> Array:
	var pieces: Array = [rng]
	for c: Vector2 in cuts:
		var next: Array = []
		for p: Vector2 in pieces:
			if c.y <= p.x or c.x >= p.y:
				next.append(p)
				continue
			if c.x > p.x:
				next.append(Vector2(p.x, c.x))
			if c.y < p.y:
				next.append(Vector2(c.y, p.y))
		pieces = next
	return pieces.filter(func(p: Vector2) -> bool: return p.y - p.x >= 0.5)

## Dirección local (u, v) -> vector horizontal del mundo.
func _world_dir(d: Vector2) -> Vector3:
	var w := to_world(d.x, d.y) - to_world(0.0, 0.0)
	return Vector3(w.x, 0.0, w.y)

func _build_lamps(root: Node3D, iron_mat: Material) -> void:
	var cell: float = _map.cell_size
	var ph: float = _map.play_half
	var mu: Vector2 = local_range(canals[0])[0]
	var poles: Array[Transform3D] = []
	var arms: Array[Transform3D] = []
	var heads: Array[Transform3D] = []
	for side in 2:
		var u := mu.x - cell - 1.2 if side == 0 else mu.y + cell + 1.2
		var inward := _world_dir(Vector2(1.0 if side == 0 else -1.0, 0.0))
		var v := -ph + 16.0 + (LAMP_GAP * 0.5 if side == 1 else 0.0)
		while v < ph - 12.0:
			var w := to_world(u, v)
			if _free(w, 0.9):
				var base := Vector3(w.x, street_y, w.y)
				poles.append(Transform3D(Basis.from_scale(Vector3(0.18, LAMP_H, 0.18)), base + Vector3(0.0, LAMP_H * 0.5, 0.0)))
				var arm_scale := Vector3(0.7 * absf(inward.x) + 0.09 * absf(inward.z), 0.09, 0.7 * absf(inward.z) + 0.09 * absf(inward.x))
				arms.append(Transform3D(Basis.from_scale(arm_scale), base + inward * 0.33 + Vector3(0.0, LAMP_H - 0.05, 0.0)))
				heads.append(Transform3D(Basis.from_scale(Vector3(0.5, 0.32, 0.5)), base + inward * 0.7 + Vector3(0.0, LAMP_H - 0.2, 0.0)))
			v += LAMP_GAP + _rng.randf_range(-3.0, 3.0)
	var box := BoxMesh.new()
	_multimesh(root, "LampPoles", box, iron_mat, poles)
	_multimesh(root, "LampArms", box, iron_mat, arms)
	if not heads.is_empty():
		var hm := StandardMaterial3D.new()
		hm.albedo_color = LAMP_COL
		hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		hm.emission_enabled = true
		hm.emission = LAMP_COL
		hm.emission_energy_multiplier = 2.2
		_multimesh(root, "LampHeads", box, hm, heads)

func _multimesh(parent: Node3D, n: String, mesh: Mesh, mat: Material, xfs: Array[Transform3D]) -> void:
	if xfs.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = n
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)

## Cilindro unidad (radio 1, alto 1) con el eje a lo largo de d, de radio r y largo `length`, centrado en `centre`.
static func _cyl_xf(centre: Vector3, d: Vector3, r: float, length: float) -> Transform3D:
	return Transform3D(_axis_basis(d) * Basis.from_scale(Vector3(r, length, r)), centre)

func _build_water() -> void:
	if canals.is_empty():
		return
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.0, 1.0)
	var mat := ShaderMaterial.new()
	mat.shader = WATER_SHADER
	plane.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = plane
	mm.instance_count = canals.size()
	var main_u: Vector2 = local_range(canals[0])[0]
	_water_full.clear()
	for i in canals.size():
		var rng: Array = local_range(canals[i])
		var lu: Vector2 = rng[0]
		var lv: Vector2 = rng[1]
		# El agua entra un poco bajo las paredes; la de un desagüe empieza donde acaba la del canal principal
		if i == 0:
			lu = Vector2(lu.x - 0.3, lu.y + 0.3)
		else:
			lu = Vector2(main_u.y + 0.3, lu.y)
		lv = Vector2(lv.x - 0.3, lv.y + 0.3)
		var a := to_world(lu.x, lv.x)
		var b := to_world(lu.y, lv.y)
		var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y))
		var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
		var size := hi - lo
		var centre := (lo + hi) * 0.5
		var full := Transform3D(Basis().scaled(Vector3(size.x, 1.0, size.y)), Vector3(centre.x, water_y(), centre.y))
		_water_full.append(full)
		mm.set_instance_transform(i, full if bool(canals[i].get("wet", true)) else _hidden_xf())
	_water_mm = mm
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Water"
	mmi.multimesh = mm
	mmi.layers = ProceduralMap.GROUND_VISUAL_LAYER
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_map.add_child(mmi)

static func _hidden_xf() -> Transform3D:
	return Transform3D(Basis.from_scale(Vector3.ONE * 0.0001), Vector3(0.0, -1000.0, 0.0))

## Rango local [u: Vector2(min, max), v: Vector2(min, max)] del rectángulo de un canal.
func local_range(c: Dictionary) -> Array:
	var a := to_local(c["min"])
	var b := to_local(c["max"])
	return [Vector2(minf(a.x, b.x), maxf(a.x, b.x)), Vector2(minf(a.y, b.y), maxf(a.y, b.y))]

func _add_cyl_shape(body: StaticBody3D, centre: Vector3, d: Vector3, r: float, length: float) -> void:
	var shape := CylinderShape3D.new()
	shape.radius = r
	shape.height = length
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = Transform3D(_axis_basis(d), centre)
	body.add_child(cs)

## Base con el eje Y (el de los cilindros) a lo largo de d (horizontal).
static func _axis_basis(d: Vector3) -> Basis:
	var y := d.normalized()
	var x := Vector3.UP.cross(y).normalized()
	var z := x.cross(y)
	return Basis(x, y, z)

# ───────────────────────────── Piezas rompibles (historia 009) ─────────────────────────────

signal broken_changed(i: int)

func _build_breakable(root: Node3D, i: int, pipe_mat: Material, ring_mat: Material, rust_mat: Material) -> void:
	var bk: Dictionary = breakables[i]
	var a: Vector3 = bk["a"]
	var b: Vector3 = bk["b"]
	var half: float = bk["half"]
	var height: float = bk["height"]
	var kind: String = bk["kind"]
	var node := SewerBreakable.new()
	node.name = "%s_%d" % [kind.capitalize(), i]
	node.district = self
	node.id = i
	node.hp = float(HP_BY_KIND[kind])
	node.collision_layer = 1
	node.collision_mask = 0
	var d := b - a
	d.y = 0.0
	var length := d.length()
	d = d / length
	var mid := (a + b) * 0.5
	var basis := Basis.looking_at(d, Vector3.UP)       # -Z a lo largo de la pieza
	var shape: Shape3D
	var shape_xf: Transform3D
	match kind:
		"pipe":
			_mesh_child(node, _cyl_mesh(half, length), pipe_mat, Transform3D(_axis_basis(d), mid))
			var n := int(length / 4.0)
			for k in range(n + 1):
				_mesh_child(node, _cyl_mesh(half + 0.08, 0.3), ring_mat, Transform3D(_axis_basis(d), a.lerp(b, float(k) / float(maxi(n, 1)))))
			for t: float in [0.25, 0.75]:
				var q := a.lerp(b, t)
				var bm := BoxMesh.new()
				bm.size = Vector3(half * 2.4, 0.35, 0.5)
				_mesh_child(node, bm, rust_mat, Transform3D(basis, Vector3(q.x, street_y + 0.17, q.z)))
			var cyl := CylinderShape3D.new()
			cyl.radius = half
			cyl.height = length
			shape = cyl
			shape_xf = Transform3D(_axis_basis(d), mid)
		"wall":
			var bm := BoxMesh.new()
			bm.size = Vector3(half * 2.0, height, length)
			_mesh_child(node, bm, _brick_material(), Transform3D(basis, mid + Vector3(0.0, height * 0.5, 0.0)))
			# remate de piedra arriba
			var cb := BoxMesh.new()
			cb.size = Vector3(half * 2.0 + 0.16, 0.18, length + 0.1)
			var cmat := StandardMaterial3D.new()
			cmat.albedo_color = Color(0.42, 0.4, 0.38)
			_mesh_child(node, cb, cmat, Transform3D(basis, mid + Vector3(0.0, height + 0.09, 0.0)))
			var box := BoxShape3D.new()
			box.size = Vector3(half * 2.0, height, length)
			shape = box
			shape_xf = Transform3D(basis, mid + Vector3(0.0, height * 0.5, 0.0))
		_:
			# Compuerta: tablones de madera con dos flejes de hierro, del fondo del canal hasta algo sobre la orilla
			var wood := StandardMaterial3D.new()
			wood.albedo_color = GATE_WOOD
			wood.roughness = 0.9
			var iron := StandardMaterial3D.new()
			iron.albedo_color = IRON_COL
			iron.metallic = 0.4
			iron.roughness = 0.6
			var planks := maxi(int(length / 0.45), 1)
			for k in planks:
				var q := a.lerp(b, (float(k) + 0.5) / float(planks))
				var pm := BoxMesh.new()
				pm.size = Vector3(half * 2.0, height, length / float(planks) - 0.04)
				_mesh_child(node, pm, wood, Transform3D(basis, q + Vector3(0.0, height * 0.5, 0.0)))
			for hy: float in [0.35, 0.8]:
				var bb := BoxMesh.new()
				bb.size = Vector3(half * 2.0 + 0.08, 0.16, length + 0.1)
				_mesh_child(node, bb, iron, Transform3D(basis, mid + Vector3(0.0, height * hy, 0.0)))
			var gbox := BoxShape3D.new()
			gbox.size = Vector3(half * 2.0, height, length)
			shape = gbox
			shape_xf = Transform3D(basis, mid + Vector3(0.0, height * 0.5, 0.0))
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = shape_xf
	node.add_child(cs)
	bk["node"] = node
	root.add_child(node)

static func _cyl_mesh(r: float, length: float) -> CylinderMesh:
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = length
	cm.radial_segments = 14
	cm.rings = 1
	return cm

static func _mesh_child(parent: Node3D, mesh: Mesh, mat: Material, xf: Transform3D) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = xf
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)

## Ladrillo rojizo en triplanar de mundo (sewer_brick.gdshader multiplica por un color de vértice que aquí no hay).
func _brick_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(TEX_DIR + "brick_albedo.png")
	mat.albedo_color = BRICK_TINT
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3.ONE * BRICK_UV
	if Quality.level() != Quality.Level.LOW:
		mat.normal_enabled = true
		mat.normal_texture = load(TEX_DIR + "brick_normal.png")
	mat.roughness = 0.85
	return mat

## Golpe a una pieza: tiembla un poco y suelta polvo de su color.
func on_breakable_hit(i: int, _dir: Vector3) -> void:
	var bk: Dictionary = breakables[i]
	var node: Node3D = bk["node"]
	if node == null or not node.is_inside_tree():
		return
	var at := _piece_point(bk, 0.5)
	ToonFX.puff_burst(_map.get_parent(), at, _piece_color(bk), 4, 2.2, 0.3)
	AudioManager.play_at("impact_mace" if bk["kind"] != "gate" else "impact_blunt", at, -8.0, randf_range(0.8, 0.95))
	var tw := node.create_tween()
	node.position = Vector3.ZERO
	tw.tween_property(node, "position", Vector3(randf_range(-0.06, 0.06), 0.0, randf_range(-0.06, 0.06)), 0.04)
	tw.tween_property(node, "position", Vector3.ZERO, 0.08)

## Rota: desaparece, abre el paso (jugador y enemigos) y, si es una compuerta, suelta el agua por su desagüe.
func on_breakable_broken(i: int, _dir: Vector3) -> void:
	var bk: Dictionary = breakables[i]
	if bk["broken"]:
		return
	bk["broken"] = true
	var node: SewerBreakable = bk["node"]
	var scene := _map.get_parent()
	var col: Dictionary = bk["collider"]
	_colliders.erase(col)
	EnemyMotion.remove_obstacles_near(col["pos"], 0.3)
	if node:
		node.collision_layer = 0
		for c in node.get_children():
			if c is CollisionShape3D:
				(c as CollisionShape3D).set_deferred("disabled", true)
			elif c is Node3D:
				(c as Node3D).visible = false
	var a: Vector3 = bk["a"]
	var b: Vector3 = bk["b"]
	var length := Vector2(b.x - a.x, b.z - a.z).length()
	var n := clampi(int(length / 2.5), 2, 8)
	if scene:
		for k in n:
			ToonFX.puff_burst(scene, _piece_point(bk, (float(k) + 0.5) / float(n)), _piece_color(bk), 6, 3.5, 0.5)
	var mid := _piece_point(bk, 0.5)
	if scene:
		ToonFX.impact_pop(scene, mid + Vector3(0.0, 0.5, 0.0), _piece_color(bk), 1.4)
	AudioManager.play_at("explosion_bits", mid, -3.0, randf_range(0.85, 1.0))
	AudioManager.play_at("mace_ground", mid, -4.0, 0.8)
	HitFeedback.shake(0.3)
	match String(bk["kind"]):
		"pipe":
			# Revienta: chorro de agua sucia y una mancha que queda
			if scene:
				ToonFX.puff_burst(scene, mid, WATER_TINT, 12, 5.0, 0.5)
			MapMarks.add_at(_map, Vector3(mid.x, street_y, mid.z), MapMarks.Kind.INK, 2.4)
		"gate":
			_start_flood(int(bk["canal"]))
	broken_changed.emit(i)

func broken_count() -> int:
	var n := 0
	for bk in breakables:
		if bk["broken"]:
			n += 1
	return n

## Punto de la pieza a la fracción t de su largo, a media altura.
func _piece_point(bk: Dictionary, t: float) -> Vector3:
	var a: Vector3 = bk["a"]
	var b: Vector3 = bk["b"]
	var p := a.lerp(b, t)
	if bk["kind"] != "pipe":
		p.y += float(bk["height"]) * 0.5
	return p

static func _piece_color(bk: Dictionary) -> Color:
	match String(bk["kind"]):
		"wall":
			return BRICK_COL
		"gate":
			return GATE_WOOD
	return PIPE_COL

## Compuerta rota: el agua entra en el desagüe ci con una ola que arrastra a los enemigos hacia el acantilado.
func _start_flood(ci: int) -> void:
	if ci <= 0 or ci >= canals.size() or bool(canals[ci].get("wet", true)):
		return
	_floods.append({"canal": ci, "t": 0.0, "hit": {}, "fx_t": 0.0})
	var rng: Array = local_range(canals[ci])
	var mouth := to_world((rng[0] as Vector2).x, ((rng[1] as Vector2).x + (rng[1] as Vector2).y) * 0.5)
	AudioManager.play_at("slug_splat", Vector3(mouth.x, water_y(), mouth.y), 0.0, 0.6)

func _tick_floods(delta: float) -> void:
	var k := 0
	while k < _floods.size():
		var f: Dictionary = _floods[k]
		var ci: int = f["canal"]
		f["t"] = float(f["t"]) + delta
		var t := clampf(float(f["t"]) / FLOOD_TIME, 0.0, 1.0)
		var rng: Array = local_range(canals[ci])
		var lu: Vector2 = rng[0]
		var lv: Vector2 = rng[1]
		var front := lerpf(lu.x, lu.y, t)
		var vmid := (lv.x + lv.y) * 0.5
		# Agua: crece desde la boca hasta el frente de la ola
		if _water_mm and ci < _water_full.size():
			var full: Transform3D = _water_full[ci]
			var sc := full.basis.get_scale()
			var frac := maxf(t, 0.02)
			var nsc := Vector3(sc.x * frac, 1.0, sc.z) if axis == 0 else Vector3(sc.x, 1.0, sc.z * frac)
			var c := (to_world(lu.x, vmid) + to_world(front, vmid)) * 0.5
			_water_mm.set_instance_transform(ci, Transform3D(Basis.from_scale(nsc), Vector3(c.x, water_y(), c.y)))
		# Ola: daña y empuja una vez a cada enemigo que alcanza dentro del desagüe
		var push := Vector3(dir_out().x, 0.0, dir_out().y)
		var hit: Dictionary = f["hit"]
		for e in EnemyRegistry.all().duplicate():
			if not (e is EnemyData) or e.recycled or hit.has(e):
				continue
			var ep: Vector3 = e.global_position
			if ep.y > street_y - 0.6:
				continue
			var l := to_local(Vector2(ep.x, ep.z))
			if l.y < lv.x - 0.5 or l.y > lv.y + 0.5 or l.x < lu.x - 0.5 or l.x > front + 1.0:
				continue
			hit[e] = true
			var frac_hp := FLOOD_FRAC * (0.35 if e.xp_reward >= XpCurve.XP_ELITE else 1.0)
			HitFeedback.weapon_tag = -1
			e.take_damage(maxf(FLOOD_MIN_DAMAGE, e.max_hp * frac_hp), push * FLOOD_KNOCK)
		f["fx_t"] = float(f["fx_t"]) - delta
		if float(f["fx_t"]) <= 0.0 and t < 1.0:
			f["fx_t"] = 0.12
			var fp := to_world(front, vmid)
			var scene := _map.get_parent()
			if scene:
				ToonFX.puff_burst(scene, Vector3(fp.x, water_y() + 0.3, fp.y), WATER_TINT, 5, 3.0, 0.45)
		if t >= 1.0:
			canals[ci]["wet"] = true
			if _water_mm and ci < _water_full.size():
				_water_mm.set_instance_transform(ci, _water_full[ci])
			_floods.remove_at(k)
			continue
		k += 1

func flooding() -> bool:
	return not _floods.is_empty()
