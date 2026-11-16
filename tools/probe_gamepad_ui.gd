extends Node
## Sonda: abre un menú, simula el mando (cruceta abajo/derecha y botón A) y dice qué control tiene el foco y si
## el botón enfocado recibe la pulsación. Uso: Godot --headless --path . res://tools/probe_gamepad_ui.tscn -- <escena.tscn>

func _joy(btn: int, down: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.device = 0
	e.button_index = btn
	e.pressed = down
	e.pressure = 1.0 if down else 0.0
	Input.parse_input_event(e)

func _tap(btn: int) -> void:
	_joy(btn, true)
	await get_tree().process_frame
	await get_tree().process_frame
	_joy(btn, false)
	await get_tree().process_frame
	await get_tree().process_frame

func _focus_desc() -> String:
	var f := get_viewport().gui_get_focus_owner()
	if f == null:
		return "<sin foco>"
	var txt := ""
	if f is Button:
		txt = (f as Button).text
	return "%s '%s' (%s) path=%s" % [f.get_class(), txt, f.name, str(f.get_path()).right(70)]

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var path: String = args[0] if args.size() > 0 else "res://scenes/ui/main_menu.tscn"
	var scene: Node = (load(path) as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(scene)
	await get_tree().create_timer(float(args[1]) if args.size() > 1 else 1.5).timeout
	get_tree().current_scene = scene
	var buttons := get_tree().root.find_children("*", "BaseButton", true, false)
	var vis := buttons.filter(func(b): return (b as Control).is_visible_in_tree())
	var focusable := vis.filter(func(b): return (b as Control).focus_mode != Control.FOCUS_NONE)
	print("PROBE %s: botones visibles=%d, enfocables=%d" % [path, vis.size(), focusable.size()])
	print("  foco inicial: ", _focus_desc())
	var pressed_log := []
	for b in vis:
		(b as BaseButton).pressed.connect(func(): pressed_log.append((b as Node).name))
	for step in [JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_DOWN]:
		await _tap(step)
		print("  tras cruceta %d: %s" % [step, _focus_desc()])
	for ev in InputMap.action_get_events("ui_accept") + InputMap.action_get_events("ui_cancel") + InputMap.action_get_events("ui_down"):
		print("  ui_accept: ", ev.as_text())
	var before := _focus_desc()
	await _tap(JOY_BUTTON_A)
	print("  A sobre [%s] -> pulsados: %s" % [before, str(pressed_log)])
	get_tree().quit()
