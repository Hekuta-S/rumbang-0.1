class_name DungeonMap
extends ProceduralMap

## Cuevas goblin procedurales (modo "dungeon", estilo Soul Knight).
##
## A partir de una semilla genera 6–8 cavernas sobre una rejilla de huecos, unidas
## por túneles serpenteantes (árbol + algún bucle). La caverna inicial queda en el
## origen y la final (la más lejana) guarda el altar.
##  - Forma de cada caverna: unión de varias elipses con borde deformado por ruido
##    (nunca un cuadrado), de 28–44 m de ancho.
##  - Suelo de tierra y paredes de roca irregulares (MultiMesh, 1 llamada cada uno);
##    colisión de paredes con cajas fusionadas por filas.
##  - Temas por caverna: campamento (chozas, tiendas, fogata), almacén (barriles y
##    cajas destruibles, empalizadas) o santuario (tótem y postes de calaveras).
##  - Barriles y cajas son DestructibleProp: se rompen a golpes.
## Reutiliza de ProceduralMap el sistema de props/luces y expone get_height_at()
## (suelo plano = 0) y get_colliders() (paredes incluidas) para EnemyMotion.

const CELL := 2.0                     ## lado de una celda (m)
const SLOT := 26                      ## separación entre centros de caverna (celdas)
const WALL_H := 4.0
const TUNNEL_R := 1.6                 ## radio de los túneles (celdas)
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const DIRS8 := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]

const FLOOR := 1
const CORRIDOR := 2

## Formas de caverna (las normales eligen una al azar):
##  blobs   elipse principal con 2-4 lóbulos (la clásica)
##  cross   dos elipses alargadas cruzadas: cuatro brazos
##  hall    sala larga con dos filas de columnas de roca
##  twin    dos cámaras unidas por un cuello estrecho
##  pillars la clásica con 3-5 columnas de roca para cubrirse
const SHAPES := ["blobs", "cross", "hall", "twin", "pillars"]
const PILLAR_R := 1.3                 ## radio de las columnas (celdas)
const CENTER_CLEAR := 4.0             ## celdas libres alrededor del centro (encuentros, portal)
## Probabilidad de que una caverna normal sea de TESORO (sin enemigos, con botín).
const TREASURE_CHANCE := 0.6
## Estructuras que se pueden destruir a golpes (nodos DestructibleProp en vez de instancias fijas).
const STRUCTURES := ["hut", "tent", "palisade", "skull_pole", "totem"]
const TOTEM_SOULS := 3                ## almas verdes que suelta un tótem al romperse
const SHRINE_TOTEM_SOULS := 5         ## el tótem grande del santuario suelta más

## Amplitud del ruido que deforma el borde de las cavernas (en radios de la elipse).
var edge_noise_amp := 0.28
## Mundo (ver WorldDefs): paletas de nivel y decoración. Vacío = el elegido en GameData.world.
var world_id := ""
## Índice del tema del nivel actual (lo pone DungeonEncounter antes de generar: nivel 1 → 0, 2 → 1…).
var level_theme := 0

func world() -> Dictionary:
	return WorldDefs.get_def(world_id if world_id != "" else GameData.world)

## Paleta del nivel actual: suelo, roca, color del fuego y extras (ver WorldDefs.WORLDS).
func palette() -> Dictionary:
	var themes: Array = world()["level_themes"]
	return themes[posmod(level_theme, themes.size())]

@export var min_rooms: int = 6
@export var max_rooms: int = 8
@export var slot_limit: int = 2       ## huecos válidos: -slot_limit..slot_limit
@export var room_radius: Vector2i = Vector2i(7, 10)   ## radio de la elipse principal (celdas)
@export var grass_per_room: int = 140

## Cavernas: [{slot, center: Vector3, half: Vector2 (m, caja envolvente), type, theme, cells: Array[Vector2i]}]
var rooms: Array = []
## Caverna de pruebas de combate (vecina de la inicial, tema "almacén"): ver DungeonEncounter.
var arena_index: int = -1
var destructibles: Array[DestructibleProp] = []
var _cells: Dictionary = {}           # Vector2i -> FLOOR | CORRIDOR
var _owner: Dictionary = {}           # Vector2i -> índice de caverna
var _wall_dist: Dictionary = {}       # Vector2i (suelo) -> distancia en celdas a la pared
var _walls: Dictionary = {}           # Vector2i -> true (primer anillo, con colisión)
var _outer: Dictionary = {}           # Vector2i -> true (segundo anillo, solo visual)
var _wall_boxes: Array = []           # [{pos: Vector2, half: Vector2}]
var _grass: Array[Transform3D] = []
var _breakables: Array = []           # [[kind, Transform3D]]
var _crystals: Array = []             # [Transform3D] (temas con cristales)
var _edge_noise := FastNoiseLite.new()

func generate(p_seed: int = 0) -> void:
	_clear()
	for d in destructibles:
		if is_instance_valid(d):
			d.queue_free()
	destructibles.clear()
	rooms.clear()
	_cells.clear()
	_owner.clear()
	_wall_dist.clear()
	_walls.clear()
	_outer.clear()
	_wall_boxes.clear()
	_grass.clear()
	_breakables.clear()
	_crystals.clear()
	# Navegación del mapa anterior
	_flow_cache.clear()
	_flow_order.clear()
	_flow = {}
	_flow_target = Vector2i(-99999, -99999)
	_blocked.clear()
	_blocked_ready = false
	_prop_cells.clear()
	# En red todos usan la semilla del anfitrión (Net.level_seed) para generar el mismo mapa
	if p_seed == 0 and Net.is_online() and Net.level_seed != 0:
		p_seed = Net.level_seed
	used_seed = p_seed if p_seed != 0 else int(Time.get_unix_time_from_system()) ^ randi()
	_rng.seed = used_seed
	_edge_noise.seed = used_seed
	_edge_noise.frequency = 0.09
	_layout_rooms()
	_carve()
	_find_walls()
	_compute_wall_dist()
	_build_floor()
	_build_walls()
	for i in rooms.size():
		_decorate_room(i)
	_build_prop_nodes()
	_build_grass()
	_build_crystals()
	_build_breakables()
	_build_extra()
	generated.emit(used_seed)
	print("[DungeonMap] semilla=", used_seed, " cavernas=", rooms.size(), " celdas=", _cells.size(),
		" props=", _count_instances(), " rompibles=", destructibles.size())

func get_height_at(_x: float, _z: float) -> float:
	return 0.0

func get_colliders() -> Array:
	var out := super.get_colliders()
	for d in destructibles:
		if is_instance_valid(d) and not d.is_broken() and d.kind in STRUCTURES:
			var def: Dictionary = _prop_def(d.kind)
			var size: Vector3 = def["size"]
			var sc := d.transform.basis.get_scale().x
			var o := {"pos": Vector2(d.position.x, d.position.z), "yaw": d.transform.basis.get_euler().y}
			if def["shape"] == "cyl":
				o["shape"] = "cyl"
				o["r"] = size.x * sc
				o["half"] = Vector2.ZERO
			else:
				o["shape"] = "box"
				o["half"] = Vector2(size.x * 0.5, size.z * 0.5) * sc
				o["r"] = (o["half"] as Vector2).length()
			out.append(o)
	for b in _wall_boxes:
		var half: Vector2 = b["half"]
		out.append({"pos": b["pos"], "yaw": 0.0, "shape": "box", "half": half, "r": half.length()})
	return out

## Centro de la caverna final (aquí irá el jefe / portal).
func get_basin_center() -> Vector3:
	for r in rooms:
		if r["type"] == "end":
			return r["center"]
	return Vector3.ZERO

# ───────────────────────────── Distribución ─────────────────────────────

func _layout_rooms() -> void:
	var target := _rng.randi_range(min_rooms, max_rooms)
	var slots: Array[Vector2i] = [Vector2i.ZERO]
	var links: Array = []
	var guard := 0
	while slots.size() < target and guard < 500:
		guard += 1
		var from: Vector2i = slots[_rng.randi() % slots.size()]
		var to: Vector2i = from + DIRS[_rng.randi() % 4]
		if to in slots or absi(to.x) > slot_limit or absi(to.y) > slot_limit:
			continue
		slots.append(to)
		links.append([from, to])
	# Un bucle extra entre vecinos aún no unidos, para que no sea un árbol lineal
	for s in slots:
		for d in DIRS:
			var n: Vector2i = s + d
			if n in slots and not _linked(links, s, n) and _rng.randf() < 0.15:
				links.append([s, n])

	var far := _farthest(slots, links)
	for s in slots:
		var type := "start" if s == Vector2i.ZERO else ("end" if s == far else "normal")
		# Centro desplazado dentro del hueco para que no quede todo alineado
		var jitter := Vector2i(_rng.randi_range(-3, 3), _rng.randi_range(-3, 3)) if type == "normal" else Vector2i.ZERO
		var c := s * SLOT + jitter
		# Elipses: la principal en el centro + 2–4 lóbulos alrededor
		var blobs: Array = []
		var r0 := Vector2(_rng.randi_range(room_radius.x, room_radius.y), _rng.randi_range(room_radius.x, room_radius.y))
		if type != "normal":
			r0 = Vector2(room_radius.x + 1, room_radius.x + 1)
		var shape := _base_shape() if type != "normal" else _pick_shape()
		var pillars: Array = []
		_shape_blobs(shape, Vector2(c), r0, blobs, pillars)
		rooms.append({
			"shape": shape,
			"pillars": pillars,
			"slot": s,
			"cell": c,
			"blobs": blobs,
			"center": Vector3(c.x * CELL, 0.0, c.y * CELL),
			"type": type,
			"theme": "start" if type == "start" else ("end" if type == "end" else _room_theme()),
			"cells": [],
		})
	set_meta("links", links)
	_pick_arena(links)
	_pick_treasure()

## Forma de la caverna inicial y la final.
func _base_shape() -> String:
	return "blobs"

## Forma al azar de una caverna normal (ver SHAPES).
func _pick_shape() -> String:
	return String(SHAPES[_rng.randi() % SHAPES.size()])

## Decoración al azar de una caverna normal, según el mundo.
func _room_theme() -> String:
	var themes: Array = world()["room_themes"]
	return String(themes[_rng.randi() % themes.size()])

## La primera caverna conectada a la inicial (que no sea la final) es la arena del primer encuentro.
## Se fuerza el tema "almacén" para probar barriles, cajas y empalizadas durante el combate.
func _pick_arena(links: Array) -> void:
	arena_index = -1
	for l in links:
		var other: Vector2i
		if l[0] == Vector2i.ZERO:
			other = l[1]
		elif l[1] == Vector2i.ZERO:
			other = l[0]
		else:
			continue
		var idx := _room_index(other)
		if idx >= 0 and (arena_index < 0 or rooms[arena_index]["type"] == "end"):
			arena_index = idx
	if arena_index >= 0 and rooms[arena_index]["type"] == "normal":
		rooms[arena_index]["theme"] = "storage"

## Centro (mundo) y radio aproximado (m) de una caverna.
func room_center(i: int) -> Vector3:
	return rooms[i]["center"]

## Bocas de túnel de la caverna `i`: celdas de túnel pegadas a su suelo, agrupadas por túnel.
## Cada boca es un Array de posiciones de mundo (centros de celda). Las usan las puertas.
func room_mouths(i: int) -> Array:
	var mouth: Dictionary = {}
	for c in (rooms[i]["cells"] as Array):
		for d in DIRS8:
			var n: Vector2i = c + d
			if _cells.get(n, 0) == CORRIDOR:
				mouth[n] = true
	var groups: Array = []
	var seen: Dictionary = {}
	for start in mouth:
		if seen.has(start):
			continue
		var group: Array = []
		var stack: Array = [start]
		seen[start] = true
		while not stack.is_empty():
			var c: Vector2i = stack.pop_back()
			group.append(_cell_pos(c))
			for d in DIRS8:
				var n: Vector2i = c + d
				if mouth.has(n) and not seen.has(n):
					seen[n] = true
					stack.append(n)
		groups.append(group)
	return groups

## ¿Está esta posición sobre el suelo propio (no túnel) de la caverna `i`?
func is_in_room(p: Vector3, i: int) -> bool:
	return _owner.get(world_to_cell(p), -1) == i

func room_reach(i: int) -> float:
	var r0: Vector2 = rooms[i]["blobs"][0][1]
	return minf(r0.x, r0.y) * CELL

# ───────────────────────────── Navegación ─────────────────────────────
# Campo de flujo sobre la rejilla de suelo: un BFS desde la celda objetivo da a cada celda
# su distancia en pasos. Se recalcula solo cuando el objetivo cambia de celda.

var _flow: Dictionary = {}            # Vector2i -> pasos hasta el objetivo
var _flow_target := Vector2i(-99999, -99999)
var _blocked: Dictionary = {}         # Vector2i -> true (celdas tapadas por props fijos: vallas, tiendas...)
var _blocked_ready := false
const BLOCKED_COST := 6
## Caché de campos de flujo por celda objetivo. Con varios jugadores los enemigos persiguen a objetivos
## distintos: sin caché, el campo se recalculaba entero cada vez que cambiaba de jugador.
const FLOW_CACHE_MAX := 8
var _flow_cache: Dictionary = {}      # Vector2i -> campo
var _flow_order: Array[Vector2i] = []

func _use_flow(target: Vector2i) -> void:
	if _flow_cache.has(target):
		_flow = _flow_cache[target]
		_flow_target = target
		_flow_order.erase(target)
		_flow_order.append(target)
		return
	_build_flow(target)
	_flow_cache[target] = _flow
	_flow_order.append(target)
	while _flow_order.size() > FLOW_CACHE_MAX:
		_flow_cache.erase(_flow_order.pop_front())

## Celdas de suelo que ocupa algún colisionador de PropColliders (huella AABB, más medio
## cuerpo de margen).
func _collect_blocked() -> void:
	_blocked_ready = true
	var body := get_node_or_null("PropColliders")
	if body == null:
		return
	for cs in body.get_children():
		if not (cs is CollisionShape3D) or cs.shape == null:
			continue
		var half := Vector3.ONE * 0.5
		if cs.shape is BoxShape3D:
			half = (cs.shape as BoxShape3D).size * 0.5
		elif cs.shape is CylinderShape3D:
			var r: float = (cs.shape as CylinderShape3D).radius
			half = Vector3(r, 1.0, r)
		var xf: Transform3D = cs.global_transform
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var w := xf * Vector3(half.x * sx, 0.0, half.z * sz)
				lo = Vector2(minf(lo.x, w.x), minf(lo.y, w.z))
				hi = Vector2(maxf(hi.x, w.x), maxf(hi.y, w.z))
		for cx in range(roundi(lo.x / CELL), roundi(hi.x / CELL) + 1):
			for cz in range(roundi(lo.y / CELL), roundi(hi.y / CELL) + 1):
				var c := Vector2i(cx, cz)
				# Solo si el prop cubre de verdad el centro de la celda (± medio cuerpo)
				var cp := Vector2(cx * CELL, cz * CELL)
				if _cells.has(c) and cp.x > lo.x - 0.5 and cp.x < hi.x + 0.5 and cp.y > lo.y - 0.5 and cp.y < hi.y + 0.5:
					_blocked[c] = true

func world_to_cell(p: Vector3) -> Vector2i:
	return Vector2i(roundi(p.x / CELL), roundi(p.z / CELL))

## Siguientes `count` puntos (mundo, centros de celda) del camino de `from` a `to` rodeando
## las paredes. Vacío si alguno de los dos está fuera del suelo.
func flow_path(from: Vector3, to: Vector3, count: int = 6) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var tc := world_to_cell(to)
	if not _cells.has(tc):
		return out
	if tc != _flow_target:
		_use_flow(tc)
	var cur := world_to_cell(from)
	if not _flow.has(cur):
		# Pegado a un prop (celda bloqueada): salir por la vecina más cercana al objetivo
		var best := -1
		for d in DIRS8:
			var n: Vector2i = cur + d
			if _flow.has(n) and (best < 0 or int(_flow[n]) < best):
				best = _flow[n]
				cur = n
		if best < 0:
			return out
		out.append(_cell_pos(cur))
	for i in count:
		var nxt := _flow_step(cur)
		if nxt == cur:
			break
		cur = nxt
		out.append(to if cur == tc else _cell_pos(cur))
	return out

## true si un cuerpo de radio `radius` va en línea recta de `a` a `b` sin salir del suelo
## (solo paredes: comprobación exacta sobre la rejilla, sin física).
func segment_walkable(a: Vector3, b: Vector3, radius: float) -> bool:
	var d := Vector2(b.x - a.x, b.z - a.z)
	var n := maxi(int(d.length() / (CELL * 0.25)), 1)
	var side := Vector2(-d.y, d.x).normalized() * radius
	for i in n + 1:
		var p := Vector2(a.x, a.z) + d * (float(i) / n)
		for o in [Vector2.ZERO, side, -side]:
			var q: Vector2 = p + o
			if not _cells.has(Vector2i(roundi(q.x / CELL), roundi(q.y / CELL))):
				return false
	return true

func _flow_step(c: Vector2i) -> Vector2i:
	var best := c
	var best_d: int = _flow[c]
	for d in DIRS8:
		var n: Vector2i = c + d
		if not _flow.has(n) or int(_flow[n]) >= best_d:
			continue
		# Sin cortar esquinas en diagonal
		if d.x != 0 and d.y != 0 and not (_cells.has(c + Vector2i(d.x, 0)) and _cells.has(c + Vector2i(0, d.y))):
			continue
		best = n
		best_d = _flow[n]
	return best

## Un enemigo se ha atascado al entrar en la celda de `p`: encarecerla y recalcular el flujo.
func penalize_cell(p: Vector3) -> void:
	var c := world_to_cell(p)
	if _cells.has(c) and not _blocked.has(c):
		_blocked[c] = true
		_flow_target = Vector2i(-99999, -99999)
		_flow_cache.clear()
		_flow_order.clear()

## Dijkstra con cola de cubetas (los costes son enteros pequeños): las celdas tapadas por un
## prop cuestan BLOCKED_COST en vez de 1, así el camino las evita sin quedar nunca cortado.
func _build_flow(target: Vector2i) -> void:
	if not _blocked_ready:
		_collect_blocked()
	_flow_target = target
	_flow = {}
	_flow[target] = 0
	var buckets: Array = [[target]]
	var dist := 0
	while dist < buckets.size():
		for cur in buckets[dist]:
			if int(_flow[cur]) != dist:
				continue   # entrada obsoleta: ya se encontró un camino más corto
			for d in DIRS:
				var n: Vector2i = cur + d
				if not _cells.has(n):
					continue
				var nd: int = dist + (BLOCKED_COST if _blocked.has(n) else 1)
				if _flow.has(n) and int(_flow[n]) <= nd:
					continue
				_flow[n] = nd
				while buckets.size() <= nd:
					buckets.append([])
				buckets[nd].append(n)
		dist += 1

func _linked(links: Array, a: Vector2i, b: Vector2i) -> bool:
	for l in links:
		if (l[0] == a and l[1] == b) or (l[0] == b and l[1] == a):
			return true
	return false

## Caverna más lejana (BFS) desde la inicial.
func _farthest(slots: Array[Vector2i], links: Array) -> Vector2i:
	var dist := {Vector2i.ZERO: 0}
	var queue: Array[Vector2i] = [Vector2i.ZERO]
	var best := Vector2i.ZERO
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		for l in links:
			var nxt: Vector2i
			if l[0] == cur:
				nxt = l[1]
			elif l[1] == cur:
				nxt = l[0]
			else:
				continue
			if not dist.has(nxt):
				dist[nxt] = dist[cur] + 1
				queue.append(nxt)
				if dist[nxt] > dist[best]:
					best = nxt
	return best

func _room_index(slot: Vector2i) -> int:
	for i in rooms.size():
		if rooms[i]["slot"] == slot:
			return i
	return -1

func _carve() -> void:
	for i in rooms.size():
		var r: Dictionary = rooms[i]
		var c: Vector2i = r["cell"]
		# Caja que envuelve todas las elipses (+ margen del ruido del borde)
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for b in r["blobs"]:
			var bc: Vector2 = b[0]
			var br: Vector2 = (b[1] as Vector2) * 1.3
			lo = Vector2(minf(lo.x, bc.x - br.x), minf(lo.y, bc.y - br.y))
			hi = Vector2(maxf(hi.x, bc.x + br.x), maxf(hi.y, bc.y + br.y))
		for x in range(floori(lo.x), ceili(hi.x) + 1):
			for z in range(floori(lo.y), ceili(hi.y) + 1):
				var p := Vector2(x, z)
				var best := INF
				for b in r["blobs"]:
					best = minf(best, _blob_dist(p, b))
				# Borde deformado por ruido (|ruido| ≤ 1 → ±edge_noise_amp): solo se consulta cerca del borde
				if best > 1.3:
					continue
				if best < 0.7 or best + _edge_noise.get_noise_2d(x, z) * edge_noise_amp < 1.0:
					var cell := Vector2i(x, z)
					if not _cells.has(cell):
						_cells[cell] = FLOOR
						_owner[cell] = i
						(r["cells"] as Array).append(cell)
	for l in get_meta("links"):
		_carve_tunnel(Vector2(rooms[_room_index(l[0])]["cell"]), Vector2(rooms[_room_index(l[1])]["cell"]))
	_raise_pillars()

## Distancia normalizada de la celda `p` a una elipse [centro, radios] (1 = borde). Con un tercer
## valor (exponente > 2) la forma es una superelipse: un rectángulo de esquinas redondeadas.
func _blob_dist(p: Vector2, b: Array) -> float:
	var d: Vector2 = ((p - (b[0] as Vector2)) / (b[1] as Vector2)).abs()
	var power: float = b[2] if b.size() > 2 else 2.0
	if power == 2.0:
		return d.length()
	return pow(pow(d.x, power) + pow(d.y, power), 1.0 / power)

## Túnel serpenteante entre los centros (en celdas) de dos cavernas.
func _carve_tunnel(a: Vector2, b: Vector2) -> void:
	var length := a.distance_to(b)
	var side := (b - a).normalized().orthogonal()
	var amp := _rng.randf_range(1.5, 3.5)
	var phase := _rng.randf() * TAU
	var steps := int(length * 2.0)
	for k in steps + 1:
		var t := float(k) / steps
		var p := a.lerp(b, t) + side * sin(t * PI * 2.0 + phase) * amp * sin(t * PI)
		var rad := TUNNEL_R + _edge_noise.get_noise_2d(p.x * 3.0, p.y * 3.0) * 0.5
		for dx in range(-3, 4):
			for dz in range(-3, 4):
				var q := Vector2i(roundi(p.x) + dx, roundi(p.y) + dz)
				if Vector2(q).distance_to(p) <= rad and not _cells.has(q):
					_cells[q] = CORRIDOR

func _find_walls() -> void:
	for c in _cells:
		for d in DIRS8:
			var n: Vector2i = c + d
			if not _cells.has(n):
				_walls[n] = true
	for w in _walls:
		for d in DIRS8:
			var n: Vector2i = w + d
			if not _cells.has(n) and not _walls.has(n):
				_outer[n] = true

## Distancia (en celdas, BFS) de cada celda de suelo a la pared más cercana.
func _compute_wall_dist() -> void:
	var queue: Array[Vector2i] = []
	for c in _cells:
		for d in DIRS:
			if _walls.has(c + d):
				_wall_dist[c] = 1
				queue.append(c)
				break
	var head := 0
	while head < queue.size():
		var cur := queue[head]
		head += 1
		for d in DIRS:
			var n: Vector2i = cur + d
			if _cells.has(n) and not _wall_dist.has(n):
				_wall_dist[n] = int(_wall_dist[cur]) + 1
				queue.append(n)

func _cell_pos(c: Vector2i) -> Vector3:
	return Vector3(c.x * CELL, 0.0, c.y * CELL)

# ───────────────────────────── Geometría ─────────────────────────────

func _build_floor() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(CELL, CELL)
	plane.material = _floor_material()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = plane
	mm.instance_count = _cells.size()
	var i := 0
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for c in _cells:
		var p := _cell_pos(c)
		mm.set_instance_transform(i, Transform3D(Basis(), p))
		mm.set_instance_color(i, _floor_color(c))
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
		i += 1
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Floor"
	mmi.multimesh = mm
	mmi.layers = GROUND_VISUAL_LAYER
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)

	var body := StaticBody3D.new()
	body.name = "FloorBody"
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(hi.x - lo.x + CELL * 4.0, 1.0, hi.y - lo.y + CELL * 4.0)
	cs.shape = bx
	cs.position = Vector3((lo.x + hi.x) * 0.5, -0.5, (lo.y + hi.y) * 0.5)
	body.add_child(cs)
	add_child(body)

func _floor_material() -> Material:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	return mat

## Color de la celda de suelo `c`: tierra con manchas de musgo cerca de las paredes.
func _floor_color(c: Vector2i) -> Color:
	var n := (_edge_noise.get_noise_2d(c.x * 4.0, c.y * 4.0) + 1.0) * 0.5
	var near_wall := 1.0 - clampf(float(_wall_dist.get(c, 4)) / 4.0, 0.0, 1.0)
	var col: Color = (palette()["dirt"] as Color).lerp(palette()["moss"], n * 0.5 + near_wall * 0.4) * _rng.randf_range(0.85, 1.05)
	if _cells[c] == CORRIDOR:
		col *= 0.85
	return col

func _build_walls() -> void:
	_build_wall_visuals()
	_build_wall_colliders()

## Bloques de roca girados y escalados al azar: pared de cueva sin rejilla visible.
func _build_wall_visuals() -> void:
	var rock := BoxMesh.new()
	rock.size = Vector3(CELL, 1.0, CELL)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	rock.material = mat
	var all: Array = []
	for c in _walls:
		all.append([c, _rng.randf_range(WALL_H * 0.8, WALL_H * 1.3), 1.25])
	for c in _outer:
		all.append([c, _rng.randf_range(WALL_H * 1.3, WALL_H * 2.0), 1.4])
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = rock
	mm.instance_count = all.size()
	for i in all.size():
		var c: Vector2i = all[i][0]
		var h: float = all[i][1]
		var s: float = all[i][2] * _rng.randf_range(0.9, 1.15)
		var basis := Basis.from_euler(Vector3(_rng.randf_range(-0.12, 0.12), _rng.randf() * TAU, _rng.randf_range(-0.12, 0.12)))
		basis = basis.scaled_local(Vector3(s, h, s))
		mm.set_instance_transform(i, Transform3D(basis, _cell_pos(c) + Vector3(0.0, h * 0.5 - 0.2, 0.0)))
		var v := _rng.randf_range(0.7, 1.0)
		mm.set_instance_color(i, (palette()["rock"] as Color) * v)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Walls"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if _mobile else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mmi)

## Colisión: fusiona celdas consecutivas de cada fila en una sola caja.
func _build_wall_colliders() -> void:
	var body := StaticBody3D.new()
	body.name = "WallColliders"
	body.collision_mask = 0
	add_child(body)
	# Tramos de cada fila; luego los tramos iguales de filas seguidas se funden en un rectángulo
	var rows: Dictionary = {}
	for c in _walls:
		if not rows.has(c.y):
			rows[c.y] = []
		(rows[c.y] as Array).append(c.x)
	var spans: Dictionary = {}                 # z -> [[x0, x1], ...]
	for z in rows:
		var xs: Array = rows[z]
		xs.sort()
		var list: Array = []
		var start: int = xs[0]
		var prev: int = xs[0]
		for k in range(1, xs.size() + 1):
			if k < xs.size() and xs[k] == prev + 1:
				prev = xs[k]
				continue
			list.append([start, prev])
			if k < xs.size():
				start = xs[k]
				prev = xs[k]
		spans[z] = list
	var zs: Array = spans.keys()
	zs.sort()
	var open: Dictionary = {}                  # "x0:x1" -> z inicial del rectángulo abierto
	for zi in zs.size():
		var z: int = zs[zi]
		var here: Dictionary = {}
		for sp in spans[z]:
			here["%d:%d" % [sp[0], sp[1]]] = sp
		# Cerrar los rectángulos que no siguen en esta fila (o si hay un hueco de filas)
		for key in open.keys():
			if not here.has(key) or (zi > 0 and zs[zi - 1] != z - 1):
				var p: PackedStringArray = key.split(":")
				_add_wall_box(int(p[0]), int(p[1]), int(open[key]), z - 1 if here.has(key) else int(zs[zi - 1]), body)
				open.erase(key)
		for key in here:
			if not open.has(key):
				open[key] = z
	for key in open:
		var p2: PackedStringArray = key.split(":")
		_add_wall_box(int(p2[0]), int(p2[1]), int(open[key]), int(zs[zs.size() - 1]), body)

func _add_wall_box(x0: int, x1: int, z0: int, z1: int, body: StaticBody3D) -> void:
	var len_x := float(x1 - x0 + 1) * CELL
	var len_z := float(z1 - z0 + 1) * CELL
	var center := Vector2((x0 + x1) * 0.5 * CELL, (z0 + z1) * 0.5 * CELL)
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(len_x, WALL_H, len_z)
	cs.shape = bx
	cs.position = Vector3(center.x, WALL_H * 0.5, center.y)
	body.add_child(cs)
	_wall_boxes.append({"pos": center, "half": Vector2(len_x * 0.5, len_z * 0.5)})

# ───────────────────────────── Decoración ─────────────────────────────

## Celda libre al azar de la caverna con al menos `min_wall` celdas de pared y
## `max_wall` como máximo (pegado a la pared = 1). Vector2.INF si no encuentra.
func _spot(room: Dictionary, radius: float, min_wall: int, max_wall: int = 99) -> Vector2:
	var cells: Array = room["cells"]
	for attempt in 40:
		var c: Vector2i = cells[_rng.randi() % cells.size()]
		var wd: int = _wall_dist.get(c, 0)
		if wd < min_wall or wd > max_wall:
			continue
		var p := Vector2(c.x * CELL, c.y * CELL) + Vector2(_rng.randf_range(-0.6, 0.6), _rng.randf_range(-0.6, 0.6))
		if not _occupied(p, radius):
			return p
	return Vector2.INF

## Orientación hacia el centro de la caverna (las chozas miran al fuego).
func _yaw_to(p: Vector2, target: Vector2) -> float:
	var d := target - p
	return atan2(d.x, d.y)

func _decorate_room(i: int) -> void:
	var r: Dictionary = rooms[i]
	var c: Vector3 = r["center"]
	var center := Vector2(c.x, c.z)
	_reserve(center, 4.5)                                 # centro libre para combatir

	match r["theme"]:
		"treasure":
			# Cámara del tesoro: pedestal con luz dorada, braseros y mercancía apilada
			_place("totem", center + Vector2(0.0, -2.5), 1.0, 0.0, 0.9)
			_add_light(Vector3(center.x, 1.8, center.y), Color(1.0, 0.82, 0.35), 2.8, 13.0)
			for k in 4:
				var a4 := TAU * (k + 0.5) / 4.0
				_add_brazier(center + Vector2(cos(a4), sin(a4)) * 6.5)
			for k in _rng.randi_range(3, 5):
				var pt := _spot(r, 1.5, 2, 4)
				if pt != Vector2.INF:
					if _rng.randf() < 0.5:
						_crate_stack(pt)
					else:
						_barrel_cluster(pt)
		"start":
			_add_campfire(center + Vector2(4.5, 3.0))
			for k in 2:
				_try_place(r, "tent", 2.0, 4, 6, center)
			for k in 3:
				_try_place(r, "skull_pole", 0.6, 2, 4)
		"end":
			_add("altar", center, 0.0, 1.0)
			for k in 6:
				var a := TAU * k / 6.0
				var p := center + Vector2(cos(a), sin(a)) * 7.0
				_place("totem" if k % 2 == 0 else "skull_pole", p, 1.0, _yaw_to(p, center))
			for k in 3:
				var a2 := TAU * (k + 0.5) / 3.0
				_add_brazier(center + Vector2(cos(a2), sin(a2)) * 10.0)
		"camp":
			_add_campfire(center + Vector2(_rng.randf_range(-2.5, 2.5), _rng.randf_range(-2.5, 2.5)) * 0.0)
			for k in _rng.randi_range(2, 3):
				_try_place(r, "hut", 3.0, 4, 6, center)
			for k in _rng.randi_range(1, 2):
				_try_place(r, "tent", 2.0, 3, 6, center)
			for k in _rng.randi_range(2, 4):
				_try_place(r, "skull_pole", 0.6, 2, 5)
			_try_place(r, "totem", 0.9, 3, 6)
			for k in _rng.randi_range(2, 3):
				var p := _spot(r, 1.5, 2, 4)
				if p != Vector2.INF:
					_barrel_cluster(p)
		"storage":
			for k in _rng.randi_range(5, 8):
				var p := _spot(r, 1.5, 2, 5)
				if p == Vector2.INF:
					continue
				if _rng.randf() < 0.55:
					_barrel_cluster(p)
				else:
					_crate_stack(p)
			for k in _rng.randi_range(2, 3):
				_try_place(r, "palisade", 1.8, 3, 5, center)
			_add_brazier(center + Vector2(5.0, 0.0))
		"shrine":
			_place("totem", center, 1.2, 0.0, 1.3)
			for k in 5:
				var a := TAU * k / 5.0 + 0.3
				var p := center + Vector2(cos(a), sin(a)) * 5.5
				_place("skull_pole", p, 0.6, _yaw_to(p, center))
			for k in 2:
				var a3 := _rng.randf() * TAU
				_add_brazier(center + Vector2(cos(a3), sin(a3)) * 8.5)
			for k in _rng.randi_range(2, 4):
				var p2 := _spot(r, 1.2, 2, 4)
				if p2 != Vector2.INF:
					_barrel_cluster(p2)

	# Estalagmitas pegadas a la pared: cierran la silueta de la cueva
	for k in _rng.randi_range(6, 10):
		_try_place(r, "stalagmite", 1.0, 1, 2)
	# Detalle suelto: huesos, hongos, rocas pequeñas
	var detail: Array = ["mushroom", "mushroom", "rock_a"]
	for b in int(palette()["bones"]):
		detail.append("bones")
	for k in _rng.randi_range(8, 14):
		var p := _spot(r, 0.8, 1, 99)
		if p == Vector2.INF:
			continue
		var kind: String = detail[_rng.randi() % detail.size()]
		var s := 0.45 if kind == "rock_a" else -1.0
		_place(kind, p, 0.8, -1.0, s, kind == "rock_a")
	_scatter_grass(r)
	_place_crystals(r)

func _try_place(r: Dictionary, kind: String, radius: float, min_wall: int, max_wall: int, face: Vector2 = Vector2.INF) -> void:
	var p := _spot(r, radius, min_wall, max_wall)
	if p == Vector2.INF:
		return
	_place(kind, p, radius, _yaw_to(p, face) if face != Vector2.INF else -1.0)

func _add_campfire(pos: Vector2) -> void:
	_place("campfire", pos, 1.5, -1.0, 1.0)
	_add_light(Vector3(pos.x, 1.4, pos.y), palette()["fire"], 3.2, 14.0)
	if embers_enabled:
		_add_embers(Vector3(pos.x, 0.8, pos.y))

# Barriles y cajas: se guardan aparte y se crean como DestructibleProp
func _breakable(kind: String, pos: Vector2, y: float = 0.0, s: float = -1.0, tilt: float = 0.0) -> void:
	var sc: Vector2 = _prop_def(kind)["scale"]
	var scale_v := s if s > 0.0 else _rng.randf_range(sc.x, sc.y)
	var basis := Basis.from_euler(Vector3(_rng.randf_range(-tilt, tilt), _rng.randf() * TAU, _rng.randf_range(-tilt, tilt))).scaled(Vector3.ONE * scale_v)
	_breakables.append([kind, Transform3D(basis, Vector3(pos.x, y, pos.y))])

func _barrel_cluster(at: Vector2) -> void:
	_reserve(at, 0.6)
	_breakable("barrel", at)
	for i in _rng.randi_range(1, 3):
		var p := at + Vector2(_rng.randf_range(-1.3, 1.3), _rng.randf_range(-1.3, 1.3))
		if not _occupied(p, 0.55):
			_reserve(p, 0.55)
			_breakable("barrel", p, 0.0, -1.0, 0.06 if _rng.randf() < 0.3 else 0.0)

func _crate_stack(at: Vector2) -> void:
	_reserve(at, 0.8)
	_breakable("crate", at)
	if _rng.randf() < 0.6:
		_breakable("crate", at + Vector2(_rng.randf_range(-0.1, 0.1), _rng.randf_range(-0.1, 0.1)), 0.9, 0.8)
	var side := at + Vector2(_rng.randf_range(-1.4, 1.4), _rng.randf_range(-1.4, 1.4))
	if not _occupied(side, 0.6):
		_reserve(side, 0.6)
		_breakable("crate", side)

## Las estructuras destruibles se guardan aparte (como barriles y cajas) en vez de ir al MultiMesh.
func _add(kind: String, pos: Vector2, yaw: float = -1.0, s: float = -1.0, y_offset: float = -0.04, collide: bool = true, tilt: float = 0.0) -> void:
	if not kind in STRUCTURES:
		super._add(kind, pos, yaw, s, y_offset, collide, tilt)
		return
	var sc: Vector2 = _prop_def(kind)["scale"]
	var scale_v := s if s > 0.0 else _rng.randf_range(sc.x, sc.y)
	var yaw_v := yaw if yaw >= 0.0 else _rng.randf() * TAU
	var euler := Vector3(_rng.randf_range(-tilt, tilt), yaw_v, _rng.randf_range(-tilt, tilt))
	var basis := Basis.from_euler(euler).scaled(Vector3.ONE * scale_v)
	_breakables.append([kind, Transform3D(basis, Vector3(pos.x, get_height_at(pos.x, pos.y) + y_offset, pos.y))])

var _prop_cells: Dictionary = {}      # DestructibleProp -> Array[Vector2i] (celdas que tapaba en el flujo)

func _block_prop(d: DestructibleProp) -> void:
	var def: Dictionary = _prop_def(d.kind)
	var size: Vector3 = def["size"]
	var sc := d.transform.basis.get_scale().x
	var r := size.x * sc if def["shape"] == "cyl" else Vector2(size.x * 0.5, size.z * 0.5).length() * sc
	var cells: Array = []
	var c0 := world_to_cell(d.position)
	var n := ceili((r + 0.5) / CELL)
	for dx in range(-n, n + 1):
		for dz in range(-n, n + 1):
			var c := c0 + Vector2i(dx, dz)
			if _cells.has(c) and not _blocked.has(c) and Vector2(c.x * CELL - d.position.x, c.y * CELL - d.position.z).length() <= r + 0.5:
				_blocked[c] = true
				cells.append(c)
	_prop_cells[d] = cells

func _on_breakable_destroyed(d: DestructibleProp) -> void:
	for c in _prop_cells.get(d, []):
		_blocked.erase(c)
	_prop_cells.erase(d)
	if d.kind == "totem":
		var big := d.transform.basis.get_scale().x > 1.15
		HealSoul.burst(self, d.global_position + Vector3(0, 1.4, 0), SHRINE_TOTEM_SOULS if big else TOTEM_SOULS)

func _build_breakables() -> void:
	var holder := Node3D.new()
	holder.name = "Breakables"
	add_child(holder)
	for b in _breakables:
		var kind: String = b[0]
		var mesh := _load_kind(kind)
		if mesh == null:
			continue
		var d := DestructibleProp.new()
		d.name = "%s_%d" % [kind, destructibles.size()]
		d.setup(kind, mesh, _mesh_xf[kind], _prop_def(kind), b[1], DestructibleProp.hp_for(kind))
		holder.add_child(d)
		destructibles.append(d)
		d.destroyed.connect(_on_breakable_destroyed)
		if kind in STRUCTURES:
			if not _blocked_ready:
				_collect_blocked()
			_block_prop(d)

## Mechones de pasto sobre las celdas de la caverna, más densos cerca de las paredes.
func _scatter_grass(r: Dictionary) -> void:
	var cells: Array = r["cells"]
	var n := int(grass_per_room * (0.5 if _mobile else 1.0) * prop_density)
	for i in n:
		var c: Vector2i = cells[_rng.randi() % cells.size()]
		var wd: int = _wall_dist.get(c, 9)
		if wd > 3 and _rng.randf() < 0.7:
			continue
		var p := Vector2(c.x * CELL, c.y * CELL) + Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0))
		var basis := Basis.from_euler(Vector3(0.0, _rng.randf() * TAU, 0.0)).scaled(Vector3.ONE * _rng.randf_range(0.6, 1.3))
		_grass.append(Transform3D(basis, Vector3(p.x, 0.0, p.y)))

func _build_grass() -> void:
	if _grass.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = GrassMesh.build()
	mm.instance_count = _grass.size()
	for i in _grass.size():
		mm.set_instance_transform(i, _grass[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Grass"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)

## Geometría y efectos propios de cada mundo, tras colocar los props (ver SewerMap).
func _build_extra() -> void:
	pass

# ───────────────────────────── Formas, columnas y tesoro ─────────────────────────────

## Elipses (y columnas) de una caverna según su forma.
func _shape_blobs(shape: String, c: Vector2, r0: Vector2, blobs: Array, pillars: Array) -> void:
	var axis := Vector2.RIGHT if _rng.randf() < 0.5 else Vector2.DOWN
	var side := axis.orthogonal()
	match shape:
		"cross":
			blobs.append([c, r0 * 0.8])
			blobs.append([c, Vector2(r0.x * 1.35, r0.y * 0.42)])
			blobs.append([c, Vector2(r0.x * 0.42, r0.y * 1.35)])
		"hall":
			var long := Vector2(r0.x * 1.55, r0.y * 0.58) if axis == Vector2.RIGHT else Vector2(r0.x * 0.58, r0.y * 1.55)
			blobs.append([c, long])
			blobs.append([c + axis * r0.x * 1.05, r0 * 0.45])
			blobs.append([c - axis * r0.x * 1.05, r0 * 0.45])
			# Dos filas de columnas a lo largo, dejando libre el centro
			for k in [-2, -1, 1, 2]:
				for s in [-1.0, 1.0]:
					pillars.append(c + axis * float(k) * 3.6 + side * s * r0.y * 0.3)
		"twin":
			blobs.append([c + axis * r0.x * 0.55, r0 * 0.66])
			blobs.append([c - axis * r0.x * 0.55, r0 * 0.66])
			blobs.append([c, Vector2(r0.x * 0.5, r0.y * 0.32) if axis == Vector2.RIGHT else Vector2(r0.x * 0.32, r0.y * 0.5)])
		_:
			blobs.append([c, r0])
			for k in _rng.randi_range(2, 4):
				var ang := _rng.randf() * TAU
				var dist := _rng.randf_range(0.45, 0.8) * r0.length() * 0.7
				var rr := r0 * _rng.randf_range(0.4, 0.65)
				blobs.append([c + Vector2(cos(ang), sin(ang)) * dist, rr])
			if shape == "pillars":
				var n := _rng.randi_range(3, 5)
				var a0 := _rng.randf() * TAU
				for k in n:
					var a := a0 + TAU * k / n + _rng.randf_range(-0.25, 0.25)
					pillars.append(c + Vector2(cos(a), sin(a)) * minf(r0.x, r0.y) * _rng.randf_range(0.5, 0.65))
	# Ninguna columna invade el centro (encuentros, portal, altar)
	for i in range(pillars.size() - 1, -1, -1):
		if (pillars[i] as Vector2).distance_to(c) < CENTER_CLEAR + PILLAR_R:
			pillars.remove_at(i)

## Las columnas se quitan del suelo: pasan a ser roca (pared con colisión y navegación alrededor).
func _raise_pillars() -> void:
	for i in rooms.size():
		var r: Dictionary = rooms[i]
		for pc in r.get("pillars", []):
			var p: Vector2 = pc
			for dx in range(-2, 3):
				for dz in range(-2, 3):
					var q := Vector2i(roundi(p.x) + dx, roundi(p.y) + dz)
					if Vector2(q).distance_to(p) <= PILLAR_R and _cells.get(q, 0) == FLOOR and _owner.get(q, -1) == i:
						_cells.erase(q)
						_owner.erase(q)
						(r["cells"] as Array).erase(q)

## Una caverna normal (no la arena ni la final) puede ser la cámara del tesoro.
func _pick_treasure() -> void:
	var options: Array = []
	for i in rooms.size():
		if rooms[i]["type"] == "normal" and i != arena_index:
			options.append(i)
	if options.is_empty() or _rng.randf() >= TREASURE_CHANCE:
		return
	var t: int = options[_rng.randi() % options.size()]
	rooms[t]["type"] = "treasure"
	rooms[t]["theme"] = "treasure"

## Braseros con la luz del tema del nivel.
func _add_brazier(pos: Vector2) -> void:
	_place("brazier", pos, 0.8)
	_add_light(Vector3(pos.x, 1.7, pos.y), palette()["fire"], 2.6, 11.0)
	if embers_enabled:
		_add_embers(Vector3(pos.x, 1.4, pos.y))

## Cristales luminosos pegados a la pared (gruta de cristal, fragua): solo se guardan aquí.
func _place_crystals(r: Dictionary) -> void:
	var n := int(palette()["crystals"])
	if n <= 0:
		return
	if _mobile:
		n = n / 2
	for k in n:
		var p := _spot(r, 0.7, 1, 2)
		if p == Vector2.INF:
			continue
		_reserve(p, 0.7)
		for j in _rng.randi_range(1, 3):
			var off := Vector2(_rng.randf_range(-0.5, 0.5), _rng.randf_range(-0.5, 0.5))
			var h := _rng.randf_range(0.6, 1.8)
			var basis := Basis.from_euler(Vector3(_rng.randf_range(-0.35, 0.35), _rng.randf() * TAU, _rng.randf_range(-0.35, 0.35)))
			basis = basis.scaled_local(Vector3(_rng.randf_range(0.25, 0.45), h, _rng.randf_range(0.25, 0.45)))
			_crystals.append(Transform3D(basis, Vector3(p.x + off.x, h * 0.45, p.y + off.y)))
		# Algún cristal ilumina su rincón (respeta el tope de luces)
		if k % 4 == 0:
			_add_light(Vector3(p.x, 1.2, p.y), palette()["crystal"], 1.6, 7.0)

func _build_crystals() -> void:
	if _crystals.is_empty():
		return
	var prism := PrismMesh.new()
	prism.size = Vector3(1.0, 1.0, 1.0)
	var mat := StandardMaterial3D.new()
	var col: Color = palette()["crystal"]
	mat.albedo_color = col.darkened(0.3)
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 2.2
	mat.roughness = 0.2
	prism.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = prism
	mm.instance_count = _crystals.size()
	for i in _crystals.size():
		mm.set_instance_transform(i, _crystals[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Crystals"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
