extends CanvasLayer

@onready var resume_btn = $Control/VBox/ResumeBtn
@onready var menu_btn = $Control/VBox/MenuBtn
@onready var options_btn = $Control/VBox/OptionsBtn
@onready var quit_btn = $Control/VBox/QuitBtn

const Style := preload("res://scripts/ui/rumbang_style.gd")

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_apply_style()
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

var _stats_label: Label

func _apply_style() -> void:
	$Control.theme = Style.get_theme()
	$Control/ColorRect.color = Color(0.02, 0.01, 0.05, 0.72)
	var vb: VBoxContainer = $Control/VBox
	vb.offset_left = -170.0
	vb.offset_right = 170.0
	var title: Label = vb.get_node("Label")
	title.add_theme_color_override("font_color", Style.TITLE)
	title.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.10))
	title.add_theme_font_size_override("font_size", 30)
	for btn in [resume_btn, menu_btn, options_btn, quit_btn]:
		btn.custom_minimum_size = Vector2(0, 48)

func _refresh_stats_panel() -> void:
	if _stats_label == null:
		_stats_label = Label.new()
		_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_stats_label.add_theme_font_size_override("font_size", 11)
		_stats_label.add_theme_color_override("font_color", Style.TEXT_DIM)
		$Control/VBox.add_child(_stats_label)
	var player := get_tree().get_first_node_in_group("player")
	var sb = player.get("stat_block") if player else null
	if sb == null:
		_stats_label.text = ""
		return
	var lines: Array = ["— Estadísticas —"]
	lines.append_array(sb.describe())
	var inv = player.get("inventory")
	if inv:
		lines.append("Objetos: %d" % inv.collected_items.size())
	# Mejoras específicas por arma (p. ej. Espalanza: Hoja extra 2/7)
	var winv = player.get("weapon_inventory")
	if winv:
		for w in winv.weapon_slots:
			if not WeaponUpgrades.has_specific(w):
				continue
			var parts: Array = []
			for d in WeaponUpgrades.for_weapon(w):
				var lvl: int = winv.get_upgrade_level(w, d["id"])
				if lvl > 0:
					parts.append("%s %s" % [d["name"], WeaponUpgrades.level_label(d, lvl)])
			lines.append("%s: %s" % [WeaponData.weapon_names.get(w, "Arma"), ", ".join(parts) if not parts.is_empty() else "sin mejoras"])
	_stats_label.text = "
".join(lines)

func open_menu():
	_refresh_stats_panel()
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
