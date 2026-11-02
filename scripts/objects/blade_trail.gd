class_name BladeTrail
extends MeshInstance3D

## Estela que sigue la hoja de un arma: guarda la posición de `base` y `tip` cada frame mientras está activa y
## dibuja una cinta que se desvanece. Uso: emit(duración) al iniciar el golpe.
##
## Para que se vea redondeada (y no con picos): la cinta se suaviza entre muestras con una curva Catmull-Rom
## (un golpe rápido a 30-60 fps dejaba tramos rectos y esquinas), se estrecha poco a poco hacia la cola con una
## curva suave y el shader difumina los bordes (ver blade_trail.gdshader).

const SHADER: Shader = preload("res://assets/shaders/blade_trail.gdshader")
const LIFETIME := 0.24                 ## cuánto dura cada tramo de la cinta (s)
const MAX_POINTS := 40
const SUBDIV := 4                      ## tramos interpolados entre cada par de muestras
const TAIL_WIDTH := 0.15               ## ancho relativo al final de la cola (1 = como la hoja)
const RELAX_PASSES := 2                ## pasadas de suavizado de esquinas

var base: Node3D
var tip: Node3D
var _points: Array = []                # [[base: Vector3, tip: Vector3, time: float]] (el más nuevo primero)
var _emit_left: float = 0.0
var _time: float = 0.0
var _imesh := ImmediateMesh.new()
var _mat: ShaderMaterial

func setup(p_base: Node3D, p_tip: Node3D, color: Color = Color(0.2, 1.0, 0.45)) -> void:
	base = p_base
	tip = p_tip
	top_level = true
	mesh = _imesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("trail_color", color)
	material_override = _mat

func emit(duration: float) -> void:
	_emit_left = maxf(_emit_left, duration)

func _process(delta: float) -> void:
	_time += delta
	global_transform = Transform3D.IDENTITY
	if _emit_left > 0.0 and is_instance_valid(base) and base.is_visible_in_tree():
		_emit_left -= delta
		_points.push_front([base.global_position, tip.global_position, _time])
		if _points.size() > MAX_POINTS:
			_points.pop_back()
	while not _points.is_empty() and _time - float(_points.back()[2]) > LIFETIME:
		_points.pop_back()
	_imesh.clear_surfaces()
	if _points.size() < 2:
		return
	var curve := _smooth()
	var n := curve.size()
	if n < 2:
		return
	# Velocidad de la hoja (más rápida = estela más brillante): distancia de la punta entre las dos muestras nuevas
	var speed: float = (_points[0][1] as Vector3).distance_to(_points[1][1]) / maxf(delta, 0.001)
	if _mat:
		_mat.set_shader_parameter("swing", clampf(speed / 18.0, 0.0, 1.0))
	_imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in n:
		var c: Array = curve[i]
		var along := float(i) / float(n - 1)          # 0 = cabeza (junto a la hoja) .. 1 = cola
		var life: float = clampf(1.0 - (_time - float(c[2])) / LIFETIME, 0.0, 1.0)
		# Se estrecha hacia la cola con una curva suave (la cola se cierra redondeada, sin pico)
		var w := lerpf(1.0, TAIL_WIDTH, pow(along, 1.6))
		var b: Vector3 = c[0]
		var t: Vector3 = c[1]
		var mid := (b + t) * 0.5
		var bb := mid + (b - mid) * w
		var tt := mid + (t - mid) * w
		_imesh.surface_set_color(Color(1, 1, 1, life))
		_imesh.surface_set_uv(Vector2(along, 0.0))
		_imesh.surface_add_vertex(bb)
		_imesh.surface_set_color(Color(1, 1, 1, life))
		_imesh.surface_set_uv(Vector2(along, 1.0))
		_imesh.surface_add_vertex(tt)
	_imesh.surface_end()

## Curva suavizada de las muestras: [[base, punta, tiempo], ...] de la cabeza a la cola. Primero se
## redondean las esquinas (cada muestra se acerca a la media de sus vecinas; la cabeza sigue pegada a la hoja)
## y luego se interpola entre ellas con Catmull-Rom.
func _smooth() -> Array:
	var pts: Array = _relax(_points, RELAX_PASSES)
	var out: Array = []
	var m := pts.size()
	for i in m - 1:
		var p0: Array = pts[maxi(i - 1, 0)]
		var p1: Array = pts[i]
		var p2: Array = pts[i + 1]
		var p3: Array = pts[mini(i + 2, m - 1)]
		for s in SUBDIV:
			var k := float(s) / float(SUBDIV)
			out.append([
				_catmull(p0[0], p1[0], p2[0], p3[0], k),
				_catmull(p0[1], p1[1], p2[1], p3[1], k),
				lerpf(float(p1[2]), float(p2[2]), k),
			])
	out.append(pts[m - 1])
	return out

## Suavizado laplaciano: quita los picos de un giro brusco de la hoja entre dos muestras.
static func _relax(src: Array, passes: int) -> Array:
	var pts: Array = src.duplicate(true)
	for _p in passes:
		var nxt: Array = pts.duplicate(true)
		for i in range(1, pts.size() - 1):
			for k in 2:
				nxt[i][k] = (pts[i - 1][k] as Vector3) * 0.25 + (pts[i][k] as Vector3) * 0.5 + (pts[i + 1][k] as Vector3) * 0.25
		pts = nxt
	return pts

static func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, k: float) -> Vector3:
	var k2 := k * k
	var k3 := k2 * k
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * k + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * k2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * k3)
