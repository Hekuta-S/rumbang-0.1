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
const THEMES := ["camp", "camp", "storage", "shrine"]

const FLOOR := 1
const CORRIDOR := 2

@export var min_rooms: int = 6
@export var max_rooms: int = 8
@export var slot_limit: int = 2       ## huecos válidos: -slot_limit..slot_limit
@export var room_radius: Vector2i = Vector2i(7, 10)   ## radio de la elipse principal (celdas)
@export var grass_per_room: int = 140

## Cavernas: [{slot, center: Vector3, half: Vector2 (m, caja envolvente), type, theme, cells: Array[Vector2i]}]
var rooms: Array = []
var destructibles: Array[DestructibleProp] = []
var _cells: Dictionary = {}           # Vector2i -> FLOOR | CORRIDOR
var _owner: Dictionary = {}           # Vector2i -> índice de caverna
var _wall_dist: Dictionary = {}       # Vector2i (suelo) -> distancia en celdas a la pared
var _walls: Dictionary = {}           # Vector2i -> true (primer anillo, con colisión)
var _outer: Dictionary = {}           # Vector2i -> true (segundo anillo, solo visual)
var _wall_boxes: Array = []           # [{pos: Vector2, half: Vector2}]
var _grass: Array[Transform3D] = []
var _breakables: Array = []           # [[kind, Transform3D]]
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
	_build_breakables()
	generated.emit(used_seed)
	print("[DungeonMap] semilla=", used_seed, " cavernas=", rooms.size(), " celdas=", _cells.size(),
		" props=", _count_instances(), " rompibles=", destructibles.size())

func get_height_at(_x: float, _z: float) -> float:
	return 0.0

func get_colliders() -> Array:
	var out := super.get_colliders()
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
		blobs.append([Vector2(c), r0])
		for k in _rng.randi_range(2, 4):
			var ang := _rng.randf() * TAU
			var dist := _rng.randf_range(0.45, 0.8) * r0.length() * 0.7
			var rr := r0 * _rng.randf_range(0.4, 0.65)
			blobs.append([Vector2(c) + Vector2(cos(ang), sin(ang)) * dist, rr])
		rooms.append({
			"slot": s,
			"cell": c,
			"blobs": blobs,
			"center": Vector3(c.x * CELL, 0.0, c.y * CELL),
			"type": type,
			"theme": "start" if type == "start" else ("end" if type == "end" else THEMES[_rng.randi() % THEMES.size()]),
			"cells": [],
		})
	set_meta("links", links)

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
		var reach := room_radius.y * 2
		for x in range(c.x - reach, c.x + reach + 1):
			for z in range(c.y - reach, c.y + reach + 1):
				var p := Vector2(x, z)
				var best := INF
				for b in r["blobs"]:
					var d: Vector2 = (p - (b[0] as Vector2)) / (b[1] as Vector2)
					best = minf(best, d.length())
				# Borde deformado por ruido: pared de roca irregular
				if best + _edge_noise.get_noise_2d(x, z) * 0.28 < 1.0:
					var cell := Vector2i(x, z)
					if not _cells.has(cell):
						_cells[cell] = FLOOR
						_owner[cell] = i
						(r["cells"] as Array).append(cell)
	# Túneles serpenteantes entre centros
	for l in get_meta("links"):
		var a: Vector2 = Vector2(rooms[_room_index(l[0])]["cell"])
		var b: Vector2 = Vector2(rooms[_room_index(l[1])]["cell"])
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
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	plane.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = plane
	mm.instance_count = _cells.size()
	var i := 0
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var dirt := Color(0.3, 0.22, 0.15)
	var moss := Color(0.2, 0.24, 0.13)
	for c in _cells:
		var p := _cell_pos(c)
		mm.set_instance_transform(i, Transform3D(Basis(), p))
		# Tierra con manchas de musgo cerca de las paredes
		var n := (_edge_noise.get_noise_2d(c.x * 4.0, c.y * 4.0) + 1.0) * 0.5
		var near_wall := 1.0 - clampf(float(_wall_dist.get(c, 4)) / 4.0, 0.0, 1.0)
		var col := dirt.lerp(moss, n * 0.5 + near_wall * 0.4) * _rng.randf_range(0.85, 1.05)
		if _cells[c] == CORRIDOR:
			col *= 0.85
		mm.set_instance_color(i, col)
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

func _build_walls() -> void:
	# Bloques de roca girados y escalados al azar: pared de cueva sin rejilla visible
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
		mm.set_instance_color(i, Color(0.21, 0.18, 0.17) * v)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Walls"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if _mobile else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mmi)

	# Colisión: fusiona celdas consecutivas de cada fila en una sola caja
	var body := StaticBody3D.new()
	body.name = "WallColliders"
	body.collision_mask = 0
	add_child(body)
	var rows: Dictionary = {}
	for c in _walls:
		if not rows.has(c.y):
			rows[c.y] = []
		(rows[c.y] as Array).append(c.x)
	for z in rows:
		var xs: Array = rows[z]
		xs.sort()
		var start: int = xs[0]
		var prev: int = xs[0]
		for k in range(1, xs.size() + 1):
			if k < xs.size() and xs[k] == prev + 1:
				prev = xs[k]
				continue
			_add_wall_box(start, prev, z, body)
			if k < xs.size():
				start = xs[k]
				prev = xs[k]

func _add_wall_box(x0: int, x1: int, z: int, body: StaticBody3D) -> void:
	var len_m := float(x1 - x0 + 1) * CELL
	var center := Vector2((x0 + x1) * 0.5 * CELL, z * CELL)
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(len_m, WALL_H, CELL)
	cs.shape = bx
	cs.position = Vector3(center.x, WALL_H * 0.5, center.y)
	body.add_child(cs)
	_wall_boxes.append({"pos": center, "half": Vector2(len_m * 0.5, CELL * 0.5)})

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
	for k in _rng.randi_range(8, 14):
		var p := _spot(r, 0.8, 1, 99)
		if p == Vector2.INF:
			continue
		var kind: String = ["bones", "mushroom", "mushroom", "rock_a"][_rng.randi() % 4]
		var s := 0.45 if kind == "rock_a" else -1.0
		_place(kind, p, 0.8, -1.0, s, kind == "rock_a")
	_scatter_grass(r)

func _try_place(r: Dictionary, kind: String, radius: float, min_wall: int, max_wall: int, face: Vector2 = Vector2.INF) -> void:
	var p := _spot(r, radius, min_wall, max_wall)
	if p == Vector2.INF:
		return
	_place(kind, p, radius, _yaw_to(p, face) if face != Vector2.INF else -1.0)

func _add_campfire(pos: Vector2) -> void:
	_place("campfire", pos, 1.5, -1.0, 1.0)
	_add_light(Vector3(pos.x, 1.4, pos.y), Color(1.0, 0.5, 0.18), 3.2, 14.0)
	if embers_enabled:
		_add_embers(Vector3(pos.x, 0.8, pos.y))

# Barriles y cajas: se guardan aparte y se crean como DestructibleProp
func _breakable(kind: String, pos: Vector2, y: float = 0.0, s: float = -1.0, tilt: float = 0.0) -> void:
	var sc: Vector2 = PROPS[kind]["scale"]
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
		d.setup(kind, mesh, _mesh_xf[kind], PROPS[kind], b[1], 25.0 if kind == "crate" else 18.0)
		holder.add_child(d)
		destructibles.append(d)

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
