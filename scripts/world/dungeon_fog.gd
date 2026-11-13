extends Node

## Niebla entre salas de la mazmorra (DungeonMap).
##  - Cada caverna es una ZONA: sus celdas y la mitad de cada túnel que parte de ella (el reparto sale de una
##    búsqueda en anchura desde el suelo de las cavernas, así que la frontera cae a medio camino del túnel).
##  - En cada frontera de túnel hay una CORTINA de niebla (capas de planos con el shader fog_gate) que tapa la vista
##    hacia la sala vecina y se abre en un hueco alrededor del jugador para cruzarla. Debajo, un manto de niebla
##    a ras de suelo se derrama a ambos lados. Todo comparte UN material (capas = uniforms de instancia).
##  - Solo se dibujan las cortinas que tocan la zona del jugador (las demás quedan tras la roca o tras otra niebla).
##  - Como detrás de la niebla no se ve nada, lo que no pertenece a la zona del jugador no se dibuja: trozos de
##    pared y techo, props, pasto, destruibles y enemigos lejanos (visible = false). Se recalcula al cambiar de zona.
## Uso: DungeonFog.new() → setup(mapa, jugador). Se reconstruye solo cuando el mapa se regenera (nivel nuevo).

const SHADER: Shader = preload("res://assets/shaders/fog_gate.gdshader")
const TICK := 0.2
const GRID := 24.0                    ## m: rejilla para saber qué zonas toca cada nodo
const GATE_WIDTH := 9.0               ## m, ancho máximo de una cortina
const GATE_HEIGHT := 7.0
const LAYERS := 3
const LAYERS_MOBILE := 2              ## cada capa es un plano transparente a pantalla casi completa: en móvil una menos
const LAYER_GAP := 0.9
const ENEMY_NEAR := 10.0              ## un enemigo así de cerca del jugador se dibuja aunque esté en otra zona
const LIGHT_NEAR := 16.0              ## m: una luz así de cerca se enciende aunque sea de otra zona (pasillos)
const FOG_COLOR := Color(0.36, 0.38, 0.47)
const FLOOR_DEPTH := 9.0              ## m que ocupa el manto bajo (mitad a cada lado de la cortina)

var map: DungeonMap
var player: Node3D
var _mat: ShaderMaterial
var _gates: Node3D
var _gate_list: Array = []            ## [{nodes: Array[MeshInstance3D], a: zona, b: zona}]
var _zone: Dictionary = {}            ## Vector2i (celda) -> índice de caverna
var _grid_zones: Dictionary = {}      ## Vector2i (rejilla de GRID m) -> máscara de zonas (bits)
var _nodes: Array = []                ## nodos de geometría del mapa
var _masks: Array = []                ## máscara de zonas de cada uno (mismo orden)
var _cur_zone := -2
var _acc := 0.0
var _last_pp := Vector3.INF
var _light_zone: Dictionary = {}      ## posición de luz (cuartos de m) -> zona (las antorchas cuelgan de la pared, fuera del suelo)

func setup(p_map: DungeonMap, p_player: Node3D) -> void:
	map = p_map
	player = p_player
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = SHADER
		_mat.set_shader_parameter("fog_color", FOG_COLOR)
		# Con menos capas, cada una más opaca: la cortina tapa lo mismo (lo de la otra sala no se dibuja)
		_mat.set_shader_parameter("layer_gain", float(LAYERS) / float(_layers()))
		var fn := FastNoiseLite.new()
		fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		fn.frequency = 0.02
		fn.fractal_octaves = 3
		var tex := NoiseTexture2D.new()
		tex.width = 128
		tex.height = 128
		tex.seamless = true
		tex.noise = fn
		_mat.set_shader_parameter("noise_tex", tex)
	map.light_eligible = _light_ok
	if not map.generated.is_connected(_rebuild):
		map.generated.connect(_rebuild)
	_rebuild(map.used_seed)

func _rebuild(_seed: int = 0) -> void:
	_cur_zone = -2
	_light_zone.clear()
	if _gates != null and is_instance_valid(_gates):
		_gates.queue_free()
	_gates = Node3D.new()
	_gates.name = "FogGates"
	_gate_list.clear()
	add_child(_gates)
	_compute_zones()
	_build_gates()
	_collect_nodes.call_deferred()

# ── Zonas ──

func _compute_zones() -> void:
	_zone.clear()
	var queue: Array[Vector2i] = []
	for c in map._cells:
		if int(map._cells[c]) == DungeonMap.FLOOR:
			_zone[c] = int(map._owner.get(c, -1))
			queue.append(c)
	var head := 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		for d in DungeonMap.DIRS:
			var n: Vector2i = cur + d
			if map._cells.has(n) and not _zone.has(n):
				_zone[n] = _zone[cur]
				queue.append(n)

func zone_at(p: Vector3) -> int:
	return int(_zone.get(map.world_to_cell(p), -1))

## Zona de un punto que puede estar en la roca (antorcha de pared): la de la celda de suelo más cercana.
func zone_near(p: Vector3, max_ring: int = 4) -> int:
	var c := map.world_to_cell(p)
	for r in max_ring + 1:
		var best := -1
		var best_d := INF
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var n := c + Vector2i(dx, dz)
				if _zone.has(n):
					var d := float(dx * dx + dz * dz)
					if d < best_d:
						best_d = d
						best = int(_zone[n])
		if best >= 0:
			return best
	return -1

## Filtro de luces de DungeonMap: solo compiten por encenderse las de la zona del jugador y las muy cercanas.
func _light_ok(pos: Vector3, d2: float) -> bool:
	if _cur_zone < 0 or d2 <= LIGHT_NEAR * LIGHT_NEAR:
		return true
	var key := Vector3i(roundi(pos.x * 4.0), roundi(pos.y * 4.0), roundi(pos.z * 4.0))
	if not _light_zone.has(key):
		_light_zone[key] = zone_near(pos)
	var z: int = _light_zone[key]
	return z < 0 or z == _cur_zone

# ── Cortinas ──

func _build_gates() -> void:
	# Pares de celdas de túnel vecinas con distinta zona
	var pairs: Array = []
	for c in _zone:
		if int(map._cells[c]) != DungeonMap.CORRIDOR:
			continue
		for d in DungeonMap.DIRS:
			var n: Vector2i = c + d
			if not _zone.has(n) or int(map._cells.get(n, 0)) != DungeonMap.CORRIDOR:
				continue
			if int(_zone[n]) > int(_zone[c]):
				pairs.append([c, n])
	# Agrupa los pares contiguos (misma pareja de zonas): cada grupo es una cortina
	var used := {}
	for i in pairs.size():
		if used.has(i):
			continue
		var za := int(_zone[pairs[i][0]])
		var zb := int(_zone[pairs[i][1]])
		var group: Array = [i]
		used[i] = true
		var k := 0
		while k < group.size():
			var a: Array = pairs[group[k]]
			k += 1
			for j in pairs.size():
				if used.has(j) or int(_zone[pairs[j][0]]) != za or int(_zone[pairs[j][1]]) != zb:
					continue
				var b: Array = pairs[j]
				if (a[0] as Vector2i).distance_to(b[0]) <= 2.5:
					used[j] = true
					group.append(j)
		var center := Vector3.ZERO
		var dir := Vector3.ZERO
		var mids: Array[Vector3] = []
		for gi in group:
			var pa: Vector3 = map._cell_pos(pairs[gi][0])
			var pb: Vector3 = map._cell_pos(pairs[gi][1])
			mids.append((pa + pb) * 0.5)
			center += mids[-1]
			dir += pb - pa
		center /= group.size()
		dir.y = 0.0
		if dir.length_squared() < 0.01:
			continue
		dir = dir.normalized()
		# Ancho = lo que ocupa el túnel en la frontera (si no, la cortina asomaría a la caverna por los lados)
		var side := dir.cross(Vector3.UP)
		var lo := 0.0
		var hi := 0.0
		for m in mids:
			var t := (m - center).dot(side)
			lo = minf(lo, t)
			hi = maxf(hi, t)
		_add_gate(center, dir, clampf(hi - lo + DungeonMap.CELL + 2.0, 5.0, GATE_WIDTH), za, zb)

func _add_gate(center: Vector3, dir: Vector3, width: float, za: int, zb: int) -> void:
	var yaw := atan2(dir.x, dir.z)
	var nodes: Array = []
	var q := QuadMesh.new()
	q.size = Vector2(width, GATE_HEIGHT)
	var layers := _layers()
	for l in layers:
		var mi := _fog_mesh(q, float(l), 0.0)
		mi.global_position = center + dir * (float(l) - (layers - 1) * 0.5) * LAYER_GAP + Vector3(0.0, GATE_HEIGHT * 0.5 - 0.3, 0.0)
		mi.rotation.y = yaw
		nodes.append(mi)
	# Manto bajo: plano horizontal (local X = ancho del túnel, local Y = a lo largo del túnel)
	var fq := QuadMesh.new()
	fq.size = Vector2(width, FLOOR_DEPTH)
	var fl := _fog_mesh(fq, 7.0, 1.0)
	fl.global_position = center + Vector3(0.0, 0.12, 0.0)
	fl.rotation = Vector3(-PI * 0.5, yaw, 0.0)
	nodes.append(fl)
	_gate_list.append({"nodes": nodes, "a": za, "b": zb})

static func _layers() -> int:
	return LAYERS_MOBILE if Quality.is_mobile() else LAYERS

func _fog_mesh(mesh: Mesh, seed_v: float, floor_v: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.set_meta("fog_gate", true)
	_gates.add_child(mi)
	mi.set_instance_shader_parameter("layer_seed", seed_v)
	mi.set_instance_shader_parameter("floor_mode", floor_v)
	return mi

# ── Qué se dibuja ──

func _collect_nodes() -> void:
	_nodes.clear()
	_masks.clear()
	_grid_zones.clear()
	for c in _zone:
		var key := _grid_key(map._cell_pos(c))
		_grid_zones[key] = int(_grid_zones.get(key, 0)) | (1 << clampi(int(_zone[c]), 0, 30))
	var skip: Array = []
	for n in map.destructibles:
		skip.append(n)
	for node in map.find_children("*", "GeometryInstance3D", true, false):
		var g := node as GeometryInstance3D
		if g.name == "Floor" or g.has_meta("fog_gate") or _is_under_breakables(g):
			continue
		var box := g.global_transform * g.get_aabb()
		if box.size.length() < 0.001:
			continue
		var mask := 0
		var x0 := floori((box.position.x - 3.0) / GRID)
		var x1 := floori((box.end.x + 3.0) / GRID)
		var z0 := floori((box.position.z - 3.0) / GRID)
		var z1 := floori((box.end.z + 3.0) / GRID)
		for gx in range(x0, x1 + 1):
			for gz in range(z0, z1 + 1):
				mask |= int(_grid_zones.get(Vector2i(gx, gz), 0))
		_nodes.append(g)
		_masks.append(mask)
	_apply(_cur_zone)

func _is_under_breakables(n: Node) -> bool:
	var p := n.get_parent()
	while p != null and p != map:
		if p.name == "Breakables":
			return true
		p = p.get_parent()
	return false

static func _grid_key_of(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / GRID), floori(z / GRID))

func _grid_key(p: Vector3) -> Vector2i:
	return _grid_key_of(p.x, p.z)

func _process(delta: float) -> void:
	if map == null or not is_instance_valid(player):
		return
	var pp := player.global_position
	if pp != _last_pp:
		_last_pp = pp
		_mat.set_shader_parameter("player_pos", pp)
	_acc += delta
	if _acc < TICK:
		return
	_acc = 0.0
	var z := zone_at(player.global_position)
	if z >= 0 and z != _cur_zone:
		_cur_zone = z
		_apply(z)
	if _cur_zone >= 0:
		_update_enemies()

func _apply(z: int) -> void:
	if z < 0:
		return
	var bit := 1 << clampi(z, 0, 30)
	for g in _gate_list:
		var show: bool = int(g["a"]) == z or int(g["b"]) == z
		for mi in g["nodes"]:
			if is_instance_valid(mi):
				(mi as MeshInstance3D).visible = show
	for i in _nodes.size():
		var n = _nodes[i]
		if is_instance_valid(n):
			(n as GeometryInstance3D).visible = (int(_masks[i]) & bit) != 0
	for d in map.destructibles:
		if is_instance_valid(d):
			d.visible = zone_at(d.global_position) == z
	if map.has_method("refresh_lights"):
		map.refresh_lights()

func _update_enemies() -> void:
	var pp := player.global_position
	for e in EnemyRegistry.all():
		if not (e is Node3D) or not is_instance_valid(e):
			continue
		var near: bool = (e as Node3D).global_position.distance_to(pp) < ENEMY_NEAR
		(e as Node3D).visible = near or zone_at((e as Node3D).global_position) == _cur_zone
