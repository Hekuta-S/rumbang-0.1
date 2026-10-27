class_name ProceduralMap
extends Node3D

## Mapa procedural "dark fantasy" inspirado en Megabonk.
##
## Genera a partir de una semilla:
##  - Terreno con colinas suaves, una plaza plana de inicio y acantilados que
##    cierran la arena.
##  - Una cuenca hundida ("cripta") con altar, pilares y brasas, conectada por
##    una rampa con la plaza de inicio.
##  - Bosque de árboles muertos, cementerios, ruinas, barriles, cajas, rocas,
##    hongos luminosos y huesos (props de assets/models/mapa/*.glb).
##
## Usa MultiMeshInstance3D por chunk (pocas draw calls), un único
## StaticBody3D para el suelo y otro para los colisionadores de props.
## get_height_at(x, z) lo consume EnvironmentManager.get_floor_y().

signal generated(used_seed: int)

const GROUND_SHADER: Shader = preload("res://assets/shaders/dark_ground.gdshader")
const PROP_SHADER: Shader = preload("res://assets/shaders/prop_flat.gdshader")
## Tamaño de los chunks de props (m): grandes = menos llamadas de dibujo. Los props tienen muy pocos
## triángulos (56–590), así que dibujarlos todos cuesta menos que muchas llamadas de dibujo.
const CHUNK_PC := 120.0
const CHUNK_MOBILE := 240.0           ## un solo chunk: 1 llamada por tipo de prop
const PROP_DIR := "res://assets/models/mapa/"
const HASH_CELL := 8.0
## Capa visual 2 (valor 2): solo el suelo. Decals como la aura de Vangry usan cull_mask = 2.
const GROUND_VISUAL_LAYER := 2

## kind -> {file, shape: "cyl"|"box"|"", size, scale: Vector2(min,max)}
## cyl: size.x = radio, size.y = alto.  box: size = dimensiones completas.
const PROPS := {
	"tree_a":   {"file": "tree_dead_a",      "shape": "cyl", "size": Vector3(0.45, 4.5, 0.0), "scale": Vector2(0.85, 1.35)},
	"tree_b":   {"file": "tree_dead_b",      "shape": "cyl", "size": Vector3(0.45, 3.5, 0.0), "scale": Vector2(0.85, 1.35)},
	"barrel":   {"file": "barrel",           "shape": "cyl", "size": Vector3(0.45, 0.92, 0.0), "scale": Vector2(0.95, 1.1)},
	"crate":    {"file": "crate",            "shape": "box", "size": Vector3(0.9, 0.9, 0.9), "scale": Vector2(0.9, 1.15)},
	"grave_a":  {"file": "gravestone_round", "shape": "",    "size": Vector3.ZERO, "scale": Vector2(0.9, 1.2)},
	"grave_b":  {"file": "gravestone_cross", "shape": "",    "size": Vector3.ZERO, "scale": Vector2(0.9, 1.2)},
	"pillar":   {"file": "pillar_broken",    "shape": "cyl", "size": Vector3(0.65, 3.2, 0.0), "scale": Vector2(0.95, 1.2)},
	"wall":     {"file": "wall_ruin",        "shape": "box", "size": Vector3(4.0, 2.2, 0.7), "scale": Vector2(0.9, 1.15)},
	"rock_a":   {"file": "rock_a",           "shape": "cyl", "size": Vector3(1.0, 1.3, 0.0), "scale": Vector2(0.7, 1.5)},
	"rock_b":   {"file": "rock_b",           "shape": "cyl", "size": Vector3(1.6, 2.0, 0.0), "scale": Vector2(0.8, 1.4)},
	"brazier":  {"file": "brazier",          "shape": "cyl", "size": Vector3(0.35, 1.2, 0.0), "scale": Vector2(1.0, 1.0)},
	"bones":    {"file": "bone_pile",        "shape": "",    "size": Vector3.ZERO, "scale": Vector2(0.9, 1.3)},
	"altar":    {"file": "altar",            "shape": "box", "size": Vector3(3.4, 1.8, 3.4), "scale": Vector2(1.0, 1.0)},
	"fence":    {"file": "fence",            "shape": "box", "size": Vector3(2.5, 1.4, 0.25), "scale": Vector2(1.0, 1.0)},
	"mushroom": {"file": "mushroom",         "shape": "",    "size": Vector3.ZERO, "scale": Vector2(0.6, 1.6)},
	# Campamento goblin / cueva (modo mazmorra)
	"hut":        {"file": "goblin_hut",        "shape": "cyl", "size": Vector3(1.9, 3.5, 0.0),  "scale": Vector2(0.9, 1.15)},
	"totem":      {"file": "goblin_totem",      "shape": "cyl", "size": Vector3(0.45, 3.0, 0.0), "scale": Vector2(0.9, 1.25)},
	"palisade":   {"file": "goblin_palisade",   "shape": "box", "size": Vector3(3.2, 2.0, 0.4),  "scale": Vector2(1.0, 1.0)},
	"skull_pole": {"file": "goblin_skull_pole", "shape": "cyl", "size": Vector3(0.12, 2.6, 0.0), "scale": Vector2(0.9, 1.2)},
	"campfire":   {"file": "goblin_campfire",   "shape": "cyl", "size": Vector3(0.75, 0.5, 0.0), "scale": Vector2(1.0, 1.0)},
	"tent":       {"file": "goblin_tent",       "shape": "cyl", "size": Vector3(1.25, 2.6, 0.0), "scale": Vector2(0.9, 1.15)},
	"stalagmite": {"file": "cave_stalagmite",   "shape": "cyl", "size": Vector3(0.6, 3.2, 0.0),  "scale": Vector2(0.7, 1.7)},
}

@export var map_seed: int = 0                       ## 0 = aleatoria en cada partida
@export var half_size: float = 115.0                ## mitad del lado de la malla
@export var cell_size: float = 1.5                  ## resolución del terreno (m)
@export var hill_amplitude: float = 4.5
@export var basin_depth: float = 9.0
@export var basin_distance: float = 58.0            ## centro de la cuenca desde el origen
@export var basin_floor_radius: float = 20.0
@export var basin_rim_radius: float = 32.0
@export var play_half: float = 98.0                 ## donde empiezan los acantilados
@export var cliff_height: float = 22.0
@export var chunk_size: float = 80.0
@export_range(0.0, 2.0, 0.05) var prop_density: float = 1.0
@export var max_lights: int = 16
@export var embers_enabled: bool = true

var used_seed: int = 0
var _rng := RandomNumberGenerator.new()
var _noise_hills := FastNoiseLite.new()
var _noise_detail := FastNoiseLite.new()
var _noise_forest := FastNoiseLite.new()

var _side: int = 0                                  # vértices por lado
var _heights := PackedFloat32Array()
var _basin_center := Vector2.ZERO
var _ramp_end := Vector2.ZERO
var _ramp_surface_y: float = 0.0

var _mesh_cache: Dictionary = {}                    # kind -> Mesh
var _mesh_xf: Dictionary = {}                       # kind -> Transform3D
var _instances: Dictionary = {}                     # kind -> Array[Transform3D]
var _collide: Dictionary = {}                       # kind -> bool (crear colisión)
var _hash: Dictionary = {}                          # Vector2i -> Array[[Vector2, float]]
var _lights: Array[OmniLight3D] = []
var _light_base: Array[float] = []
var _flicker_t: float = 0.0
## Brasas (partículas) de los braseros; junto con las luces solo funcionan cerca del jugador.
var _embers: Array[CPUParticles3D] = []
var _cull_timer: float = 0.0
## Distancia (m) a la que se apagan luces y brasas lejanas (más corta en móvil).
const LIGHT_CULL_DIST_PC := 55.0
const LIGHT_CULL_DIST_MOBILE := 38.0
var _mobile: bool = false

func _ready() -> void:
	add_to_group("procedural_map")
	_mobile = Quality.is_mobile() or OS.has_feature("mobile")
	chunk_size = CHUNK_MOBILE if _mobile else CHUNK_PC
	if _mobile:
		cell_size = maxf(cell_size, 2.5)
		prop_density *= 0.55
		max_lights = mini(max_lights, 6)
		embers_enabled = false
	generate(map_seed)

# ───────────────────────────── API pública ─────────────────────────────

func generate(p_seed: int = 0) -> void:
	_clear()
	used_seed = p_seed if p_seed != 0 else int(Time.get_unix_time_from_system()) ^ randi()
	_rng.seed = used_seed
	_setup_noise()
	_pick_layout()
	_build_terrain()
	_scatter_props()
	_build_prop_nodes()
	generated.emit(used_seed)
	print("[ProceduralMap] semilla=", used_seed, " cuenca=", _basin_center, " props=", _count_instances())

## Altura del suelo (interpolación bilinear de la malla real).
func get_height_at(x: float, z: float) -> float:
	if _side == 0:
		return 0.0
	var fx := clampf((x + half_size) / cell_size, 0.0, float(_side - 1) - 0.001)
	var fz := clampf((z + half_size) / cell_size, 0.0, float(_side - 1) - 0.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - float(ix)
	var tz := fz - float(iz)
	var h00 := _heights[iz * _side + ix]
	var h10 := _heights[iz * _side + ix + 1]
	var h01 := _heights[(iz + 1) * _side + ix]
	var h11 := _heights[(iz + 1) * _side + ix + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)

## Colisionadores de props como datos 2D (para el movimiento manual de enemigos, ver EnemyMotion):
## [{pos: Vector2 (x,z), shape: "cyl"|"box", r: radio de alcance, half: Vector2 medias medidas, yaw}]
func get_colliders() -> Array:
	var out: Array = []
	for kind in _collide:
		var def: Dictionary = PROPS[kind]
		var size: Vector3 = def["size"]
		for t in (_collide[kind] as Array):
			var xf: Transform3D = t
			var sc := xf.basis.get_scale().x
			var o := {"pos": Vector2(xf.origin.x, xf.origin.z), "yaw": xf.basis.get_euler().y}
			if def["shape"] == "cyl":
				o["shape"] = "cyl"
				o["r"] = size.x * sc
				o["half"] = Vector2.ZERO
			else:
				o["shape"] = "box"
				o["half"] = Vector2(size.x * 0.5, size.z * 0.5) * sc
				o["r"] = o["half"].length()
			out.append(o)
	return out

func get_basin_center() -> Vector3:
	return Vector3(_basin_center.x, get_height_at(_basin_center.x, _basin_center.y), _basin_center.y)

# ───────────────────────────── Terreno ─────────────────────────────

func _clear() -> void:
	for c in get_children():
		c.queue_free()
	_mesh_cache.clear()
	_mesh_xf.clear()
	_instances.clear()
	_collide.clear()
	_hash.clear()
	_lights.clear()
	_light_base.clear()
	_embers.clear()

func _setup_noise() -> void:
	_noise_hills.seed = used_seed
	_noise_hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_hills.frequency = 0.011
	_noise_hills.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise_hills.fractal_octaves = 3

	_noise_detail.seed = used_seed + 17
	_noise_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_detail.frequency = 0.06
	_noise_detail.fractal_octaves = 2

	_noise_forest.seed = used_seed + 91
	_noise_forest.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_forest.frequency = 0.018
	_noise_forest.fractal_octaves = 2

func _pick_layout() -> void:
	var ang := _rng.randf() * TAU
	var dir := Vector2(cos(ang), sin(ang))
	_basin_center = dir * basin_distance
	# La rampa une la cuenca con la plaza de inicio
	var length := basin_rim_radius + 14.0
	_ramp_end = _basin_center - dir * length
	_ramp_surface_y = 0.0

## Devuelve Vector4(altura, máscara_cuenca, máscara_rampa, máscara_acantilado)
func _terrain(x: float, z: float) -> Vector4:
	var p := Vector2(x, z)
	var r := p.length()
	var h := _noise_hills.get_noise_2d(x, z) * hill_amplitude + _noise_detail.get_noise_2d(x, z) * 0.7
	h *= smoothstep(9.0, 24.0, r)                         # plaza plana en el origen

	var d := p.distance_to(_basin_center)
	var bt := 1.0 - smoothstep(basin_floor_radius, basin_rim_radius, d)
	var bowl := -basin_depth + _noise_detail.get_noise_2d(x * 2.0, z * 2.0) * 0.25
	h = lerpf(h, bowl, bt)
	var lip := (d - basin_rim_radius) / 4.0
	h += 1.2 * exp(-lip * lip)                            # borde elevado de la cuenca

	# Rampa de acceso (solo excava)
	var ab := _ramp_end - _basin_center
	var ab_len := ab.length()
	var t := clampf((p - _basin_center).dot(ab) / (ab_len * ab_len), 0.0, 1.0)
	var closest := _basin_center + ab * t
	var l := p.distance_to(closest)
	var w := 1.0 - smoothstep(3.5, 7.5, l)
	var start := basin_floor_radius * 0.6
	var s := clampf((t * ab_len - start) / (ab_len - start), 0.0, 1.0)
	var target := lerpf(-basin_depth, _ramp_surface_y, s)
	h = lerpf(h, minf(h, target), w)

	# Acantilados perimetrales
	var e := maxf(absf(x), absf(z))
	var ct := smoothstep(play_half, play_half + 7.0, e)
	h += ct * (cliff_height + _noise_detail.get_noise_2d(x * 3.0, z * 3.0) * 3.0)

	return Vector4(h, bt, w * (1.0 - bt), ct)

func _build_terrain() -> void:
	_side = int(round(half_size * 2.0 / cell_size)) + 1
	_heights.resize(_side * _side)
	var colors := PackedColorArray()
	colors.resize(_side * _side)
	var verts := PackedVector3Array()
	verts.resize(_side * _side)

	for j in range(_side):
		for i in range(_side):
			var x := -half_size + float(i) * cell_size
			var z := -half_size + float(j) * cell_size
			var tv := _terrain(x, z)
			var idx := j * _side + i
			_heights[idx] = tv.x
			verts[idx] = Vector3(x, tv.x, z)
			var plaza := 1.0 - smoothstep(6.0, 16.0, Vector2(x, z).length())
			colors[idx] = Color(tv.y, tv.z, plaza, tv.w)

	var normals := PackedVector3Array()
	normals.resize(_side * _side)
	for j in range(_side):
		for i in range(_side):
			var hl := _heights[j * _side + maxi(i - 1, 0)]
			var hr := _heights[j * _side + mini(i + 1, _side - 1)]
			var hd := _heights[maxi(j - 1, 0) * _side + i]
			var hu := _heights[mini(j + 1, _side - 1) * _side + i]
			normals[j * _side + i] = Vector3(hl - hr, 2.0 * cell_size, hd - hu).normalized()

	var indices := PackedInt32Array()
	indices.resize((_side - 1) * (_side - 1) * 6)
	var k := 0
	for j in range(_side - 1):
		for i in range(_side - 1):
			var a := j * _side + i
			var b := a + 1
			var c := a + _side
			var d := c + 1
			indices[k] = a; indices[k + 1] = b; indices[k + 2] = c
			indices[k + 3] = b; indices[k + 4] = d; indices[k + 5] = c
			k += 6

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mat := ShaderMaterial.new()
	mat.shader = GROUND_SHADER
	mesh.surface_set_material(0, mat)

	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.layers = 1 | GROUND_VISUAL_LAYER     # capa extra: los decals de suelo (auras) solo se proyectan aquí
	add_child(mi)

	var body := StaticBody3D.new()
	body.name = "GroundBody"
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	body.add_child(cs)
	add_child(body)

# ───────────────────────────── Colocación de props ─────────────────────────────

func _count_instances() -> int:
	var n := 0
	for k in _instances:
		n += (_instances[k] as Array).size()
	return n

func _occupied(p: Vector2, r: float) -> bool:
	var cx := int(floor(p.x / HASH_CELL))
	var cz := int(floor(p.y / HASH_CELL))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var arr: Array = _hash.get(Vector2i(cx + dx, cz + dz), [])
			for e in arr:
				if p.distance_to(e[0]) < r + float(e[1]):
					return true
	return false

func _reserve(p: Vector2, r: float) -> void:
	var key := Vector2i(int(floor(p.x / HASH_CELL)), int(floor(p.y / HASH_CELL)))
	if not _hash.has(key):
		_hash[key] = []
	(_hash[key] as Array).append([p, r])

func _dist_to_ramp(p: Vector2) -> float:
	var ab := _ramp_end - _basin_center
	var t := clampf((p - _basin_center).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(_basin_center + ab * t)

func _slope(x: float, z: float) -> float:
	var hx := get_height_at(x + 1.0, z) - get_height_at(x - 1.0, z)
	var hz := get_height_at(x, z + 1.0) - get_height_at(x, z - 1.0)
	return Vector2(hx, hz).length() * 0.5

## Terreno "normal": fuera de la cuenca, de la rampa y de los acantilados.
func _is_surface(p: Vector2, max_slope: float) -> bool:
	if absf(p.x) > play_half - 4.0 or absf(p.y) > play_half - 4.0:
		return false
	if p.distance_to(_basin_center) < basin_rim_radius + 3.0:
		return false
	if _dist_to_ramp(p) < 9.0:
		return false
	return _slope(p.x, p.y) <= max_slope

func _rand_pos(extent: float) -> Vector2:
	return Vector2(_rng.randf_range(-extent, extent), _rng.randf_range(-extent, extent))

func _add(kind: String, pos: Vector2, yaw: float = -1.0, s: float = -1.0, y_offset: float = -0.04, collide: bool = true, tilt: float = 0.0) -> void:
	var def: Dictionary = PROPS[kind]
	var sc: Vector2 = def["scale"]
	var scale_v := s if s > 0.0 else _rng.randf_range(sc.x, sc.y)
	var yaw_v := yaw if yaw >= 0.0 else _rng.randf() * TAU
	var euler := Vector3(_rng.randf_range(-tilt, tilt), yaw_v, _rng.randf_range(-tilt, tilt))
	var basis := Basis.from_euler(euler).scaled(Vector3.ONE * scale_v)
	var t := Transform3D(basis, Vector3(pos.x, get_height_at(pos.x, pos.y) + y_offset, pos.y))
	if not _instances.has(kind):
		_instances[kind] = []
	(_instances[kind] as Array).append(t)
	if collide and def["shape"] != "":
		if not _collide.has(kind):
			_collide[kind] = []
		(_collide[kind] as Array).append(t)

func _place(kind: String, pos: Vector2, radius: float, yaw: float = -1.0, s: float = -1.0, collide: bool = true, tilt: float = 0.0) -> void:
	_reserve(pos, radius)
	_add(kind, pos, yaw, s, -0.04, collide, tilt)

func _add_light(pos: Vector3, color: Color, energy: float, light_range: float) -> void:
	if _lights.size() >= max_lights:
		return
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = light_range
	l.omni_attenuation = 1.6
	l.shadow_enabled = false
	l.position = pos
	add_child(l)
	_lights.append(l)
	_light_base.append(energy)

func _add_brazier(pos: Vector2) -> void:
	_place("brazier", pos, 0.8)
	var y := get_height_at(pos.x, pos.y)
	_add_light(Vector3(pos.x, y + 1.7, pos.y), Color(1.0, 0.55, 0.2), 2.6, 11.0)
	if embers_enabled:
		_add_embers(Vector3(pos.x, y + 1.4, pos.y))

func _add_embers(pos: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.position = pos
	p.amount = Quality.count(8)
	p.lifetime = 1.6
	p.direction = Vector3.UP
	p.spread = 25.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.6
	p.gravity = Vector3(0, 0.3, 0)
	p.scale_amount_min = 0.03
	p.scale_amount_max = 0.07
	var m := SphereMesh.new()
	m.radius = 0.5
	m.height = 1.0
	m.radial_segments = 4
	m.rings = 2
	p.mesh = m
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_color = Color(1.0, 0.6, 0.2)
	sm.emission_enabled = true
	sm.emission = Color(1.0, 0.5, 0.1)
	sm.emission_energy_multiplier = 4.0
	p.material_override = sm
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	_embers.append(p)

func _scatter_props() -> void:
	_place_plaza()
	_place_basin()
	_place_ruins(3)
	_place_graveyards(3)
	_place_forest()
	_place_misc()
	_place_edge_rocks()

func _place_plaza() -> void:
	_reserve(Vector2.ZERO, 6.0)
	for k in range(4):
		var a := PI * 0.25 + float(k) * PI * 0.5
		_add_brazier(Vector2(cos(a), sin(a)) * 8.0)
	for k in range(int(8.0 * prop_density)):
		var a := _rng.randf() * TAU
		var pos := Vector2(cos(a), sin(a)) * _rng.randf_range(13.0, 17.0)
		if not _occupied(pos, 1.4) and _is_surface(pos, 0.5):
			_place("rock_a", pos, 1.3)

func _place_basin() -> void:
	var c := _basin_center
	_place("altar", c, 3.0, 0.0, 1.0)
	var y := get_height_at(c.x, c.y)
	_add_light(Vector3(c.x, y + 3.2, c.y), Color(0.6, 0.3, 1.0), 4.0, 18.0)
	for k in range(8):
		var a := float(k) * TAU / 8.0 + 0.2
		var pos := c + Vector2(cos(a), sin(a)) * 14.0
		if _dist_to_ramp(pos) > 5.5:
			_place("pillar", pos, 1.4)
	for k in range(4):
		var a := PI * 0.125 + float(k) * PI * 0.5
		var pos := c + Vector2(cos(a), sin(a)) * 8.5
		if _dist_to_ramp(pos) > 4.5:
			_add_brazier(pos)
	var graves := int(16.0 * prop_density)
	for i in range(graves * 6):
		if graves <= 0:
			break
		var a := _rng.randf() * TAU
		var pos := c + Vector2(cos(a), sin(a)) * _rng.randf_range(10.0, 18.5)
		if _dist_to_ramp(pos) < 5.0 or _occupied(pos, 1.0):
			continue
		_place("grave_a" if _rng.randf() < 0.55 else "grave_b", pos, 0.9, -1.0, -1.0, false, 0.06)
		graves -= 1
	for i in range(int(10.0 * prop_density)):
		var a := _rng.randf() * TAU
		var pos := c + Vector2(cos(a), sin(a)) * _rng.randf_range(9.0, 19.0)
		if _dist_to_ramp(pos) > 5.0 and not _occupied(pos, 1.0):
			_place("bones", pos, 0.8, -1.0, -1.0, false)
	for i in range(int(14.0 * prop_density)):
		var a := _rng.randf() * TAU
		var pos := c + Vector2(cos(a), sin(a)) * _rng.randf_range(17.0, 21.5)
		if _dist_to_ramp(pos) > 5.0 and not _occupied(pos, 1.0):
			_place("mushroom", pos, 0.8, -1.0, -1.0, false)
	for i in range(int(8.0 * prop_density)):
		var a := _rng.randf() * TAU
		var pos := c + Vector2(cos(a), sin(a)) * _rng.randf_range(15.0, 19.0)
		if _dist_to_ramp(pos) > 5.0 and not _occupied(pos, 0.9):
			_place("barrel" if _rng.randf() < 0.6 else "crate", pos, 0.9)

func _find_site(radius: float, min_origin: float) -> Vector2:
	for attempt in range(120):
		var p := _rand_pos(play_half - radius - 6.0)
		if p.length() < min_origin:
			continue
		if p.distance_to(_basin_center) < basin_rim_radius + radius + 4.0:
			continue
		if _dist_to_ramp(p) < radius + 8.0:
			continue
		if _occupied(p, radius):
			continue
		if _slope(p.x, p.y) > 0.22:
			continue
		return p
	return Vector2(INF, INF)

func _place_ruins(count: int) -> void:
	for n in range(count):
		var c := _find_site(10.0, 30.0)
		if c.x == INF:
			continue
		_reserve(c, 9.0)
		for k in range(_rng.randi_range(3, 4)):
			var a := _rng.randf() * TAU
			_place("pillar", c + Vector2(cos(a), sin(a)) * _rng.randf_range(3.5, 6.0), 1.4)
		for k in range(_rng.randi_range(2, 3)):
			var a := _rng.randf() * TAU
			var pos := c + Vector2(cos(a), sin(a)) * _rng.randf_range(5.5, 8.0)
			_place("wall", pos, 2.2, a + PI * 0.5)
		for k in range(_rng.randi_range(3, 5)):
			var pos := c + Vector2(_rng.randf_range(-6.0, 6.0), _rng.randf_range(-6.0, 6.0))
			if not _occupied(pos, 0.8):
				_place("barrel", pos, 0.8)
		for k in range(_rng.randi_range(2, 4)):
			var pos := c + Vector2(_rng.randf_range(-6.0, 6.0), _rng.randf_range(-6.0, 6.0))
			if not _occupied(pos, 0.9):
				_place("crate", pos, 0.9)
		for k in range(2):
			var pos := c + Vector2(_rng.randf_range(-7.0, 7.0), _rng.randf_range(-7.0, 7.0))
			if not _occupied(pos, 1.5):
				_place("rock_a", pos, 1.3)
		if not _occupied(c, 1.0):
			_place("bones", c, 0.8, -1.0, -1.0, false)
		_add_brazier(c + Vector2(2.0, 1.5))

func _place_graveyards(count: int) -> void:
	for n in range(count):
		var c := _find_site(13.0, 28.0)
		if c.x == INF:
			continue
		_reserve(c, 11.0)
		var yaw := _rng.randf() * TAU
		var rows := Basis(Vector3.UP, yaw)
		for gx in range(-4, 5):
			for gz in range(-4, 5):
				var local := Vector3(float(gx) * 2.6 + _rng.randf_range(-0.4, 0.4), 0.0, float(gz) * 2.6 + _rng.randf_range(-0.4, 0.4))
				if Vector2(local.x, local.z).length() > 10.0 or _rng.randf() < 0.35:
					continue
				var w := rows * local
				var pos := c + Vector2(w.x, w.z)
				if _occupied(pos, 0.9):
					continue
				_place("grave_a" if _rng.randf() < 0.6 else "grave_b", pos, 0.9, yaw + _rng.randf_range(-0.15, 0.15), -1.0, false, 0.08)
		for k in range(10):
			var a := float(k) * TAU / 10.0 + _rng.randf_range(-0.1, 0.1)
			if _rng.randf() < 0.3:
				continue
			var pos := c + Vector2(cos(a), sin(a)) * 12.5
			_place("fence", pos, 1.3, a + PI * 0.5)
		for k in range(2):
			var a := _rng.randf() * TAU
			var pos := c + Vector2(cos(a), sin(a)) * _rng.randf_range(9.0, 13.0)
			if not _occupied(pos, 1.6):
				_place("tree_a" if _rng.randf() < 0.5 else "tree_b", pos, 1.6)
		for k in range(3):
			var pos := c + Vector2(_rng.randf_range(-8.0, 8.0), _rng.randf_range(-8.0, 8.0))
			if not _occupied(pos, 0.9):
				_place("bones", pos, 0.8, -1.0, -1.0, false)

func _place_forest() -> void:
	var target := int(150.0 * prop_density)
	var placed := 0
	for attempt in range(target * 40):
		if placed >= target:
			break
		var p := _rand_pos(play_half - 3.0)
		if p.length() < 17.0 or not _is_surface(p, 0.6):
			continue
		var f := _noise_forest.get_noise_2d(p.x, p.y)
		if f < -0.1 or _rng.randf() > (f + 0.1) * 2.2 + 0.08:
			continue
		if _occupied(p, 1.7):
			continue
		_place("tree_a" if _rng.randf() < 0.5 else "tree_b", p, 1.7, -1.0, -1.0, true, 0.05)
		placed += 1

func _place_misc() -> void:
	var rocks := int(44.0 * prop_density)
	for i in range(rocks * 8):
		if rocks <= 0:
			break
		var p := _rand_pos(play_half - 4.0)
		if p.length() < 14.0 or not _is_surface(p, 0.7) or _occupied(p, 1.8):
			continue
		_place("rock_a" if _rng.randf() < 0.65 else "rock_b", p, 1.8)
		rocks -= 1
	var shrooms := int(26.0 * prop_density)
	for i in range(shrooms * 12):
		if shrooms <= 0:
			break
		var p := _rand_pos(play_half - 4.0)
		if p.length() < 14.0 or not _is_surface(p, 0.6) or _occupied(p, 0.8):
			continue
		if _noise_forest.get_noise_2d(p.x, p.y) < 0.1:
			continue
		_place("mushroom", p, 0.8, -1.0, -1.0, false)
		shrooms -= 1
	var loose := int(22.0 * prop_density)
	for i in range(loose * 10):
		if loose <= 0:
			break
		var p := _rand_pos(play_half - 4.0)
		if p.length() < 12.0 or not _is_surface(p, 0.4) or _occupied(p, 1.0):
			continue
		_place("barrel" if _rng.randf() < 0.55 else "crate", p, 1.0)
		if _rng.randf() < 0.5:
			var q := p + Vector2(_rng.randf_range(-1.3, 1.3), _rng.randf_range(-1.3, 1.3))
			if not _occupied(q, 0.8):
				_place("barrel", q, 0.8)
		loose -= 1
	var bones := int(14.0 * prop_density)
	for i in range(bones * 10):
		if bones <= 0:
			break
		var p := _rand_pos(play_half - 4.0)
		if p.length() < 12.0 or not _is_surface(p, 0.5) or _occupied(p, 0.9):
			continue
		_place("bones", p, 0.8, -1.0, -1.0, false)
		bones -= 1
	# Algún brasero suelto con luz como punto de referencia
	for i in range(3):
		var p := _find_site(2.0, 25.0)
		if p.x != INF:
			_add_brazier(p)

func _place_edge_rocks() -> void:
	var edge := play_half - 2.0
	var step := 8.0 if not _mobile else 12.0
	var n := int(edge * 2.0 / step)
	for side in range(4):
		for i in range(n):
			var u := -edge + float(i) * step + _rng.randf_range(-2.0, 2.0)
			var inset := _rng.randf_range(0.0, 3.0)
			var p := Vector2.ZERO
			match side:
				0: p = Vector2(u, -edge + inset)
				1: p = Vector2(u, edge - inset)
				2: p = Vector2(-edge + inset, u)
				_: p = Vector2(edge - inset, u)
			if p.distance_to(_basin_center) < basin_rim_radius or _rng.randf() < 0.25:
				continue
			_add("rock_b", p, -1.0, _rng.randf_range(1.0, 1.8), -0.3, false)

# ───────────────────────────── Nodos de props ─────────────────────────────

func _load_kind(kind: String) -> Mesh:
	if _mesh_cache.has(kind):
		return _mesh_cache[kind]
	var path: String = PROP_DIR + String(PROPS[kind]["file"]) + ".glb"
	var ps := load(path) as PackedScene
	if ps == null:
		push_warning("[ProceduralMap] No se pudo cargar " + path + " (¿importado?)")
		_mesh_cache[kind] = null
		return null
	var root := ps.instantiate()
	var found := _find_mesh_instance(root)
	var mesh: Mesh = null
	var xf := Transform3D.IDENTITY
	if found:
		mesh = _flatten_mesh(found.mesh)
		var n: Node = found
		while n and n != root:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
	root.free()
	_mesh_cache[kind] = mesh
	_mesh_xf[kind] = xf
	return mesh

var _prop_material: ShaderMaterial = null

## Fusiona todas las superficies de la malla en una sola: el color de cada material pasa al color de vértice
## (RGB = albedo en lineal, A = 1 si el material emite luz) y se usa el material único prop_flat.
## Pierde el brillo metálico de los aros de hierro, a cambio de 2–3 veces menos llamadas de dibujo.
func _flatten_mesh(src: Mesh) -> Mesh:
	if src == null:
		return src
	if _prop_material == null:
		_prop_material = ShaderMaterial.new()
		_prop_material.shader = PROP_SHADER
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for s in range(src.get_surface_count()):
		var arr := src.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var n = arr[Mesh.ARRAY_NORMAL]
		var ix = arr[Mesh.ARRAY_INDEX]
		var base := verts.size()
		var color := Color(0.5, 0.5, 0.5, 0.0)
		var emissive := false
		var m := src.surface_get_material(s)
		if m is BaseMaterial3D:
			color = (m as BaseMaterial3D).albedo_color
			emissive = (m as BaseMaterial3D).emission_enabled
		var lin := color.srgb_to_linear()
		lin.a = 1.0 if emissive else 0.0
		verts.append_array(v)
		if n != null:
			norms.append_array(n)
		else:
			norms.resize(verts.size())
		for i in range(v.size()):
			cols.append(lin)
		if ix != null:
			for k in ix:
				idx.append(base + int(k))
		else:
			for k in range(v.size()):
				idx.append(base + k)
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = norms
	out[Mesh.ARRAY_COLOR] = cols
	out[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	mesh.surface_set_material(0, _prop_material)
	return mesh

func _find_mesh_instance(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var r := _find_mesh_instance(c)
		if r:
			return r
	return null

func _build_prop_nodes() -> void:
	var container := Node3D.new()
	container.name = "Props"
	add_child(container)
	var body := StaticBody3D.new()
	body.name = "PropColliders"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)

	for kind in _instances:
		var mesh := _load_kind(kind)
		if mesh == null:
			continue
		var xf: Transform3D = _mesh_xf[kind]
		# Agrupar por chunk para que el culling de cámara funcione
		var chunks: Dictionary = {}
		for t in (_instances[kind] as Array):
			var key := Vector2i(int(floor((t.origin.x + half_size) / chunk_size)), int(floor((t.origin.z + half_size) / chunk_size)))
			if not chunks.has(key):
				chunks[key] = []
			(chunks[key] as Array).append(t)
		for key in chunks:
			var list: Array = chunks[key]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = mesh
			mm.instance_count = list.size()
			for i in range(list.size()):
				mm.set_instance_transform(i, (list[i] as Transform3D) * xf)
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "%s_%d_%d" % [kind, key.x, key.y]
			mmi.multimesh = mm
			var small: bool = kind in ["bones", "mushroom", "grave_a", "grave_b", "barrel", "crate"]
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if (_mobile or small) else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			container.add_child(mmi)

	for kind in _collide:
		var def: Dictionary = PROPS[kind]
		var size: Vector3 = def["size"]
		var shape: Shape3D
		var offset: float
		if def["shape"] == "cyl":
			var cyl := CylinderShape3D.new()
			cyl.radius = size.x
			cyl.height = size.y
			shape = cyl
			offset = size.y * 0.5
		else:
			var bx := BoxShape3D.new()
			bx.size = size
			shape = bx
			offset = size.y * 0.5
		for t in (_collide[kind] as Array):
			var cs := CollisionShape3D.new()
			cs.shape = shape
			cs.transform = (t as Transform3D).translated_local(Vector3(0.0, offset, 0.0))
			body.add_child(cs)

func _process(delta: float) -> void:
	if _lights.is_empty():
		return
	_cull_timer -= delta
	if _cull_timer <= 0.0:
		_cull_timer = 0.4
		_cull_lights_and_embers()
	_flicker_t += delta
	for i in range(_lights.size()):
		var l := _lights[i]
		if not is_instance_valid(l) or not l.visible:
			continue
		var f := 0.85 + 0.15 * sin(_flicker_t * 9.0 + float(i) * 1.7) + 0.08 * sin(_flicker_t * 23.0 + float(i) * 4.1)
		l.light_energy = _light_base[i] * f

## Apaga luces y brasas lejos del jugador (cada 0,4 s): cada luz dinámica y cada sistema de partículas
## cuesta en cada frame aunque estén fuera de vista.
func _cull_lights_and_embers() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var limit: float = LIGHT_CULL_DIST_MOBILE if _mobile else LIGHT_CULL_DIST_PC
	var limit_sq := limit * limit
	var pp := player.global_position
	var lights_on := Quality.lights_enabled()
	for l in _lights:
		if is_instance_valid(l):
			l.visible = lights_on and l.global_position.distance_squared_to(pp) <= limit_sq
	for p in _embers:
		if is_instance_valid(p):
			var near := p.global_position.distance_squared_to(pp) <= limit_sq
			if near != p.emitting:
				p.emitting = near
