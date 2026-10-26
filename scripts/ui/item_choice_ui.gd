extends CanvasLayer

@onready var btn1 = $Control/HBoxContainer/Panel1/MarginContainer/VBoxContainer/SelectBtn1
@onready var btn2 = $Control/HBoxContainer/Panel2/MarginContainer/VBoxContainer/SelectBtn2
@onready var title1 = $Control/HBoxContainer/Panel1/MarginContainer/VBoxContainer/Title1
@onready var title2 = $Control/HBoxContainer/Panel2/MarginContainer/VBoxContainer/Title2
@onready var desc1 = $Control/HBoxContainer/Panel1/MarginContainer/VBoxContainer/Desc1
@onready var desc2 = $Control/HBoxContainer/Panel2/MarginContainer/VBoxContainer/Desc2

var opt1_id: String = ""
var opt2_id: String = ""

signal item_selected(item_id)

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var Style := preload("res://scripts/ui/rumbang_style.gd")
	$Control.theme = Style.get_theme()
	$Control/ColorRect.color = Color(0.02, 0.01, 0.05, 0.72)
	$Control/TitleLabel.add_theme_color_override("font_color", Style.TITLE)
	$Control/TitleLabel.add_theme_font_size_override("font_size", 26)
	for b in [btn1, btn2]:
		b.add_theme_color_override("font_color", Style.TEXT)
	btn1.pressed.connect(func(): _select_item(opt1_id))
	btn2.pressed.connect(func(): _select_item(opt2_id))

func present_choices():
	var player := get_tree().get_first_node_in_group("player")
	var inv: InventoryComponent = player.get("inventory") if player else null
	var all: Array = ItemDB.roll_choices(inv, 2)

	if all.is_empty(): return # Failsafe: todo al máximo
	if all.size() == 1:
		all.append(all[0])

	opt1_id = all[0]["id"]
	opt2_id = all[1]["id"]

	title1.text = all[0]["name"]
	desc1.text = all[0]["description"]
	title2.text = all[1]["name"]
	desc2.text = all[1]["description"]
	
	get_tree().paused = true
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _select_item(id: String):
	item_selected.emit(id)
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
