## character_select.gd — Personalización del personaje (único personaje jugable, ver CharacterLook).
## Vista previa 3D a la izquierda; a la derecha nombre, colores, accesorios y proporciones. Cada cambio
## se ve al momento; al empezar la partida se guarda en user://personaje.cfg.
class_name CharacterSelect
extends Control

const Style := preload("res://scripts/ui/rumbang_style.gd")
const PIXEL_FONT := Style.FONT
const SWATCH := Vector2(26, 26)
## Zona a la que se acerca la cámara al tocar cada opción
const FOCUS := {
	"hair": "face", "eyes": "face", "hat": "face", "hat2": "face", "head": "face", "hair_style": "face",
	"underwear": "torso", "waistband": "torso", "shirt": "torso", "pants": "legs",
	"shoes": "feet", "shoes_accent": "feet", "sole": "feet", "footwear": "feet",
}

var _look: CharacterLook
var _preview: CharacterPreview
var _name_edit: LineEdit
var _pickers: Dictionary = {}        ## ranura -> ColorPickerButton
var _options: Dictionary = {}        ## "hat"/"footwear" -> OptionButton
var _sliders: Dictionary = {}        ## proporción -> HSlider
var _value_labels: Dictionary = {}   ## proporción -> Label
## Primera partida: la creación va ANTES de la invocación (título -> crear personaje -> tutorial del patio).
## Sin botón de atrás, empieza con la espada y al confirmar sigue al tutorial en vez de a una partida.
static var creation := false
const TUTORIAL := "res://scenes/core/tutorial_patio.tscn"

var _btn_start: Button
var _btn_back: Button
var _syncing := false

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	theme = Style.get_theme()
	if creation:
		GameData.game_mode = "dungeon"
		GameData.set_dungeon_weapon(WeaponData.WeaponType.SWORD)   # la primera arma es una espada
	GameData.selected_index = GameData.custom_index()
	_look = CharacterLook.current().duplicate_look()
	_build_ui()
	if creation:
		_btn_start.text = "CONFIRMAR E INVOCAR"
		_btn_back.visible = false
	CharacterPreview.preload_all(CharacterLook.CHAR_ID)
	_preview.look = _look
	_preview.show_character(CharacterLook.CHAR_ID, Style.ACCENT)
	_sync_controls()

func _exit_tree() -> void:
	CharacterPreview.clear_cache()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back()
		get_viewport().set_input_as_handled()

# ───────────────────────────── construcción ─────────────────────────────

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(PRESET_FULL_RECT)
	bg.color = Style.BG
	add_child(bg)
	var accent_bar := ColorRect.new()
	accent_bar.set_anchors_preset(PRESET_TOP_WIDE)
	accent_bar.custom_minimum_size = Vector2(0, 3)
	accent_bar.color = Style.ACCENT
	add_child(accent_bar)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 16)
	margin.add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.text = "CREA TU PERSONAJE"
	title.add_theme_font_override("font", PIXEL_FONT)
	Style.style_title(title, 22)
	header.add_child(title)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(fill)
	var btn_back := Style.make_button("← ATRÁS", Style.BTN_BORDER, Vector2(160, 42))
	btn_back.pressed.connect(_on_back)
	header.add_child(btn_back)
	_btn_back = btn_back

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 24)
	root.add_child(body)
	body.add_child(_build_preview())
	body.add_child(_build_editor())

func _build_preview() -> Control:
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.size_flags_stretch_ratio = 1.0
	vb.add_theme_constant_override("separation", 10)
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var pb := StyleBoxFlat.new()
	pb.bg_color = Color(Style.ACCENT, 0.08)
	pb.set_border_width_all(2)
	pb.border_color = Color(Style.ACCENT, 0.45)
	pb.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", pb)
	vb.add_child(panel)
	_preview = CharacterPreview.new()
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.tooltip_text = "Arrastra para girar al personaje"
	panel.add_child(_preview)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	vb.add_child(row)
	var rnd := Style.make_button("ALEATORIO", Style.BTN_BORDER, Vector2(0, 44))
	rnd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rnd.pressed.connect(func():
		_look.randomize_look()
		_sync_controls()
		_changed())
	row.add_child(rnd)
	var reset := Style.make_button("RESTABLECER", Style.BTN_BORDER, Vector2(0, 44))
	reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset.pressed.connect(func():
		var keep_name := _look.char_name
		_look = CharacterLook.new()
		_look.char_name = keep_name
		_sync_controls()
		_changed())
	row.add_child(reset)
	_btn_start = Style.make_button("COMENZAR PARTIDA", Style.ACCENT, Vector2(0, 56))
	_btn_start.pressed.connect(_on_start)
	vb.add_child(_btn_start)
	return vb

func _build_editor() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 1.15
	var ps := StyleBoxFlat.new()
	ps.bg_color = Style.PANEL
	ps.set_border_width_all(2)
	ps.border_color = Color(Style.ACCENT, 0.55)
	ps.set_corner_radius_all(6)
	ps.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", ps)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 8)
	scroll.add_child(vb)

	vb.add_child(_section("NOMBRE"))
	_name_edit = LineEdit.new()
	_name_edit.max_length = CharacterLook.NAME_MAX
	_name_edit.placeholder_text = "Nombre del personaje"
	_name_edit.text_changed.connect(func(t: String):
		_look.char_name = CharacterLook.sanitize_name(t))
	vb.add_child(_name_edit)

	vb.add_child(_section("PROPORCIONES"))
	for p in CharacterLook.PROPORTIONS:
		vb.add_child(_slider_row(p[0], p[1], p[2], p[3]))

	vb.add_child(_section("PELO"))
	vb.add_child(_option_row("hair_style", "Peinado", CharacterLook.HAIR_STYLES))

	vb.add_child(_section("ACCESORIOS"))
	vb.add_child(_option_row("footwear", "Calzado", CharacterLook.footwear_options()))
	vb.add_child(_option_row("shirt", "Camiseta", CharacterLook.shirt_options()))
	vb.add_child(_option_row("pants", "Pantalón", CharacterLook.pants_options()))

	vb.add_child(_section("COLORES"))
	for s in CharacterLook.COLOR_SLOTS:
		var swatches: Array = {"skin": CharacterLook.SKIN_TONES, "hair": CharacterLook.HAIR_TONES,
			"eyes": CharacterLook.EYE_TONES}.get(s[0], CharacterLook.PALETTE)
		vb.add_child(_color_row(s[0], s[1], swatches))

	var info := Label.new()
	var c := GameData.get_selected()
	var w: int = int(GameData.initial_weapons()[0])
	info.text = "Arma inicial: %s    Pasiva: %s" % [WeaponData.weapon_names.get(w, "Arma"), c.get("passive_name", "—")]
	if GameData.start_tome() != "":
		info.text += "    Tomo inicial: %s" % TomeDB.tome_name(GameData.start_tome())
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_font_size_override("font_size", 13)
	info.add_theme_color_override("font_color", Style.TEXT_DIM)
	vb.add_child(_section("PARTIDA"))
	vb.add_child(info)
	return panel

func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", PIXEL_FONT)
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", Style.ACCENT)
	return l

func _row_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(150, 0)
	l.add_theme_font_size_override("font_size", 14)
	return l

func _slider_row(key: String, label: String, lo: float, hi: float) -> Control:
	var row := HBoxContainer.new()
	row.add_child(_row_label(label))
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = 0.01
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.value_changed.connect(func(v: float):
		if _syncing:
			return
		_look.set(key, v)
		_value_labels[key].text = "%d%%" % roundi(v * 100.0)
		_changed(key))
	row.add_child(sl)
	var val := Label.new()
	val.custom_minimum_size = Vector2(52, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val)
	_sliders[key] = sl
	_value_labels[key] = val
	return row

func _option_row(key: String, label: String, options: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_child(_row_label(label))
	var ob := OptionButton.new()
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for id in options:
		ob.add_item(options[id])
		ob.set_item_metadata(ob.item_count - 1, id)
	ob.item_selected.connect(func(i: int):
		if _syncing:
			return
		_look.set(key, String(ob.get_item_metadata(i)))
		_changed(key))
	row.add_child(ob)
	_options[key] = ob
	return row

func _color_row(slot: String, label: String, swatches: Array) -> Control:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	var row := HBoxContainer.new()
	row.add_child(_row_label(label))
	var picker := ColorPickerButton.new()
	picker.custom_minimum_size = Vector2(60, 26)
	picker.edit_alpha = false
	picker.tooltip_text = "Color personalizado"
	picker.color_changed.connect(func(c: Color):
		if _syncing:
			return
		_look.colors[slot] = c
		_changed(slot))
	row.add_child(picker)
	vb.add_child(row)
	var sw_row := HFlowContainer.new()
	sw_row.add_theme_constant_override("h_separation", 4)
	sw_row.add_theme_constant_override("v_separation", 4)
	for col in swatches:
		var b := Button.new()
		b.custom_minimum_size = SWATCH
		b.focus_mode = Control.FOCUS_NONE
		var st := StyleBoxFlat.new()
		st.bg_color = col
		st.set_corner_radius_all(4)
		st.set_border_width_all(1)
		st.border_color = Color(1, 1, 1, 0.25)
		b.add_theme_stylebox_override("normal", st)
		var hv := st.duplicate() as StyleBoxFlat
		hv.border_color = Color.WHITE
		hv.set_border_width_all(2)
		b.add_theme_stylebox_override("hover", hv)
		b.add_theme_stylebox_override("pressed", hv)
		b.pressed.connect(func():
			_look.colors[slot] = col
			picker.color = col
			_changed(slot))
		sw_row.add_child(b)
	vb.add_child(sw_row)
	_pickers[slot] = picker
	return vb

# ───────────────────────────── estado ─────────────────────────────

## Pone los controles con los valores de _look (sin disparar cambios).
func _sync_controls() -> void:
	_syncing = true
	_name_edit.text = _look.char_name
	for k in _sliders:
		_sliders[k].value = float(_look.get(k))
		_value_labels[k].text = "%d%%" % roundi(float(_look.get(k)) * 100.0)
	for k in _options:
		var ob: OptionButton = _options[k]
		for i in ob.item_count:
			if String(ob.get_item_metadata(i)) == String(_look.get(k)):
				ob.select(i)
	for slot in _pickers:
		_pickers[slot].color = _look.color(slot)
	_syncing = false

func _changed(key: String = "") -> void:
	_preview.apply_look(_look)
	var shot: String = FOCUS.get(key, "full")
	if shot != "full":
		_preview.zoom_shot = shot
	_preview.focus(shot)

# ───────────────────────────── acciones ─────────────────────────────

func _on_start() -> void:
	_look.char_name = CharacterLook.sanitize_name(_name_edit.text)
	_look.save()
	CharacterLook.set_current(_look)
	GameData.selected_index = GameData.custom_index()
	if creation:
		creation = false
		DungeonHub.set_character_created(true)
		SceneLoader.load_scene(TUTORIAL)
		return
	var scene := Net.game_scene() if GameData.game_mode == "dungeon" else "res://scenes/core/main_procedural.tscn"
	SceneLoader.load_scene(scene)

func _on_back() -> void:
	if creation:
		return   # la primera vez no se puede salir sin crear el personaje
	SceneLoader.load_scene("res://scenes/ui/dungeon_hub.tscn")   # el Salón es el menú principal
