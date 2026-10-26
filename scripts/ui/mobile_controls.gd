extends CanvasLayer

## Controles táctiles: SOLO un joystick flotante (mover) y un botón de salto.
## - El joystick aparece donde se toca la mitad izquierda de la pantalla (si no se toca, descansa en
##   su sitio habitual); el botón de salto es fijo abajo a la derecha.
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
const COL_JUMP := Color(0.25, 0.85, 0.45)

var _overlay: Control
var _touch_available := false

var _joy_radius := 80.0
var _joy_rest := Vector2.ZERO          ## centro de reposo del joystick
var _joy_center := Vector2.ZERO        ## centro actual (flotante mientras se usa)
var _joy_offset := Vector2.ZERO        ## desplazamiento del pulgar, limitado al radio
var _joy_id := -1

var _jump_center := Vector2.ZERO
var _jump_radius := 56.0
var _jump_id := -1

var _look_id := -1
var _alpha := IDLE_ALPHA

func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	_touch_available = DisplayServer.is_touchscreen_available()

	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_controls)
	add_child(_overlay)

	get_viewport().size_changed.connect(_layout)
	visibility_changed.connect(func(): if not visible: _release_all())
	_layout()

func _exit_tree() -> void:
	_release_all()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_release_all()

# ───────────────────────────── Disposición ─────────────────────────────

func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	var shortest := minf(vp.x, vp.y)
	_joy_radius = clampf(shortest * 0.13, 56.0, 105.0)
	_jump_radius = clampf(shortest * 0.095, 42.0, 78.0)

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
	_jump_center = Vector2(vp.x - safe_r - EDGE_MARGIN - _jump_radius, vp.y - safe_b - EDGE_MARGIN - _jump_radius * 1.15)
	if _joy_id == -1:
		_joy_center = _joy_rest
		_joy_offset = Vector2.ZERO
	_overlay.queue_redraw()

# ───────────────────────────── Dibujo ─────────────────────────────

func _process(delta: float) -> void:
	# Pausa: soltar todo para que el personaje no siga corriendo al volver
	if get_tree().paused and (_joy_id != -1 or _jump_id != -1 or _look_id != -1):
		_release_all()
	var target := ACTIVE_ALPHA if (_joy_id != -1 or _jump_id != -1) else IDLE_ALPHA
	var new_alpha := lerpf(_alpha, target, minf(1.0, delta * 12.0))
	if absf(new_alpha - _alpha) > 0.003:
		_alpha = new_alpha
		_overlay.queue_redraw()

func _draw_controls() -> void:
	var a := _alpha
	# Joystick: base translúcida con aro y pulgar
	_overlay.draw_circle(_joy_center, _joy_radius, Color(COL_FILL.r, COL_FILL.g, COL_FILL.b, COL_FILL.a * a * 1.6))
	_overlay.draw_arc(_joy_center, _joy_radius, 0.0, TAU, 56, Color(COL_RING.r, COL_RING.g, COL_RING.b, COL_RING.a * a), 3.0, true)
	var knob_pos := _joy_center + _joy_offset
	var knob_r := _joy_radius * 0.45
	_overlay.draw_circle(knob_pos, knob_r, Color(COL_KNOB.r, COL_KNOB.g, COL_KNOB.b, COL_KNOB.a * a * 0.55))
	_overlay.draw_arc(knob_pos, knob_r, 0.0, TAU, 40, Color(1, 1, 1, a), 2.5, true)

	# Botón de salto: círculo verde con flecha hacia arriba; se aprieta al pulsarlo
	var pressed := _jump_id != -1
	var r := _jump_radius * (0.92 if pressed else 1.0)
	var fill := COL_JUMP.lightened(0.35) if pressed else COL_JUMP
	_overlay.draw_circle(_jump_center, r, Color(fill.r, fill.g, fill.b, 0.4 * a * 1.4))
	_overlay.draw_arc(_jump_center, r, 0.0, TAU, 48, Color(fill.r, fill.g, fill.b, a), 3.5, true)
	var k := r * 0.42
	var arrow := PackedVector2Array([
		_jump_center + Vector2(0, -k),
		_jump_center + Vector2(k, k * 0.55),
		_jump_center + Vector2(0, k * 0.1),
		_jump_center + Vector2(-k, k * 0.55),
	])
	_overlay.draw_colored_polygon(arrow, Color(1, 1, 1, a))

# ───────────────────────────── Entrada ─────────────────────────────

func _input(event: InputEvent) -> void:
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

func _on_press(idx: int, pos: Vector2, pressed: bool) -> void:
	if pressed:
		if _jump_id == -1 and pos.distance_to(_jump_center) <= _jump_radius * 1.25:
			_jump_id = idx
			VirtualInput.is_jumping = true
			_overlay.queue_redraw()
		elif _joy_id == -1 and _in_joystick_zone(pos):
			_joy_id = idx
			_joy_center = _clamp_to_screen(pos)
			_update_joystick(pos)
		elif _look_id == -1 and idx != _joy_id and idx != _jump_id:
			_look_id = idx
	else:
		if idx == _jump_id:
			_jump_id = -1
			VirtualInput.is_jumping = false
			_overlay.queue_redraw()
		elif idx == _joy_id:
			_joy_id = -1
			_joy_center = _joy_rest
			_joy_offset = Vector2.ZERO
			VirtualInput.movement_vector = Vector2.ZERO
			_overlay.queue_redraw()
		elif idx == _look_id:
			_look_id = -1

func _on_drag(idx: int, pos: Vector2, relative: Vector2) -> void:
	if idx == _joy_id:
		_update_joystick(pos)
	elif idx == _look_id:
		VirtualInput.look_vector = relative

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
	_jump_id = -1
	_look_id = -1
	_joy_center = _joy_rest
	_joy_offset = Vector2.ZERO
	VirtualInput.movement_vector = Vector2.ZERO
	VirtualInput.is_jumping = false
	if is_instance_valid(_overlay):
		_overlay.queue_redraw()
