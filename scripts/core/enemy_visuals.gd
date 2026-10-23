class_name EnemyVisuals
extends Node3D

## Dibuja a TODOS los enemigos normales (EnemyData) con MultiMesh: una llamada de dibujo por modelo y por
## nivel de detalle, con la animación leída de texturas horneadas (VAT, ver assets/shaders/enemy_vat.gdshader
## y tools/bake_enemy_vat.gd).
##
## LOD por cubos de distancia: cada modelo tiene 3 MultiMesh (malla completa / ~45 % / ~20 % de triángulos,
## cada uno con sus propias texturas VAT). Cada frame el enemigo se escribe en el cubo que le toca según su
## distancia al jugador. Solo el cubo cercano proyecta sombra (calidad Alta en PC).

const VAT_DIR := "res://assets/vat/"
const SHADER: Shader = preload("res://assets/shaders/enemy_vat.gdshader")
const IMPOSTOR_SHADER: Shader = preload("res://assets/shaders/enemy_impostor.gdshader")
const CAPACITY := 512                 ## instancias máximas por cubo (32 KB por cubo: coste de memoria despreciable)
const STRIDE := 16                    ## 12 floats de transformación + 4 de datos por instancia
const MAX_DRAW_DIST := 80.0

## Orden fijo de los modelos: EnemyData.vat_idx apunta a esta lista.
const KEYS: Array[String] = ["magoblin", "normal", "bruto", "zombie"]
const LOD_COUNT := 3
const LOD_SUFFIX: Array[String] = ["", "_lod1", "_lod2"]
## Distancias (m) a partir de las cuales se pasa al LOD 1 y al LOD 2 (más cortas en móvil).
const LOD_DIST_PC: Array[float] = [16.0, 34.0]
const LOD_DIST_MOBILE: Array[float] = [12.0, 26.0]

## Tipo de enemigo (EnemyData.EnemyType) -> [clave de modelo, textura]
const TYPE_TABLE := {
	0: ["magoblin", "res://assets/textures/enemigos/textura_mago_goblin.png"],
	1: ["normal", "res://assets/textures/enemigos/texture_normal_goblin.png"],
	2: ["bruto", "res://assets/textures/enemigos/textura_goblin_bruto.png"],
	3: ["magoblin", "res://assets/textures/enemigos/textura_mago_goblin.png"],
	4: ["zombie", "res://assets/textures/enemigos/textura_zombie_goblin.png"],
	5: ["magoblin", "res://assets/textures/enemigos/textura_mago_goblin.png"],
}

static var _available: int = -1       # -1 sin comprobar, 0 no, 1 sí
static var _imp_available: int = -1

## Modo impostor: los enemigos se dibujan como sprites (2 triángulos) que cambian según el ángulo de la
## cámara, en vez de mallas 3D animadas. Mucho más barato (clave en Android); ver tools/bake_enemy_impostors.gd.
var _impostor: bool = false
static var instance: EnemyVisuals = null   ## solo en modo impostor (lo usan EnemyData / EnemyManager)
var _slot_lists: Array = []                ## por modelo: EnemyData en cada casilla (índice = casilla)
var _dirty: Array[bool] = []

var _mms: Array[MultiMesh] = []       # índice = modelo * LOD_COUNT + lod
var _bufs: Array[PackedFloat32Array] = []
var _counts: PackedInt32Array = PackedInt32Array()
var _prev_counts: PackedInt32Array = PackedInt32Array()   ## instancias del frame anterior (para no re-subir cubos vacíos)
var _lifts: PackedFloat32Array = PackedFloat32Array()
var _lod_dist: Array[float] = LOD_DIST_PC
var _frame: int = 0
## El culling por cámara de cada enemigo se repite cada CULL_EVERY frames (se mueven poco entre frames).
const CULL_EVERY := 3
const NEAR_ALWAYS_DRAW := 5.0         ## a menos de esta distancia (m) nunca se descarta por cámara
## Los primeros frames se dibuja una instancia ficticia fuera del mapa en cada cubo, para que el shader
## y su pipeline se compilen durante la pantalla de carga y no al aparecer el primer enemigo.
var _warm_frames: int = 5

## true si los assets horneados existen (si no, los enemigos se dibujan como cápsulas).
static func is_available() -> bool:
	if _available < 0:
		_available = 1
		for key in KEYS:
			for suffix in ["_mesh.res", "_idle.res", "_walk.res", "_meta.json"]:
				if not ResourceLoader.exists(VAT_DIR + key + suffix) and not FileAccess.file_exists(VAT_DIR + key + suffix):
					_available = 0
	return _available == 1

## true si los atlas de impostores horneados existen.
static func impostors_available() -> bool:
	if _imp_available < 0:
		_imp_available = 1
		for key in KEYS:
			if not ResourceLoader.exists(VAT_DIR + key + "_impostor.png") 					or not (ResourceLoader.exists(VAT_DIR + key + "_impostor.json") or FileAccess.file_exists(VAT_DIR + key + "_impostor.json")):
				_imp_available = 0
	return _imp_available == 1

static func key_for_type(type_val: int) -> String:
	return TYPE_TABLE[type_val][0] if TYPE_TABLE.has(type_val) else ""

static func index_for_type(type_val: int) -> int:
	return KEYS.find(key_for_type(type_val))

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_to_group("enemy_visuals")
	_lod_dist = LOD_DIST_MOBILE if Quality.is_mobile() else LOD_DIST_PC
	_impostor = Quality.use_impostors() and is_available() and impostors_available()
	if _impostor:
		instance = self
	var tex_for: Dictionary = {}
	for t in TYPE_TABLE:
		tex_for[TYPE_TABLE[t][0]] = TYPE_TABLE[t][1]
	for key in KEYS:
		_make_model_slots(key, tex_for[key])
	_counts.resize(_mms.size())
	_prev_counts.resize(_mms.size())
	if _impostor:
		for k in range(_mms.size()):
			_slot_lists.append([])
			_dirty.append(false)

# ───────────────────────────── Creación de los cubos ─────────────────────────────

func _new_instance(mesh: Mesh, mat: Material, name_: String, shadows: bool, lift: float) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = false
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = CAPACITY
	mm.visible_instance_count = 0
	mm.custom_aabb = AABB(Vector3(-130, -40, -130), Vector3(260, 100, 260))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = name_
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	var buf := PackedFloat32Array()
	buf.resize(CAPACITY * STRIDE)
	_mms.append(mm)
	_bufs.append(buf)
	_lifts.append(lift)

## Sin los assets horneados los enemigos se dibujan como cápsulas verdes (jugable pero feo);
## se arregla ejecutando tools/bake_enemy_vat.gd.
func _make_fallback_slots(key: String) -> void:
	var cap := CapsuleMesh.new()
	cap.radius = 0.4
	cap.height = 1.45
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.75, 0.35)
	for lod in range(LOD_COUNT):
		_new_instance(cap, mat, "MM_%s_%d" % [key, lod], false, 0.72)

func _material_for(key: String, suffix: String, meta: Dictionary, rows: int, tex_path: String, vmin: Array, vsize: Array) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("albedo_tex", load(tex_path))
	mat.set_shader_parameter("vat_idle", load(VAT_DIR + key + suffix + "_idle.res"))
	mat.set_shader_parameter("vat_walk", load(VAT_DIR + key + suffix + "_walk.res"))
	mat.set_shader_parameter("tex_w", int(meta["tex_w"]))
	mat.set_shader_parameter("rows", rows)
	mat.set_shader_parameter("pos_min", Vector3(vmin[0], vmin[1], vmin[2]))
	mat.set_shader_parameter("pos_size", Vector3(vsize[0], vsize[1], vsize[2]))
	mat.set_shader_parameter("idle_frames", int(meta["idle_frames"]))
	mat.set_shader_parameter("idle_fps", float(meta["idle_fps"]))
	mat.set_shader_parameter("walk_frames", int(meta["walk_frames"]))
	mat.set_shader_parameter("walk_fps", float(meta["walk_fps"]))
	return mat

## Un cuadrado con el atlas del modelo; un único cubo por modelo (índice = modelo).
func _make_impostor_slots(key: String) -> void:
	var info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(VAT_DIR + key + "_impostor.json"))
	var mat := ShaderMaterial.new()
	mat.shader = IMPOSTOR_SHADER
	mat.set_shader_parameter("atlas", load(VAT_DIR + key + "_impostor.png"))
	mat.set_shader_parameter("angles", int(info["angles"]))
	mat.set_shader_parameter("cols", int(info["cols"]))
	mat.set_shader_parameter("idle_sprites", int(info["idle_sprites"]))
	mat.set_shader_parameter("idle_fps", float(info["idle_fps"]))
	mat.set_shader_parameter("walk_sprites", int(info["walk_sprites"]))
	mat.set_shader_parameter("walk_fps", float(info["walk_fps"]))
	mat.set_shader_parameter("quad_w", float(info["quad_w"]))
	mat.set_shader_parameter("quad_h", float(info["quad_h"]))
	mat.set_shader_parameter("center_y", float(info["center_y"]))
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_new_instance(quad, mat, "MM_%s_imp" % key, false, 0.0)

func _make_model_slots(key: String, tex_path: String) -> void:
	if not is_available():
		_make_fallback_slots(key)
		return
	if _impostor:
		_make_impostor_slots(key)
		return
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(VAT_DIR + key + "_meta.json"))
	# Filas por fotograma de cada LOD (el 0 es la malla completa)
	var rows: Array[int] = [int(meta["rows"])]
	for lod in range(1, LOD_COUNT):
		rows.append(0)
	var vmins: Array = [meta["vmin"]]
	var vsizes: Array = [meta["vsize"]]
	for lod in range(1, LOD_COUNT):
		vmins.append(meta["vmin"])
		vsizes.append(meta["vsize"])
	for info in meta.get("lods", []):
		var li := LOD_SUFFIX.find("_" + String(info["name"]))
		if li > 0:
			rows[li] = int(info["rows"])
			vmins[li] = info["vmin"]
			vsizes[li] = info["vsize"]
	for lod in range(LOD_COUNT):
		var suffix := LOD_SUFFIX[lod]
		# Sin los LOD horneados, ese nivel reutiliza la malla completa
		var has_lod: bool = lod == 0 or rows[lod] > 0
		var use_suffix: String = suffix if has_lod else ""
		var use_rows: int = rows[lod] if has_lod else rows[0]
		var mesh: Mesh = load(VAT_DIR + key + use_suffix + "_mesh.res")
		var mat := _material_for(key, use_suffix, meta, use_rows, tex_path, vmins[lod] if has_lod else vmins[0], vsizes[lod] if has_lod else vsizes[0])
		_new_instance(mesh, mat, "MM_%s_%d" % [key, lod], lod == 0 and Quality.shadows_enabled(), 0.0)

# ───────────────────────────── Dibujo ─────────────────────────────

func _exit_tree() -> void:
	if instance == self:
		instance = null

func _process(_delta: float) -> void:
	if _impostor:
		_process_impostor()
		return
	_frame += 1
	for k in range(_counts.size()):
		_counts[k] = 0
	var now := Time.get_ticks_msec() * 0.001
	var frac := Engine.get_physics_interpolation_fraction()
	var cam := get_viewport().get_camera_3d()
	if _warm_frames > 0:
		_warm_frames -= 1
		for k in range(_counts.size()):
			var wb := _bufs[k]
			for j in range(STRIDE):
				wb[j] = 0.0
			wb[0] = 1.0; wb[5] = 1.0; wb[10] = 1.0
			wb[7] = -300.0
			_bufs[k] = wb
			_counts[k] = 1
	_fill_vat(now, frac, cam)
	for k in range(_mms.size()):
		var c: int = _counts[k]
		if c == 0 and _prev_counts[k] == 0:
			continue          # cubo vacío antes y ahora: no hay nada que subir
		var mm := _mms[k]
		mm.visible_instance_count = c
		if c > 0:
			mm.buffer = _bufs[k]
		_prev_counts[k] = c

## Modo malla: cada enemigo va al cubo de su modelo y su LOD, con transformación completa.
func _fill_vat(now: float, frac: float, cam: Camera3D) -> void:
	var d1: float = _lod_dist[0]
	var d2: float = _lod_dist[1]
	for e in EnemyRegistry.all():
		if not (e is EnemyData):
			continue          # los jefes son nodos y no usan MultiMesh
		var dist: float = e._last_dist
		if dist > MAX_DRAW_DIST:
			continue
		var model: int = e.vat_idx
		if model < 0:
			continue
		# Cubo según la distancia: 0 completo, 1 medio, 2 lejano
		var slot: int = model * LOD_COUNT + (0 if (_impostor or dist < d1) else (1 if dist < d2 else 2))
		var n: int = _counts[slot]
		if n >= CAPACITY:
			continue
		# Posición interpolada entre el tick anterior y el actual (sin crear Transform3D/Basis)
		var cur: Vector3 = e.global_position
		var prev: Vector3 = e.prev_position
		# Los enemigos que se actualizan cada 2 o 4 ticks se interpolan sobre todo ese intervalo
		var a: float = (float(e.tick_age) + frac) / float(e.tick_span) if e.tick_span > 1 else frac
		var px: float = prev.x + (cur.x - prev.x) * a
		var py: float = prev.y + (cur.y - prev.y) * a
		var pz: float = prev.z + (cur.z - prev.z) * a
		# Culling por cámara: una llamada (centro del enemigo) y solo cada CULL_EVERY frames por enemigo
		if cam != null and dist > NEAR_ALWAYS_DRAW:
			if (_frame + e.vat_idx_seed) % CULL_EVERY == 0:
				e._offscreen = not cam.is_position_in_frustum(Vector3(px, py + 0.9, pz))
			if e._offscreen:
				continue
		else:
			e._offscreen = false
		var buf: PackedFloat32Array = _bufs[slot]
		var i := n * STRIDE
		var yaw: float = e.yaw
		var c := cos(yaw)
		var s := sin(yaw)
		var sc: Vector3 = e.scale
		buf[i] = c * sc.x; buf[i + 1] = 0.0; buf[i + 2] = s * sc.z; buf[i + 3] = px
		buf[i + 4] = 0.0; buf[i + 5] = sc.y; buf[i + 6] = 0.0; buf[i + 7] = py + _lifts[slot]
		buf[i + 8] = -s * sc.x; buf[i + 9] = 0.0; buf[i + 10] = c * sc.z; buf[i + 11] = pz
		buf[i + 12] = now + e.vat_phase
		buf[i + 13] = 1.0 if e.vat_walking else 0.0
		buf[i + 14] = 1.0 if e.vat_flash > 0.0 else 0.0
		buf[i + 15] = 1.0 if e.slow_timer > 0.0 else 0.0
		_bufs[slot] = buf
		_counts[slot] = n + 1

# ───────────────────────────── Modo impostor: casillas fijas ─────────────────────────────
# Cada enemigo ocupa una casilla fija de su cubo (EnemyData.vis_slot). Su registro solo se reescribe cuando
# el enemigo se actualiza (EnemyManager) o recibe un golpe; la posición entre actualizaciones la interpola
# el shader con el reloj global enemy_ticks. Así no hay recorrido de todos los enemigos en cada frame.
# Disposición de los 16 floats de cada casilla (ver assets/shaders/enemy_impostor.gdshader):
#   0 sx  1 dx  2 tick  3 x   |  4 sy  5 dy  6 dur   7 y   |  8 yaw  9 dz  10 tick_golpe  11 z
#   12 fase de animación  13 caminando  14 ralentizado  15 (libre)

## Reserva casilla al enemigo (al activarse). Sin sitio queda sin dibujar (vis_slot = -1).
func attach(e) -> void:
	e.vis_slot = -1
	var model: int = e.vat_idx
	if model < 0 or model >= _slot_lists.size():
		return
	var list: Array = _slot_lists[model]
	if list.size() >= CAPACITY:
		push_warning("EnemyVisuals: cubo de impostores lleno (%d); el enemigo no se dibuja" % CAPACITY)
		return
	e.vis_slot = list.size()
	list.append(e)
	var buf: PackedFloat32Array = _bufs[model]
	buf[e.vis_slot * STRIDE + 10] = -1000.0       # sin golpe reciente
	write(e, float(EnemyManager.tick))

## Libera la casilla (al reciclarse): el último enemigo del cubo ocupa su lugar.
func detach(e) -> void:
	var slot: int = e.vis_slot
	if slot < 0:
		return
	e.vis_slot = -1
	var model: int = e.vat_idx
	var list: Array = _slot_lists[model]
	var last = list.pop_back()
	if last != e:
		list[slot] = last
		last.vis_slot = slot
		var buf: PackedFloat32Array = _bufs[model]
		var src: int = list.size() * STRIDE
		var dst: int = slot * STRIDE
		for j in range(STRIDE):
			buf[dst + j] = buf[src + j]
	_dirty[model] = true

## Escribe el estado actual del enemigo en su casilla (lo llama EnemyManager tras cada actualización).
func write(e, tick_f: float) -> void:
	var slot: int = e.vis_slot
	if slot < 0:
		return
	var model: int = e.vat_idx
	var buf: PackedFloat32Array = _bufs[model]
	var i: int = slot * STRIDE
	var cur: Vector3 = e.global_position
	var prev: Vector3 = e.prev_position
	var sc: Vector3 = e.scale
	buf[i] = sc.x
	buf[i + 1] = prev.x - cur.x
	buf[i + 2] = tick_f
	buf[i + 3] = cur.x
	buf[i + 4] = sc.y
	buf[i + 5] = prev.y - cur.y
	buf[i + 6] = float(e.tick_span)
	buf[i + 7] = cur.y
	buf[i + 8] = e.yaw
	buf[i + 9] = prev.z - cur.z
	buf[i + 11] = cur.z
	buf[i + 12] = e.vat_phase
	buf[i + 13] = 1.0 if e.vat_walking else 0.0
	buf[i + 14] = 1.0 if e.slow_timer > 0.0 else 0.0
	_dirty[model] = true

## Marca el instante del último golpe (el shader hace el destello de FLASH_S segundos).
func flash(e) -> void:
	var slot: int = e.vis_slot
	if slot < 0:
		return
	var buf: PackedFloat32Array = _bufs[e.vat_idx]
	buf[slot * STRIDE + 10] = float(EnemyManager.tick)
	_dirty[e.vat_idx] = true

func _process_impostor() -> void:
	var frac := 0.0 if get_tree().paused else Engine.get_physics_interpolation_fraction()
	RenderingServer.global_shader_parameter_set("enemy_ticks", float(EnemyManager.tick) + frac)
	RenderingServer.global_shader_parameter_set("enemy_tick_dt", 1.0 / float(Engine.physics_ticks_per_second))
	var warm := _warm_frames > 0
	if warm:
		_warm_frames -= 1      # los primeros frames se dibuja algo para compilar el shader en la pantalla de carga
	for k in range(_mms.size()):
		var c: int = (_slot_lists[k] as Array).size()
		_counts[k] = c
		var mm := _mms[k]
		if _dirty[k]:
			mm.buffer = _bufs[k]
			_dirty[k] = false
		var shown: int = maxi(c, 1) if warm else c
		if shown != _prev_counts[k]:
			mm.visible_instance_count = shown
			_prev_counts[k] = shown

## Nº de enemigos dibujados ahora mismo (depuración / pruebas).
func drawn_count() -> int:
	var n := 0
	for k in range(_counts.size()):
		n += _counts[k]
	return n

## Triángulos que se dibujan ahora mismo: suma de (instancias × triángulos de la malla de cada cubo).
func drawn_triangles() -> int:
	var total := 0
	for k in range(_mms.size()):
		var mesh := _mms[k].mesh
		if mesh != null and mesh.get_surface_count() > 0:
			var arrays := mesh.surface_get_arrays(0)
			total += _counts[k] * (arrays[Mesh.ARRAY_INDEX].size() / 3)
	return total
