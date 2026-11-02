extends CanvasLayer

## Controles táctiles: joystick flotante (mover) + botones de acción.
## - El joystick aparece donde se toca la mitad izquierda de la pantalla (si no se toca, descansa en
##   su sitio habitual).
## - Botones abajo a la derecha: ATAQUE (grande, mantener = ataque continuo) rodeado de dos arcos:
##   SALTO, RODAR, ESPECIAL y FIJAR objetivo (arco interior); HABILIDAD, PARAR, RECARGAR y ARMA (arco exterior).
## - Cualquier otro dedo que arrastre mueve la cámara.
## - Respeta el área segura (muescas / barras del sistema) y se recoloca al cambiar el tamaño.
## - Suelta todo al pausar, al perder el foco o al ocultarse (nada se queda "pegado").

const DEAD_ZONE := 0.12
const EDGE_MARGIN := 28.0
const IDLE_ALPHA := 0.5
const ACTIVE_ALPHA := 0.95
const JOY_ZONE_WIDTH := 0.5        ## fracción izquierda de la pantalla donde nace el joystick
const JOY_ZONE_TOP := 0.2          ## no nace en el 20 % superior (HUD)

const COL_FILL := Color(0.05, 0.07, 0.12, 0.35)
const COL_RING := Color(0.85, 0.92, 1.0, 0.75)
const COL_KNOB := Color(0.85, 0.92, 1.0, 0.85)

## Botones de acción. mode: "hold" = activo mientras el dedo esté puesto; "tap" = un solo pulso.
## ring 0 = botón grande; 1 y 2 = arcos interior y exterior; angle en grados (270 = arriba, 180 = izquierda).
## Cada botón se dibuja con un icono vectorial (ver _draw_icon), sin texto.
const BUTTONS := [
	{"key": "attack", "name": "Ataque", "mode": "hold", "color": Color(1.0, 0.35, 0.3), "ring": 0, "angle": 0.0},
	{"key": "jump", "name": "Salto", "mode": "hold", "color": Color(0.25, 0.85, 0.45), "ring": 1, "angle": 176.0},
	{"key": "dodge", "name": "Rodar", "mode": "tap", "color": Color(0.35, 0.7, 1.0), "ring": 1, "angle": 214.0},
	{"key": "alt", "name": "Ataque especial", "mode": "hold", "color": Color(1.0, 0.6, 0.2), "ring": 1, "angle": 252.0},
	{"key": "target", "name": "Fijar objetivo", "mode": "tap", "color": Color(1.0, 0.3, 0.45), "ring": 1, "angle": 290.0},
	{"key": "skill", "name": "Habilidad", "mode": "tap", "color": Color(0.8, 0.45, 1.0), "ring": 2, "angle": 185.0},
	{"key": "parry", "name": "Parar", "mode": "tap", "color": Color(1.0, 0.9, 0.3), "ring": 2, "angle": 215.0},
	{"key": "reload", "name": "Recargar", "mode": "tap", "color": Color(0.6, 0.9, 0.9), "ring": 2, "angle": 245.0},
	{"key": "weapon", "name": "Cambiar arma", "mode": "tap", "color": Color(0.85, 0.85, 0.9), "ring": 2, "angle": 275.0},
]

## Editor de disposición: el joystick también se puede mover/escalar.
const JOY_KEY := "joystick"
const EDIT_SCALE_MIN := 0.5
const EDIT_SCALE_MAX := 2.0

var _overlay: Control
var _touch_available := false

var _joy_radius := 80.0
var _joy_rest := Vector2.ZERO          ## centro de reposo del joystick
var _joy_center := Vector2.ZERO        ## centro actual (flotante mientras se usa)
var _joy_offset := Vector2.ZERO        ## desplazamiento del pulgar, limitado al radio
var _joy_id := -1

var _btn_center: Array[Vector2] = []   ## centro de cada botón (mismo orden que BUTTONS)
var _btn_radius: Array[float] = []
var _btn_id: Array[int] = []           ## dedo que lo pulsa (-1 = libre)

var _look_id := -1
var _alpha := IDLE_ALPHA

# Editor de disposición
var _editing := false
var _edit_sel := ""                    ## clave seleccionada ("" = ninguna, JOY_KEY = joystick)
var _edit_drag_id := -1
var _edit_grab := Vector2.ZERO         ## desfase dedo → centro al empezar a arrastrar
var _edit_layer: CanvasLayer
var _edit_panel: PanelContainer
var _edit_title: Label
var _edit_slider: HSlider
var _edit_val: Label
var _edit_visible: CheckButton

func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("mobile_controls")
	SettingsManager.touch_edit_requested.connect(begin_edit)
	_touch_available = DisplayServer.is_touchscreen_available()
	VirtualInput.touch_ui_active = true
	for i in BUTTONS.size():
		_btn_center.append(Vector2.ZERO)
		_btn_radius.append(40.0)
		_btn_id.append(-1)

	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_controls)
	add_child(_overlay)

	get_viewport().size_changed.connect(_layout)
	SettingsManager.touch_layout_changed.connect(_on_settings_changed)
	visibility_changed.connect(func(): if not visible: _release_all())
	_layout()

## Tamaño, opacidad o visibilidad cambiados desde el menú de ajustes.
func _on_settings_changed() -> void:
	_release_all()
	_layout()

func _is_hidden(i: int) -> bool:
	return SettingsManager.touch_hidden.has(String(BUTTONS[i]["key"]))

func _exit_tree() -> void:
	if _editing:
		end_edit()
	VirtualInput.touch_ui_active = false
	_release_all()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_release_all()

# ───────────────────────────── Disposición ─────────────────────────────

func _layout() -> void:
	if _btn_center.is_empty():
		return
	var vp := get_viewport().get_visible_rect().size
	var shortest := minf(vp.x, vp.y)
	var k := SettingsManager.touch_scale
	_joy_radius = clampf(shortest * 0.13, 56.0, 105.0) * k
	var big_r := clampf(shortest * 0.115, 48.0, 92.0) * k
	var small_r := clampf(shortest * 0.058, 28.0, 48.0) * k

	# Área segura: márgenes extra en los bordes (muescas, barra de gestos...)
	var safe_l := 0.0
	var safe_r := 0.0
	var safe_b := 0.0
	var win := DisplayServer.window_get_size()
	var safe := DisplayServer.get_display_safe_area()
	if win.x > 0 and win.y > 0 and safe.size.x > 0:
		var sx := vp.x / float(win.x)
		var sy := vp.y / float(win.y)
		safe_l = maxf(0.0, float(safe.position.x) * sx)
		safe_r = maxf(0.0, float(win.x - safe.end.x) * sx)
		safe_b = maxf(0.0, float(win.y - safe.end.y) * sy)

	_joy_rest = Vector2(safe_l + EDGE_MARGIN + _joy_radius, vp.y - safe_b - EDGE_MARGIN - _joy_radius)
	var jc := _custom(JOY_KEY)
	if not jc.is_empty():
		_joy_radius *= _custom_scale(jc)
		var jm := _joy_radius + 4.0
		_joy_rest = Vector2(clampf(float(jc["x"]) * vp.x, jm, vp.x - jm), clampf(float(jc["y"]) * vp.y, jm, vp.y - jm))
	if _joy_id == -1:
		_joy_center = _joy_rest
		_joy_offset = Vector2.ZERO

	var origin := Vector2(vp.x - safe_r - EDGE_MARGIN - big_r, vp.y - safe_b - EDGE_MARGIN - big_r)
	var ring1 := big_r + small_r + 10.0
	var ring2 := ring1 + small_r * 2.0 + 8.0
	for i in BUTTONS.size():
		var b: Dictionary = BUTTONS[i]
		match int(b["ring"]):
			0:
				_btn_center[i] = origin
				_btn_radius[i] = big_r
			1:
				_btn_center[i] = origin + Vector2.from_angle(deg_to_rad(float(b["angle"]))) * ring1
				_btn_radius[i] = small_r
			_:
				_btn_center[i] = origin + Vector2.from_angle(deg_to_rad(float(b["angle"]))) * ring2
				_btn_radius[i] = small_r
		# Disposición personalizada (posición y tamaño elegidos por el jugador)
		var bc := _custom(String(b["key"]))
		if not bc.is_empty():
			_btn_radius[i] *= _custom_scale(bc)
			_btn_center[i] = Vector2(float(bc["x"]) * vp.x, float(bc["y"]) * vp.y)
		# Que ningún botón se salga de la pantalla
		_btn_center[i].x = clampf(_btn_center[i].x, _btn_radius[i] + 4.0, vp.x - _btn_radius[i] - 4.0)
		_btn_center[i].y = clampf(_btn_center[i].y, _btn_radius[i] + 4.0, vp.y - _btn_radius[i] - 4.0)
	_overlay.queue_redraw()

func _custom(key: String) -> Dictionary:
	var c: Variant = SettingsManager.touch_custom.get(key)
	if c is Dictionary and c.has("x") and c.has("y"):
		return c
	return {}

func _custom_scale(c: Dictionary) -> float:
	return clampf(float(c.get("s", 1.0)), EDIT_SCALE_MIN, EDIT_SCALE_MAX)

# ───────────────────────────── Dibujo ─────────────────────────────

func _any_button_down() -> bool:
	for id in _btn_id:
		if id != -1:
			return true
	return false

func _process(delta: float) -> void:
	# Pausa: soltar todo para que el personaje no siga corriendo al volver
	if get_tree().paused and (_joy_id != -1 or _any_button_down() or _look_id != -1):
		_release_all()
	var target := ACTIVE_ALPHA if (_joy_id != -1 or _any_button_down()) else IDLE_ALPHA
	var new_alpha := lerpf(_alpha, target, minf(1.0, delta * 12.0))
	if absf(new_alpha - _alpha) > 0.003:
		_alpha = new_alpha
		_overlay.queue_redraw()

func _draw_controls() -> void:
	var a := _alpha * SettingsManager.touch_opacity
	if _editing:
		a = 1.0
		_overlay.draw_rect(Rect2(Vector2.ZERO, _overlay.size), Color(0.02, 0.02, 0.06, 0.82))
	# Joystick: base translúcida con aro y pulgar
	_overlay.draw_circle(_joy_center, _joy_radius, Color(COL_FILL.r, COL_FILL.g, COL_FILL.b, COL_FILL.a * a * 1.6))
	_overlay.draw_arc(_joy_center, _joy_radius, 0.0, TAU, 56, Color(COL_RING.r, COL_RING.g, COL_RING.b, COL_RING.a * a), 3.0, true)
	var knob_pos := _joy_center + _joy_offset
	var knob_r := _joy_radius * 0.45
	_overlay.draw_circle(knob_pos, knob_r, Color(COL_KNOB.r, COL_KNOB.g, COL_KNOB.b, COL_KNOB.a * a * 0.55))
	_overlay.draw_arc(knob_pos, knob_r, 0.0, TAU, 40, Color(1, 1, 1, a), 2.5, true)

	# Botones de acción: círculo de color con icono; se aprietan al pulsarlos
	for i in BUTTONS.size():
		var hidden := _is_hidden(i)
		if hidden and not _editing:
			continue
		var b: Dictionary = BUTTONS[i]
		var pressed := _btn_id[i] != -1
		var c: Vector2 = _btn_center[i]
		var r: float = _btn_radius[i] * (0.92 if pressed else 1.0)
		var base: Color = b["color"]
		var fill := base.lightened(0.35) if pressed else base
		var ba := a * (0.35 if hidden else 1.0)   # en el editor, los ocultos salen apagados
		_overlay.draw_circle(c, r, Color(fill.r, fill.g, fill.b, 0.4 * ba * 1.4))
		_overlay.draw_arc(c, r, 0.0, TAU, 48, Color(fill.r, fill.g, fill.b, ba), 3.5, true)
		_draw_icon(String(b["key"]), c, r, Color(1, 1, 1, ba))
		if _editing and b["key"] == _edit_sel:
			_draw_selection(c, r)
	if _editing and _edit_sel == JOY_KEY:
		_draw_selection(_joy_center, _joy_radius)

func _draw_selection(c: Vector2, r: float) -> void:
	_overlay.draw_arc(c, r + 9.0, 0.0, TAU, 64, Color(1, 0.95, 0.35, 0.95), 3.0, true)
	for k in 4:
		var dir := Vector2.from_angle(PI * 0.25 + k * PI * 0.5)
		_overlay.draw_circle(c + dir * (r + 9.0), 4.0, Color(1, 0.95, 0.35, 0.95))

# ───────────────────────────── Iconos ─────────────────────────────

## Icono vectorial centrado en c; r = radio del botón.
func _draw_icon(key: String, c: Vector2, r: float, col: Color) -> void:
	var u := r * 0.5
	var w := maxf(2.5, r * 0.1)
	var o := _overlay
	match key:
		"attack":   # espada en diagonal con guarda
			o.draw_line(c + Vector2(-0.75, 0.75) * u, c + Vector2(0.8, -0.8) * u, col, w * 1.6, true)
			var perp := Vector2(1, 1).normalized() * u * 0.5
			var guard := c + Vector2(-0.2, 0.2) * u
			o.draw_line(guard - perp, guard + perp, col, w * 1.4, true)
			o.draw_circle(c + Vector2(-0.8, 0.8) * u, w * 1.1, col)
		"jump":     # flecha de salto
			var k := u * 0.9
			o.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -k), c + Vector2(k, k * 0.55), c + Vector2(0, k * 0.1), c + Vector2(-k, k * 0.55),
			]), col)
		"dodge":    # dos chevrones hacia delante (impulso)
			for dx in [-0.5, 0.25]:
				o.draw_polyline(PackedVector2Array([
					c + Vector2(dx * u, -0.7 * u), c + Vector2((dx + 0.6) * u, 0.0), c + Vector2(dx * u, 0.7 * u),
				]), col, w * 1.3, true)
		"alt":      # destello de 4 puntas
			var pts := PackedVector2Array()
			for k in 8:
				var rad := u * (0.95 if k % 2 == 0 else 0.3)
				pts.append(c + Vector2.from_angle(-PI * 0.5 + k * PI * 0.25) * rad)
			o.draw_colored_polygon(pts, col)
		"target":   # mira
			o.draw_arc(c, u * 0.6, 0.0, TAU, 32, col, w, true)
			for k in 4:
				var d := Vector2.from_angle(k * PI * 0.5)
				o.draw_line(c + d * u * 0.4, c + d * u * 1.05, col, w, true)
			o.draw_circle(c, w * 0.9, col)
		"skill":    # rayo
			o.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0.2, -1.0) * u, c + Vector2(-0.55, 0.1) * u, c + Vector2(-0.05, 0.1) * u,
				c + Vector2(-0.25, 1.0) * u, c + Vector2(0.55, -0.2) * u, c + Vector2(0.05, -0.2) * u,
			]), col)
		"parry":    # escudo
			var shield := PackedVector2Array([
				c + Vector2(-0.8, -0.75) * u, c + Vector2(0.0, -0.95) * u, c + Vector2(0.8, -0.75) * u,
				c + Vector2(0.75, 0.15) * u, c + Vector2(0.0, 1.0) * u, c + Vector2(-0.75, 0.15) * u,
			])
			o.draw_colored_polygon(shield, Color(col.r, col.g, col.b, col.a * 0.35))
			var outline := shield.duplicate()
			outline.append(shield[0])
			o.draw_polyline(outline, col, w, true)
		"reload":   # flecha circular
			var rad := u * 0.7
			var end_a := deg_to_rad(230.0)
			o.draw_arc(c, rad, deg_to_rad(-60.0), end_a, 28, col, w * 1.3, true)
			var p := c + Vector2.from_angle(end_a) * rad
			var tangent := Vector2(-sin(end_a), cos(end_a))
			var normal := Vector2.from_angle(end_a)
			o.draw_colored_polygon(PackedVector2Array([
				p + tangent * u * 0.6, p + normal * u * 0.4, p - normal * u * 0.4,
			]), col)
		"weapon":   # intercambio: dos flechas opuestas
			_draw_arrow(c + Vector2(-0.8, -0.38) * u, c + Vector2(0.8, -0.38) * u, u * 0.4, w * 1.3, col)
			_draw_arrow(c + Vector2(0.8, 0.38) * u, c + Vector2(-0.8, 0.38) * u, u * 0.4, w * 1.3, col)

func _draw_arrow(from: Vector2, to: Vector2, head: float, w: float, col: Color) -> void:
	var dir := (to - from).normalized()
	var side := Vector2(-dir.y, dir.x)
	_overlay.draw_line(from, to, col, w, true)
	_overlay.draw_polyline(PackedVector2Array([to - dir * head + side * head, to, to - dir * head - side * head]), col, w, true)

# ───────────────────────────── Entrada ─────────────────────────────

func _input(event: InputEvent) -> void:
	if _editing:
		_edit_input(event)
		return
	if not visible or get_tree().paused:
		return

	if event is InputEventScreenTouch:
		_on_press(event.index, event.position, event.pressed)
	elif event is InputEventScreenDrag:
		_on_drag(event.index, event.position, event.relative)
	elif not _touch_available:
		# Pruebas en PC con el ratón (en un móvil el toque ya llega como InputEventScreenTouch)
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			_on_press(0, event.position, event.pressed)
		elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			_on_drag(0, event.position, event.relative)

## Botón más cercano cuyo radio táctil contiene el punto. Elegir el MÁS CERCANO (no el primero del
## array) evita que las zonas ampliadas de los botones vecinos se roben los toques: antes, un toque en
## el borde de FIJAR podía caer en la zona de ATAQUE ESPECIAL y no fijaba a nadie.
func _button_at(pos: Vector2) -> int:
	var best := -1
	var best_d := INF
	for i in BUTTONS.size():
		if _btn_id[i] != -1 or _is_hidden(i):
			continue
		var d := pos.distance_to(_btn_center[i])
		if d <= _btn_radius[i] * 1.2 and d < best_d:
			best_d = d
			best = i
	return best

func _on_press(idx: int, pos: Vector2, pressed: bool) -> void:
	if pressed:
		var bi := _button_at(pos)
		if bi != -1:
			_btn_id[bi] = idx
			_set_button(bi, true)
			_overlay.queue_redraw()
		elif _joy_id == -1 and _in_joystick_zone(pos):
			_joy_id = idx
			_joy_center = _clamp_to_screen(pos)
			_update_joystick(pos)
		elif _look_id == -1 and idx != _joy_id and not _btn_id.has(idx):
			_look_id = idx
	else:
		var bi := _btn_id.find(idx)
		if bi != -1:
			_btn_id[bi] = -1
			_set_button(bi, false)
			_overlay.queue_redraw()
		elif idx == _joy_id:
			_joy_id = -1
			_joy_center = _joy_rest
			_joy_offset = Vector2.ZERO
			VirtualInput.movement_vector = Vector2.ZERO
			_overlay.queue_redraw()
		elif idx == _look_id:
			_look_id = -1

## Traduce el estado de un botón a VirtualInput.
func _set_button(bi: int, down: bool) -> void:
	match String(BUTTONS[bi]["key"]):
		"attack": VirtualInput.is_attacking = down
		"jump": VirtualInput.is_jumping = down
		"alt": VirtualInput.is_alt_attack = down
		"skill": VirtualInput.just_pressed_skill = down or VirtualInput.just_pressed_skill
		"reload": VirtualInput.just_pressed_reload = down or VirtualInput.just_pressed_reload
		"dodge": VirtualInput.just_pressed_dodge = down or VirtualInput.just_pressed_dodge
		"parry": VirtualInput.just_pressed_parry = down or VirtualInput.just_pressed_parry
		"weapon": VirtualInput.just_pressed_cycle_next = down or VirtualInput.just_pressed_cycle_next
		"target": VirtualInput.just_pressed_target = down or VirtualInput.just_pressed_target

func _on_drag(idx: int, pos: Vector2, relative: Vector2) -> void:
	if idx == _joy_id:
		_update_joystick(pos)
	elif idx == _look_id:
		VirtualInput.look_vector += relative
	elif VirtualInput.attack_aims and _attack_button_id() == idx:
		# Apuntando con el botón de disparo: el mismo dedo mueve la mira
		VirtualInput.look_vector += relative

func _attack_button_id() -> int:
	for i in BUTTONS.size():
		if String(BUTTONS[i]["key"]) == "attack":
			return _btn_id[i]
	return -1

func _in_joystick_zone(pos: Vector2) -> bool:
	var vp := get_viewport().get_visible_rect().size
	return pos.x < vp.x * JOY_ZONE_WIDTH and pos.y > vp.y * JOY_ZONE_TOP

## Evita que el joystick flotante nazca cortado por el borde de la pantalla.
func _clamp_to_screen(pos: Vector2) -> Vector2:
	var vp := get_viewport().get_visible_rect().size
	var m := _joy_radius + 8.0
	return Vector2(clampf(pos.x, m, vp.x - m), clampf(pos.y, m, vp.y - m))

func _update_joystick(pos: Vector2) -> void:
	var off := pos - _joy_center
	if off.length() > _joy_radius:
		off = off.normalized() * _joy_radius
	_joy_offset = off
	var n := off / _joy_radius
	var mag := n.length()
	if mag < DEAD_ZONE:
		VirtualInput.movement_vector = Vector2.ZERO
	else:
		# Zona muerta reescalada para que el movimiento arranque suave desde 0
		VirtualInput.movement_vector = n.normalized() * ((mag - DEAD_ZONE) / (1.0 - DEAD_ZONE))
	_overlay.queue_redraw()

func _release_all() -> void:
	_joy_id = -1
	_look_id = -1
	for i in _btn_id.size():
		_btn_id[i] = -1
	_joy_center = _joy_rest
	_joy_offset = Vector2.ZERO
	VirtualInput.movement_vector = Vector2.ZERO
	VirtualInput.is_jumping = false
	VirtualInput.is_attacking = false
	VirtualInput.is_alt_attack = false
	if is_instance_valid(_overlay):
		_overlay.queue_redraw()

# ───────────────────────────── Editor de disposición ─────────────────────────────
## Se abre desde Ajustes → Controles táctiles. Tocar un botón (o el joystick) lo selecciona; arrastrarlo
## lo mueve; el deslizador cambia su tamaño; "Visible" lo muestra/oculta. Funciona con el juego en pausa.

func begin_edit() -> void:
	if _editing:
		return
	_release_all()
	_editing = true
	_edit_sel = ""
	_edit_drag_id = -1
	layer = 125
	_build_edit_panel()
	_refresh_edit_panel()
	_overlay.queue_redraw()

func end_edit() -> void:
	if not _editing:
		return
	_editing = false
	layer = 50
	if is_instance_valid(_edit_layer):
		_edit_layer.queue_free()
	_edit_layer = null
	_edit_panel = null
	SettingsManager.save_settings()
	_layout()
	SettingsManager.touch_edit_finished.emit()

func _key_index(key: String) -> int:
	for i in BUTTONS.size():
		if String(BUTTONS[i]["key"]) == key:
			return i
	return -1

func _edit_center(key: String) -> Vector2:
	return _joy_rest if key == JOY_KEY else _btn_center[_key_index(key)]

func _edit_radius(key: String) -> float:
	return _joy_radius if key == JOY_KEY else _btn_radius[_key_index(key)]

func _edit_name(key: String) -> String:
	return "Joystick" if key == JOY_KEY else String(BUTTONS[_key_index(key)]["name"])

## Elemento bajo el dedo (botones antes que el joystick); "" si no hay.
func _edit_hit(pos: Vector2) -> String:
	var best := ""
	var best_d := INF
	for i in BUTTONS.size():
		var d := pos.distance_to(_btn_center[i])
		if d <= _btn_radius[i] * 1.15 and d < best_d:
			best = String(BUTTONS[i]["key"])
			best_d = d
	if best == "" and pos.distance_to(_joy_rest) <= _joy_radius * 1.1:
		return JOY_KEY
	return best

func _edit_over_panel(pos: Vector2) -> bool:
	return is_instance_valid(_edit_panel) and _edit_panel.get_global_rect().has_point(pos)

func _edit_input(event: InputEvent) -> void:
	var consumed := false
	if event is InputEventScreenTouch:
		consumed = _edit_press(event.index, event.position, event.pressed)
	elif event is InputEventScreenDrag:
		consumed = _edit_drag(event.index, event.position)
	elif not _touch_available:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			consumed = _edit_press(0, event.position, event.pressed)
		elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			consumed = _edit_drag(0, event.position)
	if consumed:
		get_viewport().set_input_as_handled()

func _edit_press(idx: int, pos: Vector2, pressed: bool) -> bool:
	if pressed:
		if _edit_over_panel(pos):
			return false
		_edit_sel = _edit_hit(pos)
		if _edit_sel != "" and _edit_drag_id == -1:
			_edit_drag_id = idx
			_edit_grab = _edit_center(_edit_sel) - pos
		_refresh_edit_panel()
		_overlay.queue_redraw()
		return true
	if idx == _edit_drag_id:
		_edit_drag_id = -1
		SettingsManager.save_settings()
		_place_edit_panel()
		return true
	return false

func _edit_drag(idx: int, pos: Vector2) -> bool:
	if idx != _edit_drag_id or _edit_sel == "":
		return false
	var vp := get_viewport().get_visible_rect().size
	var r := _edit_radius(_edit_sel) + 4.0
	var target := pos + _edit_grab
	target = Vector2(clampf(target.x, r, vp.x - r), clampf(target.y, r, vp.y - r))
	_store_custom(_edit_sel, target, _selected_scale())
	_layout()
	return true

func _selected_scale() -> float:
	var c := _custom(_edit_sel)
	return 1.0 if c.is_empty() else _custom_scale(c)

func _store_custom(key: String, center: Vector2, s: float) -> void:
	var vp := get_viewport().get_visible_rect().size
	SettingsManager.touch_custom[key] = {"x": center.x / vp.x, "y": center.y / vp.y, "s": s}

func _build_edit_panel() -> void:
	_edit_layer = CanvasLayer.new()
	_edit_layer.layer = 130
	add_child(_edit_layer)
	_edit_panel = PanelContainer.new()
	_edit_panel.theme = RumbangStyle.get_theme()
	_edit_layer.add_child(_edit_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	_edit_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(340, 0)
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)

	_edit_title = Label.new()
	_edit_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_edit_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_edit_title.add_theme_color_override("font_color", RumbangStyle.NEON_CYAN)
	box.add_child(_edit_title)

	var size_row := HBoxContainer.new()
	box.add_child(size_row)
	var size_lbl := Label.new()
	size_lbl.text = "Tamaño"
	size_lbl.custom_minimum_size = Vector2(70, 0)
	size_row.add_child(size_lbl)
	_edit_slider = HSlider.new()
	_edit_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_edit_slider.min_value = EDIT_SCALE_MIN
	_edit_slider.max_value = EDIT_SCALE_MAX
	_edit_slider.step = 0.05
	_edit_slider.value = 1.0
	_edit_slider.value_changed.connect(_on_edit_scale)
	_edit_slider.drag_ended.connect(func(_changed: bool): SettingsManager.save_settings())
	size_row.add_child(_edit_slider)
	_edit_val = Label.new()
	_edit_val.custom_minimum_size = Vector2(52, 0)
	size_row.add_child(_edit_val)

	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 8)
	box.add_child(row1)
	_edit_visible = CheckButton.new()
	_edit_visible.text = "Visible"
	_edit_visible.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit_visible.toggled.connect(_on_edit_visible)
	row1.add_child(_edit_visible)
	var reset_one := Button.new()
	reset_one.text = "Restablecer botón"
	reset_one.pressed.connect(_on_edit_reset_one)
	row1.add_child(reset_one)

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	box.add_child(row2)
	var reset_all := Button.new()
	reset_all.text = "Restablecer todo"
	reset_all.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset_all.pressed.connect(_on_edit_reset_all)
	row2.add_child(reset_all)
	var done := Button.new()
	done.text = "Listo"
	done.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	done.pressed.connect(end_edit)
	row2.add_child(done)

func _refresh_edit_panel() -> void:
	if _edit_panel == null:
		return
	var has := _edit_sel != ""
	_edit_title.text = _edit_name(_edit_sel) if has else "Toca un botón para editarlo; arrástralo para moverlo"
	_edit_slider.editable = has
	_edit_visible.disabled = (not has) or _edit_sel == JOY_KEY
	var s := _selected_scale() if has else 1.0
	_edit_slider.set_value_no_signal(s)
	_edit_val.text = "×%.2f" % s
	_edit_visible.set_pressed_no_signal(not (has and SettingsManager.touch_hidden.has(_edit_sel)))
	_place_edit_panel()

## El panel se coloca en la mitad contraria a la del elemento seleccionado para no taparlo.
func _place_edit_panel() -> void:
	if _edit_panel == null:
		return
	_edit_panel.reset_size()
	var vp := get_viewport().get_visible_rect().size
	var sz := _edit_panel.get_combined_minimum_size()
	var at_bottom := _edit_sel != "" and _edit_center(_edit_sel).y < vp.y * 0.5
	_edit_panel.position = Vector2((vp.x - sz.x) * 0.5, vp.y - sz.y - 12.0 if at_bottom else 12.0)

func _on_edit_scale(v: float) -> void:
	if _edit_sel == "":
		return
	_store_custom(_edit_sel, _edit_center(_edit_sel), v)
	_edit_val.text = "×%.2f" % v
	_layout()

func _on_edit_visible(on: bool) -> void:
	if _edit_sel == "" or _edit_sel == JOY_KEY:
		return
	if on:
		SettingsManager.touch_hidden.erase(_edit_sel)
	elif not SettingsManager.touch_hidden.has(_edit_sel):
		SettingsManager.touch_hidden.append(_edit_sel)
	SettingsManager.save_settings()
	_overlay.queue_redraw()

func _on_edit_reset_one() -> void:
	if _edit_sel == "":
		return
	SettingsManager.touch_custom.erase(_edit_sel)
	SettingsManager.touch_hidden.erase(_edit_sel)
	SettingsManager.save_settings()
	_layout()
	_refresh_edit_panel()

func _on_edit_reset_all() -> void:
	SettingsManager.touch_custom.clear()
	SettingsManager.touch_hidden = []
	SettingsManager.save_settings()
	_layout()
	_refresh_edit_panel()
