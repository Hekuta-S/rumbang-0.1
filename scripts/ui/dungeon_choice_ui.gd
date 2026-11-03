class_name DungeonChoiceUI
extends CanvasLayer

## Elección genérica de la mazmorra con el estilo de WeaponChoiceUI: camino del portal, runas y la
## forja (DungeonShop). Pausa el juego mientras está abierta. Cada opción es
## {id, icon, title, desc, color?, price? (-1 = gratis), disabled?}.
##  - Normal: elegir emite `chosen(id)` y se cierra.
##  - keep_open (forja): elegir emite `chosen(id)` y sigue abierta (quien la usa llama a set_options
##    para refrescar precios); el botón SALIR emite `closed`.

signal chosen(id: String)
signal closed

const Style := preload("res://scripts/ui/rumbang_style.gd")

var keep_open := false
var _title := ""
var _subtitle := ""
var _options: Array = []
var _row: HBoxContainer
var _info: Label

static func present(parent: Node, title: String, subtitle: String, options: Array, p_keep_open: bool = false) -> DungeonChoiceUI:
	var ui := DungeonChoiceUI.new()
	ui._title = title
	ui._subtitle = subtitle
	ui._options = options
	ui.keep_open = p_keep_open
	parent.add_child(ui)
	ui._build()
	return ui

func _build() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = Style.get_theme()
	add_child(root)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.01, 0.05, 0.78)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vbox.grow_vertical = Control.GROW_DIRECTION_BOTH
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 20)
	root.add_child(vbox)
	var title := Label.new()
	title.text = _title
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Style.style_title(title, 26)
	vbox.add_child(title)
	_info = Label.new()
	_info.text = _subtitle
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Style.style_title(_info, 14, Style.NEON_CYAN, Style.NEON_CYAN)
	vbox.add_child(_info)
	_row = HBoxContainer.new()
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("separation", 22)
	vbox.add_child(_row)
	if keep_open:
		var close := Button.new()
		close.text = "SALIR"
		close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		close.pressed.connect(_close)
		vbox.add_child(close)
	_fill()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

## Cambia las opciones (y la línea de información) sin cerrar.
func set_options(options: Array, subtitle: String = "") -> void:
	_options = options
	if subtitle != "":
		_info.text = subtitle
	_fill()

func _fill() -> void:
	for c in _row.get_children():
		c.queue_free()
	var first: Button = null
	for i in _options.size():
		var b := _card(_options[i], i + 1)
		_row.add_child(b)
		if first == null and not b.disabled:
			first = b
	if first:
		first.grab_focus.call_deferred()

func _card(o: Dictionary, number: int) -> Button:
	var col_c: Color = o.get("color", Style.ACCENT)
	var b := Button.new()
	b.custom_minimum_size = Vector2(230, 250)
	b.focus_mode = Control.FOCUS_ALL
	b.disabled = bool(o.get("disabled", false))
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb: StyleBoxFlat = (Style.get_theme().get_stylebox(st if st != "disabled" else "normal", "Button") as StyleBoxFlat).duplicate()
		sb.skew = Vector2.ZERO
		sb.border_color = col_c if st != "disabled" else Style.BTN_BORDER
		if st == "normal" or st == "disabled":
			sb.bg_color = Style.PANEL
		b.add_theme_stylebox_override(st, sb)
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 14
	col.offset_right = -14
	col.offset_top = 14
	col.offset_bottom = -14
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 10)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(col)
	col.add_child(_label(str(o.get("icon", "")), 44, Color.WHITE))
	col.add_child(_label("%d · %s" % [number, o["title"]], 13, col_c))
	col.add_child(_label(str(o.get("desc", "")), 11, Style.TEXT))
	var price := int(o.get("price", -1))
	if price >= 0:
		col.add_child(_label("%d ORO" % price, 13, Style.TITLE if not b.disabled else Style.TEXT_DIM))
	if b.disabled:
		b.modulate = Color(1, 1, 1, 0.5)
	b.pressed.connect(_pick.bind(String(o["id"])))
	return b

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(200, 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var i: int = event.keycode - KEY_1
		if i >= 0 and i < _options.size() and not bool(_options[i].get("disabled", false)):
			_pick(String(_options[i]["id"]))
			get_viewport().set_input_as_handled()
		elif keep_open and event.keycode == KEY_ESCAPE:
			_close()
			get_viewport().set_input_as_handled()

func _pick(id: String) -> void:
	if keep_open:
		chosen.emit(id)
		return
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	chosen.emit(id)
	queue_free()

func _close() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()
	queue_free()
