class_name FloatingVitals
extends Control

## Escritorio: vida y recursos en vertical, flotando a la izquierda del personaje (no en una esquina).
## Sigue al personaje en pantalla con un muelle: al girar la cámara o al moverse se queda atrás, se ladea y
## vuelve a su sitio con un pequeño rebote. La altura acompaña al tamaño del personaje en pantalla.
## No guarda datos: los lee de VitalsPanel (vida, rastro, destellos) y de ResourceBars (energía, maná, balas),
## que en escritorio siguen existiendo como ancla de la disposición pero no dibujan nada.

const ANCHOR_UP := 0.95               ## altura del punto de anclaje sobre los pies (m)
const SIDE_M := 0.46                  ## separación hacia la izquierda de la cámara (m)
const SIDE_MIN_PX := 46.0             ## separación mínima en pantalla (cámara lejos)
const BODY_M := 1.5                   ## la barra mide lo que estos metros proyectados...
const H_MIN := 96.0                   ## ...entre estos límites (px)
const H_MAX := 190.0
const HP_W := 14.0
const EN_W := 7.0
const THIN_W := 4.0
const COL_GAP := 5.0
const PIP_GAP := 3.0
const STIFF := 150.0                  ## muelle: rigidez...
const DAMP := 15.0                    ## ...y amortiguación (por debajo de la crítica: rebota un poco)
const SWAY_CAM := 700.0               ## empujón (px/s) por radián de giro de la cámara
const SWAY_MOVE := 5.0                ## px de retraso por m/s del personaje
const SWAY_MAX := 70.0                ## separación máxima respecto a su sitio (px)
const TILT_MAX := 0.16                ## ladeo máximo (rad)
const EDGE := 30.0                    ## margen con los bordes de la pantalla

const HP_TOP := Color(0.6, 0.95, 0.44)
const HP_BOT := Color(0.25, 0.64, 0.23)
const TRAIL_COLOR := Color(0.95, 0.26, 0.2)
const HEAL_COLOR := Color(0.82, 1.0, 0.72)
const TICK := 25.0
const TICK_MAJOR := 100.0

var _vitals: VitalsPanel
var _bars: ResourceBars
var _player: Node3D
var _font: Font
var _plate: StyleBoxFlat
var _pos := Vector2.ZERO              ## posición actual (borde derecho de la barra de vida, centro vertical)
var _vel := Vector2.ZERO
var _tilt := 0.0
var _h := 140.0
var _prev_yaw := 0.0
var _prev_pitch := 0.0
var _placed := false                  ## ya tiene posición (la primera vez no hay muelle: aparece en su sitio)
var _on_screen := false
var _t := 0.0

func setup(vitals: VitalsPanel, bars: ResourceBars) -> void:
	_vitals = vitals
	_bars = bars

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_font = ThemeDB.fallback_font
	_plate = StyleBoxFlat.new()
	_plate.bg_color = Color(0.0, 0.0, 0.0, 0.6)
	_plate.set_corner_radius_all(5)
	_plate.shadow_color = Color(0, 0, 0, 0.28)
	_plate.shadow_size = 5

## Pura: sitio de la barra en pantalla. `center` y `side` son el personaje y el punto a su izquierda ya
## proyectados; `move` es su velocidad en pantalla (m/s, derecha y abajo positivos): la barra se queda atrás.
static func target_for(center: Vector2, side: Vector2, move: Vector2) -> Vector2:
	var t := side
	t.x = minf(t.x, center.x - SIDE_MIN_PX)
	return t - move.limit_length(8.0) * SWAY_MOVE

func screen_pos() -> Vector2:
	return _pos

func is_on_screen() -> bool:
	return _on_screen

func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	queue_redraw()
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	var cam := get_viewport().get_camera_3d()
	_on_screen = false
	if _player == null or cam == null:
		return
	var anchor := _player.global_position + Vector3.UP * ANCHOR_UP
	if cam.is_position_behind(anchor):
		_placed = false
		return
	_on_screen = true
	var right := cam.global_basis.x
	var up := cam.global_basis.y
	var v3: Vector3 = _player.velocity if _player is CharacterBody3D else Vector3.ZERO
	var target := target_for(cam.unproject_position(anchor), cam.unproject_position(anchor - right * SIDE_M),
		Vector2(v3.dot(right), -v3.dot(up)))
	var body := cam.unproject_position(anchor + up * BODY_M * 0.5).distance_to(cam.unproject_position(anchor - up * BODY_M * 0.5))
	var want_h := clampf(body, H_MIN, H_MAX)
	var yaw := cam.global_rotation.y
	var pitch := cam.global_rotation.x
	if not _placed:
		_placed = true
		_pos = target
		_vel = Vector2.ZERO
		_h = want_h
	else:
		var dt := minf(delta, 0.033)
		# Giro de la cámara: la barra se queda atrás (va con el mundo) y el muelle la devuelve
		_vel += Vector2(wrapf(yaw - _prev_yaw, -PI, PI), wrapf(pitch - _prev_pitch, -PI, PI)) * SWAY_CAM
		_vel += ((target - _pos) * STIFF - _vel * DAMP) * dt
		_pos += _vel * dt
		var off := _pos - target
		if off.length() > SWAY_MAX:
			_pos = target + off.limit_length(SWAY_MAX)
		_h = lerpf(_h, want_h, 1.0 - exp(-10.0 * delta))
	_prev_yaw = yaw
	_prev_pitch = pitch
	_tilt = lerpf(_tilt, clampf(_vel.x * 0.0009, -TILT_MAX, TILT_MAX), 1.0 - exp(-12.0 * delta))
	# Siempre dentro de la pantalla (deja sitio abajo para el número)
	var vp := get_viewport().get_visible_rect().size
	_pos.x = clampf(_pos.x, EDGE + 60.0, vp.x - EDGE)
	_pos.y = clampf(_pos.y, EDGE + _h * 0.5, vp.y - EDGE - 24.0 - _h * 0.5)

func _text(pos: Vector2, s: String, fs: int, color: Color, right_align: bool = true) -> float:
	var w := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var p := Vector2(pos.x - w, pos.y) if right_align else pos
	draw_string_outline(_font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.88))
	draw_string(_font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)
	return w

## Columna fina (maná, balas) que se llena de abajo arriba, con su número encima.
func _thin(x: float, top: float, h: float, ratio: float, color: Color, label: String, label_y: float) -> void:
	draw_rect(Rect2(x, top, THIN_W, h), Color(color.darkened(0.8), 0.9))
	ratio = clampf(ratio, 0.0, 1.0)
	if ratio > 0.001:
		draw_rect(Rect2(x, top + h * (1.0 - ratio), THIN_W, h * ratio), color)
	_text(Vector2(x + THIN_W, label_y), label, 10, color.lightened(0.3))

func _draw() -> void:
	if _vitals == null or not _on_screen:
		return
	var v := _vitals
	var jitter := Vector2.ZERO
	if v._shake > 0.0:
		jitter = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 5.0 * v._shake * v._shake
	draw_set_transform(_pos + jitter, _tilt)
	var low := v.is_low()
	var pulse := 0.5 + 0.5 * sin(_t * 9.0)
	var top_c := HP_TOP
	var bot_c := HP_BOT
	if low:
		top_c = VitalsPanel.HP_COLOR_LOW.lerp(Color(1.0, 0.55, 0.45), pulse)
		bot_c = VitalsPanel.HP_COLOR.darkened(0.25)
	top_c = top_c.lerp(HEAL_COLOR, v._heal_flash * 0.5)
	bot_c = bot_c.lerp(HP_TOP, v._heal_flash * 0.4)
	var accent := top_c.lerp(bot_c, 0.35)
	var h := _h
	var top := -h * 0.5
	var r := Rect2(-HP_W, top, HP_W, h)
	# Columnas de recursos (mazmorra), de dentro afuera: energía, maná, balas
	var res: PlayerResources = _bars._res if _bars and _bars.visible else null
	if res and not res.active:
		res = null
	var left := r.position.x
	var en_x := 0.0
	var thin_x: Array[float] = []
	if res:
		en_x = left - COL_GAP - EN_W
		left = en_x
		for shown: bool in [_bars._show_mana, _bars._show_ammo]:
			if shown:
				left -= COL_GAP + THIN_W
				thin_x.append(left)
	# Placa oscura redondeada con sombra: une las columnas y las separa del escenario
	var plate := Rect2(left, top, -left, h).grow(3.0)
	draw_style_box(_plate, plate)
	if low:
		draw_rect(plate, Color(1.0, 0.2, 0.15, 0.25 + 0.4 * pulse), false, 2.0)
	# Vida: canal, trozo de daño (destello blanco que queda en rojo), trozo de curación y relleno con degradado
	draw_rect(r, Color(accent.darkened(0.86), 0.92))
	var hp := v.hp_ratio()
	var disp: float = v._disp
	var trail := v.trail_ratio()
	if trail > hp:
		draw_rect(Rect2(r.position.x, r.end.y - h * trail, HP_W, h * (trail - hp)), TRAIL_COLOR.lerp(Color(1, 0.97, 0.9), v._hit_flash))
	if hp > disp + 0.0005:
		draw_rect(Rect2(r.position.x, r.end.y - h * hp, HP_W, h * (hp - disp)), Color(HEAL_COLOR, 0.9))
	if disp > 0.001:
		var f := Rect2(r.position.x, r.end.y - h * disp, HP_W, h * disp)
		draw_polygon(
			PackedVector2Array([f.position, Vector2(f.end.x, f.position.y), f.end, Vector2(f.position.x, f.end.y)]),
			PackedColorArray([top_c, bot_c, bot_c, top_c]))
		draw_rect(Rect2(f.position, Vector2(2.0, f.size.y)), Color(1, 1, 1, 0.28))                # filo de luz
		if disp < 0.999:
			draw_rect(Rect2(f.position, Vector2(f.size.x, 2.0)), Color(1, 1, 1, 0.6))             # borde de avance
	# Marcas: muescas cortas cada TICK y cortes de ancho completo cada TICK_MAJOR (hasta ~24 marcas)
	var max_hp: float = maxf(v._max_hp, 1.0)
	var tick := TICK
	while max_hp / tick > 24.0:
		tick *= 2.0
	var tv := tick
	while tv < max_hp - 0.5:
		var y := roundf(r.end.y - h * (tv / max_hp))
		if fmod(tv, TICK_MAJOR) < 0.5:
			draw_rect(Rect2(r.position.x, y - 1.0, HP_W, 2.0), Color(0, 0, 0, 0.6))
		else:
			draw_rect(Rect2(r.end.x - HP_W * 0.4, y - 0.5, HP_W * 0.4, 1.0), Color(0, 0, 0, 0.42))
		tv += tick
	# Energía: pips apilados (uno cada ENERGY_PIP puntos), se gastan de arriba abajo
	if res:
		var tired: bool = res.is_exhausted()
		var emax := maxf(res.energy_max(), 1.0)
		var n := maxi(1, int(ceil(emax / ResourceBars.ENERGY_PIP)))
		var pip_h := (h - PIP_GAP * (n - 1)) / n
		var ecol := _bars._flash_col(PlayerResources.Kind.ENERGY, ResourceBars.EXHAUSTED_COLOR if tired else ResourceBars.ENERGY_COLOR)
		for i in n:
			var py := r.end.y - (i + 1) * pip_h - i * PIP_GAP
			var lo := i * ResourceBars.ENERGY_PIP
			var fill := clampf((res.energy - lo) / minf(ResourceBars.ENERGY_PIP, emax - lo), 0.0, 1.0)
			draw_rect(Rect2(en_x, py, EN_W, pip_h), Color(ecol.darkened(0.8), 0.9))
			if fill > 0.001:
				# Pip lleno: brillante; pip a medias: más apagado (se está recargando)
				draw_rect(Rect2(en_x, py + pip_h * (1.0 - fill), EN_W, pip_h * fill), ecol if fill >= 0.999 else Color(ecol, 0.6))
				draw_rect(Rect2(en_x, py + pip_h * (1.0 - fill), 2.0, pip_h * fill), Color(1, 1, 1, 0.22))
		var k := 0
		var label_y := top - 8.0
		if _bars._show_mana:
			var mcol := _bars._flash_col(PlayerResources.Kind.MANA, ResourceBars.MANA_COLOR)
			_thin(thin_x[k], top, h, res.mana / res.mana_max(), mcol, "%d" % int(res.mana), label_y)
			k += 1
			label_y -= 12.0
		if _bars._show_ammo:
			var acol := _bars._flash_col(PlayerResources.Kind.AMMO, ResourceBars.AMMO_COLOR)
			var a := _bars._ammo_values()
			_thin(thin_x[k], top, h, float(a.x) / float(a.y) if a.y > 0 else 0.0, acol, "%d/%d" % [a.x, a.y] if a.y > 0 else "—", label_y)
	# Encima de la vida: regeneración ("+x.x", solo si hay y falta vida)
	if v._regen > 0.0 and hp < 1.0 and hp > 0.0:
		_text(Vector2(2.0, top - 8.0), "+%.1f" % v._regen, 10, HEAL_COLOR)
	# Debajo: cruz y vida actual en grande
	var fs := 18
	var base := r.end.y + 8.0 + fs * 0.75
	var num_col := VitalsPanel.HP_COLOR_LOW.lerp(Color.WHITE, 0.45 + 0.3 * pulse) if low else Color.WHITE
	var tw := _text(Vector2(3.0, base), str(int(ceil(v._hp))), fs, num_col)
	var cc := Vector2(3.0 - tw - 10.0, base - fs * 0.36)
	draw_rect(Rect2(cc.x - 2.5, cc.y - 6.5, 5.0, 13.0), Color(0, 0, 0, 0.85))
	draw_rect(Rect2(cc.x - 6.5, cc.y - 2.5, 13.0, 5.0), Color(0, 0, 0, 0.85))
	draw_rect(Rect2(cc.x - 1.5, cc.y - 5.5, 3.0, 11.0), accent)
	draw_rect(Rect2(cc.x - 5.5, cc.y - 1.5, 11.0, 3.0), accent)
