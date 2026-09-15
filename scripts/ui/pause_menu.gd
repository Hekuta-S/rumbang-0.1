extends CanvasLayer

@onready var resume_btn = $Control/VBox/ResumeBtn
@onready var menu_btn = $Control/VBox/MenuBtn
@onready var options_btn = $Control/VBox/OptionsBtn
@onready var quit_btn = $Control/VBox/QuitBtn

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	resume_btn.pressed.connect(_on_resume_pressed)
	menu_btn.pressed.connect(_on_menu_pressed)
	options_btn.pressed.connect(_on_options_pressed)
	quit_btn.pressed.connect(_on_quit_pressed)

func _input(event):
	if event.is_action_pressed("ui_cancel"):
		if visible:
			close_menu()
		else:
			open_menu()

func open_menu():
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func close_menu():
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_resume_pressed():
	close_menu()

func _on_menu_pressed():
	get_tree().paused = false
	SceneLoader.load_scene("res://scenes/ui/main_menu.tscn")

func _on_options_pressed():
	var SettingsMenu = load("res://scripts/ui/settings_menu.gd")
	var sm = SettingsMenu.new()
	add_child(sm)

func _on_quit_pressed():
	get_tree().quit()
