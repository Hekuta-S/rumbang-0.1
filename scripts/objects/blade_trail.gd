class_name BladeTrail
extends MeshInstance3D

## Estela que sigue la hoja de un arma: guarda la posición de `base` y `tip` cada frame mientras está activa y
## dibuja una cinta que se desvanece. Uso: emit(duración) al iniciar el golpe.
##
## Para que se vea redondeada (y no con picos): la cinta se suaviza entre muestras con una curva Catmull-Rom
## (un golpe rápido a 30-60 fps dejaba tramos rectos y esquinas), se estrecha poco a poco hacia la cola con una
## curva suave y el shader difumina los bordes (ver blade_trail.gdshader).
##
## Cada arma tiene su estilo (STYLES): cuánto dura la cinta, cómo se estrecha y cómo la pinta el shader
## (aguja fina de las dagas, arco limpio con hilos de la espada, barrido ancho que acaba en brasa del espadón,
## soplo romo con líneas de velocidad de la maza...).
##
## Rendimiento (es el efecto que más se ve en mazmorras: cada golpe de cada arma cuerpo a cuerpo):
##  - Las muestras van en arrays empaquetados que se reutilizan. La malla es un ImmediateMesh, que reutiliza
##    su buffer de GPU (probado: subir un ArrayMesh nuevo cada frame costaba ~4 veces más de GPU).
##  - No se genera geometría donde el shader no pinta nada: la franja del lado del asta que `band_from`
##    deja vacía y la cola que ya se "comió" el umbral de edad (ver _visible()). Menos vértices y, sobre
##    todo, menos píxeles transparentes que rellenar.
##  - El nodo deja de procesarse cuando no queda nada que dibujar.

const SHADER: Shader = preload("res://assets/shaders/blade_trail.gdshader")
const MAX_POINTS := 40
const SPEED_FULL := 18.0               ## m/s de la punta a los que la estela brilla al máximo

## Estilo por arma. "life" = s que dura cada tramo; "tail" = ancho relativo al final de la cola (1 = como la
## hoja); "taper" = curva con que se estrecha; el resto son parámetros del shader (ver blade_trail.gdshader).
## "ember" = cuánto vira la cola hacia el color de brasa.
const STYLES := {
	"": {"life": 0.24, "tail": 0.15, "taper": 1.6},
	"sword": {"life": 0.22, "tail": 0.12, "taper": 1.6, "energy": 1.6, "band": 0.4, "core_from": 0.6,
		"core_gain": 1.25, "streaks": 3.0, "streak_amt": 0.28},
	"great": {"life": 0.34, "tail": 0.32, "taper": 1.2, "energy": 1.8, "band": 0.3, "core_from": 0.45,
		"core_gain": 1.3, "flow": 12.0, "tear": 0.6, "ember": 0.8, "tail_pow": 1.1},
	"dagger": {"life": 0.13, "tail": 0.04, "taper": 2.2, "energy": 2.0, "band_from": 0.45, "band": 0.3,
		"core_from": 0.7, "core_gain": 1.6, "flow": 40.0, "ripple": 26.0, "tail_pow": 1.6},
	"mace": {"life": 0.3, "tail": 0.45, "taper": 1.0, "energy": 1.25, "band": 0.15, "core_from": 0.3,
		"core_gain": 0.5, "streaks": 5.0, "streak_amt": 0.55, "tear": 0.3, "tail_pow": 1.0, "flow": 10.0},
	# Puños: cinta corta y ancha (del antebrazo a los nudillos) que se apaga rápido, con líneas de velocidad
	"fist": {"life": 0.2, "tail": 0.3, "taper": 1.3, "energy": 1.5, "band": 0.25, "core_from": 0.5,
		"core_gain": 1.1, "streaks": 4.0, "streak_amt": 0.45, "tail_pow": 1.2, "flow": 18.0},
	"spear": {"life": 0.2, "tail": 0.1, "taper": 1.8, "energy": 1.6, "band_from": 0.3, "band": 0.35,
		"core_from": 0.65, "core_gain": 1.4, "streaks": 2.0, "streak_amt": 0.2},
}
const EMBER := Color(1.0, 0.35, 0.1)
const SHADER_KEYS := ["energy", "band_from", "band", "core_from", "core_gain", "streaks", "streak_amt",
	"tear", "tail_pow", "flow", "ripple"]

var base: Node3D
var tip: Node3D
var style := ""
var _life := 0.24
var _tail := 0.15
var _taper := 1.6
var _subdiv := 4                       ## tramos interpolados entre cada par de muestras
var _relax_passes := 2                 ## pasadas de suavizado de esquinas
# Muestras, de la más vieja [0] a la más nueva [n - 1]
var _pb := PackedVector3Array()
var _pt := PackedVector3Array()
var _ptime := PackedFloat32Array()
# Las mismas muestras suavizadas (ver _relax), alineadas con las de arriba
var _sb := PackedVector3Array()
var _st := PackedVector3Array()
var _relax_all := true                 ## recalcular todo el suavizado en el próximo frame
const SUBDIV_STEP := 0.1               ## m de recorrido de la punta por cada tramo interpolado
var _emit_left: float = 0.0
var _time: float = 0.0
var _power := 1.0                      ## fuerza del golpe en curso (más brillo y algo más de cola)
var _drawn := false
var _imesh := ImmediateMesh.new()       ## reutiliza su buffer (un ArrayMesh nuevo cada frame salía más caro en GPU)
var _mat: ShaderMaterial
# Copia en CPU de lo que el shader usa para decidir qué es visible (ver blade_trail.gdshader)
var _band_from := 0.0
var _tail_pow := 1.3
const CUT_MIN := 0.12              ## = CUT_MIN del shader
const CUT_AGE := 0.7               ## = CUT_AGE del shader
const HEAD_RAMP := 0.1             ## = ancho de la entrada de la cabeza en el shader

func setup(p_base: Node3D, p_tip: Node3D, color: Color = Color(0.2, 1.0, 0.45), p_style: String = "") -> void:
	base = p_base
	tip = p_tip
	style = p_style if STYLES.has(p_style) else ""
	top_level = true
	mesh = _imesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("trail_color", color)
	var st: Dictionary = STYLES[style]
	_life = float(st["life"])
	_tail = float(st["tail"])
	_taper = float(st["taper"])
	_band_from = float(st.get("band_from", 0.0))
	_tail_pow = float(st.get("tail_pow", 1.3))
	for key in SHADER_KEYS:
		if st.has(key):
			_mat.set_shader_parameter(key, st[key])
	var ember := float(st.get("ember", 0.0))
	_mat.set_shader_parameter("tail_color", color.lerp(EMBER, ember))
	_mat.set_shader_parameter("tail_mix", 1.0 if ember > 0.0 else 0.0)
	material_override = _mat
	set_process(false)

## Activa la estela `duration` s. `power` (1 = golpe normal) realza los golpes fuertes.
func emit(duration: float, power: float = 1.0) -> void:
	if _emit_left <= 0.0:
		# Calidad baja: menos tramos interpolados y una sola pasada de suavizado
		var low := Quality.level() == Quality.Level.LOW
		_subdiv = 2 if low else 4
		_relax_passes = 1 if low else 2
		_relax_all = true
		_power = 1.0
	_emit_left = maxf(_emit_left, duration)
	_power = clampf(maxf(_power, power), 0.5, 2.0)
	if _mat:
		_mat.set_shader_parameter("power", _power)
	global_transform = Transform3D.IDENTITY
	set_process(true)

## Segundos que dura ahora cada tramo de la cinta (los golpes fuertes dejan algo más de cola).
func life() -> float:
	return _life * (0.8 + 0.2 * _power)

func _process(delta: float) -> void:
	_time += delta
	var life_now := life()
	if _emit_left > 0.0:
		_emit_left -= delta                # también con el arma oculta: una emisión pendiente no lo deja despierto
		if is_instance_valid(base) and base.is_visible_in_tree():
			_pb.append(base.global_position)
			_pt.append(tip.global_position)
			_ptime.append(_time)
			_sb.append(base.global_position)    # su versión suavizada se calcula en _relax()
			_st.append(tip.global_position)
			if _ptime.size() > MAX_POINTS:
				_drop_oldest()
	while not _ptime.is_empty() and _time - _ptime[0] > life_now:
		_drop_oldest()
	var m := _ptime.size()
	if m < 2:
		if _drawn:
			_imesh.clear_surfaces()
			_drawn = false
		if m == 0 and _emit_left <= 0.0:
			set_process(false)             # nada que dibujar: no gasta hasta el próximo emit()
		return
	# Velocidad de la hoja (más rápida = estela más brillante): distancia de la punta entre las dos muestras nuevas
	if _mat:
		_mat.set_shader_parameter("swing", clampf(_pt[m - 1].distance_to(_pt[m - 2]) / maxf(delta, 0.001) / SPEED_FULL, 0.0, 1.0))
	_relax(m)
	_build(m, life_now)

func _drop_oldest() -> void:
	_pb.remove_at(0)
	_pt.remove_at(0)
	_ptime.remove_at(0)
	_sb.remove_at(0)
	_st.remove_at(0)

## Suavizado laplaciano: quita los picos de un giro brusco de la hoja entre dos muestras (cada una se acerca
## a la media de sus vecinas; los extremos no se mueven). Equivale a `_relax_passes` pasadas del filtro
## [¼ ½ ¼], pero INCREMENTAL: las muestras no se mueven una vez tomadas, así que al añadir una por la cabeza
## o quitar otra por la cola solo cambian las 3 de cada extremo. Se recalcula todo solo tras un emit()
## (puede cambiar la calidad) o con pocas muestras.
func _relax(m: int) -> void:
	if _relax_all or m < 7:
		_relax_all = m < 7
		for i in m:
			_smooth_at(i, m)
		return
	for i in 3:
		_smooth_at(i, m)
		_smooth_at(m - 1 - i, m)

## Muestra `i` suavizada en _sb/_st a partir de las crudas _pb/_pt. Dos pasadas de [¼ ½ ¼] con extremos
## fijos dan el filtro [1 4 6 4 1]/16 en el interior y estos pesos junto a los extremos.
func _smooth_at(i: int, m: int) -> void:
	if i == 0 or i == m - 1 or m < 3:
		_sb[i] = _pb[i]
		_st[i] = _pt[i]
	elif _relax_passes < 2 or m < 5:
		_sb[i] = _pb[i - 1] * 0.25 + _pb[i] * 0.5 + _pb[i + 1] * 0.25
		_st[i] = _pt[i - 1] * 0.25 + _pt[i] * 0.5 + _pt[i + 1] * 0.25
	elif i == 1:
		_sb[i] = _pb[0] * 0.375 + _pb[1] * 0.3125 + _pb[2] * 0.25 + _pb[3] * 0.0625
		_st[i] = _pt[0] * 0.375 + _pt[1] * 0.3125 + _pt[2] * 0.25 + _pt[3] * 0.0625
	elif i == m - 2:
		_sb[i] = _pb[m - 1] * 0.375 + _pb[m - 2] * 0.3125 + _pb[m - 3] * 0.25 + _pb[m - 4] * 0.0625
		_st[i] = _pt[m - 1] * 0.375 + _pt[m - 2] * 0.3125 + _pt[m - 3] * 0.25 + _pt[m - 4] * 0.0625
	else:
		_sb[i] = (_pb[i - 2] + _pb[i + 2] + (_pb[i - 1] + _pb[i + 1]) * 4.0 + _pb[i] * 6.0) * 0.0625
		_st[i] = (_pt[i - 2] + _pt[i + 2] + (_pt[i - 1] + _pt[i + 1]) * 4.0 + _pt[i] * 6.0) * 0.0625

## ¿Pinta algo el shader en esta fila de la cinta? Mismo umbral que blade_trail.gdshader: la forma solo
## existe donde el campo (como mucho `ends`, el perfil a lo largo) supera el corte que sube con la edad.
func _visible(along: float, life: float) -> bool:
	var ends := minf(along / HEAD_RAMP, 1.0) * pow(1.0 - along, _tail_pow)
	return ends > CUT_MIN + (1.0 - life) * CUT_AGE

## Escribe la cinta en la malla, de la cabeza (muestra más nueva) a la cola, interpolando con Catmull-Rom.
## La cola invisible no se genera: a lo largo de la cinta el perfil baja y la edad sube, así que en cuanto
## una fila (pasada la cabeza) queda invisible, todas las siguientes también.
##
## Cada tramo entre dos muestras se subdivide según lo que recorrió la punta (SUBDIV_STEP, hasta _subdiv):
## un giro rápido sale curvo y la parte lenta no paga vértices de más. La curva de Catmull-Rom se pasa a
## polinomio una vez por tramo y se evalúa con Horner (3 multiplicaciones por punto).
func _build(m: int, life_now: float) -> void:
	var inv_len := 1.0 / float(m - 1)
	var band := _band_from
	var col := Color(1, 1, 1, 1)
	var uv := Vector2.ZERO
	var done := false
	_imesh.clear_surfaces()
	_imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in range(m - 1, 0, -1):
		if done:
			break
		var i0 := mini(i + 1, m - 1)
		var i3 := maxi(i - 2, 0)
		# Polinomio del tramo i -> i-1: p(k) = ((c3·k + c2)·k + c1)·k + c0
		var b0 := _sb[i0]; var b1 := _sb[i]; var b2 := _sb[i - 1]; var b3 := _sb[i3]
		var bc1 := (b2 - b0) * 0.5
		var bc2 := b0 - b1 * 2.5 + b2 * 2.0 - b3 * 0.5
		var bc3 := (b1 - b2) * 1.5 + (b3 - b0) * 0.5
		var t0 := _st[i0]; var t1 := _st[i]; var t2 := _st[i - 1]; var t3 := _st[i3]
		var tc1 := (t2 - t0) * 0.5
		var tc2 := t0 - t1 * 2.5 + t2 * 2.0 - t3 * 0.5
		var tc3 := (t1 - t2) * 1.5 + (t3 - t0) * 0.5
		var sub := clampi(ceili(t1.distance_to(t2) / SUBDIV_STEP), 1, _subdiv)
		var inv_sub := 1.0 / float(sub)
		var steps := sub + (1 if i == 1 else 0)         # el último tramo incluye la muestra más vieja
		var time_new := _ptime[i]
		var time_old := _ptime[i - 1]
		for s in steps:
			var k := float(s) * inv_sub
			var along := (float(m - 1 - i) + k) * inv_len  # 0 = cabeza (junto a la hoja) .. 1 = cola
			var a := clampf(1.0 - (_time - lerpf(time_new, time_old, k)) / life_now, 0.0, 1.0)
			if along > HEAD_RAMP and not _visible(along, a):
				# Una fila más (ya invisible) para cerrar la cola en el borde exacto, y fuera
				done = true
			var b := ((bc3 * k + bc2) * k + bc1) * k + b1
			var t := ((tc3 * k + tc2) * k + tc1) * k + t1
			# Se estrecha hacia la cola con una curva suave (la cola se cierra redondeada, sin pico)
			var w := lerpf(1.0, _tail, pow(along, _taper))
			var mid := (b + t) * 0.5
			var pt := mid + (t - mid) * w
			col.a = a
			uv.x = along
			# El lado del asta empieza donde el shader empieza a pintar (band_from), no en el asta
			uv.y = band
			_imesh.surface_set_color(col)
			_imesh.surface_set_uv(uv)
			_imesh.surface_add_vertex((mid + (b - mid) * w).lerp(pt, band))
			uv.y = 1.0
			_imesh.surface_set_color(col)
			_imesh.surface_set_uv(uv)
			_imesh.surface_add_vertex(pt)
			if done:
				break
	_imesh.surface_end()
	_drawn = true

static func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, k: float) -> Vector3:
	var k2 := k * k
	var k3 := k2 * k
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * k + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * k2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * k3)
