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
## Rendimiento: las muestras van en arrays empaquetados que se reutilizan (ninguna asignación por frame), la
## cinta se escribe directamente en la malla y el nodo deja de procesarse cuando no queda nada que dibujar.

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
# Copias de trabajo del suavizado (se reutilizan)
var _sb := PackedVector3Array()
var _st := PackedVector3Array()
var _sb2 := PackedVector3Array()
var _st2 := PackedVector3Array()
var _emit_left: float = 0.0
var _time: float = 0.0
var _power := 1.0                      ## fuerza del golpe en curso (más brillo y algo más de cola)
var _drawn := false
var _imesh := ImmediateMesh.new()
var _mat: ShaderMaterial

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

## Suavizado laplaciano en las copias de trabajo: quita los picos de un giro brusco de la hoja entre dos
## muestras (cada una se acerca a la media de sus vecinas; los extremos no se mueven).
func _relax(m: int) -> void:
	_sb.resize(m)
	_st.resize(m)
	for i in m:
		_sb[i] = _pb[i]
		_st[i] = _pt[i]
	if m < 3:
		return
	_sb2.resize(m)
	_st2.resize(m)
	for _p in _relax_passes:
		_sb2[0] = _sb[0]
		_st2[0] = _st[0]
		_sb2[m - 1] = _sb[m - 1]
		_st2[m - 1] = _st[m - 1]
		for i in range(1, m - 1):
			_sb2[i] = _sb[i - 1] * 0.25 + _sb[i] * 0.5 + _sb[i + 1] * 0.25
			_st2[i] = _st[i - 1] * 0.25 + _st[i] * 0.5 + _st[i + 1] * 0.25
		var swap_b := _sb
		_sb = _sb2
		_sb2 = swap_b
		var swap_t := _st
		_st = _st2
		_st2 = swap_t

## Escribe la cinta en la malla, de la cabeza (muestra más nueva) a la cola, interpolando con Catmull-Rom.
func _build(m: int, life_now: float) -> void:
	var total := (m - 1) * _subdiv + 1
	var inv_total := 1.0 / float(total - 1)
	var inv_sub := 1.0 / float(_subdiv)
	var col := Color(1, 1, 1, 1)
	var uv := Vector2.ZERO
	var idx := 0
	_imesh.clear_surfaces()
	_imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in range(m - 1, 0, -1):
		var i0 := mini(i + 1, m - 1)
		var i3 := maxi(i - 2, 0)
		var steps := _subdiv + (1 if i == 1 else 0)     # el último tramo incluye la muestra más vieja
		for s in steps:
			var k := float(s) * inv_sub
			var b := _catmull(_sb[i0], _sb[i], _sb[i - 1], _sb[i3], k)
			var t := _catmull(_st[i0], _st[i], _st[i - 1], _st[i3], k)
			var along := float(idx) * inv_total          # 0 = cabeza (junto a la hoja) .. 1 = cola
			idx += 1
			col.a = clampf(1.0 - (_time - lerpf(_ptime[i], _ptime[i - 1], k)) / life_now, 0.0, 1.0)
			# Se estrecha hacia la cola con una curva suave (la cola se cierra redondeada, sin pico)
			var w := lerpf(1.0, _tail, pow(along, _taper))
			var mid := (b + t) * 0.5
			uv.x = along
			uv.y = 0.0
			_imesh.surface_set_color(col)
			_imesh.surface_set_uv(uv)
			_imesh.surface_add_vertex(mid + (b - mid) * w)
			uv.y = 1.0
			_imesh.surface_set_color(col)
			_imesh.surface_set_uv(uv)
			_imesh.surface_add_vertex(mid + (t - mid) * w)
	_imesh.surface_end()
	_drawn = true

static func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, k: float) -> Vector3:
	var k2 := k * k
	var k3 := k2 * k
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * k + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * k2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * k3)
