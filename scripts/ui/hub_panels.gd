class_name HubPanels
extends Control

## Paneles de las estaciones del Salón (DungeonHub):
##   yunque -> arma inicial de la mazmorra        arena -> personaje de supervivencia y entrar
##   cofre / libro / mesa -> mejoras, logros y ajustes del menú de siempre (main_menu.gd incrustado)
##   salir  -> confirmación
## Al cerrarse avisa a hub.on_panel_closed(id).

const Style := preload("res://scripts/ui/rumbang_style.gd")
const MENU_SCRIPT := preload("res://scripts/ui/main_menu.gd")
const MENU_PANELS := {"cofre": "mejoras", "libro": "logros", "mesa": "ajustes"}

var hub: DungeonHub
var current := ""                 ## estación abierta ("" = ninguna)
var _panel: Control               ## panel propio abierto (yunque, arena, salir)
var _menu: Control                ## main_menu.gd incrustado (se crea al primer uso)
var _cards: Dictionary = {}       ## arma -> Button del yunque
var _preview: CharacterPreview
var _arena_index := -1
var _arena_info: Label
var _arena_name: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func open(id: String) -> void:
	if current != "":
		return
	current = id
	if MENU_PANELS.has(id):
		if _menu == null:
			_menu = MENU_SCRIPT.new()
			_menu.embedded = true
			_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
			add_child(_menu)
			_menu.panel_closed.connect(close)
		_menu.open_panel(String(MENU_PANELS[id]))
		return
	match id:
		"yunque":
			_panel = _build_anvil()
		"arena":
			_panel = _build_arena()
		"salir":
			_panel = _build_exit()
		_:
			current = ""
			return
	add_child(_panel)
	_panel.modulate.a = 0.0
	create_tween().tween_property(_panel, "modulate:a", 1.0, 0.25)
	var first := _panel.find_children("*", "Button", true, false)
	if not first.is_empty():
		(first[0] as Button).grab_focus.call_deferred()

func close() -> void:
	if current == "":
		return
	var id := current
	current = ""
	if _panel:
		_panel.queue_free()
		_panel = null
		_preview = null
	if _menu:
		for p in [_menu.get("upgrades_panel"), _menu.get("codex_panel")]:
			if p is Control:
				(p as Control).hide()
		for c in _menu.get_children():
			if c is CanvasLayer and not c.is_queued_for_deletion():
				c.queue_free()      # ajustes
	if hub:
		hub.on_panel_closed(id)

# ───────────────────────────── piezas ─────────────────────────────

func _frame(w: float, left: bool = false) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Style.panel_style(Color(0.04, 0.02, 0.07, 0.92)))
	if left:
		p.set_anchors_preset(Control.PRESET_CENTER_LEFT)
		p.offset_left = 48
		p.grow_vertical = Control.GROW_DIRECTION_BOTH
	else:
		p.set_anchors_preset(Control.PRESET_CENTER)
		p.grow_horizontal = Control.GROW_DIRECTION_BOTH
		p.grow_vertical = Control.GROW_DIRECTION_BOTH
	p.custom_minimum_size = Vector2(w, 0)
	return p

func _title(box: Container, text: String, sub: String) -> void:
	var t := Label.new()
	t.text = text
	Style.style_title(t, 22)
	box.add_child(t)
	if sub != "":
		var s := Label.new()
		s.text = sub
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		s.add_theme_font_size_override("font_size", 11)
		s.add_theme_color_override("font_color", Style.TEXT_DIM)
		box.add_child(s)

func _back_button(box: Container, text: String = "  VOLVER") -> Button:
	var b := Style.make_button(text, Style.BTN_BORDER, Vector2(200, 42))
	b.pressed.connect(close)
	box.add_child(b)
	return b

# ───────────────────────────── yunque ─────────────────────────────

func _build_anvil() -> Control:
	var p := _frame(900)
	p.offset_top = 40
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	p.add_child(box)
	_title(box, "YUNQUE", "Elige el arma con la que entras en las mazmorras. En supervivencia cada personaje lleva la suya.")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)
	_cards.clear()
	# El arma que llevabas en la mano al acabar la última partida también se puede llevar
	var weapons: Array = GameData.DUNGEON_WEAPONS.duplicate()
	if not weapons.has(GameData.dungeon_weapon):
		weapons.append(GameData.dungeon_weapon)
	var card_w := 280.0 if weapons.size() <= 3 else (210.0 if weapons.size() <= 4 else 180.0)
	for w in weapons:
		var card := Button.new()
		card.name = "Arma_%d" % w
		card.custom_minimum_size = Vector2(card_w, 300)
		card.toggle_mode = false
		var v := VBoxContainer.new()
		v.set_anchors_preset(Control.PRESET_FULL_RECT)
		v.offset_left = 12
		v.offset_right = -12
		v.offset_top = 10
		v.offset_bottom = -10
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_theme_constant_override("separation", 8)
		card.add_child(v)
		var icon_path := String(WeaponChoiceUI.ICONS.get(w, ""))
		if icon_path != "" and ResourceLoader.exists(icon_path):
			var tr := TextureRect.new()
			tr.texture = load(icon_path)
			tr.custom_minimum_size = Vector2(0, 120)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			v.add_child(tr)
		var n := Label.new()
		n.text = String(WeaponData.weapon_names.get(w, "Arma"))
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		n.add_theme_font_size_override("font_size", 14)
		n.add_theme_color_override("font_color", Style.TITLE)
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(n)
		var d := Label.new()
		d.text = String(WeaponChoiceUI.DESCRIPTIONS.get(w, ""))
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.add_theme_font_size_override("font_size", 10)
		d.add_theme_color_override("font_color", Style.TEXT_DIM)
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(d)
		var eq := Label.new()
		eq.name = "Equipada"
		eq.text = "EQUIPADA"
		eq.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		eq.add_theme_font_size_override("font_size", 12)
		eq.add_theme_color_override("font_color", Style.ACCENT)
		eq.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(eq)
		card.pressed.connect(equip.bind(w))
		row.add_child(card)
		_cards[w] = card
	_refresh_cards()
	box.add_child(_loadout_box())
	_back_button(box)
	return p

## Lo equipado que se guardó al acabar la última partida (PlayerEquipment.saved_loadout()).
func _loadout_box() -> Control:
	var v := VBoxContainer.new()
	v.name = "Equipo"
	v.add_theme_constant_override("separation", 3)
	var t := Label.new()
	t.text = "EQUIPO GUARDADO"
	Style.style_title(t, 14)
	v.add_child(t)
	var saved := PlayerEquipment.saved_loadout()
	var names := {"casco": "Casco", "pechera": "Pechera", "pantalones": "Pantalones",
		"talisman_1": "Talismán 1", "talisman_2": "Talismán 2", "arma": "Arma"}
	for slot in PlayerEquipment.SLOTS + ["arma"]:
		var l := Label.new()
		l.name = "Slot_" + slot
		var it: Dictionary = saved.get(slot, {})
		l.text = "%s: %s" % [names[slot], EquipmentDB.describe(it) if not it.is_empty() else "— vacío —"]
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_font_size_override("font_size", 10)
		l.add_theme_color_override("font_color", EquipmentDB.rarity_color(it) if not it.is_empty() else Style.TEXT_DIM)
		v.add_child(l)
	var hint := Label.new()
	hint.text = "El equipo se consigue en las mazmorras: cajas, barriles, enemigos, cofres y la forja de Tatan. Al acabar la partida solo se conserva lo equipado."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Style.TEXT_DIM)
	v.add_child(hint)
	return v

## Equipa un arma del yunque (la usa también el test).
func equip(w: int) -> void:
	if GameData.dungeon_weapon != w:
		AudioManager.play("impact_blunt", -4.0, 1.2)
	GameData.set_dungeon_weapon(w)
	_refresh_cards()
	if hub:
		hub.refresh_rack()

func _refresh_cards() -> void:
	for w in _cards:
		var b: Button = _cards[w]
		var on := int(w) == GameData.dungeon_weapon
		var st := Style.button_style(Color(0.12, 0.07, 0.16, 0.95) if on else Color(0.05, 0.03, 0.08, 0.9),
			Style.ACCENT if on else Style.BTN_BORDER, 4, 3 if on else 2)
		for s in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(s, st)
		(b.find_child("Equipada", true, false) as Label).visible = on

# ───────────────────────────── arena (supervivencia) ─────────────────────────────

## Personajes de supervivencia: los de siempre que tienen modelo (índices de GameData.CHARACTERS).
static func survival_characters() -> Array[int]:
	var out: Array[int] = []
	for i in GameData.CHARACTERS.size():
		var id := String(GameData.CHARACTERS[i].get("id", ""))
		var path := GameData.get_idle_model_path(id)
		if path != "" and ResourceLoader.exists(path):
			out.append(i)
	return out

func _build_arena() -> Control:
	var p := _frame(1000, true)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	p.add_child(row)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	left.custom_minimum_size = Vector2(260, 0)
	row.add_child(left)
	_title(left, "ARENA", "Supervivencia: hordas sin fin. Elige con quién luchas.")
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(260, 360)
	left.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var chars := survival_characters()
	for i in chars:
		var c: Dictionary = GameData.CHARACTERS[i]
		var b := Style.make_button("  " + String(c.get("name", "?")).to_upper(), Style.BTN_BORDER, Vector2(240, 40))
		b.name = "Personaje_" + String(c.get("id", ""))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_pick_survivor.bind(i))
		b.focus_entered.connect(_pick_survivor.bind(i))
		list.add_child(b)
	_preview = CharacterPreview.new()
	_preview.custom_minimum_size = Vector2(340, 460)
	row.add_child(_preview)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	right.custom_minimum_size = Vector2(300, 0)
	row.add_child(right)
	_arena_name = Label.new()
	Style.style_title(_arena_name, 20)
	right.add_child(_arena_name)
	_arena_info = Label.new()
	_arena_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_arena_info.custom_minimum_size = Vector2(300, 260)
	_arena_info.add_theme_font_size_override("font_size", 11)
	_arena_info.add_theme_color_override("font_color", Style.TEXT)
	right.add_child(_arena_info)
	var go := Style.make_button("  ENTRAR A LA ARENA", Style.ACCENT, Vector2(280, 50))
	go.name = "Entrar"
	go.pressed.connect(func():
		if _arena_index >= 0 and hub:
			var idx := _arena_index
			close()
			hub.start_survival(idx))
	right.add_child(go)
	_back_button(right)
	var start := GameData.selected_index if chars.has(GameData.selected_index) else (chars[0] if not chars.is_empty() else -1)
	if start >= 0:
		_pick_survivor.call_deferred(start)
	return p

func _pick_survivor(i: int) -> void:
	if i == _arena_index or _preview == null:
		return
	_arena_index = i
	var c: Dictionary = GameData.CHARACTERS[i]
	var id := String(c.get("id", ""))
	_arena_name.text = String(c.get("name", "?")).to_upper()
	var w: Array = c.get("initial_weapons", [WeaponData.WeaponType.SPEAR_LANCE])
	var weapon := String(WeaponData.weapon_names.get(int(w[0]), "")) if not w.is_empty() else ""
	_arena_info.text = "%s\n\n%s\n\nArma: %s\nPasiva: %s" % [String(c.get("subtitle", "")), String(c.get("lore", "")),
		weapon, String(c.get("passive_name", "-"))]
	_preview.show_character(id, c.get("color", Style.ACCENT))

func selected_survivor() -> int:
	return _arena_index

# ───────────────────────────── salir ─────────────────────────────

func _build_exit() -> Control:
	var p := _frame(420)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	p.add_child(box)
	_title(box, "¿SALIR DEL JUEGO?", "El rey no se lo va a tomar bien.")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var stay := _back_button(row, "  QUEDARME")
	stay.name = "Quedarme"
	var go := Style.make_button("  SALIR", Style.ACCENT, Vector2(160, 42))
	go.name = "Salir"
	go.pressed.connect(func():
		close()
		if hub:
			hub.quit_game())
	row.add_child(go)
	return p
