class_name SewerMap
extends DungeonMap

## Cloacas procedurales (mundo "sewers", ver WorldDefs; escena main_sewers.tscn).
##
## Reutiliza de DungeonMap la distribución, la navegación, los encuentros y los destructibles, y cambia
## la geometría y la decoración:
##  - Cámaras de ladrillo casi rectas (superelipses) con formas propias: cámara, cisterna (foso de agua
##    alrededor del centro, con cuatro pasos), cruce y galería de tuberías (larga, con columnas y canal).
##  - Túneles rectos o en L con un canal de agua residual en el centro y pasarelas a los lados.
##  - Agua residual: frena al jugador local y le envenena poco a poco mientras la pisa.
##  - Decoración por sala: colector (tuberías que vierten al agua, válvulas), vertedero (bolsas y
##    montones de basura) y bombeo (bidones tóxicos y luz verde). Rejillas del techo con haces de luz.
##  - Bidones tóxicos (DestructibleProp): al romperse estallan en una nube venenosa que daña a
##    enemigos y al jugador, y revientan los bidones vecinos.

const SEWER_SHAPES := ["chamber", "cistern", "junction", "pipe_hall"]
const ROOM_POWER := 5.0               ## exponente de las superelipses (más alto = más cuadrado)
const SEWER_TUNNEL_R := 2.1           ## radio de los túneles (celdas): canal + pasarelas
const CANAL_HALF := 0.75              ## medio ancho del canal (celdas)
const WATER_Y := 0.09                 ## altura de la superficie del agua (m): cubre los pies
const WATER_SLOW := 0.62              ## velocidad del jugador dentro del agua
const WATER_POISON_DPS := 1.0         ## veneno por carga mientras se pisa el agua
const WATER_POISON_EVERY := 1.0       ## s seguidos en el agua por cada carga de veneno
const TOXIC_RADIUS := 3.2             ## m de la nube de un bidón tóxico
const TOXIC_CHAIN_DELAY := 0.18       ## s hasta que revienta el bidón vecino
const SHAFT_HEIGHT := 10.0
const BRICK_SHADER: Shader = preload("res://assets/shaders/sewer_brick.gdshader")
const WATER_SHADER: Shader = preload("res://assets/shaders/sewer_water.gdshader")
const SPORE_CLOUD: PackedScene = preload("res://scenes/objects/spore_cloud.tscn")

## Props propios: modelos de blender_sources/sewer_enemies.blend (texto build_sewer_props.py),
## exportados a PROP_DIR como sewer_<tipo>.glb.
const SEWER_PROPS := {
	"trash_bag":    {"file": "sewer_trash_bag",    "shape": "cyl", "size": Vector3(0.42, 0.7, 0.0),  "scale": Vector2(0.8, 1.2)},
	"toxic_barrel": {"file": "sewer_toxic_barrel", "shape": "cyl", "size": Vector3(0.42, 0.95, 0.0), "scale": Vector2(0.95, 1.05)},
	"trash_pile":   {"file": "sewer_trash_pile",   "shape": "cyl", "size": Vector3(1.0, 0.9, 0.0),   "scale": Vector2(0.85, 1.3)},
	"wall_pipe":    {"file": "sewer_wall_pipe",    "shape": "",    "size": Vector3.ZERO,             "scale": Vector2(0.9, 1.1)},
	"drain":        {"file": "sewer_drain",        "shape": "",    "size": Vector3.ZERO,             "scale": Vector2(1.0, 1.0)},
	"valve":        {"file": "sewer_valve",        "shape": "cyl", "size": Vector3(0.25, 1.3, 0.0),  "scale": Vector2(0.9, 1.1)},
}

## Haz de luz que entra por una rejilla del techo (aditivo, sin sombras).
const SHAFT_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 col : source_color = vec4(0.75, 0.85, 0.65, 1.0);
uniform float strength = 0.09;
void fragment() {
	float rim = pow(abs(dot(NORMAL, VIEW)), 1.6);
	float fade = smoothstep(0.0, 0.25, UV.y) * (1.0 - UV.y * 0.35);
	float dust = 0.75 + 0.25 * sin(UV.y * 40.0 - TIME * 0.8 + UV.x * 12.0);
	ALBEDO = col.rgb;
	ALPHA = clamp(strength * rim * fade * dust, 0.0, 1.0);
}
"""
## Mancha de luz con la sombra de los barrotes de la rejilla, en el suelo.
const GRATE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 col : source_color = vec4(0.75, 0.85, 0.65, 1.0);
void fragment() {
	vec2 c = UV - 0.5;
	float r = 1.0 - smoothstep(0.3, 0.5, length(c));
	float bars = step(0.3, fract(UV.x * 6.0)) * step(0.3, fract(UV.y * 6.0));
	ALBEDO = col.rgb;
	ALPHA = r * (0.08 + 0.22 * bars);
}
"""
static var _shaft_shader: Shader
static var _grate_shader: Shader

var _water: Dictionary = {}           # Vector2i -> true (celdas con agua residual)
var _shafts: Array = []               # [Vector2] haces de luz de las rejillas
var _wade_t := 0.0                    # s seguidos dentro del agua (jugador local)

func _init() -> void:
	edge_noise_amp = 0.05

func generate(p_seed: int = 0) -> void:
	_water.clear()
	_shafts.clear()
	super.generate(p_seed)

## ¿Hay agua residual en este punto?
func is_water(p: Vector3) -> bool:
	return _water.has(world_to_cell(p))

func _prop_def(kind: String) -> Dictionary:
	return SEWER_PROPS[kind] if SEWER_PROPS.has(kind) else PROPS[kind]

# ───────────────────────────── Formas y canales ─────────────────────────────

func _base_shape() -> String:
	return "chamber"

func _pick_shape() -> String:
	return String(SEWER_SHAPES[_rng.randi() % SEWER_SHAPES.size()])

func _shape_blobs(shape: String, c: Vector2, r0: Vector2, blobs: Array, pillars: Array) -> void:
	if not shape in SEWER_SHAPES:
		super._shape_blobs(shape, c, r0, blobs, pillars)
		return
	var axis := Vector2.RIGHT if _rng.randf() < 0.5 else Vector2.DOWN
	var side := axis.orthogonal()
	match shape:
		"chamber":
			# Sala rectangular con 1-2 hornacinas laterales
			blobs.append([c, r0 * 0.95, ROOM_POWER])
			for k in _rng.randi_range(1, 2):
				var dir: Vector2 = [axis, -axis, side, -side][_rng.randi() % 4]
				var reach: float = r0.x if absf(dir.x) > 0.5 else r0.y
				blobs.append([c + dir * reach * 0.85, r0 * 0.36, ROOM_POWER])
		"cistern":
			# Pozo redondo: el foso de agua lo pone _carve
			var m := maxf(maxf(r0.x, r0.y), 9.0)
			blobs.append([c, Vector2(m, m) * 1.05])
		"junction":
			blobs.append([c, r0 * 0.62, ROOM_POWER])
			blobs.append([c, Vector2(r0.x * 1.35, r0.y * 0.45), ROOM_POWER])
			blobs.append([c, Vector2(r0.x * 0.45, r0.y * 1.35), ROOM_POWER])
		"pipe_hall":
			var long := Vector2(r0.x * 1.6, r0.y * 0.62) if axis == Vector2.RIGHT else Vector2(r0.x * 0.62, r0.y * 1.6)
			blobs.append([c, long, ROOM_POWER])
			for k in [-2, -1, 1, 2]:
				for s in [-1.0, 1.0]:
					pillars.append(c + axis * float(k) * 3.6 + side * s * minf(long.x, long.y) * 0.45)
	for i in range(pillars.size() - 1, -1, -1):
		if (pillars[i] as Vector2).distance_to(c) < CENTER_CLEAR + PILLAR_R:
			pillars.remove_at(i)

func _carve() -> void:
	super._carve()
	for r in rooms:
		var c := Vector2(r["cell"])
		match r["shape"]:
			"cistern":
				# Foso alrededor del centro, con cuatro pasos secos en cruz
				for cell in r["cells"]:
					var d := Vector2(cell) - c
					var dist := d.length()
					if dist >= CENTER_CLEAR + 1.5 and dist <= CENTER_CLEAR + 3.2 and absf(d.x) > 1.2 and absf(d.y) > 1.2:
						_water[cell] = true
			"pipe_hall":
				# Canal a un lado de la galería, entre las columnas y la pared
				var b: Vector2 = r["blobs"][0][1]
				var along_x := b.x > b.y
				var half_w := minf(b.x, b.y)
				for cell in r["cells"]:
					var off: float = (Vector2(cell) - c).y if along_x else (Vector2(cell) - c).x
					if off >= half_w * 0.6 and off <= half_w * 0.85:
						_water[cell] = true
	# Las columnas y la pared se comen parte del canal
	for cell in _water.keys():
		if not _cells.has(cell):
			_water.erase(cell)

## Túnel recto o en L: primero por el eje con más recorrido, luego por el otro.
func _carve_tunnel(a: Vector2, b: Vector2) -> void:
	var corner := Vector2(b.x, a.y) if absf(b.x - a.x) >= absf(b.y - a.y) else Vector2(a.x, b.y)
	_carve_segment(a, corner)
	_carve_segment(corner, b)

func _carve_segment(a: Vector2, b: Vector2) -> void:
	var steps := maxi(int(a.distance_to(b) * 2.0), 1)
	for k in steps + 1:
		var p := a.lerp(b, float(k) / steps)
		for dx in range(-3, 4):
			for dz in range(-3, 4):
				var q := Vector2i(roundi(p.x) + dx, roundi(p.y) + dz)
				var d := Vector2(q).distance_to(p)
				if d <= SEWER_TUNNEL_R and not _cells.has(q):
					_cells[q] = CORRIDOR
				# Canal central: no entra en el centro de las salas (encuentros, portal, altar)
				if d <= CANAL_HALF and _cells.has(q) and _far_from_centers(q):
					_water[q] = true

func _far_from_centers(q: Vector2i) -> bool:
	for r in rooms:
		if Vector2(q).distance_to(Vector2(r["cell"])) < CENTER_CLEAR + 2.5:
			return false
	return true

# ───────────────────────────── Geometría ─────────────────────────────

## Las cloacas siguen con muros de bloques sobre la rejilla: no hace falta suelo bajo ellos.
func _floor_under_walls() -> bool:
	return false

func _floor_material() -> Material:
	var mat := _brick_material()
	mat.set_shader_parameter("floor_tiles", true)
	return mat

## Material de ladrillo/losas con las texturas horneadas (assets/textures/dungeon: brick y flagstone).
func _brick_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = BRICK_SHADER
	mat.set_shader_parameter("grime_color", palette()["moss"])
	mat.set_shader_parameter("brick_tex", load(TEX_DIR + "brick_albedo.png"))
	mat.set_shader_parameter("brick_normal", load(TEX_DIR + "brick_normal.png"))
	mat.set_shader_parameter("tile_tex", load(TEX_DIR + "flagstone_albedo.png"))
	mat.set_shader_parameter("tile_normal", load(TEX_DIR + "flagstone_normal.png"))
	mat.set_shader_parameter("use_normal_map", Quality.level() != Quality.Level.LOW)
	return mat

## Losas del color del tema, más sucias junto a las paredes y bajo el agua.
func _floor_color(c: Vector2i) -> Color:
	var n := (_edge_noise.get_noise_2d(c.x * 4.0, c.y * 4.0) + 1.0) * 0.5
	var near_wall := 1.0 - clampf(float(_wall_dist.get(c, 4)) / 4.0, 0.0, 1.0)
	var col: Color = (palette()["dirt"] as Color).lerp(palette()["moss"], n * 0.35 + near_wall * 0.45)
	col *= _rng.randf_range(0.6, 0.85)
	if _water.has(c):
		col *= 0.4
	return col

## Paredes de ladrillo: bloques alineados (sin giro) de altura casi constante.
func _build_wall_visuals() -> void:
	var box := BoxMesh.new()
	box.size = Vector3(CELL, 1.0, CELL)
	box.material = _brick_material()
	var all: Array = []
	for c in _walls:
		all.append([c, WALL_H * _rng.randf_range(1.05, 1.15)])
	for c in _outer:
		all.append([c, WALL_H * _rng.randf_range(1.5, 1.7)])
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = box
	mm.instance_count = all.size()
	for i in all.size():
		var c: Vector2i = all[i][0]
		var h: float = all[i][1]
		var basis := Basis().scaled(Vector3(1.0, h, 1.0))
		mm.set_instance_transform(i, Transform3D(basis, _cell_pos(c) + Vector3(0.0, h * 0.5 - 0.05, 0.0)))
		mm.set_instance_color(i, (palette()["rock"] as Color) * _rng.randf_range(0.85, 1.05))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Walls"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if _mobile else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mmi)

func _build_extra() -> void:
	_build_water()
	_build_shafts()

func _build_water() -> void:
	if _water.is_empty():
		return
	var plane := PlaneMesh.new()
	plane.size = Vector2(CELL, CELL)
	var mat := ShaderMaterial.new()
	mat.shader = WATER_SHADER
	mat.set_shader_parameter("glow_color", palette()["crystal"])
	plane.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = plane
	mm.instance_count = _water.size()
	var i := 0
	for c in _water:
		mm.set_instance_transform(i, Transform3D(Basis(), _cell_pos(c) + Vector3(0.0, WATER_Y, 0.0)))
		i += 1
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Water"
	mmi.multimesh = mm
	mmi.layers = GROUND_VISUAL_LAYER
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)

## Haces de luz de las rejillas del techo: cono aditivo, mancha con barrotes en el suelo y una luz suave.
func _build_shafts() -> void:
	if _shafts.is_empty():
		return
	if _shaft_shader == null:
		_shaft_shader = Shader.new()
		_shaft_shader.code = SHAFT_SHADER
		_grate_shader = Shader.new()
		_grate_shader.code = GRATE_SHADER
	var cone := CylinderMesh.new()
	cone.top_radius = 0.55
	cone.bottom_radius = 1.25
	cone.height = SHAFT_HEIGHT
	cone.cap_top = false
	cone.cap_bottom = false
	cone.radial_segments = 16
	var cone_mat := ShaderMaterial.new()
	cone_mat.shader = _shaft_shader
	cone.material = cone_mat
	var patch := QuadMesh.new()
	patch.size = Vector2(3.2, 3.2)
	var patch_mat := ShaderMaterial.new()
	patch_mat.shader = _grate_shader
	patch.material = patch_mat
	for p in _shafts:
		var pos: Vector2 = p
		var shaft := MeshInstance3D.new()
		shaft.mesh = cone
		shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		shaft.position = Vector3(pos.x, SHAFT_HEIGHT * 0.5, pos.y)
		add_child(shaft)
		var spot := MeshInstance3D.new()
		spot.mesh = patch
		spot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		spot.rotation.x = -PI * 0.5
		spot.position = Vector3(pos.x, 0.03, pos.y)
		add_child(spot)
		_add_light(Vector3(pos.x, 3.0, pos.y), Color(0.78, 0.88, 0.7), 1.3, 8.0)

# ───────────────────────────── Decoración ─────────────────────────────

func _decorate_room(i: int) -> void:
	var r: Dictionary = rooms[i]
	var c: Vector3 = r["center"]
	var center := Vector2(c.x, c.z)
	_reserve(center, 4.5)                                 # centro libre para combatir

	match r["theme"]:
		"start":
			# Bajada por la boca de alcantarilla: haz de luz junto al centro
			_add_shaft(center + Vector2(3.0, 2.0))
			for k in 2:
				_try_place(r, "trash_bag", 0.6, 2, 4)
			_place("drain", center + Vector2(-3.5, -1.5), 0.8, 0.0, -1.0, false)
		"end":
			_add("altar", center, 0.0, 1.0)
			for k in 6:
				var a := TAU * k / 6.0
				var p := center + Vector2(cos(a), sin(a)) * 7.0
				if k % 2 == 0:
					_reserve(p, 0.7)
					_breakable("toxic_barrel", p)
				else:
					_place("valve", p, 0.6, _yaw_to(p, center))
			for k in 3:
				var a2 := TAU * (k + 0.5) / 3.0
				_add_brazier(center + Vector2(cos(a2), sin(a2)) * 10.0)
		"treasure":
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
		"collector":
			for k in _rng.randi_range(4, 7):
				_wall_pipe(r, center)
			for k in _rng.randi_range(1, 2):
				_try_place(r, "valve", 0.6, 2, 4)
			for k in _rng.randi_range(2, 3):
				var p := _spot(r, 1.5, 2, 5)
				if p != Vector2.INF:
					_crate_stack(p)
			_add_brazier(center + Vector2(5.0, 0.0))
		"dump", "storage":
			for k in _rng.randi_range(3, 5):
				_try_place(r, "trash_pile", 1.3, 2, 5)
			for k in _rng.randi_range(3, 5):
				var p := _spot(r, 1.2, 2, 5)
				if p != Vector2.INF:
					_bag_cluster(p)
			for k in _rng.randi_range(1, 2):
				var p2 := _spot(r, 1.5, 2, 4)
				if p2 != Vector2.INF:
					_barrel_cluster(p2)
			_add_brazier(center + Vector2(0.0, 5.0))
		"pumps":
			for k in _rng.randi_range(3, 4):
				var p := _spot(r, 1.3, 2, 5)
				if p != Vector2.INF:
					_toxic_cluster(p)
			for k in _rng.randi_range(2, 4):
				_wall_pipe(r, center)
			for k in _rng.randi_range(2, 3):
				_try_place(r, "valve", 0.6, 2, 4)
			_add_light(Vector3(center.x, 2.2, center.y), palette()["crystal"], 2.0, 12.0)

	# Comunes: tuberías en la pared, rejillas con luz, basura suelta y algún sumidero
	for k in _rng.randi_range(2, 3):
		_wall_pipe(r, center)
	if r["theme"] != "start" and _rng.randf() < 0.7:
		var sp := _spot(r, 1.6, 3, 6)
		if sp != Vector2.INF:
			_add_shaft(sp)
	for k in _rng.randi_range(1, 3):
		var p := _spot(r, 0.8, 1, 3)
		if p != Vector2.INF:
			_reserve(p, 0.6)
			_breakable("trash_bag", p)
	var detail: Array = ["rock_a", "drain"]
	for b in int(palette()["bones"]):
		detail.append("bones")
	for k in _rng.randi_range(4, 7):
		var p := _spot(r, 0.8, 1, 99)
		if p == Vector2.INF:
			continue
		var kind: String = detail[_rng.randi() % detail.size()]
		_place(kind, p, 0.8, -1.0, 0.4 if kind == "rock_a" else -1.0, kind == "rock_a")
	_place_crystals(r)

## Haz de luz de una rejilla del techo en `pos` (deja libre su mancha de luz).
func _add_shaft(pos: Vector2) -> void:
	_reserve(pos, 1.2)
	_shafts.append(pos)

## Tubería pegada a la pared que vierte hacia el centro de la sala.
func _wall_pipe(r: Dictionary, center: Vector2) -> void:
	var p := _spot(r, 0.7, 1, 1)
	if p == Vector2.INF:
		return
	_place("wall_pipe", p, 0.7, _yaw_to(p, center), -1.0, false)

func _bag_cluster(at: Vector2) -> void:
	_reserve(at, 0.5)
	_breakable("trash_bag", at)
	for i in _rng.randi_range(1, 3):
		var p := at + Vector2(_rng.randf_range(-1.1, 1.1), _rng.randf_range(-1.1, 1.1))
		if not _occupied(p, 0.5):
			_reserve(p, 0.5)
			_breakable("trash_bag", p, 0.0, -1.0, 0.15)

func _toxic_cluster(at: Vector2) -> void:
	_reserve(at, 0.6)
	_breakable("toxic_barrel", at)
	for i in _rng.randi_range(1, 2):
		var p := at + Vector2(_rng.randf_range(-1.3, 1.3), _rng.randf_range(-1.3, 1.3))
		if not _occupied(p, 0.55):
			_reserve(p, 0.55)
			_breakable("toxic_barrel", p)

## Sin pasto en las cloacas.
func _scatter_grass(_r: Dictionary) -> void:
	pass

## Charcos tóxicos luminosos junto a las paredes (los "cristales" del tema).
func _place_crystals(r: Dictionary) -> void:
	var n := int(palette()["crystals"])
	if _mobile:
		n = n / 2
	for k in n:
		var p := _spot(r, 0.9, 1, 3)
		if p == Vector2.INF:
			continue
		_reserve(p, 0.9)
		var s := _rng.randf_range(0.4, 0.85)
		var basis := Basis.from_euler(Vector3(0.0, _rng.randf() * TAU, 0.0)).scaled(Vector3(s * _rng.randf_range(1.0, 1.6), 1.0, s))
		_crystals.append(Transform3D(basis, Vector3(p.x, 0.02, p.y)))
		if k % 4 == 0:
			_add_light(Vector3(p.x, 0.8, p.y), palette()["crystal"], 1.2, 6.0)

func _build_crystals() -> void:
	if _crystals.is_empty():
		return
	var disc := CylinderMesh.new()
	disc.top_radius = 0.7
	disc.bottom_radius = 0.7
	disc.height = 0.03
	disc.radial_segments = 14
	var mat := StandardMaterial3D.new()
	var col: Color = palette()["crystal"]
	mat.albedo_color = col.darkened(0.75)
	mat.emission_enabled = true
	mat.emission = col.darkened(0.3)
	mat.emission_energy_multiplier = 0.5
	mat.roughness = 0.1
	disc.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = disc
	mm.instance_count = _crystals.size()
	for i in _crystals.size():
		mm.set_instance_transform(i, _crystals[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "ToxicPuddles"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)

# ───────────────────────────── Agua y bidones tóxicos ─────────────────────────────

## El agua frena al jugador local y, si sigue dentro, le envenena (cada equipo trata a su jugador).
func _physics_process(delta: float) -> void:
	if _water.is_empty() or Net.is_dedicated():
		return
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p == null or bool(p.get_meta("downed", false)) or not is_water(p.global_position):
		_wade_t = 0.0
		return
	var mc = p.get("movement_controller")
	if mc != null:
		var now := Time.get_ticks_msec() / 1000.0
		mc.slow_mult = WATER_SLOW if now >= mc.slow_until else minf(mc.slow_mult, WATER_SLOW)
		mc.slow_until = maxf(mc.slow_until, now + 0.15)
	_wade_t += delta
	if _wade_t >= WATER_POISON_EVERY:
		_wade_t = 0.0
		StatusEffects.apply_to(p, "poison", WATER_POISON_DPS, 2.5)

func _on_breakable_destroyed(d: DestructibleProp) -> void:
	super._on_breakable_destroyed(d)
	if d.kind == "toxic_barrel":
		_toxic_burst(d.global_position)

## Nube venenosa de un bidón: daña a los enemigos (SporeCloud), envenena al jugador local si está
## dentro y revienta los bidones tóxicos cercanos.
func _toxic_burst(pos: Vector3) -> void:
	var cloud := SPORE_CLOUD.instantiate()
	cloud.radius = TOXIC_RADIUS
	cloud.damage_per_tick = 4.0
	cloud.lifetime = 4.0
	add_child(cloud)
	cloud.global_position = pos + Vector3(0.0, 0.6, 0.0)
	AudioManager.play_at("explosion", pos, -4.0, randf_range(0.8, 0.95))
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p != null and not Net.is_dedicated() and p.global_position.distance_to(pos) <= TOXIC_RADIUS:
		StatusEffects.apply_to(p, "poison", 2.0, 4.0, null, -1, 2)
	for other in destructibles:
		if is_instance_valid(other) and not other.is_broken() and other.kind == "toxic_barrel" \
				and other.global_position.distance_to(pos) <= TOXIC_RADIUS * 0.8:
			var target: DestructibleProp = other
			get_tree().create_timer(TOXIC_CHAIN_DELAY).timeout.connect(func():
				if is_instance_valid(target) and not target.is_broken():
					target.take_damage(999.0, (target.global_position - pos).normalized()))
