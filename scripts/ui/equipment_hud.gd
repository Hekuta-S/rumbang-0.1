class_name EquipmentHud
extends CanvasLayer

## Tira pequeña del HUD (mazmorra): un icono por ranura de equipo, del color de la rareza de lo que
## llevas (gris apagado si está vacía), y cuántas piezas hay en la mochila. Detalle en pausa > EQUIPO.

const Style := preload("res://scripts/ui/rumbang_style.gd")
const ICONS := {"casco": "⛑", "pechera": "🛡", "pantalones": "👖", "talisman_1": "🔮", "talisman_2": "🔮", "arma": "⚔"}
const SLOTS := ["casco", "pechera", "pantalones", "talisman_1", "talisman_2"]

var equipment: PlayerEquipment
var _row: HBoxContainer
var _plate: StoneUI.SocketPlate
var _bag: Label
var _buffs: Label                     ## efectos temporales activos y su tiempo
var last_popup: Label                 ## último aviso de efecto (para pruebas)

static func attach(parent: Node, p_equipment: PlayerEquipment) -> EquipmentHud:
	var h := EquipmentHud.new()
	h.name = "EquipmentHud"
	h.equipment = p_equipment
	parent.add_child(h)
	return h

func _ready() -> void:
	layer = 12
	_row = HBoxContainer.new()
	_row.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_row.offset_left = 16
	_row.offset_bottom = -176
	_row.add_theme_constant_override("separation", 6)
	_row.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_row)
	# Placa de piedra con un hueco por ranura (el arma ya está en la barra de armas)
	_plate = StoneUI.SocketPlate.new(SLOTS.size(), 1, 30.0, 6.0, 9.0)
	_plate.name = "Placa"
	_row.add_child(_plate)
	_bag = Label.new()
	_bag.add_theme_font_size_override("font_size", 11)
	_bag.add_theme_color_override("font_color", Style.TEXT_DIM)
	_bag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_child(_bag)
	_buffs = Label.new()
	_buffs.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_buffs.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_buffs.offset_left = 16
	_buffs.offset_bottom = -200
	_buffs.add_theme_font_size_override("font_size", 10)
	_buffs.add_theme_constant_override("outline_size", 5)
	_buffs.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_buffs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_buffs)
	if equipment:
		equipment.equipment_changed.connect(refresh)
		equipment.perk_triggered.connect(_on_perk_triggered)
	refresh()
	set_process(false)

## Un efecto especial se activó: aviso flotante sobre la tira con su nombre, en el color de la rareza.
func _on_perk_triggered(item: Dictionary, perk: Dictionary) -> void:
	var l := Label.new()
	l.text = "★ " + String(perk.get("name", ""))
	l.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	l.grow_vertical = Control.GROW_DIRECTION_BEGIN
	l.offset_left = 16
	l.offset_bottom = -222
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_color_override("font_color", EquipmentDB.rarity_color(item))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	last_popup = l
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "offset_bottom", -252.0, 0.9)
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
