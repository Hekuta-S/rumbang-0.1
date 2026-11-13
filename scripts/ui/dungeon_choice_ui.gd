class_name DungeonChoiceUI
extends CanvasLayer

## Elección genérica de la mazmorra con el estilo de WeaponChoiceUI: camino del portal, runas y la
## forja (DungeonShop). Pausa el juego mientras está abierta. Cada opción es
## {id, icon, title, desc, color?, price? (-1 = gratis), disabled?, reason? (por qué está bloqueada:
## "FALTAN 20 ORO", "MOCHILA LLENA"…)}. Con más de MANY opciones van en una sola fila con scroll
## horizontal. Mientras está abierta oculta el HUD de la partida (nodo "HUD" de la escena).
##  - Normal: elegir emite `chosen(id)` y se cierra.
##  - keep_open (forja): elegir emite `chosen(id)` y sigue abierta (quien la usa llama a set_options
##    para refrescar precios); el botón SALIR emite `closed`.

signal chosen(id: String)
signal closed

const Style := preload("res://scripts/ui/rumbang_style.gd")
const MANY := 5                        ## más opciones que esto: cartas estrechas y fila con scroll
const MARGIN := 28                     ## margen seguro alrededor de todo

var keep_open := false
var _title := ""
var _subtitle := ""
var _options: Array = []
var _row: HBoxContainer
var _scroll: ScrollContainer
var _info: Label
var _hud: CanvasLayer                  ## HUD de la partida, oculto mientras está abierta
var _hud_was_visible := false

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
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, MARGIN)
	root.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	margin.add_child(vbox)
	var title := Label.new()
	title.text = _title
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Style.style_title(title, 26)
	vbox.add_child(title)
	_info = Label.new()
	_info.text = _subtitle
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	Style.style_title(_info, 12, Style.NEON_CYAN, Style.NEON_CYAN)
	vbox.add_child(_info)
	# Una sola fila; si no cabe, scroll horizontal (rueda, arrastre o seguir el foco con teclado/mando)
	_scroll = ScrollContainer.new()
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.follow_focus = true
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.add_child(center)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 12 if _options.size() > MANY else 22)
	center.add_child(_row)
	if keep_open:
		var close := Button.new()
		close.text = "SALIR"
		close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		close.pressed.connect(_close)
		vbox.add_child(close)
	_hide_hud(true)
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
	_scroll.custom_minimum_size.y = (300 if _options.size() > MANY else 250) + 14   # + barra de scroll
	_row.add_theme_constant_override("separation", 12 if _options.size() > MANY else 22)
	UiJuice.deal_in(_row.get_children())
	if first:
		first.grab_focus.call_deferred()

func _card(o: Dictionary, number: int) -> Button:
	var col_c: Color = o.get("color", Style.ACCENT)
	var b := Button.new()
	# Con muchas opciones (la forja de Tatan vende también equipo) las cartas se estrechan para caber
	var many := _options.size() > MANY
	b.custom_minimum_size = Vector2(186 if many else 230, 300 if many else 250)
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
	col.add_child(_label(str(o.get("icon", "")), 36 if many else 44, Color.WHITE))
	col.add_child(_label("%d · %s" % [number, o["title"]], 12 if many else 13, col_c))
	col.add_child(_label(str(o.get("desc", "")), 10 if many else 11, Style.TEXT))
	var price := int(o.get("price", -1))
	if price >= 0:
		col.add_child(_label("%d ORO" % price, 13, Style.TITLE if not b.disabled else Style.TEXT_DIM))
	var reason := String(o.get("reason", ""))
	if b.disabled and reason != "":
		col.add_child(_label(reason, 11, Style.DANGER))
	if b.disabled:
		col.modulate = Color(1, 1, 1, 0.6)
	b.pressed.connect(_pick.bind(String(o["id"])))
	return b

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(200 if _options.size() <= MANY else 160, 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _unhandled_input(event: InputEvent) -> void:
	if keep_open and event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		var i: int = event.keycode - KEY_1
		if i >= 0 and i < _options.size() and not bool(_options[i].get("disabled", false)):
			_pick(String(_options[i]["id"]))
			get_viewport().set_input_as_handled()

func _pick(id: String) -> void:
	if keep_open:
		chosen.emit(id)
		return
	_hide_hud(false)
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	chosen.emit(id)
	queue_free()

func _close() -> void:
	_hide_hud(false)
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()
	queue_free()

func _exit_tree() -> void:
	_hide_hud(false)

func _hide_hud(on: bool) -> void:
	if on:
		var scene := get_tree().current_scene
		_hud = scene.get_node_or_null("HUD") as CanvasLayer if scene else null
		if _hud:
			_hud_was_visible = _hud.visible
			_hud.visible = false
	elif is_instance_valid(_hud):
		_hud.visible = _hud_was_visible
		_hud = null
