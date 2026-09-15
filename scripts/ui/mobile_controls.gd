extends CanvasLayer

var joy_center := Vector2(120, 120)
var joy_radius := 80.0
var joy_touch_id: int = -1

var stick_bg: ColorRect
var stick_knob: ColorRect

var buttons: Dictionary = {}

func _ready() -> void:
	layer = 50
	if OS.get_name() not in ["Android", "iOS"]:
		pass # En PC sigue visible para probar con el ratón (emulando toque si está configurado)
		
	var vp_size = get_viewport().get_visible_rect().size
	joy_center = Vector2(150, vp_size.y - 150)
	
	_build_joystick()
	
	buttons["is_attacking"] = _create_btn(vp_size.x - 120, vp_size.y - 120, 80, 80, Color(1, 0.2, 0.2, 0.5), "ATK")
	buttons["is_jumping"] = _create_btn(vp_size.x - 220, vp_size.y - 100, 70, 70, Color(0.2, 0.8, 0.2, 0.5), "JMP")
	buttons["is_running"] = _create_btn(vp_size.x - 100, vp_size.y - 220, 70, 70, Color(0.8, 0.8, 0.2, 0.5), "RUN")
	buttons["just_pressed_skill"] = _create_btn(vp_size.x - 200, vp_size.y - 200, 60, 60, Color(0.2, 0.2, 1.0, 0.5), "SKL")
	buttons["is_alt_attack"] = _create_btn(vp_size.x - 300, vp_size.y - 100, 60, 60, Color(0.8, 0.2, 0.8, 0.5), "ALT")
	buttons["just_pressed_reload"] = _create_btn(vp_size.x - 120, vp_size.y - 300, 60, 60, Color(0.5, 0.5, 0.5, 0.5), "RLD")
	
	set_process_input(true)

func _build_joystick() -> void:
	stick_bg = ColorRect.new()
	stick_bg.color = Color(0, 0, 0, 0.4)
	stick_bg.size = Vector2(joy_radius * 2, joy_radius * 2)
	stick_bg.position = joy_center - Vector2(joy_radius, joy_radius)
	add_child(stick_bg)
	
	stick_knob = ColorRect.new()
	stick_knob.color = Color(1, 1, 1, 0.6)
	stick_knob.size = Vector2(60, 60)
	stick_knob.position = joy_center - Vector2(30, 30)
	add_child(stick_knob)

func _create_btn(x: float, y: float, w: float, h: float, col: Color, txt: String) -> Dictionary:
	var cr = ColorRect.new()
	cr.position = Vector2(x, y)
	cr.size = Vector2(w, h)
	cr.color = col
	var lbl = Label.new()
	lbl.text = txt
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cr.add_child(lbl)
	add_child(cr)
	return {"rect": cr, "touch_id": -1, "base_color": col}

func _input(event: InputEvent) -> void:
	if not visible: return
	
	if event is InputEventScreenTouch or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		var pos = event.position
		var pressed = event.pressed
		var idx = event.index if event is InputEventScreenTouch else 0
		
		# Joystick
		if pressed and joy_touch_id == -1 and pos.distance_squared_to(joy_center) < (joy_radius * joy_radius * 1.5):
			joy_touch_id = idx
			_update_joystick(pos)
		elif not pressed and idx == joy_touch_id:
			joy_touch_id = -1
			_update_joystick(joy_center)
			
		# Buttons
		for prop in buttons:
			var b = buttons[prop]
			var rect = b["rect"] as ColorRect
			if pressed and b["touch_id"] == -1 and Rect2(rect.position, rect.size).has_point(pos):
				b["touch_id"] = idx
				rect.color = Color.WHITE
				VirtualInput.set(prop, true)
			elif not pressed and idx == b["touch_id"]:
				b["touch_id"] = -1
				rect.color = b["base_color"]
				if prop.begins_with("is_"):
					VirtualInput.set(prop, false)
					
	elif event is InputEventScreenDrag or (event is InputEventMouseMotion and (Input.get_mouse_button_mask() & MOUSE_BUTTON_MASK_LEFT)):
		var pos = event.position
		var idx = event.index if event is InputEventScreenDrag else 0
		if idx == joy_touch_id:
			_update_joystick(pos)
		else:
			var relative = event.relative if "relative" in event else Vector2.ZERO
			VirtualInput.look_vector = relative

func _update_joystick(pos: Vector2) -> void:
	var offset = pos - joy_center
	if offset.length() > joy_radius:
		offset = offset.normalized() * joy_radius
	stick_knob.position = (joy_center + offset) - Vector2(30, 30)
	
	var norm = offset / joy_radius
	VirtualInput.movement_vector = norm
