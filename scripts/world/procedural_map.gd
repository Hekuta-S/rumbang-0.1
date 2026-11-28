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

const GROUND_SHADER: Shader = preload("res://assets/shaders/toon_ground.gdshader")
const GROUND_SHADER_MOBILE: Shader = preload("res://assets/shaders/toon_ground_mobile.gdshader")   ## luz por vértice, sin anisotrópico
## Texturas del suelo con la tinta horneada (tools/make_toon_textures.py)
const GROUND_TEX := {
	"grass_tex": "res://assets/textures/toon/toon_grass.png",
	"dirt_tex": "res://assets/textures/toon/toon_dirt.png",
	"rock_tex": "res://assets/textures/toon/toon_rock.png",
	"stone_tex": "res://assets/textures/toon/toon_flagstone.png",
}
const PROP_SHADER: Shader = preload("res://assets/shaders/prop_flat.gdshader")
## Props con textura cartoon horneada (tinta incluida): tools/blender_toon_props.py
const PROP_TOON_SHADER: Shader = preload("res://assets/shaders/prop_toon.gdshader")
const PROP_TOON_DIR := "res://assets/textures/toon/props/"
## Tamaño de los chunks de props (m): grandes = menos llamadas de dibujo. Los props tienen muy pocos
## triángulos (56–590), así que dibujarlos todos cuesta menos que muchas llamadas de dibujo.
const CHUNK_PC := 160.0               ## mapa de 320 m: 2 × 2 chunks por tipo de prop
const CHUNK_MOBILE := 320.0           ## un solo chunk: 1 llamada por tipo de prop
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
@export var half_size: float = 160.0                ## mitad del lado de la malla (320 m; antes 115)
@export var cell_size: float = 1.5                  ## resolución del terreno (m)
@export var hill_amplitude: float = 4.5
@export var basin_depth: float = 9.0
@export var basin_distance: float = 58.0            ## centro de la cuenca desde el origen
@export var basin_floor_radius: float = 20.0
@export var basin_rim_radius: float = 32.0
@export var play_half: float = 143.0                ## donde empiezan los acantilados (antes 98)
@export var cliff_height: float = 22.0
@export var chunk_size: float = 80.0
@export_range(0.0, 2.0, 0.05) var prop_density: float = 1.0
## Mesetas con paredes de roca y rampas de acceso (relieve para jugar en 3D). 0 = sin mesetas.
## Una de ellas puede salir escalonada (zigurat: un segundo piso con su propia rampa).
@export var mesa_count: int = 4
@export var mesa_height_range := Vector2(4.5, 7.0)
@export var max_lights: int = 24                    ## luces que se crean como mucho (las lejanas se apagan)
## Luces encendidas a la vez como mucho: las más cercanas al jugador (dentro de la distancia de corte).
@export var visible_lights: int = 16
## Las luces son la iluminación principal (cueva cerrada): se encienden aunque la calidad las apague
## (entonces con un tope más bajo, ver DungeonMap._place_torches).
var lights_essential := false
## Props con textura cartoon horneada cuando existe (false: todos con prop_flat / prop_detail)
var use_toon_props := true
var light_scale := 1.0                ## multiplica la fuerza de todas las luces (de día, DayNightCycle las baja)
@export var embers_enabled: bool = true
## Árboles dibujados (2D horneado) y destructibles (TreeField) en vez de los modelos 3D tree_dead_*.
@export var tree_sprites: bool = true
const TREE_KINDS := ["tree_a", "tree_b"]
var trees: TreeField = null
## Barrio del Desagüe (SewerDistrict): cloacas a cielo abierto en un borde del mapa de Supervivencia.
@export var district_enabled: bool = true
var district: SewerDistrict = null        ## el primero de `districts` (compatibilidad)
var districts: Array = []                  ## [SewerDistrict]: uno en el Bosque, dos (uno a cada lado) en Cloacas

## Mapa de supervivencia: "forest" (Bosque) o "sewers" (Cloacas: casi todo el mapa es ciudad de canales).
## Vacío = GameData.survival_map (en la mazmorra siempre "forest", DungeonMap no lo usa).
var theme: String = ""
var _theme: String = "forest"
const THEMES := ["forest", "sewers"]
const SEWER_DEPTH_START := 62.0            ## Cloacas: cada barrio empieza a 62 m del centro (en el Bosque, 100)
const SEWER_MAIN_U := Vector2(80.0, 86.0)
const SEWER_HILLS := 2.0                   ## lomas más bajas: es una ciudad
## Suelo de Cloacas: mismas ranuras que GROUND_TEX (tools/make_toon_textures.py sewer_*)
const GROUND_TEX_SEWERS := {
	"grass_tex": "res://assets/textures/toon/toon_sewer_cobble.png",
	"dirt_tex": "res://assets/textures/toon/toon_sewer_mud.png",
	"rock_tex": "res://assets/textures/toon/toon_sewer_brick.png",
	"stone_tex": "res://assets/textures/toon/toon_sewer_tile.png",
}
const SEWER_GLOW := Color(0.45, 1.0, 0.35)
var _base_params: Dictionary = {}
## Área jugable (sin el barrio) respecto al mapa de 196 m de antes: escala cuántos props y mesetas hay.
const BASE_PLAY_AREA := 196.0 * 196.0
var _area_k: float = 1.0

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

## Media anchura (m) de la pared de una meseta: más estrecha que una celda del terreno, así que con 4,5 m
## o más de altura la pared queda por encima de 60° (la malla de 1,5 m la suaviza), más de lo que
## sube el jugador (45°): él usa las rampas o las runas. Los enemigos la trepan despacio (EnemyMotion.CLIMB_MULT).
const MESA_WALL := 0.6
const RAMP_HALF_W := 2.6               ## media anchura de la rampa (m)
const RAMP_LEN_PER_M := 2.4            ## largo de rampa por metro de altura (~21°)
## Mesetas: [{c: Vector2, r, base, top, parent (índice del piso de abajo o -1), reach,
##            ramps: [{dir: Vector2, len}]}]. Los pisos de un zigurat van después de su base.
var _mesas: Array = []
## Runas lanzadoras: [{pos: Vector3, target: Vector3}] (una por meseta, al pie de la pared, lejos de las rampas)
var _jump_pads: Array = []

## Toboganes de barro: rampas largas y anchas (entradas de "ramps" con "chute": true y su "half") por las que
## el deslizamiento apenas frena (CHUTE_FRICTION, ver slide_friction_at).
const CHUTE_HALF_W := 3.0
const CHUTE_LEN_PER_M := 4.2           ## ~13°: largo para coger velocidad
const CHUTE_CHANCE := 0.6
const CHUTE_FRICTION := 0.12           ## × roce del deslizamiento sobre el barro
const CHUTE_MIN_DROP := 4.0            ## m que baja como mínimo un tobogán (si no, no coge velocidad)
## Puentes de madera entre mesetas de altura parecida: [{a, b: Vector2 (extremos, dentro de cada cima),
## ya, yb (altura de la tabla en cada extremo), half, ma, mb (mesetas)}]. Los enemigos los cruzan
## (EnemyMotion los trata como otra capa de suelo) y por debajo se sigue pasando.
const BRIDGE_HALF_W := 1.4
const BRIDGE_INSET := 2.5              ## m que entra el puente en cada cima
const BRIDGE_MAX_SLOPE := 0.3         ## desnivel máximo de la tabla (m por m, ~17°)
const BRIDGE_GAP := Vector2(5.0, 42.0) ## hueco entre bordes admitido
const BRIDGE_CLEARANCE := 2.5          ## m libres bajo la tabla
var _bridges: Array = []
## Barriles explosivos: [Vector3] donde se colocan (ExplosiveBarrel los hace rodar y estallar).
var _barrels: Array = []
var _mushroom_spots: Array = []       ## [[base Vector3, escala]] de los hongos (rebotan al jugador en supervivencia)
var _bouncer: MushroomBouncer

var _mesh_cache: Dictionary = {}                    # kind -> Mesh
var _mesh_xf: Dictionary = {}                       # kind -> Transform3D
var _instances: Dictionary = {}                     # kind -> Array[Transform3D]
var _collide: Dictionary = {}                       # kind -> bool (crear colisión)
var _hash: Dictionary = {}                          # Vector2i -> Array[[Vector2, float]]
var _lights: Array[OmniLight3D] = []
var _light_base: Array[float] = []
var _flicker_t: float = 0.0
var _light_gust := PackedFloat32Array()             # 0..1 por luz: bajón por una ráfaga (ver gust)
var _gusting := false
## Puntos con vida propia del mapa, para el sonido ambiente y las reacciones (MapAmbience, MapReactions):
## tipo ("fire", "mush", "mush_big") -> PackedVector3Array
var ambient_points: Dictionary = {}
## Brasas (partículas) de los braseros; junto con las luces solo funcionan cerca del jugador.
var _embers: Array[CPUParticles3D] = []
var _cull_timer: float = 0.0
## Distancia (m) a la que se apagan luces y brasas lejanas (más corta en móvil).
const LIGHT_CULL_DIST_PC := 70.0
const LIGHT_CULL_DIST_MOBILE := 45.0
## Filtro opcional (DungeonFog): func(pos: Vector3, dist_sq: float) -> bool. Las luces que no pasan no gastan
## cupo de `visible_lights` (p. ej. antorchas de salas vecinas tapadas por la roca o la niebla).
var light_eligible: Callable
var _mobile: bool = false

func _ready() -> void:
	add_to_group("procedural_map")
	_mobile = Quality.is_mobile() or OS.has_feature("mobile")
	chunk_size = CHUNK_MOBILE if _mobile else CHUNK_PC
	if _mobile:
		cell_size = maxf(cell_size, 2.5)
		prop_density *= 0.55
		visible_lights = mini(visible_lights, 6)
		embers_enabled = false
	generate(map_seed)

# ───────────────────────────── API pública ─────────────────────────────

func generate(p_seed: int = 0) -> void:
	_clear()
	_apply_theme()
	used_seed = p_seed if p_seed != 0 else int(Time.get_unix_time_from_system()) ^ randi()
	_rng.seed = used_seed
	_setup_noise()
	_pick_layout()
	_build_terrain()
	_scatter_props()
	_build_prop_nodes()
	_build_trees()
	_build_jump_pads()
	_build_chutes()
	_build_bridges()
	_build_barrels()
	for d in districts:
		(d as SewerDistrict).build_nodes()
	if GameData.game_mode != "dungeon" and not _mushroom_spots.is_empty():
		_bouncer = MushroomBouncer.new()
		_bouncer.name = "MushroomBouncer"
		_bouncer.spots = _mushroom_spots
		add_child(_bouncer)
	generated.emit(used_seed)

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
		var def: Dictionary = _prop_def(kind)
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
	for sp: Vector2 in _bridge_supports:
		out.append({"pos": sp, "shape": "cyl", "r": 0.35, "half": Vector2.ZERO, "yaw": 0.0})
	for d in districts:
		out.append_array((d as SewerDistrict).colliders())
	return out

## Árboles como dibujos destructibles (TreeField) a partir de los props "tree_a"/"tree_b" ya repartidos.
func _build_trees() -> void:
	if not tree_sprites:
		return
	var list: Array = []
	for kind in TREE_KINDS:
		list.append_array(_instances.get(kind, []))
	if list.is_empty():
		return
	trees = TreeField.new()
	trees.name = "Trees"
	add_child(trees)
	trees.build(list, _mobile)

## ¿Hay agua en p? (canales del Barrio del Desagüe; MapReactions y MapAmbience lo usan para ondas y sonido)
func is_water(p: Vector3) -> bool:
	for d in districts:
		if (d as SewerDistrict).is_water(p):
			return true
	return false

## Tema del mapa generado ("forest" / "sewers").
func get_theme() -> String:
	return _theme

## ¿p está dentro de un barrio de cloacas (con `margin` m de holgura hacia el centro)?
func in_district(p: Vector2, margin: float = 0.0) -> bool:
	for d in districts:
		if (d as SewerDistrict).contains(p, margin):
			return true
	return false

func _in_any_canal(p: Vector2, grow: float) -> bool:
	for d in districts:
		if (d as SewerDistrict).in_canal(p, grow):
			return true
	return false

## Parámetros del tema: los del Bosque se guardan la primera vez (al cambiar de mapa a mitad de partida
## se vuelven a poner).
func _apply_theme() -> void:
	if _base_params.is_empty():
		_base_params = {"hill_amplitude": hill_amplitude, "tree_sprites": tree_sprites}
	_theme = theme if theme != "" else ("forest" if GameData.game_mode == "dungeon" else GameData.survival_map)
	if not THEMES.has(_theme):
		_theme = "forest"
	hill_amplitude = _base_params["hill_amplitude"]
	tree_sprites = _base_params["tree_sprites"]
	if _theme == "sewers":
		hill_amplitude = SEWER_HILLS
		tree_sprites = false

func get_basin_center() -> Vector3:
	return Vector3(_basin_center.x, get_height_at(_basin_center.x, _basin_center.y), _basin_center.y)

## Puentes ([{a, b, ya, yb, half, ma, mb}]), para EnemyMotion y los tests.
func get_bridges() -> Array:
	return _bridges

## Altura de la tabla del puente bajo (x, z), o NAN si no hay puente ahí.
func bridge_height_at(x: float, z: float) -> float:
	for br in _bridges:
		var a: Vector2 = br["a"]
		var ab: Vector2 = (br["b"] as Vector2) - a
		var t := (Vector2(x, z) - a).dot(ab) / ab.length_squared()
		if t < 0.0 or t > 1.0 or absf((Vector2(x, z) - a).cross(ab.normalized())) > float(br["half"]):
			continue
		return lerpf(float(br["ya"]), float(br["yb"]), t)
	return NAN

## Roce del deslizamiento en (x, z): CHUTE_FRICTION sobre el barro de un tobogán, 1 en el resto.
func slide_friction_at(x: float, z: float) -> float:
	return CHUTE_FRICTION if _on_chute(Vector2(x, z)) else 1.0

## ¿(x, z) está en un tobogán? Devuelve su dirección de bajada (Vector2.ZERO si no).
func chute_dir_at(x: float, z: float) -> Vector2:
	var p := Vector2(x, z)
	for m in _mesas:
		var rel: Vector2 = p - (m["c"] as Vector2)
		for rp in m["ramps"]:
			if not rp.get("chute", false):
				continue
			var rd: Vector2 = rp["dir"]
			var u := rel.dot(rd)
			if u > float(m["r"]) - 2.0 and u < float(m["r"]) + float(rp["len"]) + 3.0 and absf(rel.cross(rd)) < float(rp["half"]):
				return rd
	return Vector2.ZERO

func _on_chute(p: Vector2) -> bool:
	return chute_dir_at(p.x, p.y) != Vector2.ZERO

## Posiciones de los barriles explosivos.
func get_barrel_spots() -> Array:
	return _barrels

## Runas lanzadoras colocadas ([{pos, target}]).
func get_jump_pads() -> Array:
	return _jump_pads

## Datos de las mesetas (ver _mesas). Los usa EnemyMotion para llevar a los enemigos por las rampas.
func get_mesas() -> Array:
	return _mesas

## Puntos altos (centro del piso más alto de cada meseta): sitio para santuarios y recompensas.
func get_vantage_points() -> Array:
	var out: Array = []
	for i in _mesas.size():
		var has_upper := false
		for m in _mesas:
			if int(m["parent"]) == i:
				has_upper = true
				break
		if has_upper:
			continue
		var c: Vector2 = _mesas[i]["c"]
		out.append(Vector3(c.x, get_height_at(c.x, c.y), c.y))
	return out

# ───────────────────────────── Terreno ─────────────────────────────

func _clear() -> void:
	for c in get_children():
		c.queue_free()
	# Las mallas de los props no cambian entre niveles: se conservan (cargar y fusionar cada .glb costaba
	# ~30 ms en cada regeneración)
	_instances.clear()
	_collide.clear()
	_jump_pads.clear()
	_bridges.clear()
	_barrels.clear()
	_mushroom_spots.clear()
	_bouncer = null
	district = null
	districts.clear()
	trees = null
	_bridge_supports.clear()
	_hash.clear()
	_lights.clear()
	_light_base.clear()
	_light_gust.clear()
	_gusting = false
	ambient_points.clear()
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
	district = null
	districts.clear()
	if district_enabled and GameData.game_mode != "dungeon":
		if _theme == "sewers":
			# Cloacas: un barrio a cada lado de un eje y la cripta (aquí, el depósito) en la franja de en medio
			var ax := _rng.randi() % 2
			var bs := -1.0 if _rng.randf() < 0.5 else 1.0
			dir = Vector2(0.0, bs) if ax == 0 else Vector2(bs, 0.0)
			_basin_center = dir * basin_distance
			_ramp_end = _basin_center - dir * length
			var salt := 0
			for sg: float in [-1.0, 1.0]:
				var sd := SewerDistrict.new(self)
				sd.depth_start = SEWER_DEPTH_START
				sd.main_canal_u = SEWER_MAIN_U
				sd.pick_axis(used_seed, ax, sg, salt)
				districts.append(sd)
				salt += 7919
		else:
			var sd := SewerDistrict.new(self)
			sd.pick_axis(used_seed)
			districts.append(sd)
		district = districts[0]
	var full := 4.0 * play_half * play_half
	var dist_area := 0.0
	for d in districts:
		dist_area += 2.0 * play_half * (play_half - (d as SewerDistrict).depth_start)
	_area_k = clampf((full - dist_area) / BASE_PLAY_AREA, 1.0, 3.0)
	_pick_mesas()
	_pick_bridges()
	for d in districts:
		(d as SewerDistrict).pick_layout()

func _pick_mesas() -> void:
	_mesas.clear()
	var want := mini(mesa_count, 3) if _mobile else mesa_count
	if _area_k > 1.4:
		want += 1 if _mobile else 2                  # mapa grande: alguna meseta más
	# La pared más suave posible en la malla es altura / (2 celdas): en móvil (celdas de 2,5 m) las
	# mesetas son más altas y sin segundo piso para que la pared siga sin poder subirse andando.
	var heights := Vector2(maxf(mesa_height_range.x, 6.8), maxf(mesa_height_range.y, 8.2)) if _mobile else mesa_height_range
	var zig_done := _mobile
	# Una meseta "pareja" cerca de otra (hueco de PARTNER_GAP m) para que haya puente entre ellas
	var partner_left := 1 if _rng.randf() < 0.85 else 0
	for attempt in range(want * 60):
		if _mesas.size() - (1 if zig_done else 0) >= want:
			break
		var zig := not zig_done and _rng.randf() < 0.5
		# Base del zigurat: cabe la rampa del segundo piso (5,5 + ~8,8 m) sin llegar al borde irregular (±7 %)
		var r := _rng.randf_range(18.5, 20.5) if zig else _rng.randf_range(9.0, 14.0)
		var height := _rng.randf_range(heights.x, heights.y)
		var ramp_len := height * RAMP_LEN_PER_M
		var c := _rand_pos(play_half - r - 8.0)
		var partner := -1
		if partner_left > 0 and not zig:
			for i in _mesas.size():
				if int(_mesas[i]["parent"]) < 0 and float(_mesas[i]["r"]) < 15.0:
					partner = i
			if partner >= 0:
				var pm: Dictionary = _mesas[partner]
				c = (pm["c"] as Vector2) + Vector2.from_angle(_rng.randf() * TAU) * (float(pm["r"]) + r + _rng.randf_range(PARTNER_GAP.x, PARTNER_GAP.y))
				if absf(c.x) > play_half - r - 8.0 or absf(c.y) > play_half - r - 8.0:
					continue
		if c.length() < 30.0 + r:
			continue                                    # la plaza de inicio queda libre
		if in_district(c, r + height * RAMP_LEN_PER_M + 10.0):
			continue                                    # ni en el Barrio del Desagüe
		if c.distance_to(_basin_center) < basin_rim_radius + r + 8.0 or _dist_to_ramp(c) < r + 10.0:
			continue
		var ok := true
		for mi in _mesas.size():
			var m: Dictionary = _mesas[mi]
			if int(m["parent"]) >= 0:
				continue
			var min_d := r + float(m["r"]) + PARTNER_GAP.x if mi == partner else r + float(m["r"]) + maxf(ramp_len, float(m["reach"])) + 6.0
			if c.distance_to(m["c"]) < min_d:
				ok = false
				break
			# Sus rampas no pueden apuntar a la nueva meseta
			for rp in m["ramps"]:
				var to_c: Vector2 = c - (m["c"] as Vector2)
				if absf(wrapf((rp["dir"] as Vector2).angle() - to_c.angle(), -PI, PI)) < atan2(r + 6.0, to_c.length()) + 0.2:
					ok = false
		if not ok:
			continue
		# Rampas: la primera mira más o menos hacia el centro del mapa; a veces otra por detrás
		var ramps: Array = []
		var a0 := atan2(-c.y, -c.x) + _rng.randf_range(-0.9, 0.9)
		var angles := [a0]
		if _rng.randf() < 0.55:
			angles.append(a0 + PI + _rng.randf_range(-0.7, 0.7))
		for a in angles:
			var d := Vector2(cos(a), sin(a))
			var foot: Vector2 = c + d * (r + ramp_len + 2.0)
			if absf(foot.x) > play_half - 5.0 or absf(foot.y) > play_half - 5.0:
				continue
			if foot.distance_to(_basin_center) < basin_rim_radius + 4.0 or _dist_to_ramp(foot) < 6.0:
				continue
			if _ramp_hits_mesa(c, d, r + ramp_len + 3.0):
				continue
			ramps.append({"dir": d, "len": ramp_len})
		if ramps.is_empty():
			continue
		# Tobogán de barro, lejos de las rampas
		var reach := ramp_len + 4.0
		if _rng.randf() < CHUTE_CHANCE:
			var clen := height * CHUTE_LEN_PER_M
			# Cima prevista (como `top` más abajo): el tobogán tiene que bajar al menos CHUTE_MIN_DROP
			var top_est := _terrain(c.x, c.y).x
			for k in 8:
				var ka := TAU * float(k) / 8.0
				top_est = maxf(top_est, _terrain(c.x + cos(ka) * r, c.y + sin(ka) * r).x)
			top_est += height
			for k in 8:
				var ca := _rng.randf() * TAU
				var cd := Vector2.from_angle(ca)
				var clear := true
				for rp in ramps:
					if absf(wrapf(ca - (rp["dir"] as Vector2).angle(), -PI, PI)) < 1.3:
						clear = false
				var cfoot: Vector2 = c + cd * (r + clen + 3.0)
				if not clear or absf(cfoot.x) > play_half - 5.0 or absf(cfoot.y) > play_half - 5.0:
					continue
				if cfoot.distance_to(_basin_center) < basin_rim_radius + 4.0 or _dist_to_ramp(cfoot) < 7.0 or cfoot.length() < 14.0:
					continue
				if top_est - _terrain(cfoot.x, cfoot.y).x < CHUTE_MIN_DROP:
					continue                            # el pie cae en una loma: apenas bajaría
				if _ramp_hits_mesa(c, cd, r + clen + 4.0):
					continue
				ramps.append({"dir": cd, "len": clen, "chute": true, "half": CHUTE_HALF_W,
					"foot_h": _terrain(cfoot.x, cfoot.y).x})
				reach = maxf(reach, clen + 4.0)
				break
		# La cima queda por encima de cualquier loma del borde
		var base := _terrain(c.x, c.y).x
		for k in 8:
			var ka := TAU * float(k) / 8.0
			base = maxf(base, _terrain(c.x + cos(ka) * r, c.y + sin(ka) * r).x)
		var top := base + height
		var idx := _mesas.size()
		_mesas.append({"c": c, "r": r, "base": base, "top": top, "parent": -1, "reach": reach, "ramps": ramps})
		if partner >= 0:
			partner_left -= 1
		if zig:
			zig_done = true
			# Segundo piso: ≥ 4 m para que su pared tampoco se suba; rampa algo más empinada (~27°) para caber
			var th := _rng.randf_range(4.0, 4.4)
			var tr := 5.5
			var tlen := th * 2.0
			var ta := _rng.randf() * TAU
			_mesas.append({"c": c, "r": tr, "base": top, "top": top + th, "parent": idx, "reach": tlen + 4.0,
				"ramps": [{"dir": Vector2(cos(ta), sin(ta)), "len": tlen}]})

const PARTNER_GAP := Vector2(9.0, 18.0)

## ¿Una rampa desde c hacia d de `reach` m pasa por encima de otra meseta?
func _ramp_hits_mesa(c: Vector2, d: Vector2, reach: float) -> bool:
	for m in _mesas:
		var mc: Vector2 = m["c"]
		var t := clampf((mc - c).dot(d), 0.0, reach)
		if (c + d * t).distance_to(mc) < float(m["r"]) + 4.0:
			return true
	return false

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
	var ramp_mask := w * (1.0 - bt)

	# Mesetas y sus rampas (solo suben el terreno)
	for m in _mesas:
		var mc: Vector2 = m["c"]
		var mr: float = m["r"]
		var dm := p.distance_to(mc)
		if dm > mr + float(m["reach"]):
			continue
		# Bajo el extremo de un puente la cima queda lisa (la tabla apoya a ras)
		var at_bridge := _near_bridge(p, 1.5)
		var top: float = float(m["top"]) + (0.0 if at_bridge else _noise_detail.get_noise_2d(x * 1.5, z * 1.5) * 0.15)
		var rel := p - mc
		# Peso de cada rampa aquí (1 en su pasillo, 0 fuera)
		var rws: Array[float] = []
		var near_ramp := 0.0
		for rp in m["ramps"]:
			var rd: Vector2 = rp["dir"]
			var u := rel.dot(rd)
			var lat := absf(rel.cross(rd))
			var hw: float = rp.get("half", RAMP_HALF_W)
			var rw := (1.0 - smoothstep(hw, hw + 1.0, lat)) * smoothstep(mr - 4.0, mr - 3.0, u)
			rws.append(rw)
			near_ramp = maxf(near_ramp, 1.0 - smoothstep(hw + 1.0, hw + 3.0, lat) if u > mr - 4.0 else 0.0)
		if at_bridge:
			near_ramp = 1.0
		# Borde irregular, salvo donde arranca una rampa (el ruido dejaría un escalón entre cima y rampa)
		var de := dm * (1.0 + 0.07 * _noise_detail.get_noise_2d(x * 0.7, z * 0.7) * (1.0 - near_ramp))
		var inside := 1.0 - smoothstep(mr - MESA_WALL, mr + MESA_WALL, de)
		h = maxf(h, lerpf(h, top, inside))
		for k in rws.size():
			var rw: float = rws[k]
			if rw <= 0.0:
				continue
			var rp: Dictionary = m["ramps"][k]
			var u := rel.dot(rp["dir"] as Vector2)
			var rs := clampf((u - (mr - MESA_WALL)) / (float(rp["len"]) + MESA_WALL), 0.0, 1.0)
			if rp.get("chute", false):
				# El tobogán es una bajada lisa: también excava las lomas que cruza (si no, frenarían)
				var foot_h: float = rp.get("foot_h", h)
				h = lerpf(h, lerpf(top, foot_h, rs), rw) if rs < 1.0 else h
			else:
				h = maxf(h, lerpf(h, lerpf(top, h, rs), rw))
			ramp_mask = maxf(ramp_mask, rw * (1.0 - rs * 0.3))

	# Acantilados perimetrales
	var e := maxf(absf(x), absf(z))
	var ct := smoothstep(play_half, play_half + 7.0, e)
	h += ct * (cliff_height + _noise_detail.get_noise_2d(x * 3.0, z * 3.0) * 3.0)

	return Vector4(h, bt, ramp_mask, ct)

## Malla del terreno en C++ (TerrainNative, native/src/terrain_native.cpp): mismo cálculo que _terrain() y los
## bucles de abajo, unas 20 veces más rápido (generar el mapa congelaba la pantalla ~1 s en un móvil).
## Sin la extensión (Web) se usa el GDScript. RUMBANG_NATIVE=0 lo desactiva.
static var native_terrain: bool = OS.get_environment("RUMBANG_NATIVE") != "0"

func _build_terrain() -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	if native_terrain and ClassDB.class_exists(&"TerrainNative"):
		var nat: Object = ClassDB.instantiate(&"TerrainNative")
		var res: Array = nat.build({"half_size": half_size, "cell_size": cell_size, "hill_amplitude": hill_amplitude,
			"basin_depth": basin_depth, "basin_floor_radius": basin_floor_radius, "basin_rim_radius": basin_rim_radius,
			"play_half": play_half, "cliff_height": cliff_height, "basin_center": _basin_center,
			"ramp_end": _ramp_end, "ramp_surface_y": _ramp_surface_y}, _noise_hills, _noise_detail, _mesas, _bridges)
		_side = res[0]
		_heights = res[1]
		arrays[Mesh.ARRAY_VERTEX] = res[2]
		arrays[Mesh.ARRAY_COLOR] = res[3]
		arrays[Mesh.ARRAY_TEX_UV] = res[4]
		arrays[Mesh.ARRAY_NORMAL] = res[5]
		arrays[Mesh.ARRAY_INDEX] = res[6]
	else:
		_build_terrain_arrays(arrays)
	for d in districts:
		(d as SewerDistrict).carve(arrays)
	_finish_terrain(arrays)

## Versión GDScript de la malla (la referencia; TerrainNative la replica).
func _build_terrain_arrays(arrays: Array) -> void:
	_side = int(round(half_size * 2.0 / cell_size)) + 1
	_heights.resize(_side * _side)
	var colors := PackedColorArray()
	colors.resize(_side * _side)
	var verts := PackedVector3Array()
	verts.resize(_side * _side)
	# UV.x = ruido de parches de tierra (el shader ya no calcula ruido por píxel)
	var uvs := PackedVector2Array()
	uvs.resize(_side * _side)

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
			uvs[idx] = Vector2(_noise_detail.get_noise_2d(x * 1.6 + 300.0, z * 1.6 - 120.0) * 0.5 + 0.5, 0.0)

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

	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

## Suelo dibujado POR TROZOS (GROUND_CHUNK_CELLS celdas de lado), no como una malla de todo el mapa:
##  - cada trozo tiene su caja: la cámara descarta los que no ve (con luz por vértice en móvil, antes se
##    iluminaban los ~24k vértices del mapa cada frame);
##  - el renderer Mobile aplica como mucho 8 omnis por malla, elegidas por caja: con una sola malla las 8
##    (de hasta 16 encendidas) valían para todo el suelo y cada píxel las recorría aunque estuvieran lejos, y
##    las demás antorchas no iluminaban el suelo. Por trozo solo cuentan las cercanas.
## Los trozos comparten vértices de borde con las mismas normales (calculadas sobre la rejilla entera): sin
## costuras. La colisión sigue siendo una sola forma.
const GROUND_CHUNK_CELLS := 20
static var _chunk_index_cache: Dictionary = {}     ## Vector2i(ancho, alto) en vértices -> PackedInt32Array

func _finish_terrain(arrays: Array) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = _ground_shader()
	var tex: Dictionary = GROUND_TEX_SEWERS if _theme == "sewers" else GROUND_TEX
	for key in tex:
		mat.set_shader_parameter(key, load(tex[key]))
	if _theme == "sewers":
		# Venas y círculo verdes (agua tóxica) y la calle menos aclarada que el camino de tierra
		mat.set_shader_parameter("vein_color", SEWER_GLOW)
		mat.set_shader_parameter("ring_color", SEWER_GLOW)
		mat.set_shader_parameter("path_tint", Vector3(1.1, 1.1, 1.05))
		mat.set_shader_parameter("rock_m", 4.0)

	var ground := Node3D.new()
	ground.name = "Ground"
	add_child(ground)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var cells := _side - 1
	var j0 := 0
	while j0 < cells:
		var j1 := mini(j0 + GROUND_CHUNK_CELLS, cells)
		var i0 := 0
		while i0 < cells:
			var i1 := mini(i0 + GROUND_CHUNK_CELLS, cells)
			ground.add_child(_ground_chunk(verts, normals, colors, uvs, i0, i1, j0, j1, mat))
			i0 = i1
		j0 = j1

	# Colisión: una forma con la malla entera (no se dibuja)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var body := StaticBody3D.new()
	body.name = "GroundBody"
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	body.add_child(cs)
	add_child(body)

## Shader del suelo: la variante móvil (luz por vértice, sin anisotrópico) en móvil y también en PC con
## calidad Baja; la completa en PC con calidad Media/Alta.
func _ground_shader() -> Shader:
	return GROUND_SHADER_MOBILE if Quality.is_mobile() or Quality.level() == Quality.Level.LOW else GROUND_SHADER

## Un trozo del suelo: celdas [i0, i1) × [j0, j1) de la rejilla, copiadas por filas (slice nativo, sin bucle
## por vértice). Los índices solo dependen del tamaño del trozo y se reutilizan entre trozos y mapas.
func _ground_chunk(verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray,
		uvs: PackedVector2Array, i0: int, i1: int, j0: int, j1: int, mat: Material) -> MeshInstance3D:
	var w := i1 - i0 + 1
	var cv := PackedVector3Array()
	var cn := PackedVector3Array()
	var cc := PackedColorArray()
	var cu := PackedVector2Array()
	for j in range(j0, j1 + 1):
		var a := j * _side + i0
		cv.append_array(verts.slice(a, a + w))
		cn.append_array(normals.slice(a, a + w))
		cc.append_array(colors.slice(a, a + w))
		cu.append_array(uvs.slice(a, a + w))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = cv
	arrays[Mesh.ARRAY_NORMAL] = cn
	arrays[Mesh.ARRAY_COLOR] = cc
	arrays[Mesh.ARRAY_TEX_UV] = cu
	arrays[Mesh.ARRAY_INDEX] = _chunk_indices(w, j1 - j0 + 1)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.name = "Chunk_%d_%d" % [i0 / GROUND_CHUNK_CELLS, j0 / GROUND_CHUNK_CELLS]
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.layers = 1 | GROUND_VISUAL_LAYER     # capa extra: los decals de suelo (auras) solo se proyectan aquí
	return mi

## Índices de una rejilla de w × h vértices, mismo orden de triángulos que la malla entera.
static func _chunk_indices(w: int, h: int) -> PackedInt32Array:
	var key := Vector2i(w, h)
	if _chunk_index_cache.has(key):
		return _chunk_index_cache[key]
	var idx := PackedInt32Array()
	idx.resize((w - 1) * (h - 1) * 6)
	var k := 0
	for j in range(h - 1):
		for i in range(w - 1):
			var a := j * w + i
			var b := a + 1
			var c := a + w
			var d := c + 1
			idx[k] = a; idx[k + 1] = b; idx[k + 2] = c
			idx[k + 3] = b; idx[k + 4] = d; idx[k + 5] = c
			k += 6
	_chunk_index_cache[key] = idx
	return idx

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
	if in_district(p, 2.0):
		return false
	if _near_mesa(p, 3.0) or _near_bridge(p, 2.0):
		return false
	return _slope(p.x, p.y) <= max_slope

## true si p cae bajo un puente (con `margin` m de holgura a los lados).
func _near_bridge(p: Vector2, margin: float) -> bool:
	for br in _bridges:
		var a: Vector2 = br["a"]
		var ab: Vector2 = (br["b"] as Vector2) - a
		var t := (p - a).dot(ab) / ab.length_squared()
		if t > -0.05 and t < 1.05 and absf((p - a).cross(ab.normalized())) < float(br["half"]) + margin:
			return true
	return false

## true si p cae sobre una meseta, su pared o una de sus rampas (con `margin` m de holgura).
func _near_mesa(p: Vector2, margin: float) -> bool:
	for m in _mesas:
		var mc: Vector2 = m["c"]
		var mr: float = m["r"]
		var rel := p - mc
		var dm := rel.length()
		if dm < mr + MESA_WALL + margin:
			return true
		for rp in m["ramps"]:
			var rd: Vector2 = rp["dir"]
			var u := rel.dot(rd)
			if u > mr - 4.0 and u < mr + float(rp["len"]) + 2.0 + margin and absf(rel.cross(rd)) < float(rp.get("half", RAMP_HALF_W)) + 1.0 + margin:
				return true
	return false

func _rand_pos(extent: float) -> Vector2:
	return Vector2(_rng.randf_range(-extent, extent), _rng.randf_range(-extent, extent))

## Forma, tamaño y escala de un tipo de prop (las subclases añaden los suyos).
func _prop_def(kind: String) -> Dictionary:
	return PROPS[kind] if PROPS.has(kind) else DISTRICT_PROPS[kind]

## Props de cloaca del Barrio del Desagüe (los mismos modelos que SewerMap.SEWER_PROPS).
const DISTRICT_PROPS := {
	"trash_bag":    {"file": "sewer_trash_bag",    "shape": "cyl", "size": Vector3(0.42, 0.7, 0.0),  "scale": Vector2(0.8, 1.2)},
	"toxic_barrel": {"file": "sewer_toxic_barrel", "shape": "cyl", "size": Vector3(0.42, 0.95, 0.0), "scale": Vector2(0.95, 1.05)},
	"trash_pile":   {"file": "sewer_trash_pile",   "shape": "cyl", "size": Vector3(1.0, 0.9, 0.0),   "scale": Vector2(0.85, 1.3)},
	"drain":        {"file": "sewer_drain",        "shape": "",    "size": Vector3.ZERO,             "scale": Vector2(1.0, 1.0)},
	"valve":        {"file": "sewer_valve",        "shape": "cyl", "size": Vector3(0.25, 1.3, 0.0),  "scale": Vector2(0.9, 1.1)},
}

func _add(kind: String, pos: Vector2, yaw: float = -1.0, s: float = -1.0, y_offset: float = -0.04, collide: bool = true, tilt: float = 0.0) -> void:
	var def: Dictionary = _prop_def(kind)
	var sc: Vector2 = def["scale"]
	var scale_v := s if s > 0.0 else _rng.randf_range(sc.x, sc.y)
	var yaw_v := yaw if yaw >= 0.0 else _rng.randf() * TAU
	var euler := Vector3(_rng.randf_range(-tilt, tilt), yaw_v, _rng.randf_range(-tilt, tilt))
	var basis := Basis.from_euler(euler).scaled(Vector3.ONE * scale_v)
	var t := Transform3D(basis, Vector3(pos.x, get_height_at(pos.x, pos.y) + y_offset, pos.y))
	if kind == "mushroom":
		_mushroom_spots.append([t.origin, scale_v])
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

func _add_light(pos: Vector3, color: Color, energy: float, light_range: float, attenuation: float = 1.6) -> void:
	if _lights.size() >= max_lights:
		return
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = light_range
	l.omni_attenuation = attenuation
	l.shadow_enabled = false
	l.position = pos
	add_child(l)
	_lights.append(l)
	_light_base.append(energy)
	_light_gust.append(0.0)

func add_ambient_point(kind: String, pos: Vector3) -> void:
	# se lee, se amplía y se vuelve a guardar: el `as` de un array empaquetado devuelve una copia
	var pts: PackedVector3Array = ambient_points.get(kind, PackedVector3Array())
	pts.append(pos)
	ambient_points[kind] = pts

## Ráfaga (un tajo, una esquiva): las luces a menos de `radius` de `pos` tiemblan y bajan un momento.
const GUST_RECOVER := 2.4             ## 1/s: lo rápido que vuelve la luz
func gust(pos: Vector3, radius: float, strength: float = 0.6) -> void:
	var local := to_local(pos)
	var r2 := radius * radius
	for i in _lights.size():
		var l := _lights[i]
		if not is_instance_valid(l) or not l.visible:
			continue
		var d2 := l.position.distance_squared_to(local)
		if d2 < r2:
			_light_gust[i] = maxf(_light_gust[i], strength * (1.0 - sqrt(d2) / radius))
			_gusting = true

func _add_brazier(pos: Vector2) -> void:
	_place("brazier", pos, 0.8)
	var y := get_height_at(pos.x, pos.y)
	_add_light(Vector3(pos.x, y + 1.7, pos.y), Color(0.75, 1.0, 0.4) if _theme == "sewers" else Color(1.0, 0.55, 0.2), 2.6, 11.0)
	add_ambient_point("fire", Vector3(pos.x, y + 1.2, pos.y))
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
	_place_mesa_decor()
	_place_ruins(int(round(3.0 * sqrt(_area_k))))
	if _theme == "sewers":
		_place_junkyards(int(round(4.0 * sqrt(_area_k))))
	else:
		_place_graveyards(int(round(3.0 * sqrt(_area_k))))
		_place_forest()
	_place_misc()
	_place_edge_rocks()
	for d in districts:
		(d as SewerDistrict).decorate()

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
	_add_light(Vector3(c.x, y + 3.2, c.y), SEWER_GLOW if _theme == "sewers" else Color(0.6, 0.3, 1.0), 4.0, 18.0)
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
		if _theme == "sewers":
			_place("trash_bag" if _rng.randf() < 0.6 else "toxic_barrel", pos, 0.9, -1.0, -1.0, false, 0.06)
		else:
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

## ¿p está en el pasillo de alguna rampa de la meseta m (con `extra` m de holgura a los lados)?
func _on_ramp_of(m: Dictionary, p: Vector2, extra: float) -> bool:
	var rel: Vector2 = p - (m["c"] as Vector2)
	for rp in m["ramps"]:
		var rd: Vector2 = rp["dir"]
		if rel.dot(rd) > 0.0 and absf(rel.cross(rd)) < float(rp.get("half", RAMP_HALF_W)) + extra:
			return true
	return false

## Cima de las mesetas: brasero (punto de referencia con luz), pilares rotos en el borde, alguna roca, y
## hongos luminosos al pie de la pared. El centro del piso más alto queda libre para el santuario.
func _place_mesa_decor() -> void:
	_pick_jump_pads()
	# Extremos de los puentes libres de pilares y rocas
	for br in _bridges:
		var a: Vector2 = br["a"]
		var b: Vector2 = br["b"]
		for k in 9:
			_reserve(a.lerp(b, float(k) / 8.0), float(br["half"]) + 0.8)
	_pick_barrels()
	for i in _mesas.size():
		var m: Dictionary = _mesas[i]
		var c: Vector2 = m["c"]
		var r: float = m["r"]
		var upper := -1
		for j in _mesas.size():
			if int(_mesas[j]["parent"]) == i:
				upper = j
		var first_dir: Vector2 = (m["ramps"][0] as Dictionary)["dir"]
		if upper < 0:
			_add_brazier(c - first_dir * minf(3.6, r - 1.8))
		var hole := float(_mesas[upper]["r"]) + MESA_WALL + 1.0 if upper >= 0 else 5.0
		if int(m["parent"]) < 0:
			var n := 5 + int(r / 6.0)
			for k in n:
				if _rng.randf() < 0.4:
					continue
				var a := TAU * float(k) / float(n) + _rng.randf_range(-0.25, 0.25)
				var pos := c + Vector2(cos(a), sin(a)) * (r - 1.9)
				if not _on_ramp_of(m, pos, 1.6) and not _occupied(pos, 1.4):
					_place("pillar", pos, 1.4, -1.0, _rng.randf_range(0.7, 1.0))
			for k in 6:
				var a := _rng.randf() * TAU
				var pos := c + Vector2(cos(a), sin(a)) * (r + MESA_WALL + _rng.randf_range(1.0, 2.5))
				if not _on_ramp_of(m, pos, 1.0) and not _occupied(pos, 0.8):
					_place("mushroom", pos, 0.8, -1.0, -1.0, false)
		for k in 2:
			var a := _rng.randf() * TAU
			var pos := c + Vector2(cos(a), sin(a)) * _rng.randf_range(hole, maxf(hole, r - 3.0))
			if Vector2(pos - c).length() < r - 2.5 and not _on_ramp_of(m, pos, 1.2) and not _occupied(pos, 1.5):
				_place("rock_a", pos, 1.3, -1.0, _rng.randf_range(0.6, 0.9))

## Una runa por meseta, al pie de la pared y lo más lejos posible de sus rampas (atajo). En un piso de
## zigurat, sobre el piso de abajo. El destino queda dentro de la cima, lejos del borde.
func _pick_jump_pads() -> void:
	_jump_pads.clear()
	for i in _mesas.size():
		var m: Dictionary = _mesas[i]
		var c: Vector2 = m["c"]
		var r: float = m["r"]
		var parent := int(m["parent"])
		var base_a := ((m["ramps"][0] as Dictionary)["dir"] as Vector2).angle() + PI
		for off in [0.0, 0.6, -0.6, 1.2, -1.2, PI * 0.5, -PI * 0.5]:
			var d := Vector2.from_angle(base_a + off)
			var pos := c + d * (r + MESA_WALL + 2.4)
			if _on_ramp_of(m, pos, 2.5) or _near_bridge(pos, 3.0):
				continue
			if parent >= 0:
				var pm: Dictionary = _mesas[parent]
				if pos.distance_to(pm["c"]) > float(pm["r"]) - 2.0 or _on_ramp_of(pm, pos, 2.0):
					continue
			elif absf(pos.x) > play_half - 4.0 or absf(pos.y) > play_half - 4.0 					or pos.distance_to(_basin_center) < basin_rim_radius + 2.0 or _dist_to_ramp(pos) < 5.0:
				continue
			var y := get_height_at(pos.x, pos.y)
			if y > float(m["top"]) - 3.0 or _slope(pos.x, pos.y) > 0.35:
				continue
			var tgt := c + d * maxf(r - 3.5, r * 0.45)
			_reserve(pos, 2.0)
			_reserve(tgt, 2.6)                   # llegada libre: sin pilares ni rocas donde cae
			_jump_pads.append({"pos": Vector3(pos.x, y, pos.y), "target": Vector3(tgt.x, get_height_at(tgt.x, tgt.y), tgt.y)})
			break

func _build_jump_pads() -> void:
	for jp in _jump_pads:
		var pad := JumpPad.new()
		pad.name = "JumpPad"
		pad.target = jp["target"]
		pad.position = jp["pos"]
		add_child(pad)

## ── Puentes ──
## Une mesetas (sin pisos de zigurat) de altura parecida con el hueco entre bordes en BRIDGE_GAP, si bajo la
## tabla queda BRIDGE_CLEARANCE m libres. Pocos (2, 1 en móvil), los más cortos.
func _pick_bridges() -> void:
	_bridges.clear()
	var cands: Array = []
	for i in _mesas.size():
		for j in range(i + 1, _mesas.size()):
			var mi: Dictionary = _mesas[i]
			var mj: Dictionary = _mesas[j]
			if int(mi["parent"]) >= 0 or int(mj["parent"]) >= 0:
				continue
			var ci: Vector2 = mi["c"]
			var cj: Vector2 = mj["c"]
			var gap := ci.distance_to(cj) - float(mi["r"]) - float(mj["r"])
			var span := gap + 2.0 * BRIDGE_INSET
			if gap < BRIDGE_GAP.x or gap > BRIDGE_GAP.y or absf(float(mi["top"]) - float(mj["top"])) > span * BRIDGE_MAX_SLOPE:
				continue
			cands.append([gap, i, j])
	cands.sort_custom(func(x, y): return x[0] < y[0])
	var want := 1 if _mobile else 2
	var used := {}
	for cand in cands:
		if _bridges.size() >= want:
			break
		var i: int = cand[1]
		var j: int = cand[2]
		if used.has(i) and used.has(j):
			continue
		var mi: Dictionary = _mesas[i]
		var mj: Dictionary = _mesas[j]
		var ci: Vector2 = mi["c"]
		var cj: Vector2 = mj["c"]
		var d := (cj - ci).normalized()
		var a := ci + d * (float(mi["r"]) - BRIDGE_INSET)
		var b := cj - d * (float(mj["r"]) - BRIDGE_INSET)
		var ya: float = mi["top"]
		var yb: float = mj["top"]
		# Sin cruzar rampas de sus mesetas (su borde está a ras de la cima) ni chocar con nada por debajo
		var ok := true
		for m in [mi, mj]:
			for rp in m["ramps"]:
				if absf(wrapf((rp["dir"] as Vector2).angle() - (d if m == mi else -d).angle(), -PI, PI)) < 0.45:
					ok = false
		var n := int(a.distance_to(b))
		for k in range(1, n):
			var q := a.lerp(b, float(k) / float(n))
			if q.distance_to(ci) < float(mi["r"]) + 1.5 or q.distance_to(cj) < float(mj["r"]) + 1.5:
				continue
			var deck := lerpf(ya, yb, float(k) / float(n))
			if _terrain(q.x, q.y).x > deck - BRIDGE_CLEARANCE:
				ok = false
				break
		for br in _bridges:
			if Geometry2D.segment_intersects_segment(a, b, br["a"], br["b"]) != null:
				ok = false
		if not ok:
			continue
		used[i] = true
		used[j] = true
		_bridges.append({"a": a, "b": b, "ya": ya, "yb": yb, "half": BRIDGE_HALF_W, "ma": i, "mb": j})

const BRIDGE_WOOD := Color(0.38, 0.25, 0.14)
const BRIDGE_WOOD_DARK := Color(0.22, 0.14, 0.08)
const BRIDGE_ROPE := Color(0.45, 0.38, 0.25)
const BRIDGE_SUPPORT_STEP := 8.0

## Tablas, largueros, postes, barandillas y pilotes hasta el suelo; colisión de tabla, barandillas y pilotes.
func _build_bridges() -> void:
	for bi in _bridges.size():
		var br: Dictionary = _bridges[bi]
		var a := Vector3((br["a"] as Vector2).x, float(br["ya"]), (br["a"] as Vector2).y)
		var b := Vector3((br["b"] as Vector2).x, float(br["yb"]), (br["b"] as Vector2).y)
		var half: float = br["half"]
		var length := a.distance_to(b)
		var fwd := (b - a).normalized()
		var basis := Basis.looking_at(fwd, Vector3.UP)          # -Z a lo largo del puente, X a lo ancho
		var side := basis.x
		var root := Node3D.new()
		root.name = "Bridge%d" % bi
		add_child(root)
		var wood := StandardMaterial3D.new()
		wood.vertex_color_use_as_albedo = true
		wood.albedo_color = Color.WHITE
		wood.roughness = 0.92
		# Tablas (con su pequeño desorden)
		var plank := BoxMesh.new()
		plank.size = Vector3(half * 2.0, 0.1, 0.32)
		plank.material = wood
		var count := int(length / 0.38)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = plank
		mm.instance_count = count
		for k in count:
			var t := (float(k) + 0.5) / float(count)
			var pos := a.lerp(b, t) + Vector3(0, -0.05 + _rng.randf_range(-0.012, 0.012), 0)
			var pb := basis.rotated(basis.y, _rng.randf_range(-0.04, 0.04))
			mm.set_instance_transform(k, Transform3D(pb, pos))
			mm.set_instance_color(k, BRIDGE_WOOD.darkened(_rng.randf_range(0.0, 0.25)))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		root.add_child(mmi)
		# Largueros bajo las tablas y barandillas
		for sx: float in [-1.0, 1.0]:
			_bridge_beam(root, a + side * sx * (half - 0.3) + Vector3(0, -0.22, 0), b + side * sx * (half - 0.3) + Vector3(0, -0.22, 0), Vector2(0.2, 0.24), BRIDGE_WOOD_DARK)
			for hgt: float in [0.55, 1.0]:
				_bridge_beam(root, a + side * sx * half + Vector3(0, hgt, 0), b + side * sx * half + Vector3(0, hgt, 0), Vector2(0.07, 0.07), BRIDGE_ROPE)
		# Postes cada ~3 m y pilotes hasta el suelo cada BRIDGE_SUPPORT_STEP m (solo sobre el hueco)
		var posts := int(length / 3.0)
		for k in range(posts + 1):
			var q := a.lerp(b, float(k) / float(posts))
			for sx: float in [-1.0, 1.0]:
				var base := q + side * sx * half
				_bridge_beam(root, base + Vector3(0, -0.1, 0), base + Vector3(0, 1.1, 0), Vector2(0.14, 0.14), BRIDGE_WOOD_DARK)
		var sup: Array = []
		var supports := int(length / BRIDGE_SUPPORT_STEP)
		for k in range(1, supports + 1):
			var q := a.lerp(b, float(k) / float(supports + 1))
			var ground := get_height_at(q.x, q.z)
			if q.y - ground < 1.5:
				continue
			for sx: float in [-1.0, 1.0]:
				var top := q + side * sx * (half - 0.3) + Vector3(0, -0.3, 0)
				_bridge_beam(root, Vector3(top.x, ground - 0.3, top.z), top, Vector2(0.3, 0.3), BRIDGE_WOOD_DARK)
				sup.append(Vector3(top.x, ground, top.z))
				_bridge_supports.append(Vector2(top.x, top.z))
		# Colisión: tabla, barandillas (no se cae uno sin querer) y pilotes
		var body := StaticBody3D.new()
		body.name = "BridgeBody%d" % bi
		body.collision_layer = 1
		body.collision_mask = 0
		root.add_child(body)
		var deck := BoxShape3D.new()
		deck.size = Vector3(half * 2.0 + 0.2, 0.3, length + 0.4)
		var dcs := CollisionShape3D.new()
		dcs.shape = deck
		dcs.transform = Transform3D(basis, (a + b) * 0.5 - basis.y * 0.15)
		body.add_child(dcs)
		for sx: float in [-1.0, 1.0]:
			var rail := BoxShape3D.new()
			rail.size = Vector3(0.15, 1.1, length)
			var rcs := CollisionShape3D.new()
			rcs.shape = rail
			rcs.transform = Transform3D(basis, (a + b) * 0.5 + side * sx * (half + 0.05) + basis.y * 0.55)
			body.add_child(rcs)
		for sp: Vector3 in sup:
			var cyl := CylinderShape3D.new()
			cyl.radius = 0.25
			var scs := CollisionShape3D.new()
			scs.shape = cyl
			cyl.height = maxf(bridge_y_at(br, Vector2(sp.x, sp.z)) - sp.y - 0.4, 0.5)
			scs.position = sp + Vector3(0, cyl.height * 0.5, 0)
			body.add_child(scs)

var _bridge_supports: Array = []       ## pilotes (x, z) para la colisión de los enemigos

## Altura de la tabla del puente `br` a la altura de p (proyectada sobre su eje).
static func bridge_y_at(br: Dictionary, p: Vector2) -> float:
	var a: Vector2 = br["a"]
	var ab: Vector2 = (br["b"] as Vector2) - a
	return lerpf(float(br["ya"]), float(br["yb"]), clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0))

## Viga de sección `sec` entre p0 y p1.
func _bridge_beam(parent: Node3D, p0: Vector3, p1: Vector3, sec: Vector2, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var seg_len := p0.distance_to(p1)
	bm.size = Vector3(sec.x, sec.y, seg_len)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.95
	bm.material = mat
	mi.mesh = bm
	var dir := (p1 - p0) / maxf(seg_len, 0.001)
	var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.FORWARD
	mi.transform = Transform3D(Basis.looking_at(dir, up), (p0 + p1) * 0.5)
	parent.add_child(mi)

## ── Toboganes ──
## Barro mojado encima del suelo de cada tobogán (brillante, para que se lea como "aquí se resbala").
func _build_chutes() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.13, 0.08)
	mat.roughness = 0.12
	mat.metallic_specular = 0.7
	var noise := FastNoiseLite.new()
	noise.frequency = 0.08
	var tex := NoiseTexture2D.new()
	tex.noise = noise
	tex.seamless = true
	tex.width = 128
	tex.height = 128
	tex.as_normal_map = true
	tex.bump_strength = 6.0
	mat.normal_enabled = true
	mat.normal_texture = tex
	mat.uv1_scale = Vector3(0.35, 0.35, 0.35)
	mat.uv1_triplanar = true
	for m in _mesas:
		var c: Vector2 = m["c"]
		var r: float = m["r"]
		for rp in m["ramps"]:
			if not rp.get("chute", false):
				continue
			var d: Vector2 = rp["dir"]
			var sd := Vector2(-d.y, d.x)
			var hw: float = float(rp["half"]) - 0.3
			var u0 := r - 2.0
			var u1 := r + float(rp["len"]) + 1.5
			var rows := int(u1 - u0) + 1
			var cols := 5
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var verts: Array = []
			for ri in rows:
				var u := lerpf(u0, u1, float(ri) / float(rows - 1))
				var row: Array = []
				for ci in cols:
					var l := lerpf(-hw, hw, float(ci) / float(cols - 1))
					var q := c + d * u + sd * l
					row.append(Vector3(q.x, get_height_at(q.x, q.y) + 0.05, q.y))
				verts.append(row)
			for ri in rows - 1:
				for ci in cols - 1:
					var v00: Vector3 = verts[ri][ci]
					var v01: Vector3 = verts[ri][ci + 1]
					var v10: Vector3 = verts[ri + 1][ci]
					var v11: Vector3 = verts[ri + 1][ci + 1]
					# Que la cara mire hacia arriba (el orden depende de hacia dónde baja el tobogán)
					var up_first: bool = (v10 - v00).cross(v01 - v00).y > 0.0
					for v in ([v00, v10, v01, v01, v10, v11] if up_first else [v00, v01, v10, v01, v11, v10]):
						st.add_vertex(v)
			st.generate_normals()
			var mesh := st.commit()
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.name = "Chute"
			add_child(mi)

## ── Barriles explosivos ──
## En el borde de cada cima (2) y arriba de cada tobogán, y algunos sueltos en laderas.
func _pick_barrels() -> void:
	_barrels.clear()
	for m in _mesas:
		if int(m["parent"]) >= 0:
			continue
		var c: Vector2 = m["c"]
		var r: float = m["r"]
		var placed := 0
		for k in 12:
			if placed >= 2:
				break
			var a := _rng.randf() * TAU
			var q := c + Vector2.from_angle(a) * (r - 2.6)
			if _on_ramp_of(m, q, 1.5) or _near_bridge(q, 1.5) or _occupied(q, 1.2):
				continue
			_reserve(q, 1.0)
			_barrels.append(Vector3(q.x, get_height_at(q.x, q.y), q.y))
			placed += 1
		for rp in m["ramps"]:
			if rp.get("chute", false):
				var q: Vector2 = c + (rp["dir"] as Vector2) * (r - 1.5) + Vector2(-(rp["dir"] as Vector2).y, (rp["dir"] as Vector2).x) * 1.2
				if not _occupied(q, 1.0):
					_reserve(q, 1.0)
					_barrels.append(Vector3(q.x, get_height_at(q.x, q.y), q.y))
	var loose := 3 if _mobile else 6
	for attempt in 200:
		if loose <= 0:
			break
		var q := _rand_pos(play_half - 8.0)
		if q.length() < 20.0 or _near_mesa(q, 2.0) or _near_bridge(q, 2.0) or _occupied(q, 1.5) or in_district(q, 2.0):
			continue
		var sl := _slope(q.x, q.y)
		if sl < 0.12 or sl > 0.5:
			continue
		_reserve(q, 1.0)
		_barrels.append(Vector3(q.x, get_height_at(q.x, q.y), q.y))
		loose -= 1

func _build_barrels() -> void:
	for pos in _barrels:
		var b := ExplosiveBarrel.new()
		b.name = "ExplosiveBarrel"
		b.position = pos
		b.barrel_mesh = _load_kind("barrel")
		b.barrel_mesh_xf = _mesh_xf.get("barrel", Transform3D.IDENTITY)
		add_child(b)

func _find_site(radius: float, min_origin: float) -> Vector2:
	for attempt in range(120):
		var p := _rand_pos(play_half - radius - 6.0)
		if p.length() < min_origin:
			continue
		if p.distance_to(_basin_center) < basin_rim_radius + radius + 4.0:
			continue
		if _dist_to_ramp(p) < radius + 8.0:
			continue
		if _near_mesa(p, radius + 2.0) or _near_bridge(p, radius + 2.0):
			continue
		if in_district(p, radius + 2.0):
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

## Cloacas: vertederos (en lugar de cementerios): montones de basura, bidones tóxicos y cajas rodeados de
## restos de valla, con una válvula y un desagüe con luz verdosa.
func _place_junkyards(count: int) -> void:
	for n in range(count):
		var c := _find_site(11.0, 26.0)
		if c.x == INF:
			continue
		_reserve(c, 9.0)
		for k in range(_rng.randi_range(3, 5)):
			var pos := c + Vector2(_rng.randf_range(-6.5, 6.5), _rng.randf_range(-6.5, 6.5))
			if _occupied(pos, 1.4):
				continue
			_place("trash_pile", pos, 1.4)
			for b in _rng.randi_range(1, 3):
				var q := pos + Vector2(_rng.randf_range(-2.0, 2.0), _rng.randf_range(-2.0, 2.0))
				if not _occupied(q, 0.6):
					_place("trash_bag", q, 0.6, -1.0, -1.0, false)
		for k in range(_rng.randi_range(3, 6)):
			var pos := c + Vector2(_rng.randf_range(-7.0, 7.0), _rng.randf_range(-7.0, 7.0))
			if not _occupied(pos, 0.9):
				_place("toxic_barrel" if _rng.randf() < 0.6 else "crate", pos, 0.9)
		for k in range(9):
			var a := float(k) * TAU / 9.0 + _rng.randf_range(-0.1, 0.1)
			if _rng.randf() < 0.4:
				continue
			_place("fence", c + Vector2(cos(a), sin(a)) * 10.5, 1.3, a + PI * 0.5)
		var vp := c + Vector2(_rng.randf_range(-3.0, 3.0), _rng.randf_range(-3.0, 3.0))
		if not _occupied(vp, 1.0):
			_place("valve", vp, 1.0)
		var y := get_height_at(c.x, c.y)
		_add_light(Vector3(c.x, y + 2.2, c.y), SEWER_GLOW, 2.0, 12.0)
		add_ambient_point("drip", Vector3(c.x, y + 1.0, c.y))

func _place_forest() -> void:
	var target := int(150.0 * prop_density * _area_k)
	var placed := 0
	for attempt in range(target * 40):
		if placed >= target:
			break
		var p := _rand_pos(play_half - 3.0)
		if p.length() < 17.0:
			continue
		# Primero el ruido del bosque (barato), después la superficie (mesetas, puentes, pendiente)
		var f := _noise_forest.get_noise_2d(p.x, p.y)
		if f < -0.1 or _rng.randf() > (f + 0.1) * 2.2 + 0.08:
			continue
		if not _is_surface(p, 0.6):
			continue
		if _occupied(p, 1.7):
			continue
		_place("tree_a" if _rng.randf() < 0.5 else "tree_b", p, 1.7, -1.0, -1.0, true, 0.05)
		placed += 1

func _place_misc() -> void:
	var rocks := int(44.0 * prop_density * _area_k)
	for i in range(rocks * 8):
		if rocks <= 0:
			break
		var p := _rand_pos(play_half - 4.0)
		if p.length() < 14.0 or not _is_surface(p, 0.7) or _occupied(p, 1.8):
			continue
		_place("rock_a" if _rng.randf() < 0.65 else "rock_b", p, 1.8)
		rocks -= 1
	var shrooms := int(26.0 * prop_density * _area_k)
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
	var loose := int(22.0 * prop_density * _area_k)
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
	var bones := int(14.0 * prop_density * _area_k)
	for i in range(bones * 10):
		if bones <= 0:
			break
		var p := _rand_pos(play_half - 4.0)
		if p.length() < 12.0 or not _is_surface(p, 0.5) or _occupied(p, 0.9):
			continue
		_place("bones", p, 0.8, -1.0, -1.0, false)
		bones -= 1
	# Algún brasero suelto con luz como punto de referencia
	for i in range(int(round(3.0 * _area_k))):
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
			if _in_any_canal(p, 2.5):
				continue                                # boca de un canal en el acantilado
			_add("rock_b", p, -1.0, _rng.randf_range(1.0, 1.8), -0.3, false)

# ───────────────────────────── Nodos de props ─────────────────────────────

func _load_kind(kind: String) -> Mesh:
	if _mesh_cache.has(kind):
		return _mesh_cache[kind]
	var path: String = PROP_DIR + String(_prop_def(kind)["file"]) + ".glb"
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
		var toon := _toon_material(String(_prop_def(kind)["file"]), kind)
		mesh = flatten_with(found.mesh, toon) if toon else _flatten_mesh(found.mesh)
		var n: Node = found
		while n and n != root:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
	root.free()
	_mesh_cache[kind] = mesh
	_mesh_xf[kind] = xf
	return mesh

var _prop_material: ShaderMaterial = null
static var _toon_materials: Dictionary = {}         # "archivo" o "archivo|sin_llama" -> ShaderMaterial (o null)

## Material cartoon del prop si tiene textura horneada (res://assets/textures/toon/props/<archivo>.png);
## null si no (se queda con prop_flat o prop_detail). Uno por tipo de prop: cada tipo ya es su propia llamada
## de dibujo. hide_emissive: no dibuja las partes emisivas (la llama del modelo, que pone fire_flame).
## Lo usa también DestructibleProp para las piezas de un prop roto (<archivo>_pieces).
static func toon_prop_material(file: String, hide_emissive: bool = false) -> ShaderMaterial:
	var key := file + ("|sin_llama" if hide_emissive else "")
	if _toon_materials.has(key):
		return _toon_materials[key]
	var mat: ShaderMaterial = null
	var path := PROP_TOON_DIR + file + ".png"
	if ResourceLoader.exists(path):
		mat = ShaderMaterial.new()
		mat.shader = PROP_TOON_SHADER
		mat.set_shader_parameter("toon_tex", load(path))
		mat.set_shader_parameter("hide_emissive", hide_emissive)
	_toon_materials[key] = mat
	return mat

## ¿Es `mat` un material cartoon horneado?
static func is_toon_material(mat: Material) -> bool:
	return mat is ShaderMaterial and (mat as ShaderMaterial).shader == PROP_TOON_SHADER

func _toon_material(file: String, kind: String) -> ShaderMaterial:
	return toon_prop_material(file, _toon_hides_flame(kind)) if use_toon_props else null

## Props cuya llama del modelo no se dibuja (en las mazmorras la pone fire_flame).
func _toon_hides_flame(_kind: String) -> bool:
	return false

## Fusiona todas las superficies de la malla en una sola: el color de cada material pasa al color de vértice
## (RGB = albedo en lineal, A = 1 si el material emite luz) y se usa el material único prop_flat.
## Pierde el brillo metálico de los aros de hierro, a cambio de 2–3 veces menos llamadas de dibujo.
func _flatten_mesh(src: Mesh) -> Mesh:
	if src == null:
		return src
	if _prop_material == null:
		_prop_material = ShaderMaterial.new()
		_prop_material.shader = PROP_SHADER
	return flatten_with(src, _prop_material)

## Clase de detalle de prop_detail según el nombre del material (pm_straw, g_hide...): 0 = la textura
## del prop (madera o piedra), 1 piedra (también hueso y barro), 2 paja, 3 piel o cuerda, 4 corteza.
static func detail_class(mat_name: String) -> int:
	var n := mat_name.to_lower()
	if "straw" in n or "thatch" in n:
		return 2
	if "hide" in n or "rope" in n or "leather" in n:
		return 3
	if "bark" in n:
		return 4
	if "stone" in n or "rock" in n or "bone" in n or "mud" in n:
		return 1
	return 0

## Igual que _flatten_mesh pero con el material que se pida (lo usa también DestructibleProp para
## las piezas sueltas de los props rotos). Si la malla trae color de vértice (oclusión horneada en
## Blender), multiplica al del material. La clase de detalle de cada material va en UV2.x.
static func flatten_with(src: Mesh, material: Material) -> Mesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var cls := PackedVector2Array()
	var uvs := PackedVector2Array()
	var has_uv := true
	var idx := PackedInt32Array()
	for s in range(src.get_surface_count()):
		var arr := src.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var n = arr[Mesh.ARRAY_NORMAL]
		var vc = arr[Mesh.ARRAY_COLOR]
		var ix = arr[Mesh.ARRAY_INDEX]
		var uv = arr[Mesh.ARRAY_TEX_UV]
		if uv != null and (uv as PackedVector2Array).size() == v.size():
			uvs.append_array(uv)
		else:
			has_uv = false
		var base := verts.size()
		var color := Color(0.5, 0.5, 0.5, 0.0)
		var emissive := false
		var m := src.surface_get_material(s)
		if m is BaseMaterial3D:
			color = (m as BaseMaterial3D).albedo_color
			emissive = (m as BaseMaterial3D).emission_enabled
		var lin := color.srgb_to_linear()
		lin.a = 1.0 if emissive else 0.0
		var c2 := Vector2(float(detail_class(m.resource_name if m else "")), 0.0)
		verts.append_array(v)
		if n != null:
			norms.append_array(n)
		else:
			norms.resize(verts.size())
		var ao: bool = vc != null and (vc as PackedColorArray).size() == v.size() and not emissive
		for i in range(v.size()):
			if ao:
				var vk: Color = vc[i]
				cols.append(Color(lin.r * vk.r, lin.g * vk.g, lin.b * vk.b, lin.a))
			else:
				cols.append(lin)
			cls.append(c2)
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
	out[Mesh.ARRAY_TEX_UV2] = cls
	if has_uv and uvs.size() == verts.size():
		out[Mesh.ARRAY_TEX_UV] = uvs      # textura horneada (prop_toon); los demás shaders no la leen
	out[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	mesh.surface_set_material(0, material)
	return mesh

func _find_mesh_instance(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var r := _find_mesh_instance(c)
		if r:
			return r
	return null

## Lado de los trozos en que se agrupan las instancias de un tipo de prop.
func _prop_chunk_size(_kind: String) -> float:
	return chunk_size

func _build_prop_nodes() -> void:
	var container := Node3D.new()
	container.name = "Props"
	add_child(container)
	var body := StaticBody3D.new()
	body.name = "PropColliders"
	body.collision_layer = 1
	body.collision_mask = 0

	for kind in _instances:
		if kind in TREE_KINDS and tree_sprites:
			continue                                    # los dibuja TreeField
		var mesh := _load_kind(kind)
		if mesh == null:
			continue
		var xf: Transform3D = _mesh_xf[kind]
		# Agrupar por chunk para que el culling de cámara funcione
		var cs := _prop_chunk_size(kind)
		var chunks: Dictionary = {}
		for t in (_instances[kind] as Array):
			var key := Vector2i(int(floor((t.origin.x + half_size) / cs)), int(floor((t.origin.z + half_size) / cs)))
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
		if kind in TREE_KINDS and tree_sprites:
			continue                                    # cada árbol lleva su cuerpo (TreeTrunk)
		var def: Dictionary = _prop_def(kind)
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
	# El cuerpo entra al árbol con todas sus formas ya puestas (añadirlas una a una con el cuerpo ya en el
	# espacio de física rehacía el cuerpo en cada una)
	add_child(body)

func _process(delta: float) -> void:
	for d in districts:
		(d as SewerDistrict).tick(delta)
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
		if _gusting and _light_gust[i] > 0.0:
			# ráfaga: la llama casi se apaga y parpadea rápido mientras se recupera
			var g := _light_gust[i]
			f *= 1.0 - g * (0.55 + 0.35 * sin(_flicker_t * 47.0 + float(i) * 2.3))
			_light_gust[i] = maxf(g - GUST_RECOVER * delta, 0.0)
		l.light_energy = _light_base[i] * f * light_scale

## Recalcula ya qué luces van encendidas (p. ej. al cambiar de sala, sin esperar al siguiente tick).
func refresh_lights() -> void:
	_cull_timer = 0.4
	_cull_lights_and_embers()

## Apaga luces y brasas lejos del jugador (cada 0,4 s): cada luz dinámica y cada sistema de partículas
## cuesta en cada frame aunque estén fuera de vista.
func _cull_lights_and_embers() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var limit: float = LIGHT_CULL_DIST_MOBILE if _mobile else LIGHT_CULL_DIST_PC
	var limit_sq := limit * limit
	var pp := player.global_position
	var lights_on := Quality.lights_enabled() or lights_essential
	# Encendidas: las `visible_lights` más cercanas dentro de la distancia de corte
	var close: Array = []
	for l in _lights:
		if is_instance_valid(l):
			var d2 := l.global_position.distance_squared_to(pp)
			if lights_on and d2 <= limit_sq and (not light_eligible.is_valid() or light_eligible.call(l.global_position, d2)):
				close.append([d2, l])
	if close.size() > visible_lights:
		close.sort_custom(func(a, b): return a[0] < b[0])
		close.resize(visible_lights)
	var on := {}
	for e in close:
		on[e[1]] = true
	for l in _lights:
		if is_instance_valid(l):
			l.visible = on.has(l)
	for p in _embers:
		if is_instance_valid(p):
			var near := p.global_position.distance_squared_to(pp) <= limit_sq
			if near != p.emitting:
				p.emitting = near
