class_name ActiveItemSlot
extends Control

## Hueco del objeto activo de supervivencia (ItemEffects): icono, tecla y recarga. Se coloca bajo la
## bolsa de cuero (BagPanel) y se oculta si no llevas ninguna activa.

const SIZE := 58.0
const ICON_DIR := "res://assets/ui/icons/items/"
const READY_COLOR := Color(1.0, 0.85, 0.35)
const INK := Color(0.1, 0.055, 0.03)

var bag: Control
var _effects: ItemEffects
var _id := ""
var _icon: TextureRect
var _shade: ColorRect
var _cd_label: Label
var _key_label: Label
var _frame: Panel
var _was_ready := true

func _ready() -> void:
	name = "ActiveItemSlot"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = custom_minimum_size
	_frame = Panel.new()
	var fs := StyleBoxFlat.new()
	fs.bg_color = Color(0.19, 0.11, 0.06)
	fs.border_color = INK
	fs.set_border_width_all(3)
	fs.set_corner_radius_all(10)
	fs.shadow_color = Color(0, 0, 0, 0.55)
	fs.shadow_offset = Vector2(3, 3)
	fs.shadow_size = 1
	_frame.add_theme_stylebox_override("panel", fs)
	_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)
	_icon = TextureRect.new()
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_icon.offset_left = 5
	_icon.offset_top = 5
	_icon.offset_right = -5
	_icon.offset_bottom = -5
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon)
	# Sombra de recarga: baja de arriba abajo a medida que se recarga
	_shade = ColorRect.new()
	_shade.color = Color(0.02, 0.01, 0.03, 0.62)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shade)
	_cd_label = Label.new()
	_cd_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cd_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cd_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_cd_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	RumbangStyle.style_title(_cd_label, 20)
	add_child(_cd_label)
	_key_label = Label.new()
	_key_label.text = "E"
	_key_label.position = Vector2(-6, -8)
	_key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	RumbangStyle.style_title(_key_label, 16, READY_COLOR, READY_COLOR)
	_key_label.visible = not Quality.is_mobile()
	add_child(_key_label)
	visible = false

func _process(_delta: float) -> void:
	if not is_instance_valid(_effects):
		var p := get_tree().get_first_node_in_group("player")
		_effects = p.get("item_effects") if p else null
		if _effects == null:
			visible = false
			return
	var id := _effects.active_id()
	if id != _id:
		_id = id
		var path := ICON_DIR + id + ".png"
		_icon.texture = load(path) if id != "" and ResourceLoader.exists(path) else null
		tooltip_text = "%s\n%s" % [ItemDB.get_item(id).get("name", id), ItemDB.get_item(id).get("description", "")] if id != "" else ""
	visible = id != ""
	if not visible:
		return
	_place()
	var left := _effects.cooldown_left()
	var frac := _effects.ready_fraction()
	_shade.position = Vector2.ZERO
	_shade.size = Vector2(SIZE, SIZE * (1.0 - frac))
	_cd_label.text = str(ceili(left)) if left > 0.0 else ""
	var ready := left <= 0.0
	if ready and not _was_ready:
		var tw := create_tween()
		pivot_offset = size * 0.5
		tw.tween_property(self, "scale", Vector2(1.18, 1.18), 0.08)
		tw.tween_property(self, "scale", Vector2.ONE, 0.14)
	_was_ready = ready
	_icon.modulate = Color.WHITE if ready else Color(0.75, 0.75, 0.75)

## Debajo de la bolsa, alineado a su borde derecho.
func _place() -> void:
	if is_instance_valid(bag) and bag.visible:
		var r := bag.get_rect()
		position = Vector2(r.position.x + r.size.x - SIZE, r.position.y + r.size.y + 10.0)
	else:
		var area := get_parent_area_size()
		position = Vector2(area.x - SIZE - 12.0, area.y * 0.5)
