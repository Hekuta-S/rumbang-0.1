class_name HubPanels
extends Control

## Paneles de las estaciones del Salón (DungeonHub):
##   yunque -> arma inicial de la mazmorra        arena -> personaje de supervivencia y entrar
##   cofre / libro / mesa -> mejoras, logros y ajustes del menú de siempre (main_menu.gd incrustado)
##   salir  -> confirmación
## Al cerrarse avisa a hub.on_panel_closed(id).

const Style := preload("res://scripts/ui/rumbang_style.gd")
const MENU_SCRIPT := preload("res://scripts/ui/main_menu.gd")
const ANVIL_W := 1140.0              ## ancho del panel del yunque (6 armas en una fila a 1280 px)
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
	if id == "yunque":    # el foco empieza en el listado, no en las pestañas
		first = _anvil_body.find_child("Lista", true, false).find_children("*", "Button", true, false)
	if not first.is_empty():
		_focus_later(first[0])

func close() -> void:
	if current == "":
		return
	var id := current
	current = ""
	if _panel:
		_panel.queue_free()
		_panel = null
		_preview = null
		anvil_tab = ""
		_detail = null
		_cards.clear()
		_stat_buttons.clear()
		_tab_buttons.clear()
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

## Yunque = mesa de la forja: dos pestañas.
##   ARMAS -> listado a la izquierda, descripción del arma marcada a la derecha (EQUIPAR).
##   NIVEL -> estadísticas tipo Dark Souls (SoulStats) a la izquierda, efecto y SUBIR a la derecha.
func _build_anvil() -> Control:
	var p := _frame(ANVIL_W)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	p.add_child(box)
	_title(box, "YUNQUE", "Elige el arma con la que entras en las mazmorras y gasta las almas en subir de nivel.")
	var tabs := HBoxContainer.new()
	tabs.name = "Pestanas"
	tabs.add_theme_constant_override("separation", 10)
	box.add_child(tabs)
	for t in [["armas", "ARMAS"], ["nivel", "NIVEL"]]:
		var b := Style.make_button(String(t[1]), Style.BTN_BORDER, Vector2(180, 38))
		b.name = "Tab_" + String(t[0])
		b.pressed.connect(show_anvil_tab.bind(String(t[0])))
		tabs.add_child(b)
		_tab_buttons[String(t[0])] = b
	_anvil_body = HBoxContainer.new()
	_anvil_body.name = "Cuerpo"
	_anvil_body.custom_minimum_size = Vector2(0, ANVIL_BODY_H)
	_anvil_body.add_theme_constant_override("separation", 18)
	box.add_child(_anvil_body)
	_back_button(box)
	show_anvil_tab("armas")
	return p

const ANVIL_BODY_H := 430.0
const ANVIL_LIST_W := 330.0
var anvil_tab := ""
var _tab_buttons: Dictionary = {}
var _anvil_body: HBoxContainer
var _detail: VBoxContainer
var _sel_weapon := -1
var _sel_stat := ""
var _stat_buttons: Dictionary = {}   ## stat -> Button de la pestaña NIVEL

func show_anvil_tab(id: String) -> void:
	anvil_tab = id
	for c in _anvil_body.get_children():
		_anvil_body.remove_child(c)
		c.queue_free()
	_cards.clear()
	_stat_buttons.clear()
	for t in _tab_buttons:
		var on: bool = t == id
		var st := Style.button_style(Color(0.14, 0.08, 0.18, 0.95) if on else Color(0.05, 0.03, 0.08, 0.9),
			Style.ACCENT if on else Style.BTN_BORDER, 4, 3 if on else 2)
		for s in ["normal", "hover", "pressed"]:
			(_tab_buttons[t] as Button).add_theme_stylebox_override(s, st)
		(_tab_buttons[t] as Button).add_theme_stylebox_override("focus", Style.focus_ring())
	# NIVEL lo abre la prisionera de las Cloacas (historia): hasta liberarla, solo un aviso
	if id == "nivel" and DungeonHub.station_locked("nivel"):
		var msg := Label.new()
		msg.name = "Bloqueado"
		msg.text = DungeonHub.locked_hint("nivel") + " Tus almas se guardan: podrás gastarlas aquí en cuanto la liberes."
		msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		msg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		msg.custom_minimum_size = Vector2(0, ANVIL_BODY_H)
		_anvil_body.add_child(msg)
		return
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(ANVIL_LIST_W, ANVIL_BODY_H)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_anvil_body.add_child(scroll)
	var list := VBoxContainer.new()
	list.name = "Lista"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	var sep := VSeparator.new()
	_anvil_body.add_child(sep)
	_detail = VBoxContainer.new()
	_detail.name = "Detalle"
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_theme_constant_override("separation", 8)
	_anvil_body.add_child(_detail)
	if id == "nivel":
		_fill_stat_list(list)
		_select_stat(_sel_stat if _sel_stat != "" else String(SoulStats.ORDER[0]))
	else:
		_fill_weapon_list(list)
		_select_weapon(_sel_weapon if _cards.has(_sel_weapon) else GameData.dungeon_weapon)
	# El primer foco va al primer botón del listado (en NIVEL hay una cabecera antes)
	for c in list.get_children():
		if c is Button:
			_focus_later(c)
			break

## Foco al siguiente frame, si el botón sigue en pantalla (cambiar de pestaña o cerrar lo borra).
func _focus_later(b: Control) -> void:
	(func():
		if is_instance_valid(b) and b.is_inside_tree() and b.is_visible_in_tree():
			b.grab_focus()).call_deferred()

func _list_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(ANVIL_LIST_W - 16.0, 40)
	b.add_theme_font_size_override("font_size", 12)
	return b

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _clear_detail() -> void:
	for c in _detail.get_children():
		_detail.remove_child(c)
		c.queue_free()

# ── ARMAS ──

func _fill_weapon_list(list: VBoxContainer) -> void:
	# El arma que llevabas en la mano al acabar la última partida también se puede llevar
	var weapons: Array = GameData.DUNGEON_WEAPONS.duplicate()
	if not weapons.has(GameData.dungeon_weapon):
		weapons.append(GameData.dungeon_weapon)
	for w in weapons:
		var b := _list_button(String(WeaponData.weapon_names.get(w, "Arma")))
		b.name = "Arma_%d" % w
		b.pressed.connect(_select_weapon.bind(int(w)))
		b.focus_entered.connect(_select_weapon.bind(int(w)))
		list.add_child(b)
		_cards[w] = b
	_refresh_cards()

func _select_weapon(w: int) -> void:
	if not is_instance_valid(_detail):
		return
	if _sel_weapon == w and _detail.get_child_count() > 0 and anvil_tab == "armas":
		return
	_sel_weapon = w
	_refresh_cards()
	_clear_detail()
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	_detail.add_child(head)
	var icon_path := String(WeaponChoiceUI.ICONS.get(w, ""))
	if icon_path != "" and ResourceLoader.exists(icon_path):
		var icon := TextureRect.new()
		icon.texture = load(icon_path)
		icon.custom_minimum_size = Vector2(110, 110)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		head.add_child(icon)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(names)
	var n := _label(String(WeaponData.weapon_names.get(w, "Arma")), 18, Style.TITLE)
	n.name = "Nombre"
	names.add_child(n)
	var sc := _label("Escalado:  " + SoulStats.scaling_text(w), 12, Style.ACCENT)
	sc.name = "Escalado"
	names.add_child(sc)
	names.add_child(_label("Bono de daño con tus niveles: +%d%%" % int(round(SoulStats.damage_bonus(w) * 100.0)), 11, Style.TEXT))
	var d := _label(String(WeaponChoiceUI.DESCRIPTIONS.get(w, "")), 11, Style.TEXT_DIM)
	d.name = "Descripcion"
	_detail.add_child(d)
	var eq_btn := Style.make_button("EQUIPADA" if w == GameData.dungeon_weapon else "EQUIPAR", Style.ACCENT, Vector2(200, 40))
	eq_btn.name = "Equipar"
	eq_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	eq_btn.disabled = w == GameData.dungeon_weapon
	eq_btn.pressed.connect(func(): equip(w))
	_detail.add_child(eq_btn)
	# Lo equipado solo se conserva entre partidas con PlayerEquipment.PERSIST_LOADOUT (ahora apagado)
	if PlayerEquipment.PERSIST_LOADOUT:
		_detail.add_child(HSeparator.new())
		_detail.add_child(_loadout_box())

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
		"talisman_1": "Talismán 1", "talisman_2": "Talismán 2", "amuleto": "Amuleto", "arma": "Arma"}
	# Sin nada guardado basta una línea (el aviso de abajo explica de dónde sale el equipo)
	var empty := true
	for slot in PlayerEquipment.SLOTS + ["arma"]:
		if not (saved.get(slot, {}) as Dictionary).is_empty():
			empty = false
	if empty:
		var none := Label.new()
		none.name = "Vacio"
		none.text = "Nada todavía."
		none.add_theme_font_size_override("font_size", 10)
		none.add_theme_color_override("font_color", Style.TEXT_DIM)
		v.add_child(none)
	for slot in ([] if empty else PlayerEquipment.SLOTS + ["arma"]):
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
	if anvil_tab == "armas" and is_instance_valid(_detail):
		_sel_weapon = -1
		_select_weapon(w)
	_refresh_cards()
	if hub:
		hub.refresh_rack()

## Listado de armas: la equipada lleva la marca y el borde de acento; la marcada, fondo más claro.
func _refresh_cards() -> void:
	for w in _cards:
		var b: Button = _cards[w]
		var on := int(w) == GameData.dungeon_weapon
		var sel := int(w) == _sel_weapon
		b.text = ("> " if sel else "  ") + String(WeaponData.weapon_names.get(w, "Arma")) + ("   [EQUIPADA]" if on else "")
		var st := Style.button_style(Color(0.16, 0.09, 0.2, 0.95) if sel else Color(0.05, 0.03, 0.08, 0.9),
			Style.ACCENT if on else Style.BTN_BORDER, 4, 3 if on else 2)
		st.skew = Vector2.ZERO          # filas rectas: con la inclinación el texto se salía
		st.content_margin_left = 10
		st.content_margin_right = 6
		for s in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(s, st)
		b.add_theme_stylebox_override("focus", Style.focus_ring(Style.NEON_CYAN, true))

# ── NIVEL (SoulStats) ──

func _fill_stat_list(list: VBoxContainer) -> void:
	var head := _label("NIVEL %d   ALMAS %d" % [SoulStats.level(), SoulStats.souls()], 13, Style.ACCENT)
	head.name = "Cabecera"
	list.add_child(head)
	list.add_child(_label("Siguiente nivel: %d almas" % SoulStats.level_cost(), 10, Style.TEXT_DIM))
	for s in SoulStats.ORDER:
		var b := _list_button("")
		b.name = "Stat_" + s
		b.pressed.connect(_select_stat.bind(String(s)))
		b.focus_entered.connect(_select_stat.bind(String(s)))
		list.add_child(b)
		_stat_buttons[s] = b
	list.add_child(_label("Las almas salen de cada baja en la mazmorra. Si caes, solo conservas la mitad de las de esa partida.", 10, Style.TEXT_DIM))
	_refresh_stats()

func _refresh_stats() -> void:
	for s in _stat_buttons:
		var b: Button = _stat_buttons[s]
		var sel: bool = s == _sel_stat
		b.text = "%s%-10s %2d" % ["> " if sel else "  ", String(SoulStats.STATS[s]["name"]), SoulStats.value(s)]
		var st := Style.button_style(Color(0.16, 0.09, 0.2, 0.95) if sel else Color(0.05, 0.03, 0.08, 0.9), Style.BTN_BORDER, 4, 2)
		st.skew = Vector2.ZERO
		st.content_margin_left = 10
		for k in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(k, st)
		b.add_theme_stylebox_override("focus", Style.focus_ring(Style.NEON_CYAN, true))
	var head := _anvil_body.find_child("Cabecera", true, false) as Label if _anvil_body else null
	if head:
		head.text = "NIVEL %d   ALMAS %d" % [SoulStats.level(), SoulStats.souls()]
		var cost := head.get_parent().get_child(head.get_index() + 1) as Label
		if cost:
			cost.text = "Siguiente nivel: %d almas" % SoulStats.level_cost()

func _select_stat(stat: String) -> void:
	if not is_instance_valid(_detail):
		return
	_sel_stat = stat
	_refresh_stats()
	_clear_detail()
	var info: Dictionary = SoulStats.STATS[stat]
	var n := _label("%s  %d" % [String(info["name"]).to_upper(), SoulStats.value(stat)], 18, Style.TITLE)
	n.name = "Nombre"
	_detail.add_child(n)
	_detail.add_child(_label(String(info["desc"]), 11, Style.TEXT_DIM))
	_detail.add_child(HSeparator.new())
	_detail.add_child(_label("AHORA", 12, Style.ACCENT))
	for line in SoulStats.effect_lines(stat):
		_detail.add_child(_label(line, 11, Style.TEXT))
	var maxed := SoulStats.points(stat) >= SoulStats.MAX_POINTS
	if not maxed:
		_detail.add_child(_label("CON UN PUNTO MAS", 12, Style.ACCENT))
		for line in SoulStats.effect_lines(stat, 1):
			_detail.add_child(_label(line, 11, Color(0.6, 1.0, 0.7)))
	if stat == "fuerza" or stat == "destreza":
		var w := GameData.dungeon_weapon
		_detail.add_child(_label("Tu arma (%s): %s" % [String(WeaponData.weapon_names.get(w, "Arma")), SoulStats.scaling_text(w)], 10, Style.TEXT_DIM))
	var cost := SoulStats.level_cost()
	var txt := "AL MAXIMO" if maxed else "SUBIR  (%d almas)" % cost
	var up := Style.make_button(txt, Style.ACCENT, Vector2(260, 42))
	up.name = "Subir"
	up.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	up.disabled = not SoulStats.can_level(stat)
	up.pressed.connect(level_up.bind(stat))
	_detail.add_child(up)
	if not maxed and SoulStats.souls() < cost:
		_detail.add_child(_label("Te faltan %d almas." % (cost - SoulStats.souls()), 10, Style.DANGER))

## Sube un punto de `stat` con las almas guardadas (la usa también el test).
func level_up(stat: String) -> bool:
	if not SoulStats.level_up(stat):
		return false
	AudioManager.play("impact_blunt", -2.0, 0.8)
	if anvil_tab == "nivel" and is_instance_valid(_detail):
		_select_stat(stat)
		var up := _detail.find_child("Subir", true, false) as Button
		if up:
			_focus_later(up)
	return true

# ───────────────────────────── arena (supervivencia) ─────────────────────────────

## Personajes de supervivencia desbloqueados (GameData.SURVIVAL_UNLOCKED) que tienen modelo (índices de GameData.CHARACTERS).
static func survival_characters() -> Array[int]:
	var out: Array[int] = []
	for i in GameData.CHARACTERS.size():
		var id := String(GameData.CHARACTERS[i].get("id", ""))
		var path := GameData.get_idle_model_path(id)
		if GameData.is_survival_unlocked(id) and path != "" and ResourceLoader.exists(path):
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
	_arena_info.custom_minimum_size = Vector2(300, 210)
	_arena_info.add_theme_font_size_override("font_size", 11)
	_arena_info.add_theme_color_override("font_color", Style.TEXT)
	right.add_child(_arena_info)
	# Mapa de la partida (GameData.survival_map); a mitad de partida un portal lleva al otro
	var map_btn := Style.make_button("", Style.BTN_BORDER, Vector2(280, 40))
	map_btn.name = "Mapa"
	var map_text := func():
		map_btn.text = "  MAPA: %s" % GameData.survival_map_name().to_upper()
		map_btn.tooltip_text = String(GameData.SURVIVAL_MAPS[GameData.survival_map]["subtitle"])
	map_text.call()
	map_btn.pressed.connect(func():
		GameData.cycle_survival_map()
		map_text.call())
	right.add_child(map_btn)
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
