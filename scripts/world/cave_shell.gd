class_name CaveShell
extends RefCounted

## Carcasa continua de la cueva de DungeonMap: paredes + techo en una sola superficie, sin bloques.
##
##  1. Contorno: las aristas entre celdas de suelo y de roca se enlazan en lazos cerrados (el borde de
##     cada zona conectada y los huecos de las columnas), se suavizan (Chaikin) y se remuestrean cada
##     `spacing` m.
##  2. Paredes: cada punto del lazo levanta una columna de `rings` vértices desde bajo el suelo hasta el
##     techo; arriba la pared se curva hacia la cueva (OVERHANG) y se mete en el techo. Se desplaza hacia la
##     roca o hacia la cueva con el relieve del escaneo de la Gruta do Janelão (cave_scan_height.png,
##     ver tools/make_cave_relief.py) más ruido; junto al suelo apenas invade la zona caminable.
##  3. Techo: rejilla en las esquinas de las celdas (suelo + primer anillo de roca), bóveda más alta lejos
##     de las paredes (DOME_RISE), con el mismo relieve.
## Las normales se calculan sobre la superficie entera y las paredes se reparten en trozos de `chunk` m (la
## cámara descarta los que no ve) sin costuras de luz; el techo también va en trozos. El techo lleva una
## colisión gruesa (capa 1) para que el SpringArm3D de la cámara no lo atraviese; las paredes siguen usando
## las cajas de DungeonMap. Coste: ~50 ms por nivel (se genera con la pantalla en negro).

const RELIEF_TEX := "res://assets/textures/dungeon/cave_scan_height.png"
const RELIEF_TILE := 12.0          ## metros que cubre el relieve
const RELIEF_AMP := 1.3            ## desplazamiento (m) con el relieve a tope
const NOISE_AMP := 0.6             ## ruido de bajo detalle añadido al relieve (m)
const OVERHANG := 1.4              ## cuánto se mete la pared hacia la cueva al llegar al techo (m)
const FOOT_H := 2.5                ## por debajo de esta altura la pared casi no invade el suelo
const WALL_CEIL_H := 5.5           ## altura del techo junto a la pared
const DOME_RISE := 5.0             ## lo que sube el techo hacia el centro de una caverna
const DOME_FALLOFF := 3.0          ## celdas en las que el techo sube ~63% de DOME_RISE
const TOP_SINK := 0.4              ## la cresta de la pared entra en el techo (sin rendijas)
## Capa visual extra de las paredes (no del techo): los Decal de pinturas rupestres solo se proyectan aquí
const WALL_DECAL_LAYER := 1024

var cell := 2.0
var chunk := 48.0
var spacing := 1.4                 ## separación entre columnas de pared (m)
var rings := 8                     ## vértices por columna de pared
var rock_color := Color(0.5, 0.5, 0.5)
var anchor_h := 2.1                ## altura de los anclajes de pared (antorchas)
## Puntos sobre la superficie de la pared a `anchor_h` m, uno por columna: [Vector3 punto, Vector2 hacia la cueva].
var anchors: Array = []

var _cells: Dictionary             # Vector2i -> suelo
var _walls: Dictionary             # Vector2i -> primer anillo de roca
var _wall_dist: Dictionary         # Vector2i (suelo) -> distancia a la pared en celdas
var _corner_h: Dictionary = {}     # Vector2i esquina -> altura del techo
var _noise := FastNoiseLite.new()
const RELIEF_RES := 64             ## el relieve se reduce a 64x64 (19 cm/px): basta con leerlo sin interpolar
const CORNERS4 := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]
static var _relief := PackedFloat32Array()   # -1..1, compartido entre mapas

## Datos de una malla en construcción (miembros: se amplían sin copiar, a diferencia de un Packed*Array
## guardado en un Dictionary).
class Part:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var i := PackedInt32Array()

var _wall_meshes: Array[ArrayMesh] = []   # resultado de compute(): un trozo de pared por malla
var _roof_meshes: Array[ArrayMesh] = []   # resultado de compute(): el techo en trozos
var _roof_faces := PackedVector3Array()    # resultado de compute(): colisión gruesa del techo
var _wall_parts: Array[Part] = []          # datos de cada trozo (para hornear luz sin recalcular)
var _roof_parts: Array[Part] = []

## Datos de entrada (solo se leen).
func setup(cells: Dictionary, walls: Dictionary, wall_dist: Dictionary, p_seed: int) -> void:
	_cells = cells
	_walls = walls
	_wall_dist = wall_dist
	_noise.seed = p_seed
	_noise.frequency = 0.15
	_noise.fractal_octaves = 2

## Calcula paredes y techo y crea sus ArrayMesh (sin nodos).
func compute() -> void:
	load_relief()
	_compute_corner_heights()
	anchors.clear()
	var chunks := _build_walls()
	_wall_meshes.clear()
	_wall_parts.clear()
	_roof_parts.clear()
	for key in chunks:
		var part: Part = chunks[key]
		_wall_parts.append(part)
		_wall_meshes.append(_array_mesh({"v": part.v, "n": part.n, "c": part.c, "i": part.i}))
	_roof_meshes.clear()
	var roof := _build_ceiling()
	for key in roof:
		var part: Part = roof[key]
		_roof_parts.append(part)
		_roof_meshes.append(_array_mesh({"v": part.v, "n": part.n, "c": part.c, "i": part.i}))
	_roof_faces = _ceiling_collision()

## Hornea en el canal alfa del color de vértice la luz de las fuentes dadas (antorchas, braseros): así las
## paredes y el techo lejos de las `visible_lights` encendidas siguen teniendo luz cálida sin una luz dinámica
## más (el shader cave_rock la suma como emisión si `baked_gain` > 0). `sources`: [[Vector3 pos, float
## energía, float alcance, float atenuación]]. Se reparten en una rejilla para no recorrerlas todas por vértice.
func bake_light(sources: Array) -> void:
	if sources.is_empty():
		return
	var cell_sz := 1.0
	for src in sources:
		cell_sz = maxf(cell_sz, float(src[2]))
	var inv := 1.0 / cell_sz
	var grid := {}                  # celda -> fuentes que caen en ella
	for src in sources:
		var p: Vector3 = src[0]
		var k := Vector2i(floori(p.x * inv), floori(p.z * inv))
		if not grid.has(k):
			grid[k] = []
		(grid[k] as Array).append(src)
	var cands := {}                 # celda -> fuentes de su vecindad 3x3, planas (x, y, z, energía, alcance², atenuación, 1/alcance)
	var meshes: Array = _wall_meshes + _roof_meshes
	var parts: Array = _wall_parts + _roof_parts
	for m in parts.size():
		var part: Part = parts[m]
		var vs := part.v
		var ns := part.n
		var cs := part.c
		var last_key := Vector2i(1 << 30, 0)
		var flat := PackedFloat32Array()
		for vi in vs.size():
			var pos := vs[vi]
			var k0 := Vector2i(floori(pos.x * inv), floori(pos.z * inv))
			if k0 != last_key:
				last_key = k0
				if not cands.has(k0):
					var f := PackedFloat32Array()
					for dx in range(-1, 2):
						for dz in range(-1, 2):
							for src in grid.get(k0 + Vector2i(dx, dz), []):
								var sp: Vector3 = src[0]
								f.append_array([sp.x, sp.y, sp.z, src[1], float(src[2]) * float(src[2]), src[3], 1.0 / float(src[2])])
					cands[k0] = f
				flat = cands[k0]
			var nrm := ns[vi]
			var sum := 0.0
			for o in range(0, flat.size(), 7):
				var tx := flat[o] - pos.x
				var ty := flat[o + 1] - pos.y
				var tz := flat[o + 2] - pos.z
				var d2 := tx * tx + ty * ty + tz * tz
				if d2 >= flat[o + 4] or d2 < 0.000001:
					continue
				var d := sqrt(d2)
				var facing := clampf(0.35 + 0.65 * (nrm.x * tx + nrm.y * ty + nrm.z * tz) / d, 0.0, 1.0)
				sum += flat[o + 3] * pow(1.0 - d * flat[o + 6], flat[o + 5]) * facing
			var col := cs[vi]
			col.a = clampf(sum * 0.5, 0.0, 1.0)
			cs[vi] = col
		part.c = cs
		var mesh: ArrayMesh = meshes[m]
		mesh.clear_surfaces()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _arrays(part))

## Crea el nodo "Walls" con los trozos de pared, el techo y la colisión del techo.
func make_nodes(material: Material, shadows: bool) -> Node3D:
	var holder := Node3D.new()
	holder.name = "Walls"
	for mesh in _wall_meshes:
		var wall := _mesh_instance("Pared", mesh, material, shadows)
		wall.layers = 1 | WALL_DECAL_LAYER
		holder.add_child(wall, true)
	var body := StaticBody3D.new()
	body.name = "CeilingBody"
	body.collision_layer = 1
	body.collision_mask = 0
	# Sin sombras: aún hay luna (fase 2 la quita); el techo no debe dejar la cueva a oscuras
	for mesh in _roof_meshes:
		holder.add_child(_mesh_instance("Techo", mesh, material, false), true)
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(_roof_faces)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	holder.add_child(body)
	return holder

# ───────────────────────────── Relieve y alturas ─────────────────────────────

static func load_relief() -> void:
	if _relief.size() == RELIEF_RES * RELIEF_RES:
		return
	_relief.resize(RELIEF_RES * RELIEF_RES)
	_relief.fill(0.0)
	if not ResourceLoader.exists(RELIEF_TEX):
		return
	var img := (load(RELIEF_TEX) as Texture2D).get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_L8)
	while img.get_width() > RELIEF_RES:          # mitades bilineales ≈ media por áreas
		img.resize(maxi(RELIEF_RES, img.get_width() / 2), maxi(RELIEF_RES, img.get_height() / 2), Image.INTERPOLATE_BILINEAR)
	var data := img.get_data()
	for i in _relief.size():
		_relief[i] = data[i] / 127.5 - 1.0

## Altura del techo en cada esquina de celda: media de las celdas (suelo o roca) que la tocan, menos el
## relieve del escaneo (lo que sobresale baja el techo).
func _compute_corner_heights() -> void:
	var ids := {}                                  # esquina -> índice en sum/cnt
	var keys: Array[Vector2i] = []
	var sum := PackedFloat32Array()
	var cnt := PackedFloat32Array()
	for pass_walls in [false, true]:
		var src: Dictionary = _walls if pass_walls else _cells
		for c in src:
			var h := WALL_CEIL_H - 0.3
			if not pass_walls:
				h = WALL_CEIL_H + DOME_RISE * (1.0 - exp(-(float(_wall_dist.get(c, 1)) - 1.0) / DOME_FALLOFF))
			for k in CORNERS4:
				var corner: Vector2i = c + k
				var id: int = ids.get(corner, -1)
				if id < 0:
					id = keys.size()
					ids[corner] = id
					keys.append(corner)
					sum.append(0.0)
					cnt.append(0.0)
				sum[id] += h
				cnt[id] += 1.0
	var mask := RELIEF_RES - 1
	var scale := RELIEF_RES / RELIEF_TILE
	_corner_h.clear()
	for id in keys.size():
		var corner := keys[id]
		var x := (corner.x - 0.5) * cell
		var z := (corner.y - 0.5) * cell
		var r := _relief[(int(z * scale) & mask) * RELIEF_RES + (int(x * scale) & mask)]
		_corner_h[corner] = sum[id] / cnt[id] - r * RELIEF_AMP * 0.8

func _corner_pos(corner: Vector2i) -> Vector2:
	return Vector2((corner.x - 0.5) * cell, (corner.y - 0.5) * cell)

## Altura del techo en (x, z), bilineal entre esquinas.
func ceiling_at(x: float, z: float) -> float:
	var gx := x / cell + 0.5
	var gz := z / cell + 0.5
	var i := floori(gx)
	var j := floori(gz)
	var fx := gx - i
	var fz := gz - j
	var h00: float = _corner_h.get(Vector2i(i, j), WALL_CEIL_H)
	var h10: float = _corner_h.get(Vector2i(i + 1, j), WALL_CEIL_H)
	var h01: float = _corner_h.get(Vector2i(i, j + 1), WALL_CEIL_H)
	var h11: float = _corner_h.get(Vector2i(i + 1, j + 1), WALL_CEIL_H)
	return lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fz)

# ───────────────────────────── Contorno ─────────────────────────────

## Lazos cerrados del borde del suelo (en esquinas de celda), con la roca a la derecha del recorrido.
func _loops() -> Array:
	var out_edges := {}            # esquina -> [esquinas destino]
	var count := 0
	for c in _cells:
		var v0 := Vector2i(c.x, c.y)
		var v1 := Vector2i(c.x + 1, c.y)
		var v2 := Vector2i(c.x + 1, c.y + 1)
		var v3 := Vector2i(c.x, c.y + 1)
		if not _cells.has(c + Vector2i(0, -1)):
			_add_edge(out_edges, v0, v1)
			count += 1
		if not _cells.has(c + Vector2i(1, 0)):
			_add_edge(out_edges, v1, v2)
			count += 1
		if not _cells.has(c + Vector2i(0, 1)):
			_add_edge(out_edges, v2, v3)
			count += 1
		if not _cells.has(c + Vector2i(-1, 0)):
			_add_edge(out_edges, v3, v0)
			count += 1
	var loops: Array = []
	while not out_edges.is_empty():
		var start: Vector2i = out_edges.keys()[0]
		var pts := PackedVector2Array()
		var cur := start
		var dir := Vector2i.ZERO
		while true:
			var outs: Array = out_edges.get(cur, [])
			if outs.is_empty():
				break
			# En un pellizco diagonal (dos salidas) gira hacia el lado del suelo: separa las zonas
			var pick := 0
			if outs.size() > 1 and dir != Vector2i.ZERO:
				var floor_side := Vector2(-dir.y, dir.x)
				var best := -INF
				for k in outs.size():
					var d: Vector2 = Vector2((outs[k] as Vector2i) - cur)
					if d.dot(floor_side) > best:
						best = d.dot(floor_side)
						pick = k
			var nxt: Vector2i = outs[pick]
			outs.remove_at(pick)
			if outs.is_empty():
				out_edges.erase(cur)
			pts.append(_corner_pos(cur))
			dir = nxt - cur
			cur = nxt
			if cur == start:
				break
		if pts.size() >= 3:
			loops.append(_resample(_chaikin(_chaikin(pts))))
	return loops

func _add_edge(edges: Dictionary, a: Vector2i, b: Vector2i) -> void:
	if not edges.has(a):
		edges[a] = []
	(edges[a] as Array).append(b)

func _chaikin(p: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := p.size()
	out.resize(n * 2)
	for i in n:
		var a := p[i]
		var b := p[(i + 1) % n]
		out[i * 2] = a.lerp(b, 0.25)
		out[i * 2 + 1] = a.lerp(b, 0.75)
	return out

## Puntos a distancias iguales (~spacing) sobre el lazo cerrado.
func _resample(p: PackedVector2Array) -> PackedVector2Array:
	var n := p.size()
	var cum := PackedFloat32Array()
	cum.resize(n + 1)
	cum[0] = 0.0
	for i in n:
		cum[i + 1] = cum[i] + p[i].distance_to(p[(i + 1) % n])
	var total := cum[n]
	var m := maxi(4, roundi(total / spacing))
	var out := PackedVector2Array()
	out.resize(m)
	var seg := 0
	for k in m:
		var d := total * k / m
		while seg < n - 1 and cum[seg + 1] < d:
			seg += 1
		var t := (d - cum[seg]) / maxf(cum[seg + 1] - cum[seg], 0.0001)
		out[k] = p[seg].lerp(p[(seg + 1) % n], t)
	return out

# ───────────────────────────── Paredes ─────────────────────────────

## Trozo (clave de rejilla de `chunk` m) -> {v, n, c, i}
func _build_walls() -> Dictionary:
	var chunks := {}
	var loop_id := 0
	# Por anillo: altura relativa, cuánto se mete hacia la cueva y oscurecido de la parte alta
	var ring_t := PackedFloat32Array()
	var ring_in := PackedFloat32Array()
	var ring_shade := PackedFloat32Array()
	for k in rings:
		var t := float(k) / (rings - 1)
		ring_t.append(t)
		ring_in.append(OVERHANG * smoothstep(0.45, 1.0, t))
		ring_shade.append(lerpf(1.0, 0.6, smoothstep(0.55, 1.0, t)))
	for loop in _loops():
		var pts: PackedVector2Array = loop
		var m := pts.size()
		var length := 0.0
		for i in m:
			length += pts[i].distance_to(pts[(i + 1) % m])
		var tiles := maxf(1.0, roundf(length / RELIEF_TILE))   # el relieve cierra sin costura en el lazo
		var pos := PackedVector3Array()
		var cols := PackedColorArray()
		pos.resize(m * rings)
		cols.resize(m * rings)
		var into_rock := PackedVector2Array()
		into_rock.resize(m)
		var s := 0.0
		var mask := RELIEF_RES - 1
		var row_scale := RELIEF_RES / RELIEF_TILE
		for i in m:
			var p := pts[i]
			var t2 := (pts[(i + 1) % m] - pts[(i - 1 + m) % m]).normalized()
			var n := Vector2(t2.y, -t2.x)                 # hacia la roca
			into_rock[i] = n
			var top_h := ceiling_at(p.x - n.x * OVERHANG, p.y - n.y * OVERHANG) + TOP_SINK
			var col_i := int(s / length * tiles * RELIEF_RES) & mask
			var nz := _noise.get_noise_2d(s * 0.6 + loop_id * 97.0, 0.0) * NOISE_AMP
			var g := i * rings
			for k in rings:
				var y := -0.3 + (top_h + 0.3) * ring_t[k]
				# relieve > 0 sobresale hacia la cueva
				var d := nz - _relief[(int(y * row_scale) & mask) * RELIEF_RES + col_i] * RELIEF_AMP
				if d < 0.0 and y < FOOT_H:
					d *= 0.2 + 0.8 * maxf(y, 0.0) / FOOT_H   # junto al suelo casi no invade
				var off := d - ring_in[k]
				pos[g + k] = Vector3(p.x + n.x * off, y, p.y + n.y * off)
				cols[g + k] = rock_color * ((0.82 - 0.18 * clampf(d / RELIEF_AMP, -1.0, 1.0)) * ring_shade[k])
			s += pts[i].distance_to(pts[(i + 1) % m])
		# Anclajes: el punto de la arista vertical de cada columna a la altura anchor_h (está en la malla)
		for i in m:
			var g := i * rings
			for k in rings - 1:
				var a := pos[g + k]
				var b := pos[g + k + 1]
				if a.y <= anchor_h and b.y > anchor_h:
					anchors.append([a.lerp(b, (anchor_h - a.y) / (b.y - a.y)), -into_rock[i]])
					break
		# Normales sobre la rejilla del lazo entero (sin costuras entre trozos)
		var nrm := PackedVector3Array()
		nrm.resize(m * rings)
		for i in m:
			var inward := Vector3(-into_rock[i].x, 0.0, -into_rock[i].y)
			for k in rings:
				var along := pos[((i + 1) % m) * rings + k] - pos[((i - 1 + m) % m) * rings + k]
				var up := pos[i * rings + mini(k + 1, rings - 1)] - pos[i * rings + maxi(k - 1, 0)]
				var nn := along.cross(up).normalized()
				if nn.dot(inward) < 0.0:
					nn = -nn
				nrm[i * rings + k] = nn
		# El giro de los triángulos es el mismo en todo el lazo: se decide con un quad a media altura
		var ka := rings / 2
		var probe := PackedInt32Array()
		_quad(probe, pos, nrm, ka, rings + ka, rings + ka + 1, ka + 1)
		var flip := probe[1] != rings + ka
		# Reparto en trozos: la columna i va al trozo de su posición; su quad con la i+1 también
		var i0 := 0
		while i0 < m:
			var key := _chunk_key(pos[i0 * rings])
			var i1 := i0
			while i1 + 1 < m and _chunk_key(pos[(i1 + 1) * rings]) == key:
				i1 += 1
			# columnas i0..i1 y la siguiente (cierra el hueco con el trozo vecino)
			_emit_columns(chunks, key, pos, nrm, cols, i0, i1 + 1, m, flip)
			i0 = i1 + 1
		loop_id += 1
	return chunks

func _emit_columns(chunks: Dictionary, key: Vector2i, pos: PackedVector3Array, nrm: PackedVector3Array, cols: PackedColorArray, i0: int, i1: int, m: int, flip: bool) -> void:
	if not chunks.has(key):
		chunks[key] = Part.new()
	var ch: Part = chunks[key]
	var base := ch.v.size()
	# Columnas i0..i1 (la última puede ser la 0 si el lazo se cierra aquí): tramos contiguos
	var a0 := i0 * rings
	var a1 := mini(i1 + 1, m) * rings
	ch.v.append_array(pos.slice(a0, a1))
	ch.n.append_array(nrm.slice(a0, a1))
	ch.c.append_array(cols.slice(a0, a1))
	if i1 >= m:
		ch.v.append_array(pos.slice(0, rings))
		ch.n.append_array(nrm.slice(0, rings))
		ch.c.append_array(cols.slice(0, rings))
	var quads := (i1 - i0) * (rings - 1)
	var j := ch.i.size()
	ch.i.resize(j + quads * 6)
	for ci in range(0, i1 - i0):
		for k in rings - 1:
			var a := base + ci * rings + k
			var b := a + rings
			ch.i[j] = a
			ch.i[j + 3] = a
			if flip:
				ch.i[j + 1] = b + 1
				ch.i[j + 2] = b
				ch.i[j + 4] = a + 1
				ch.i[j + 5] = b + 1
			else:
				ch.i[j + 1] = b
				ch.i[j + 2] = b + 1
				ch.i[j + 4] = b + 1
				ch.i[j + 5] = a + 1
			j += 6

## Dos triángulos con el giro que Godot toma como cara frontal (horario visto desde la normal).
func _quad(idx: PackedInt32Array, v: PackedVector3Array, n: PackedVector3Array, a: int, b: int, c: int, d: int) -> void:
	var face := (v[b] - v[a]).cross(v[c] - v[a])
	if face.dot(n[a] + n[c]) > 0.0:
		idx.append_array([a, c, b, a, d, c])
	else:
		idx.append_array([a, b, c, a, c, d])

func _chunk_key(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / chunk), floori(p.z / chunk))

# ───────────────────────────── Techo ─────────────────────────────

## Techo: malla indexada sobre las esquinas, repartida en trozos de `chunk` m.
func _build_ceiling() -> Dictionary:
	var ids := {}                   # esquina -> índice
	var v := PackedVector3Array()
	var nn := PackedVector3Array()
	var cc := PackedColorArray()
	v.resize(_corner_h.size())
	nn.resize(_corner_h.size())
	cc.resize(_corner_h.size())
	var two_cell := 2.0 * cell
	var i := 0
	for corner in _corner_h:
		ids[corner] = i
		var h: float = _corner_h[corner]
		v[i] = Vector3((corner.x - 0.5) * cell, h, (corner.y - 0.5) * cell)
		var hx: float = (float(_corner_h.get(corner + Vector2i(1, 0), h)) - float(_corner_h.get(corner - Vector2i(1, 0), h))) / two_cell
		var hz: float = (float(_corner_h.get(corner + Vector2i(0, 1), h)) - float(_corner_h.get(corner - Vector2i(0, 1), h))) / two_cell
		nn[i] = Vector3(hx, -1.0, hz).normalized()
		cc[i] = rock_color * clampf(0.45 + (h - WALL_CEIL_H) * 0.04, 0.4, 0.7)
		i += 1
	# Todas las celdas tienen el mismo giro (normal hacia abajo): se decide con la primera
	var first: Vector2i = _cells.keys()[0]
	var probe := PackedInt32Array()
	_quad(probe, v, nn, ids[first], ids[first + Vector2i(1, 0)], ids[first + Vector2i(1, 1)], ids[first + Vector2i(0, 1)])
	var flip: bool = probe[1] != ids[first + Vector2i(1, 0)]
	# En trozos de `chunk` m como las paredes: con el renderizador Mobile cada malla recibe 8 luces omni
	# como mucho, y un techo de una pieza solo vería 8 antorchas de todo el mapa
	var parts := {}                 # trozo -> Part
	var local := {}                 # trozo -> {índice global: índice local}
	for c in _cells.keys() + _walls.keys():
		var key := _chunk_key(Vector3(c.x * cell, 0.0, c.y * cell))
		if not parts.has(key):
			parts[key] = Part.new()
			local[key] = {}
		var part: Part = parts[key]
		var map: Dictionary = local[key]
		var q: Array[int] = [ids[c], ids[Vector2i(c.x + 1, c.y)], ids[Vector2i(c.x + 1, c.y + 1)], ids[Vector2i(c.x, c.y + 1)]]
		for j in 4:
			var g: int = q[j]
			if not map.has(g):
				map[g] = part.v.size()
				part.v.append(v[g])
				part.n.append(nn[g])
				part.c.append(cc[g])
			q[j] = map[g]
		if flip:
			part.i.append_array([q[0], q[2], q[1], q[0], q[3], q[2]])
		else:
			part.i.append_array([q[0], q[1], q[2], q[0], q[2], q[3]])
	return parts

## Colisión del techo para la cámara: cuadros de 2x2 celdas, un poco por debajo del techo visible
## (la cámara se para antes de tocarlo). ~1/4 de los triángulos del techo.
func _ceiling_collision() -> PackedVector3Array:
	var faces := PackedVector3Array()
	var done := {}
	for c in _corner_h:
		var b := Vector2i(c.x & ~1, c.y & ~1)       # esquina par del cuadro que la contiene
		if done.has(b):
			continue
		done[b] = true
		var q := [b, b + Vector2i(2, 0), b + Vector2i(2, 2), b + Vector2i(0, 2)]
		var p := PackedVector3Array()
		for k in q:
			var corner: Vector2i = k
			var h: float = _corner_h.get(corner, _corner_h.get(b, WALL_CEIL_H))
			p.append(Vector3((corner.x - 0.5) * cell, h - 0.5, (corner.y - 0.5) * cell))
		faces.append_array([p[0], p[1], p[2], p[0], p[2], p[3]])
	return faces

func _arrays(part: Part) -> Array:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = part.v
	arrays[Mesh.ARRAY_NORMAL] = part.n
	arrays[Mesh.ARRAY_COLOR] = part.c
	arrays[Mesh.ARRAY_INDEX] = part.i
	return arrays

func _array_mesh(ch: Dictionary) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = ch["v"]
	arrays[Mesh.ARRAY_NORMAL] = ch["n"]
	arrays[Mesh.ARRAY_COLOR] = ch["c"]
	arrays[Mesh.ARRAY_INDEX] = ch["i"]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _mesh_instance(nm: String, mesh: ArrayMesh, material: Material, shadows: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = mesh
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
