class_name EquipmentPanel
extends Control

## Pestaña EQUIPO del menú de pausa (solo mazmorra), en el estilo de piedra y hierro del HUD de armas (StoneUI):
## una placa con cinco huecos para casco, pechera, pantalones y los dos talismanes, el arma de la mano aparte,
## el detalle de lo que eliges (con la comparación contra lo que llevas si viene de la mochila) y la mochila como
## otra placa de huecos. Elegir un hueco muestra su detalle; Equipar/Quitar/Tirar están en el detalle.
## Se rehace al cambiar el equipo.

signal closed

const SLOT_LABELS := {"casco": "Casco", "pechera": "Pechera", "pantalones": "Pantalones",
	"talisman_1": "Talismán 1", "talisman_2": "Talismán 2", "arma": "Arma (en la mano)"}
const PLATE_SLOTS := ["casco", "pechera", "pantalones", "talisman_1", "talisman_2"]
const GOOD := Color(0.55, 0.9, 0.5)
const BAD := Color(0.92, 0.4, 0.4)

var equipment: PlayerEquipment
var stat_block: PlayerStatBlock
var _plate: StoneUI.SocketPlate        ## casco, pechera, pantalones, talismán 1 y 2
var _weapon_socket: StoneUI.Socket     ## el arma de la mano
var _bag_plate: StoneUI.SocketPlate    ## la mochila (BAG_MAX huecos)
var _detail: VBoxContainer             ## detalle de la pieza elegida
var _stats_label: Label
var _bag_title: StoneUI.Rail
var _preview: CharacterPreview
var _sel_slot := ""                    ## ranura elegida ("" = ninguna / una de la mochila)
var _sel_bag_uid := ""                 ## pieza de la mochila elegida

static func create(p_equipment: PlayerEquipment, p_stat_block: PlayerStatBlock) -> EquipmentPanel:
	var p := EquipmentPanel.new()
	p.equipment = p_equipment
	p.stat_block = p_stat_block
	return p

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = RumbangStyle.get_theme()      # la fuente pixel del juego
	var bg := ColorRect.new()
	bg.color = Color(0.015, 0.012, 0.02, 0.92)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)
	var title := StoneUI.Rail.new("EQUIPO", 18, 360)
	title.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	root.add_child(title)
	var sub := _text("Solo lo que llevas equipado (y el arma en la mano) sigue contigo en la próxima partida. La mochila se pierde.", 10, StoneUI.TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(sub)
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 14)
	root.add_child(cols)
	_build_character(cols)
	_build_center(cols)
	_build_stats(cols)
	var back := Button.new()
	back.text = "VOLVER"
	back.name = "Volver"
	back.custom_minimum_size = Vector2(220, 40)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	StoneUI.style_button(back, 14)
	back.pressed.connect(close)
	root.add_child(back)
	if equipment:
		equipment.equipment_changed.connect(refresh)
	refresh()
	back.grab_focus.call_deferred()

func close() -> void:
	closed.emit()
	queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()

# ───────────────────────────── construcción ─────────────────────────────

## Columna con el personaje 3D vistiendo lo que llevas equipado; se actualiza al cambiar de pieza.
func _build_character(parent: Container) -> void:
	var panel := StoneUI.StonePanel.new(18.0)
	panel.custom_minimum_size = Vector2(190, 0)
	panel.size_flags_stretch_ratio = 0.55
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	v.add_child(StoneUI.Rail.new("PERSONAJE", 11))
	_preview = CharacterPreview.new()
	_preview.name = "Personaje"
	_preview.play_intro = false
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.custom_minimum_size = Vector2(120, 260)
	v.add_child(_preview)
	_preview.show_equipment(equipment)
	_preview.show_character(CharacterLook.CHAR_ID, Color(0.7, 0.5, 1.0))
	v.add_child(_text("Arrastra para girarlo", 9, StoneUI.TEXT_DIM))

## Columna central: placa de huecos del equipo y el arma, detalle de lo elegido y mochila.
func _build_center(parent: Container) -> void:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_stretch_ratio = 2.0
	col.add_theme_constant_override("separation", 10)
	parent.add_child(col)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(top)
	var wbox := VBoxContainer.new()
	wbox.add_theme_constant_override("separation", 4)
	top.add_child(wbox)
	_weapon_socket = StoneUI.Socket.new(92.0)
	_weapon_socket.name = "Hueco_arma"
	_weapon_socket.pressed.connect(func():
		if not _weapon_socket.take_long_press():
			select_slot("arma"))
	_weapon_socket.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	wbox.add_child(_weapon_socket)
	var wl := _text("EN LA MANO", 9, StoneUI.AMBER, false)
	wl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wbox.add_child(wl)
	_plate = StoneUI.SocketPlate.new(PLATE_SLOTS.size(), 1, 76.0, 18.0, 20.0)
	_plate.name = "Placa_equipo"
	_plate.socket_pressed.connect(func(i): select_slot(PLATE_SLOTS[i]))
	top.add_child(_plate)
	var dp := StoneUI.StonePanel.new(16.0)
	dp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(dp)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dp.add_child(scroll)
	_detail = VBoxContainer.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_theme_constant_override("separation", 6)
	scroll.add_child(_detail)
	_bag_title = StoneUI.Rail.new("MOCHILA", 11)
	col.add_child(_bag_title)
	_bag_plate = StoneUI.SocketPlate.new(PlayerEquipment.BAG_MAX, 1, 58.0, 12.0, 16.0)
	_bag_plate.name = "Placa_mochila"
	_bag_plate.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_bag_plate.socket_pressed.connect(select_bag_index)
	col.add_child(_bag_plate)

func _build_stats(parent: Container) -> void:
	var panel := StoneUI.StonePanel.new(18.0)
	panel.custom_minimum_size = Vector2(230, 0)
	panel.size_flags_stretch_ratio = 0.85
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	v.add_child(StoneUI.Rail.new("ESTADÍSTICAS", 11))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_stats_label = _text("", 9, StoneUI.TEXT)
	_stats_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_stats_label)

# ───────────────────────────── selección ─────────────────────────────

func select_slot(slot: String) -> void:
	_sel_slot = slot
	_sel_bag_uid = ""
	refresh()

func select_bag(item: Dictionary) -> void:
	_sel_slot = ""
	_sel_bag_uid = String(item.get("uid", ""))
	refresh()

func select_bag_index(i: int) -> void:
	if i >= 0 and i < equipment.bag.size():
		select_bag(equipment.bag[i])

func _bag_item_selected() -> Dictionary:
	for it in equipment.bag:
		if String(it.get("uid", "")) == _sel_bag_uid:
			return it
	return {}

# ───────────────────────────── refresco ─────────────────────────────

func _icon_of(it: Dictionary) -> Texture2D:
	if not it.is_empty() and String(it.get("slot", "")) == "arma":
		var path := String(WeaponChoiceUI.ICONS.get(int(it.get("weapon", -1)), ""))
		if path != "" and ResourceLoader.exists(path):
			return load(path)
	return null

func refresh() -> void:
	if not is_inside_tree() or equipment == null:
		return
	# La elección sigue siendo válida? Si no, la primera ranura con pieza.
	if _sel_bag_uid != "" and _bag_item_selected().is_empty():
		_sel_bag_uid = ""
	if _sel_bag_uid == "" and _sel_slot == "":
		for s in PLATE_SLOTS + ["arma"]:     # por defecto la primera ranura con pieza (una ranura vacía también se puede elegir)
			if not equipment.get_item(s).is_empty():
				_sel_slot = s
				break
	for i in PLATE_SLOTS.size():
		var slot: String = PLATE_SLOTS[i]
		var s: StoneUI.Socket = _plate.sockets[i]
		s.show_item(equipment.get_item(slot), EquipmentDB.KIND_ICONS["talisman" if slot.begins_with("talisman") else slot])
		s.set_selected(_sel_slot == slot)
	var w := equipment.get_item("arma")
	_weapon_socket.show_item(w, EquipmentDB.KIND_ICONS["arma"], _icon_of(w))
	_weapon_socket.set_selected(_sel_slot == "arma")
	_bag_title.set_text("MOCHILA  %d/%d" % [equipment.bag.size(), PlayerEquipment.BAG_MAX])
	for i in _bag_plate.sockets.size():
		var bs: StoneUI.Socket = _bag_plate.sockets[i]
		var it: Dictionary = equipment.bag[i] if i < equipment.bag.size() else {}
		bs.show_item(it, EquipmentDB.KIND_ICONS.get(String(it.get("slot", "")), "✦"), _icon_of(it))
		# Ratón encima o pulsación larga: tarjeta con la comparación contra lo que llevas
		bs.card_builder = func() -> Control: return StoneUI.item_card(it, equipment.stat_delta(it), equipment.equipped_for(it))
		bs.set_selected(not it.is_empty() and String(it.get("uid", "")) == _sel_bag_uid)
	_rebuild_detail()
	var lines: Array = []
	if stat_block:
		lines.append_array(stat_block.describe())
	var sets := equipment.set_summary()
	if not sets.is_empty():
		lines.append("")
		lines.append_array(sets)
	_stats_label.text = "\n".join(lines)

func _rebuild_detail() -> void:
	for c in _detail.get_children():
		c.queue_free()
		_detail.remove_child(c)
	if _sel_bag_uid != "":
		_fill_bag_detail(_bag_item_selected())
	elif _sel_slot != "":
		_fill_slot_detail(_sel_slot)
	else:
		_detail.add_child(_text("Elige un hueco para ver su pieza. La mochila está vacía: rompe cajas y barriles, abre cofres o compra a Tatan en la forja.", 11, StoneUI.TEXT_DIM))

## Menú de una ranura: lo que llevas puesto (con Quitar) y la lista de objetos de la mochila que caben ahí, cada uno
## con su comparación y su botón Equipar. (La información completa de cualquier pieza sale al pasar el ratón / pulsación larga.)
func _fill_slot_detail(slot: String) -> void:
	var cur := equipment.get_item(slot)
	_detail.add_child(StoneUI.Rail.new("OBJETOS PARA " + String(SLOT_LABELS[slot]).to_upper(), 11))
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	_detail.add_child(head)
	if cur.is_empty():
		head.add_child(_text("Ranura vacía", 11, StoneUI.TEXT_DIM, false))
	else:
		var l := _text("Llevas: %s (%s)" % [cur.get("name", ""), EquipmentDB.rarity_name(cur)], 11, EquipmentDB.rarity_color(cur))
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(l)
		if slot != "arma":
			var q := _small_button("Quitar")
			q.name = "Quitar_" + slot
			q.disabled = equipment.bag.size() >= PlayerEquipment.BAG_MAX
			q.pressed.connect(func(): equipment.unequip(slot))
			head.add_child(q)
	var found := 0
	for it in equipment.bag:
		if not EquipmentDB.slots_for(it).has(slot):
			continue
		found += 1
		_detail.add_child(_candidate_row(it, slot))
	if found == 0:
		_detail.add_child(_text("No tienes objetos para esta ranura en la mochila. Rompe cajas y barriles, abre cofres o compra a Tatan en la forja.", 10, StoneUI.TEXT_DIM))

## Una fila del menú de ranura: hueco con la pieza, nombre, cambio de stats frente a lo puesto y Equipar.
func _candidate_row(it: Dictionary, slot: String) -> Control:
	var col := EquipmentDB.rarity_color(it)
	var box := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.07, 0.06, 0.06, 0.9)
	st.set_border_width_all(2)
	st.border_color = Color(col, 0.7) if int(it.get("rarity", 0)) > 0 else Color(0.34, 0.33, 0.32)
	st.set_corner_radius_all(3)
	st.set_content_margin_all(8)
	box.add_theme_stylebox_override("panel", st)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var sock := StoneUI.Socket.new(58.0)
	sock.show_item(it, EquipmentDB.KIND_ICONS.get(String(it.get("slot", "")), "✦"), _icon_of(it))
	sock.card_builder = func() -> Control: return StoneUI.item_card(it, equipment.stat_delta(it, slot), equipment.get_item(slot))
	sock.pressed.connect(func():
		if not sock.take_long_press():
			equipment.equip(it, slot))
	row.add_child(sock)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 2)
	row.add_child(v)
	v.add_child(_text(String(it.get("name", "")), 12, col))
	var flow := HFlowContainer.new()
	v.add_child(flow)
	var delta := equipment.stat_delta(it, slot)
	for k in delta:
		var val := float(delta[k])
		if not is_zero_approx(val):
			flow.add_child(_text(EquipmentDB.format_stat(k, val) + "   ", 9, GOOD if val > 0.0 else BAD, false))
	var tl := EquipmentDB.trait_lines(it)
	if not tl.is_empty():
		v.add_child(_text(" · ".join(tl), 9, Color(col, 0.85)))
	var b := _small_button("Equipar")
	b.name = "Equipar"
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func(): equipment.equip(it, slot))
	row.add_child(b)
	return box

func _fill_bag_detail(it: Dictionary) -> void:
	if it.is_empty():
		return
	var kind := String(it.get("slot", ""))
	_detail.add_child(StoneUI.Rail.new(String(EquipmentDB.KIND_NAMES.get(kind, "")).to_upper() + " · MOCHILA", 11))
	_item_text(_detail, it, true)
	# Comparación contra lo que hay en su ranura (el primer talismán si son dos)
	var delta := equipment.stat_delta(it)
	var flow := HFlowContainer.new()
	_detail.add_child(flow)
	for k in delta:
		var val := float(delta[k])
		if is_zero_approx(val):
			continue
		flow.add_child(_text(EquipmentDB.format_stat(k, val) + "   ", 10, GOOD if val > 0.0 else BAD, false))
	# Rasgos (elemento, modificador, efecto): qué cambia frente a lo que llevas puesto
	var old := equipment.equipped_for(it)
	if not old.is_empty() and EquipmentDB.trait_lines(old) != EquipmentDB.trait_lines(it):
		var old_t := EquipmentDB.trait_lines(old)
		_detail.add_child(_text("Ahora llevas: " + (" | ".join(old_t) if not old_t.is_empty() else "sin efectos"), 9, StoneUI.TEXT_DIM))
	var btns := HFlowContainer.new()
	btns.add_theme_constant_override("h_separation", 8)
	btns.add_theme_constant_override("v_separation", 6)
	_detail.add_child(btns)
	var slots := EquipmentDB.slots_for(it)
	if kind == "talisman":
		for s in slots:
			var b := _small_button("Equipar en %s" % SLOT_LABELS[s].trim_prefix("Talismán "))
			b.name = "Equipar" if s == slots[0] else "Equipar2"
			b.pressed.connect(func(): equipment.equip(it, s))
			btns.add_child(b)
	else:
		var b := _small_button("Equipar")
		b.name = "Equipar"
		b.pressed.connect(func(): equipment.equip(it))
		btns.add_child(b)
	var drop := _small_button("Tirar")
	drop.name = "Tirar"
	drop.pressed.connect(func(): equipment.discard(it))
	btns.add_child(drop)

## Nombre, rareza, stats y rasgos de una pieza dentro de `v`. `hide_stats`: en la mochila los stats salen como comparación.
func _item_text(v: Container, it: Dictionary, hide_stats: bool) -> void:
	if it.is_empty():
		v.add_child(_text("— vacío —", 12, StoneUI.TEXT_DIM))
		return
	var col := EquipmentDB.rarity_color(it)
	v.add_child(_text(String(it.get("name", "")), 15, col))
	v.add_child(_text(EquipmentDB.rarity_name(it), 10, Color(col, 0.75)))
	var st := EquipmentDB.describe_stats(it.get("stats", {}))
	if not st.is_empty() and not hide_stats:
		v.add_child(_text("\n".join(st), 11, StoneUI.TEXT))
	_add_perk_line(v, it)
	if EquipmentDB.SETS.has(String(it.get("set", ""))):
		v.add_child(_text("Set " + String(EquipmentDB.SETS[it["set"]]["name"]), 10, StoneUI.TEXT_DIM))

## Líneas de rasgos de una pieza (elemento, modificador, efecto), en el color de su rareza o de su elemento.
func _add_perk_line(v: Control, it: Dictionary) -> void:
	var el := EquipmentDB.element_of(it)
	for line in EquipmentDB.trait_lines(it):
		var col := EquipmentDB.rarity_color(it)
		if el != "" and (line.begins_with("Elemento") or line.begins_with("Armadura de")):
			col = EquipmentDB.ELEMENTS[el]["color"]
		v.add_child(_text(line, 10, col))

func _text(t: String, size: int, color: Color, wrap: bool = true) -> Label:
	var l := Label.new()
	l.text = t
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _small_button(t: String) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(0, 30)
	StoneUI.style_button(b, 11)
	return b
