class_name TreeField
extends Node3D

## Árboles del mapa de Supervivencia como dibujos 2D horneados (tools/make_map_sprites.py) y destructibles.
##
##  - Se dibujan en MultiMesh de quads (spatial_prop_tree_sprite.gdshader: billboard que solo gira en vertical),
##    una por trozo del mapa: unas pocas llamadas de dibujo para cientos de árboles.
##  - Cada árbol tiene un cuerpo ligero (TreeTrunk) en el grupo "destructibles": los tajos, las balas, las flechas
##    y las explosiones lo dañan como a un barril. Al golpearlo tiembla.
##  - Al romperse queda el tocón (con su colisión, más baja) y la parte de arriba cae de lado y se deshace en
##    polvo. El tocón ocupa el mismo sitio, así que los obstáculos de EnemyMotion no cambian.
## Los árboles talados siguen talados hasta el final de la partida (huellas del jugador, historia 009).

signal tree_broken(pos: Vector3)

const SHEET := "res://assets/textures/toon/props/arboles.png"
const SHADER: Shader = preload("res://scripts/world/spatial_prop_tree_sprite.gdshader")
## = tools/make_map_sprites.py
const VARIANTS := 4
const ROWS := 3
const BASE_Y := 0.97
const CUT_Y := 0.83
const QUAD := 6.6                     ## m de lado del dibujo a escala 1 (el tronco mide ~4,5 m, como tree_dead_a)
const STUMP_H := (BASE_Y - CUT_Y) * QUAD
const TRUNK_R := 0.42                 ## radio de la colisión (= PROPS["tree_a"].size.x)
const TRUNK_H := 4.0
const HP := 55.0
const CHUNK := 80.0
const WOBBLE := 0.09                  ## rad de temblor al golpearlo
const WOBBLE_DECAY := 7.0
const FALL_TIME := 0.75               ## s que tarda en caer la parte de arriba
const FADE_TIME := 0.45               ## s que tarda en deshacerse en polvo después
const MAX_FALLING := 12
const WOOD := Color(0.55, 0.42, 0.3)
## Cuerpos de colisión: solo existen los de los árboles a menos de BODY_RADIUS m del jugador (se crean como mucho
## BODY_BUDGET por paso y ya no se quitan). Crear los ~300 al generar el mapa costaba ~130 ms.
const BODY_RADIUS := 45.0
const BODY_CELL := 16.0
const BODY_BUDGET := 24
const STREAM_EVERY := 0.25

var _pos := PackedVector3Array()
var _scale := PackedFloat32Array()
var _variant := PackedInt32Array()
var _flip := PackedFloat32Array()
var _hp := PackedFloat32Array()
var _broken := PackedByteArray()
var _mm: Array[MultiMesh] = []
var _mm_of := PackedInt32Array()      ## MultiMesh de cada árbol (índice en _mm)
var _slot := PackedInt32Array()       ## instancia de cada árbol dentro de su MultiMesh
var _bodies: Array[TreeTrunk] = []    ## cuerpo de cada árbol (null hasta que el jugador se acerca)
var _body_grid: Dictionary = {}       ## Vector2i -> PackedInt32Array de árboles (celdas de BODY_CELL m)
var _trunk_shape: CylinderShape3D
var _stump_shape: CylinderShape3D
var _stream_t := 0.0
var _wobble: Dictionary = {}          ## árbol -> [tiempo, signo]
var _falling: Array = []              ## [{tree, t, side}]
var _fall_mm: MultiMesh
var _fall_mat: ShaderMaterial
var _mat: ShaderMaterial
var _mobile := false

## Crea los árboles a partir de las transformadas de los props "tree_a"/"tree_b" de ProceduralMap.
func build(transforms: Array, mobile: bool) -> void:
	_mobile = mobile
	var tex := load(SHEET) as Texture2D
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("sheet", tex)
	_mat.set_shader_parameter("grid", Vector2(VARIANTS, ROWS))
	var quad := QuadMesh.new()
	quad.size = Vector2(QUAD, QUAD)
	quad.center_offset = Vector3(0.0, QUAD * (0.5 - (1.0 - BASE_Y)), 0.0)    # la base del tronco en el origen
	var chunks: Dictionary = {}           # Vector2i -> Array[int]
	for xf: Transform3D in transforms:
		var i := _pos.size()
		var o := xf.origin
		_pos.append(o)
		_scale.append(xf.basis.get_scale().y)
		# Variante y espejo fijos por posición (el mismo mapa con la misma semilla)
		var h := hash(Vector2i(int(round(o.x * 10.0)), int(round(o.z * 10.0))))
		_variant.append(absi(h) % VARIANTS)
		_flip.append(1.0 if (h >> 8) & 1 == 0 else -1.0)
		_hp.append(HP)
		_broken.append(0)
		var key := Vector2i(int(floor(o.x / CHUNK)), int(floor(o.z / CHUNK)))
		if not chunks.has(key):
			chunks[key] = []
		(chunks[key] as Array).append(i)
		_mm_of.append(0)
		_slot.append(0)
	for key in chunks:
		var list: Array = chunks[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = quad
		mm.instance_count = list.size()
		for k in list.size():
			var i: int = list[k]
			_mm_of[i] = _mm.size()
			_slot[i] = k
			mm.set_instance_transform(k, Transform3D(Basis.from_scale(Vector3.ONE * _scale[i]), _pos[i]))
			mm.set_instance_custom_data(k, Color(_variant[i], 0.0, _flip[i], 0.0))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Trees_%d_%d" % [key.x, key.y]
		mmi.multimesh = mm
		mmi.material_override = _mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if mobile else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mmi)
		_mm.append(mm)
	# Partes que caen: una MultiMesh pequeña que gira alrededor del corte
	_fall_mat = _mat.duplicate() as ShaderMaterial
	_fall_mat.set_shader_parameter("pivot_y", STUMP_H)
	_fall_mm = MultiMesh.new()
	_fall_mm.transform_format = MultiMesh.TRANSFORM_3D
	_fall_mm.use_custom_data = true
	_fall_mm.mesh = quad
	_fall_mm.instance_count = MAX_FALLING
	_fall_mm.visible_instance_count = 0
	var fmi := MultiMeshInstance3D.new()
	fmi.name = "FallingTrees"
	fmi.multimesh = _fall_mm
	fmi.material_override = _fall_mat
	fmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fmi)
	# Cuerpos: se crean poco a poco cerca del jugador (_stream), no todos al generar el mapa
	_bodies.resize(_pos.size())
	_trunk_shape = CylinderShape3D.new()
	_trunk_shape.radius = TRUNK_R
	_trunk_shape.height = TRUNK_H
	_stump_shape = CylinderShape3D.new()
	_stump_shape.radius = TRUNK_R
	_stump_shape.height = STUMP_H
	for i in _pos.size():
		var key := Vector2i(int(floor(_pos[i].x / BODY_CELL)), int(floor(_pos[i].z / BODY_CELL)))
		var cur: PackedInt32Array = _body_grid.get(key, PackedInt32Array())
		cur.append(i)
		_body_grid[key] = cur
	set_process(false)

func count() -> int:
	return _pos.size()

func broken_count() -> int:
	var n := 0
	for b in _broken:
		n += b
	return n

func is_broken(i: int) -> bool:
	return _broken[i] == 1

func tree_position(i: int) -> Vector3:
	return _pos[i]

## Golpe al árbol `i` (lo llama su TreeTrunk).
func damage_tree(i: int, amount: float, dir: Vector3) -> void:
	if i < 0 or i >= _pos.size() or _broken[i] == 1:
		return
	_hp[i] -= amount
	var right := _camera_right(_pos[i])
	_wobble[i] = [0.0, -signf(dir.dot(right)) if absf(dir.dot(right)) > 0.05 else 1.0]
	set_process(true)
	var p := _pos[i] + Vector3(0.0, 1.2 * _scale[i], 0.0)
	ToonFX.puff_burst(get_parent(), p, WOOD, 4, 2.4, 0.3)
	AudioManager.play_at("impact_blunt", p, -8.0, randf_range(0.7, 0.85))
	if _hp[i] <= 0.0:
		_break(i, dir)

func _break(i: int, dir: Vector3) -> void:
	_broken[i] = 1
	_wobble.erase(i)
	var mm := _mm[_mm_of[i]]
	mm.set_instance_custom_data(_slot[i], Color(_variant[i], 1.0, _flip[i], 0.0))
	# El tocón sigue estorbando, más bajo; deja de ser rompible
	var b := _bodies[i]
	if b:
		_make_stump(b)
	# La parte de arriba cae hacia donde empujó el golpe (de lado, en el plano del dibujo)
	var right := _camera_right(_pos[i])
	var side := signf(dir.dot(right)) if absf(dir.dot(right)) > 0.05 else (1.0 if randf() < 0.5 else -1.0)
	if _falling.size() >= MAX_FALLING:
		_falling.pop_front()
	_falling.append({"tree": i, "t": 0.0, "side": side})
	set_process(true)
	var at := _pos[i] + Vector3(0.0, STUMP_H * _scale[i], 0.0)
	ToonFX.puff_burst(get_parent(), at, WOOD, 8, 3.2, 0.45)
	AudioManager.play_at("amb_creak", at, -4.0, randf_range(0.85, 1.0))
	tree_broken.emit(_pos[i])

func _camera_right(at: Vector3) -> Vector3:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return Vector3.RIGHT
	var to_cam := cam.global_position - at
	to_cam.y = 0.0
	if to_cam.length() < 0.001:
		return Vector3.RIGHT
	to_cam = to_cam.normalized()
	return Vector3(to_cam.z, 0.0, -to_cam.x)

func _process(delta: float) -> void:
	# Temblor de los golpeados
	for i in _wobble.keys():
		var w: Array = _wobble[i]
		w[0] = float(w[0]) + delta
		var t: float = w[0]
		var a := WOBBLE * float(w[1]) * exp(-WOBBLE_DECAY * t) * sin(t * 28.0)
		var mm := _mm[_mm_of[i]]
		if t > 0.6:
			a = 0.0
			_wobble.erase(i)
		mm.set_instance_custom_data(_slot[i], Color(_variant[i], 0.0, _flip[i], a))
	# Partes que caen: giran hasta tumbarse, rebotan un poco y se encogen en una nube de polvo
	var n := 0
	var k := 0
	while k < _falling.size():
		var f: Dictionary = _falling[k]
		f["t"] = float(f["t"]) + delta
		var t: float = f["t"]
		if t >= FALL_TIME + FADE_TIME:
			var i0: int = f["tree"]
			ToonFX.puff_burst(get_parent(), _pos[i0] + Vector3(float(f["side"]) * 2.0, 0.6, 0.0), WOOD, 6, 2.0, 0.5)
			_falling.remove_at(k)
			continue
		var i: int = f["tree"]
		var fall := clampf(t / FALL_TIME, 0.0, 1.0)
		var ang := fall * fall * 1.45
		if fall >= 1.0:
			ang = 1.45 - 0.12 * sin(clampf((t - FALL_TIME) / FADE_TIME, 0.0, 1.0) * PI)
		var shrink := 1.0 - clampf((t - FALL_TIME) / FADE_TIME, 0.0, 1.0)
		_fall_mm.set_instance_transform(n, Transform3D(Basis.from_scale(Vector3.ONE * _scale[i] * maxf(shrink, 0.001)), _pos[i]
			+ Vector3(0.0, STUMP_H * _scale[i] * (1.0 - maxf(shrink, 0.001)), 0.0)))
		# El signo del giro: hacia la derecha de la cámara con side > 0 (w negativo gira a la derecha)
		_fall_mm.set_instance_custom_data(n, Color(_variant[i], 2.0, _flip[i], -ang * float(f["side"])))
		n += 1
		k += 1
	_fall_mm.visible_instance_count = n
	if _wobble.is_empty() and _falling.is_empty():
		set_process(false)

func _make_stump(b: TreeTrunk) -> void:
	b.remove_from_group("destructibles")
	var cs := b.get_child(0) as CollisionShape3D
	cs.shape = _stump_shape
	cs.position = Vector3(0.0, STUMP_H * 0.5, 0.0)

func _physics_process(delta: float) -> void:
	_stream_t -= delta
	if _stream_t > 0.0:
		return
	_stream_t = STREAM_EVERY
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p:
		ensure_bodies_near(p.global_position, BODY_RADIUS, BODY_BUDGET)

## Crea los cuerpos que falten de los árboles a menos de `radius` de `at` (como mucho `budget`; -1 = todos).
## Devuelve cuántos creó.
func ensure_bodies_near(at: Vector3, radius: float, budget: int = -1) -> int:
	var made := 0
	var c0 := Vector2i(int(floor((at.x - radius) / BODY_CELL)), int(floor((at.z - radius) / BODY_CELL)))
	var c1 := Vector2i(int(floor((at.x + radius) / BODY_CELL)), int(floor((at.z + radius) / BODY_CELL)))
	var r2 := radius * radius
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			var list: PackedInt32Array = _body_grid.get(Vector2i(cx, cz), PackedInt32Array())
			for i in list:
				if _bodies[i] != null:
					continue
				var d := _pos[i] - at
				if d.x * d.x + d.z * d.z > r2:
					continue
				_spawn_body(i)
				made += 1
				if budget >= 0 and made >= budget:
					return made
	return made

func _spawn_body(i: int) -> void:
	var b := TreeTrunk.new()
	b.field = self
	b.index = i
	b.collision_layer = 1
	b.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = _trunk_shape
	cs.position = Vector3(0.0, TRUNK_H * 0.5, 0.0)
	b.add_child(cs)
	b.position = _pos[i]
	b.scale = Vector3.ONE * _scale[i]
	_bodies[i] = b
	add_child(b)
	if _broken[i] == 1:
		_make_stump(b)

func body_count() -> int:
	var n := 0
	for b in _bodies:
		if b != null:
			n += 1
	return n

func body_of(i: int) -> TreeTrunk:
	return _bodies[i]
