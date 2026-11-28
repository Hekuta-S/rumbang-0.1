extends Node

## Mando en los menús (autoload). Godot trae ui_accept/ui_cancel solo con teclado: aquí se añaden A y B, así los
## botones enfocados se pueden pulsar. Además, si se toca el mando en un menú sin ningún control enfocado, se
## enfoca el primer botón visible (los menús nuevos no tienen que acordarse de hacerlo).
## No actúa durante la partida (jugador vivo sin pausa) ni en el salón explorando: ahí A es salto/usar.

const STICK_THRESHOLD := 0.6
const NAV_BUTTONS := [JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_A]

## true mientras el último dispositivo usado fue el mando (las pistas de la UI cambian a botones del mando).
static var _pad_active := false
## Familia del último mando tocado: "xbox", "nintendo" o "playstation" (decide qué letras salen en las pistas).
static var _family := "xbox"
static var _label_re: RegEx
## Se emite al cambiar de teclado a mando (o al revés) y también al cambiar de tipo de mando.
signal device_changed(pad: bool)

## Godot lee los botones por POSICIÓN (JOY_BUTTON_A = el de abajo). Lo que pone encima del botón cambia según
## el mando: en el Pro Controller de Nintendo el de abajo es la "B" y el de la derecha la "A".
const LABELS := {
	"xbox": {"A": "A", "B": "B", "X": "X", "Y": "Y", "LB": "LB", "RB": "RB", "LT": "LT", "RT": "RT",
		"L3": "L3", "R3": "R3", "START": "MENU", "BACK": "VISTA"},
	"nintendo": {"A": "B", "B": "A", "X": "Y", "Y": "X", "LB": "L", "RB": "R", "LT": "ZL", "RT": "ZR",
		"L3": "L3", "R3": "R3", "START": "+", "BACK": "-"},
	"playstation": {"A": "CRUZ", "B": "CIRCULO", "X": "CUADRADO", "Y": "TRIANGULO", "LB": "L1", "RB": "R1",
		"LT": "L2", "RT": "R2", "L3": "L3", "R3": "R3", "START": "OPTIONS", "BACK": "CREATE"},
}
const BUTTON_KEYS := {JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB", JOY_BUTTON_LEFT_STICK: "L3",
	JOY_BUTTON_RIGHT_STICK: "R3", JOY_BUTTON_START: "START", JOY_BUTTON_BACK: "BACK"}

var _stick_x := 0                      ## -1/0/1: dirección del stick izquierdo en X ya usada para mover el foco

var _toast_layer: CanvasLayer
var _toast: PanelContainer
var _toast_label: Label
var _toast_tween: Tween

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	install_actions()
	Input.joy_connection_changed.connect(_on_joy_changed)
	_pad_active = not Input.get_connected_joypads().is_empty()
	if _pad_active:
		_family = family_of(Input.get_joy_name(Input.get_connected_joypads()[0]))
		_show_toast.call_deferred("MANDO CONECTADO", Input.get_joy_name(Input.get_connected_joypads()[0]))

## ¿Se está jugando con mando? (hay uno conectado y fue lo último que se tocó)
static func using_pad() -> bool:
	return _pad_active and not Input.get_connected_joypads().is_empty()

## Etiqueta de pista: con mando devuelve `pad_label` (con las letras del mando conectado), si no `key_text`.
## Escribe `pad_label` con los nombres de Xbox (A, B, X, Y, LB, RB, LT, RT, L3, R3, START, BACK):
## GamepadUI.hint("E", "A") da "A" en Xbox, "B" en Nintendo y "CRUZ" en PlayStation.
static func hint(key_text: String, pad_label: String) -> String:
	return pad_text(pad_label) if using_pad() else key_text

## Familia de un mando por su nombre (Input.get_joy_name).
static func family_of(joy_name: String) -> String:
	var n := joy_name.to_lower()
	for k in ["nintendo", "switch", "pro controller", "joy-con", "joycon"]:
		if n.contains(k):
			return "nintendo"
	for k in ["playstation", "dualsense", "dualshock", "sony", "ps3", "ps4", "ps5", "wireless controller"]:
		if n.contains(k):
			return "playstation"
	return "xbox"

static func pad_family() -> String:
	return _family

## Lo que pone encima de un botón (JOY_BUTTON_*) en el mando actual. Ej.: JOY_BUTTON_A -> "B" en Nintendo.
static func button_label(button: int) -> String:
	return label_for(String(BUTTON_KEYS.get(button, "?")))

## `key` en nombres de Xbox ("A", "LB", "START"…) -> lo que pone en el mando actual (o en `family`).
static func label_for(key: String, family: String = "") -> String:
	var f := family if family != "" else _family
	return String((LABELS.get(f, LABELS["xbox"]) as Dictionary).get(key, key))

## Cambia en un texto los botones escritos al estilo Xbox por los del mando actual (en una sola pasada,
## para que A->B y B->A no se pisen). Solo palabras sueltas en mayúscula: "A: usar   B: salir".
static func pad_text(text: String, family: String = "") -> String:
	var f := family if family != "" else _family
	if f == "xbox":
		return text
	if _label_re == null:
		_label_re = RegEx.create_from_string("\\b(A|B|X|Y|LB|RB|LT|RT|L3|R3|START|BACK)\\b")
	var out := ""
	var last := 0
	for m in _label_re.search_all(text):
		out += text.substr(last, m.get_start() - last) + label_for(m.get_string(), f)
		last = m.get_end()
	return out + text.substr(last)

func _on_joy_changed(device: int, connected: bool) -> void:
	var pad_name := Input.get_joy_name(device)
	if connected:
		_set_family(family_of(pad_name))
		_set_pad(true)
		_show_toast("MANDO CONECTADO", pad_name)
	else:
		_set_pad(not Input.get_connected_joypads().is_empty())
		_show_toast("MANDO DESCONECTADO", pad_name)

func _set_pad(v: bool) -> void:
	if v != _pad_active:
		_pad_active = v
		device_changed.emit(v)

func _set_family(f: String) -> void:
	if f != _family:
		_family = f
		if _pad_active:
			device_changed.emit(true)     # las pistas se rehacen con las letras nuevas

## Letrero con borde de tinta arriba al centro; se desvanece solo.
func _show_toast(title: String, detail: String) -> void:
	if _toast == null:
		_toast_layer = CanvasLayer.new()
		_toast_layer.layer = 128
		_toast_layer.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(_toast_layer)
		_toast = PanelContainer.new()
		_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.07, 0.05, 0.1, 0.92)
		sb.border_color = Color(0.02, 0.0, 0.03)
		sb.set_border_width_all(4)
		sb.set_corner_radius_all(6)
		sb.shadow_color = Color(0, 0, 0, 0.7)
		sb.shadow_offset = Vector2(4, 4)
		sb.content_margin_left = 22
		sb.content_margin_right = 22
		sb.content_margin_top = 10
		sb.content_margin_bottom = 10
		_toast.add_theme_stylebox_override("panel", sb)
		_toast_label = Label.new()
		_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_toast_label.add_theme_font_size_override("font_size", 20)
		_toast_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.7))
		_toast_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		_toast_label.add_theme_constant_override("outline_size", 5)
		_toast.add_child(_toast_label)
		_toast_layer.add_child(_toast)
	var short := detail.substr(0, 28)
	_toast_label.text = "%s%s" % [title, ("\n" + short) if short != "" else ""]
	_toast.reset_size()
	var vw := _toast.get_viewport().get_visible_rect().size.x
	_toast.position = Vector2((vw - _toast.size.x) * 0.5, 18.0)
	_toast.modulate.a = 0.0
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast, "modulate:a", 1.0, 0.2)
	_toast_tween.tween_interval(2.6)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.6)

## Añade A a ui_accept y B a ui_cancel (una sola vez).
static func install_actions() -> void:
	_add_button("ui_accept", JOY_BUTTON_A)
	_add_button("ui_cancel", JOY_BUTTON_B)

static func _add_button(action: String, button: int) -> void:
	if not InputMap.has_action(action):
		return
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton and (e as InputEventJoypadButton).button_index == button:
			return
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)

## Stick izquierdo (o cruceta) como vector de movimiento para el salón. Con zona muerta radial.
static func stick_vector(deadzone: float = 0.25) -> Vector2:
	var v := Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
	if Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_LEFT):
		v.x = -1.0
	elif Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_RIGHT):
		v.x = 1.0
	if Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_UP):
		v.y = -1.0
	elif Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_DOWN):
		v.y = 1.0
	return Vector2.ZERO if v.length() < deadzone else v.limit_length(1.0)

func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5):
		_set_family(family_of(Input.get_joy_name(event.device)))
		_set_pad(true)
	elif event is InputEventKey or event is InputEventMouseButton:
		_set_pad(false)
	if _horizontal_nav(event):
		return
	var is_nav := false
	if event is InputEventJoypadButton and event.pressed:
		is_nav = NAV_BUTTONS.has((event as InputEventJoypadButton).button_index)
	elif event is InputEventJoypadMotion:
		var m := event as InputEventJoypadMotion
		is_nav = (m.axis == JOY_AXIS_LEFT_X or m.axis == JOY_AXIS_LEFT_Y) and absf(m.axis_value) > STICK_THRESHOLD
	if not is_nav or get_viewport().gui_get_focus_owner() != null or not _menu_is_open():
		return
	var target := first_focusable(get_tree().root)
	if target != null:
		target.grab_focus()
		get_viewport().set_input_as_handled()     # esta pulsación solo enfoca; la siguiente ya actúa

func _menu_is_open() -> bool:
	var tree := get_tree()
	if tree.paused:
		return true
	var scene := tree.current_scene
	if scene != null:
		var st = scene.get("state")                 # salón: solo con un panel abierto
		if st != null:
			return str(st) == "panel"
	return tree.get_first_node_in_group("player") == null

## Primer botón visible y enfocable, del CanvasLayer más alto (el menú que está encima).
static func first_focusable(root: Node) -> Control:
	var best: Control = null
	var best_layer := -INF
	for n in root.find_children("*", "BaseButton", true, false):
		var c := n as Control
		if c == null or c.focus_mode == Control.FOCUS_NONE or not c.is_visible_in_tree() or (n as BaseButton).disabled:
			continue
		var layer := 0.0
		var p: Node = c.get_parent()
		while p != null:
			if p is CanvasLayer:
				layer = float((p as CanvasLayer).layer)
				break
			p = p.get_parent()
		if best == null or layer > best_layer:
			best = c
			best_layer = layer
	return best

## Izquierda/derecha en los menús. La búsqueda de Godot elige el botón "más cercano" en esa dirección y, al
## final de una fila de cartas, saltaba al botón de abajo (SALIR, 🔒, VOLVER A TIRAR…). Aquí: si el botón
## enfocado tiene compañeros en su fila, se mueve solo por la fila y en el extremo se queda quieto; si está
## solo en su fila (lista vertical con un panel al lado), va al botón más cercano de ese lado.
## Respeta focus_neighbor_left/right puestos a mano y no toca sliders ni campos de texto.
## Devuelve true si consumió el evento.
func _horizontal_nav(event: InputEvent) -> bool:
	var dir := 0
	var stick := false
	if event is InputEventJoypadMotion and (event as InputEventJoypadMotion).axis == JOY_AXIS_LEFT_X:
		stick = true
		var v := (event as InputEventJoypadMotion).axis_value
		var now := 0
		if absf(v) >= STICK_THRESHOLD:
			now = 1 if v > 0.0 else -1
		elif absf(v) >= 0.35:
			now = _stick_x                 # zona intermedia: sin cambios (evita rebotes)
		if now != _stick_x:
			_stick_x = now
			dir = now
	elif event is InputEventKey or event is InputEventJoypadButton:
		if event.is_action_pressed("ui_right", true):
			dir = 1
		elif event.is_action_pressed("ui_left", true):
			dir = -1
		else:
			return false
	else:
		return false
	var focused := get_viewport().gui_get_focus_owner()
	if not (focused is BaseButton) or not _menu_is_open():
		return false
	var explicit: NodePath = focused.focus_neighbor_right if dir >= 0 else focused.focus_neighbor_left
	if not explicit.is_empty():
		return false                       # el menú decidió a dónde va: que lo haga Godot
	if dir != 0:
		var target := row_neighbor(focused, dir)
		if target != null:
			target.grab_focus()
	get_viewport().set_input_as_handled()  # con el stick, también los eventos sin cambio (no deja moverse a Godot)
	return true

## Botón al lado de `from` en la dirección `dir` (1 derecha, -1 izquierda), dentro de su mismo CanvasLayer.
## null = no hay (extremo de la fila).
static func row_neighbor(from: Control, dir: int) -> Control:
	var layer := _layer_of(from)
	var root: Node = layer if layer != null else from.get_tree().root
	var o := from.get_global_rect()
	var oc := o.get_center()
	var best_row: Control = null
	var best_row_d := INF
	var best_any: Control = null
	var best_any_d := INF
	var has_mates := false
	for n in root.find_children("*", "BaseButton", true, false):
		var c := n as Control
		if c == from or c.focus_mode == Control.FOCUS_NONE or not c.is_visible_in_tree() or _layer_of(c) != layer:
			continue
		var r := c.get_global_rect()
		var vov := minf(o.end.y, r.end.y) - maxf(o.position.y, r.position.y)
		var hov := minf(o.end.x, r.end.x) - maxf(o.position.x, r.position.x)
		var side := hov < 0.5 * minf(o.size.x, r.size.x)      # no está encima ni debajo
		var same_row := side and vov > 0.3 * minf(o.size.y, r.size.y)
		if same_row:
			has_mates = true
		var dx := (r.get_center().x - oc.x) * dir
		if dx <= 0.0 or not side:
			continue
		if same_row:
			var gap := (r.position.x - o.end.x) if dir > 0 else (o.position.x - r.end.x)
			var d := gap + absf(r.get_center().y - oc.y) * 0.5
			if d < best_row_d:
				best_row_d = d
				best_row = c
		else:
			var d2 := dx + absf(r.get_center().y - oc.y) * 2.0
			if d2 < best_any_d:
				best_any_d = d2
				best_any = c
	if best_row != null:
		return best_row
	return null if has_mates else best_any

static func _layer_of(c: Node) -> CanvasLayer:
	var p := c.get_parent()
	while p != null:
		if p is CanvasLayer:
			return p as CanvasLayer
		p = p.get_parent()
	return null
