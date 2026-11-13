class_name EquipmentHud
extends CanvasLayer

## Tira pequeña del HUD (mazmorra): un icono por ranura de equipo, del color de la rareza de lo que
## llevas (gris apagado si está vacía), y cuántas piezas hay en la mochila. Va a la derecha de la vida
## (ver HudLayout) y es pulsable: tocarla abre el inventario (PauseMenu.open_inventory).

const Style := preload("res://scripts/ui/rumbang_style.gd")
const ICONS := {"casco": "⛑", "pechera": "🛡", "pantalones": "👖", "talisman_1": "🔮", "talisman_2": "🔮", "arma": "⚔"}
const SLOTS := ["casco", "pechera", "pantalones", "talisman_1", "talisman_2"]

var equipment: PlayerEquipment
var _row: HBoxContainer
var _plate: StoneUI.SocketPlate
var _bag: Label
var _buffs: Label                     ## efectos temporales activos y su tiempo
var last_popup: Label                 ## último aviso de efecto (para pruebas)
var _mobile := false
const LABEL_GAP := 4.0                ## separación entre la tira y los bonus temporales
const POPUP_RISE := 30.0              ## lo que sube el aviso de efecto mientras se apaga

static func attach(parent: Node, p_equipment: PlayerEquipment) -> EquipmentHud:
	var h := EquipmentHud.new()
	h.name = "EquipmentHud"
	h.equipment = p_equipment
	parent.add_child(h)
	return h

func _ready() -> void:
	layer = 12
	_row = HBoxContainer.new()
	_row.name = "Row"
	_row.add_theme_constant_override("separation", 6)
	_row.mouse_filter = Control.MOUSE_FILTER_PASS
	_row.gui_input.connect(_on_strip_input)
	add_child(_row)
	# Placa de piedra con un hueco por ranura (el arma ya está en la barra de armas)
	_plate = StoneUI.SocketPlate.new(SLOTS.size(), 1, 30.0, 6.0, 9.0)
	_plate.name = "Placa"
	_plate.gui_input.connect(_on_strip_input)          # entre los huecos
	_plate.socket_pressed.connect(func(_i: int): open_inventory())   # la pulsación larga no lo emite
	_row.add_child(_plate)
	_bag = Label.new()
	_bag.add_theme_font_size_override("font_size", 11)
	_bag.add_theme_color_override("font_color", Style.TEXT_DIM)
	_bag.mouse_filter = Control.MOUSE_FILTER_IGNORE   # el toque llega a la fila
	_bag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_row.add_child(_bag)
	_buffs = Label.new()
	_buffs.name = "Buffs"
	_buffs.add_theme_font_size_override("font_size", 10)
	_buffs.add_theme_constant_override("outline_size", 5)
	_buffs.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_buffs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_buffs)
	if equipment:
		equipment.equipment_changed.connect(refresh)
		equipment.perk_triggered.connect(_on_perk_triggered)
	refresh()
	apply_layout(Quality.is_mobile())
	set_process(false)

## A la derecha de la vida y centrada en vertical con ella (escritorio: abajo; móvil: arriba).
## Los bonus temporales y los avisos van justo debajo de la tira.
func apply_layout(mobile: bool) -> void:
	_mobile = mobile
	var h := _row.get_combined_minimum_size().y
	var cy := HudLayout.vitals_center_y(mobile, true)
	if mobile:
		_row.set_anchors_preset(Control.PRESET_TOP_LEFT)
	else:
		_row.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_row.offset_left = HudLayout.equip_left(mobile)
	_row.offset_top = cy - h * 0.5
	_row.offset_bottom = cy + h * 0.5
	_row.offset_right = _row.offset_left + _row.get_combined_minimum_size().x
	_place_below(_buffs, 0.0)

## Coloca una etiqueta bajo la tira (`rise` px más arriba para la animación del aviso).
func _place_below(l: Label, rise: float) -> void:
	l.set_anchors_preset(Control.PRESET_TOP_LEFT if _mobile else Control.PRESET_BOTTOM_LEFT)
	l.grow_vertical = Control.GROW_DIRECTION_END
	l.offset_left = HudLayout.equip_left(_mobile)
	l.offset_top = _row.offset_bottom + LABEL_GAP - rise
	l.offset_bottom = l.offset_top

func strip_rect() -> Rect2:
	return _row.get_global_rect()

## Clic o toque en la tira (fila, placa entre huecos o mochila): abre el inventario.
func _on_strip_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		open_inventory()

func open_inventory() -> void:
	var pm := get_tree().root.find_child("PauseMenu", true, false)
	if pm and pm.has_method("open_inventory"):
		pm.open_inventory()

## Un efecto especial se activó: aviso flotante bajo la tira con su nombre, en el color de la rareza.
func _on_perk_triggered(item: Dictionary, perk: Dictionary) -> void:
	var l := Label.new()
	l.text = "★ " + String(perk.get("name", ""))
	# Aparece algo más abajo y sube hasta quedar bajo la tira (y bajo los bonus, si hay)
	_place_below(l, -POPUP_RISE)
	if _buffs.text != "":
		l.offset_top += _buffs.get_combined_minimum_size().y
	var rest := l.offset_top - POPUP_RISE
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_color_override("font_color", EquipmentDB.rarity_color(item))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	last_popup = l
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "offset_top", rest, 0.9)
	tw.tween_property(l, "modulate:a", 0.0, 0.9).set_delay(0.3)
	tw.chain().tween_callback(l.queue_free)
	set_process(true)

## Bonus temporales vivos con su tiempo restante ("Pies de Niebla 2.1s").
func _process(_delta: float) -> void:
	if equipment == null or not is_instance_valid(equipment):
		return
	var lines: Array[String] = []
	for b in equipment.active_buffs():
		lines.append("%s %.1fs" % [b["name"], b["left"]])
	_buffs.text = "\n".join(lines)
	if lines.is_empty() and not is_instance_valid(last_popup):
		set_process(false)

func refresh() -> void:
	if equipment == null or not is_instance_valid(equipment):
		return
	for i in SLOTS.size():
		var slot: String = SLOTS[i]
		(_plate.sockets[i] as StoneUI.Socket).show_item(equipment.get_item(slot), ICONS[slot])
	_bag.text = "🎒 %d" % equipment.bag.size() if not equipment.bag.is_empty() else ""
