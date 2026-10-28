class_name WeaponChoiceUI
extends CanvasLayer

## Elección de arma al cruzar el portal de fin de nivel (mazmorra): dos cartas con armas al azar.
## Pausa el juego mientras está abierta; emite `chosen(weapon_type)` y se borra sola.

signal chosen(weapon_type: int)

const Style := preload("res://scripts/ui/rumbang_style.gd")
const DESCRIPTIONS := {
	WeaponData.WeaponType.SPEAR_LANCE: "Combo de tres golpes cuerpo a cuerpo. Click derecho: carga un lanzamiento.",
	WeaponData.WeaponType.FLAME_THROWER: "Chorro de fuego continuo. Click derecho: explosión que empuja a todos (y a ti).",
	WeaponData.WeaponType.SPORE_BAZOOKA: "Proyectil de esporas que estalla en una nube corrosiva. Click derecho: perdigonazo.",
	WeaponData.WeaponType.TRI_SHOTGUN: "Escopetazo en cono a corta distancia. Click derecho: ráfaga de cuatro disparos.",
	WeaponData.WeaponType.DUSTS: "Polvos alquímicos que estallan donde caen. Click derecho: polvo a la cara (velocidad y vida).",
	WeaponData.WeaponType.SERPENTS: "Invoca al Komodo, un espíritu que azota con la cola. Ataques variados y con sangrado.",
}
const ICONS := {
	WeaponData.WeaponType.SPEAR_LANCE: "res://assets/ui/ingame_hub/armas/espalanza.png",
	WeaponData.WeaponType.FLAME_THROWER: "res://assets/ui/ingame_hub/armas/lanzallamas.png",
	WeaponData.WeaponType.SPORE_BAZOOKA: "res://assets/ui/ingame_hub/armas/bazoka_esporas.png",
	WeaponData.WeaponType.TRI_SHOTGUN: "res://assets/ui/ingame_hub/armas/escopeta.png",
	WeaponData.WeaponType.DUSTS: "res://assets/ui/ingame_hub/armas/polvos.png",
}

var _options: Array = []

## Abre la elección con estas armas (normalmente 2).
static func present(parent: Node, options: Array, level: int) -> WeaponChoiceUI:
	var ui := WeaponChoiceUI.new()
	ui._options = options
	parent.add_child(ui)
	ui._build(level)
	return ui

func _build(level: int) -> void:
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
	vbox.add_theme_constant_override("separation", 22)
	root.add_child(vbox)
	var title := Label.new()
	title.text = "NIVEL %d SUPERADO — ELIGE UN ARMA" % level
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Style.TITLE)
	title.add_theme_font_size_override("font_size", 26)
	vbox.add_child(title)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 28)
	vbox.add_child(row)
	var first: Button = null
	for i in _options.size():
		var b := _card(int(_options[i]), i + 1)
		row.add_child(b)
		if first == null:
			first = b
	var hint := Label.new()
	hint.text = "Clic o teclas 1 / 2"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	hint.modulate = Color(1, 1, 1, 0.6)
	vbox.add_child(hint)
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if first:
		first.grab_focus()

func _card(weapon_type: int, number: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(300, 330)
	b.focus_mode = Control.FOCUS_ALL
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 16
	col.offset_right = -16
	col.offset_top = 16
	col.offset_bottom = -16
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 12)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(col)
	var icon_path: String = ICONS.get(weapon_type, "")
	if icon_path != "" and ResourceLoader.exists(icon_path):
		var tr := TextureRect.new()
		tr.texture = load(icon_path)
		tr.custom_minimum_size = Vector2(110, 110)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(tr)
	else:
		var em := Label.new()
		em.text = str(WeaponData.weapon_icons.get(weapon_type, "?"))
		em.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		em.add_theme_font_size_override("font_size", 64)
		col.add_child(em)
	var name_l := Label.new()
	name_l.text = "%d · %s" % [number, str(WeaponData.weapon_names.get(weapon_type, "Arma"))]
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_l.custom_minimum_size = Vector2(260, 0)
	name_l.add_theme_font_size_override("font_size", 16)
	name_l.add_theme_color_override("font_color", Style.ACCENT)
	col.add_child(name_l)
	var desc := Label.new()
	desc.text = DESCRIPTIONS.get(weapon_type, "")
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.custom_minimum_size = Vector2(260, 0)
	desc.add_theme_font_size_override("font_size", 12)
	col.add_child(desc)
	b.pressed.connect(_pick.bind(weapon_type))
	return b

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var i: int = event.keycode - KEY_1
		if i >= 0 and i < _options.size():
			_pick(int(_options[i]))
			get_viewport().set_input_as_handled()

func _pick(weapon_type: int) -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	chosen.emit(weapon_type)
	queue_free()
