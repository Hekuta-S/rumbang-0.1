extends Node

## Mando en los menús (autoload). Godot trae ui_accept/ui_cancel solo con teclado: aquí se añaden A y B, así los
## botones enfocados se pueden pulsar. Además, si se toca el mando en un menú sin ningún control enfocado, se
## enfoca el primer botón visible (los menús nuevos no tienen que acordarse de hacerlo).
## No actúa durante la partida (jugador vivo sin pausa) ni en el salón explorando: ahí A es salto/usar.

const STICK_THRESHOLD := 0.6
const NAV_BUTTONS := [JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_A]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	install_actions()

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
