class_name MapMarks
extends Node3D

## Huellas en el suelo de Supervivencia (historia 009): cráteres de las explosiones y golpes fuertes, y manchas de
## tinta donde caen los enemigos. Se quedan toda la partida, con un tope de MAX_MARKS: al llegar al tope se recicla
## la más antigua. Una sola MultiMesh (spatial_fx_map_mark.gdshader): una llamada de dibujo para todas.
##
## Cualquiera las pide con MapMarks.add_at(nodo, posición, tipo, tamaño); si no hay MapMarks en la escena, no pasa nada.

enum Kind { CRATER, INK }

const SHEET := "res://assets/textures/toon/fx/marcas.png"
const SHADER: Shader = preload("res://scripts/world/spatial_fx_map_mark.gdshader")
const MAX_MARKS := 128
const LIFT := 0.04                    ## m sobre el suelo (sin parpadeo con el terreno)
const INK_CHANCE := 0.35              ## de cada muerte, cuántas dejan mancha
const INK_SPACING := 1.2              ## m mínimos entre dos manchas de tinta
const POP_TIME := 0.18                ## s en que aparece (crece de 0,6 a 1)

var _map: Node3D
var _mm: MultiMesh
var _next := 0
var _used := 0
var _pos := PackedVector3Array()
var _kind := PackedInt32Array()
var _xf: Array[Transform3D] = []
var _pop: Dictionary = {}             ## índice -> tiempo desde que apareció
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	add_to_group("map_marks")

func setup(map: Node3D) -> void:
	_map = map
	if _mm == null:
		var plane := PlaneMesh.new()
		plane.size = Vector2.ONE
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		mat.set_shader_parameter("sheet", load(SHEET))
		_mm = MultiMesh.new()
		_mm.transform_format = MultiMesh.TRANSFORM_3D
		_mm.use_custom_data = true
		_mm.mesh = plane
		_mm.instance_count = MAX_MARKS
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Marks"
		mmi.multimesh = _mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
	clear()

## Quita todas las marcas (partida nueva).
func clear() -> void:
	_next = 0
	_used = 0
	_pos.clear()
	_kind.clear()
	_xf.clear()
	_pop.clear()
	if _mm:
		_mm.visible_instance_count = 0
	set_process(false)

func count(kind: int = -1) -> int:
	if kind < 0:
		return _used
	var n := 0
	for i in _used:
		if _kind[i] == kind:
			n += 1
	return n

## Marca de `kind` en (x, z) de `pos`, de `size` m de lado, pegada al suelo e inclinada como él.
func add(pos: Vector3, kind: int, size: float) -> void:
	if _mm == null:
		return
	var y := pos.y
	var n := Vector3.UP
	if _map and _map.has_method("get_height_at"):
		y = _map.get_height_at(pos.x, pos.z)
		var hx: float = _map.get_height_at(pos.x + 0.5, pos.z) - _map.get_height_at(pos.x - 0.5, pos.z)
		var hz: float = _map.get_height_at(pos.x, pos.z + 0.5) - _map.get_height_at(pos.x, pos.z - 0.5)
		n = Vector3(-hx, 1.0, -hz).normalized()
	var x := n.cross(Vector3.FORWARD).normalized()
	if x.length_squared() < 0.01:
		x = Vector3.RIGHT
	var z := x.cross(n)
	var basis := Basis(x, n, z).rotated(n, _rng.randf() * TAU).scaled(Vector3(size, 1.0, size))
	var xf := Transform3D(basis, Vector3(pos.x, y + LIFT, pos.z))
	var i := _next
	_next = (_next + 1) % MAX_MARKS
	if i >= _pos.size():
		_pos.append(xf.origin)
		_kind.append(kind)
		_xf.append(xf)
	else:
		_pos[i] = xf.origin
		_kind[i] = kind
		_xf[i] = xf
	_used = mini(_used + 1, MAX_MARKS)
	var cell := (0 if kind == Kind.CRATER else 2) + _rng.randi_range(0, 1)
	_mm.set_instance_custom_data(i, Color(cell, 0.0, 0.0, 0.92 if kind == Kind.CRATER else 0.85))
	_mm.set_instance_transform(i, xf)
	_mm.visible_instance_count = _used
	_pop[i] = 0.0
	set_process(true)

## Mancha de tinta donde muere un enemigo (no todas: INK_CHANCE, y no encima de otra).
func on_enemy_died(pos: Vector3) -> void:
	if _rng.randf() > INK_CHANCE:
		return
	var from := maxi(_used - 24, 0)
	for k in range(from, _used):
		var i := (_next - 1 - (k - from) + MAX_MARKS) % MAX_MARKS
		if i < _pos.size() and _kind[i] == Kind.INK and Vector2(_pos[i].x - pos.x, _pos[i].z - pos.z).length() < INK_SPACING:
			return
	add(pos, Kind.INK, _rng.randf_range(1.1, 1.8))

func _process(delta: float) -> void:
	for i in _pop.keys():
		var t: float = float(_pop[i]) + delta
		var k := clampf(t / POP_TIME, 0.0, 1.0)
		var s := lerpf(0.6, 1.0, 1.0 - (1.0 - k) * (1.0 - k))
		var xf: Transform3D = _xf[i]
		_mm.set_instance_transform(i, Transform3D(xf.basis * Basis.from_scale(Vector3(s, 1.0, s)), xf.origin))
		if k >= 1.0:
			_pop.erase(i)
		else:
			_pop[i] = t
	if _pop.is_empty():
		set_process(false)

## Atajo para cualquiera (explosiones, golpes): busca el MapMarks de la escena de `context` y añade la marca.
static func add_at(context: Node, pos: Vector3, kind: int, size: float) -> void:
	if context == null or not context.is_inside_tree():
		return
	var mm := context.get_tree().get_first_node_in_group("map_marks") as MapMarks
	if mm:
		mm.add(pos, kind, size)
