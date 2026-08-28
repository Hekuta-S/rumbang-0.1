extends CanvasLayer

signal restart_pressed

@onready var hp_bar: ProgressBar = $Control/StatsPanel/Margin/VBox/BarsWithPortrait/DomeClipping/BarsHBox/HPBar
@onready var hp_label: Label = $Control/StatsPanel/Margin/VBox/BarsWithPortrait/LabelsHBox/HPLabel

@onready var shield_bar: ProgressBar = $Control/StatsPanel/Margin/VBox/BarsWithPortrait/DomeClipping/BarsHBox/ShieldBar
@onready var shield_label: Label = $Control/StatsPanel/Margin/VBox/BarsWithPortrait/LabelsHBox/ShieldLabel

@onready var energy_bar: ProgressBar = $Control/StatsPanel/Margin/VBox/BarsWithPortrait/DomeClipping/BarsHBox/EnergyBar
@onready var energy_label: Label = $Control/StatsPanel/Margin/VBox/BarsWithPortrait/LabelsHBox/EnergyLabel

@onready var floor_label: Label = $Control/TopRight/FloorPanel/Margin/FloorLabel
@onready var gold_label: Label = $Control/TopRight/GoldPanel/Margin/GoldLabel

@onready var weapons_container: Container = $Control/WeaponsPanel/Margin/VBox/WeaponsContainer

@onready var reload_bar: ProgressBar = $Control/WeaponsPanel/Margin/VBox/ReloadBar
@onready var reload_label: Label = $Control/WeaponsPanel/Margin/VBox/ReloadBar/ReloadLabel

@onready var crosshair: Control = $Control/Crosshair
@onready var game_over_screen: Control = $GameOverScreen
@onready var victory_screen: Control = $VictoryScreen

var weapon_slot_nodes: Array = []

var xp_bar: ProgressBar
var xp_label: Label
var fps_label: Label

func _ready() -> void:
	_create_xp_bar()
	_create_fps_label()
	setup_weapon_slots_nodes()
	call_deferred("_connect_to_player")

func _process(_delta: float) -> void:
	if is_instance_valid(fps_label):
		fps_label.text = "FPS: %d" % Engine.get_frames_per_second()

func _create_fps_label() -> void:
	fps_label = Label.new()
	fps_label.text = "FPS: 0"
	fps_label.add_theme_font_size_override("font_size", 20)
	fps_label.add_theme_color_override("font_color", Color(0, 1, 0)) # Verde
	fps_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	fps_label.add_theme_constant_override("outline_size", 4)
	
	# Anclar arriba a la derecha
	fps_label.anchor_left = 1.0
	fps_label.anchor_right = 1.0
	fps_label.anchor_top = 0.0
	fps_label.anchor_bottom = 0.0
	
	fps_label.offset_left = -150
	fps_label.offset_right = -20
	fps_label.offset_top = 20
	fps_label.offset_bottom = 50
	fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	
	$Control.add_child(fps_label)

func _create_xp_bar() -> void:
	var xp_panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.5)
	xp_panel.add_theme_stylebox_override("panel", style)
	
	xp_panel.anchor_top = 1.0
	xp_panel.anchor_bottom = 1.0
	xp_panel.anchor_left = 0.0
	xp_panel.anchor_right = 1.0
	xp_panel.offset_top = -30
	xp_panel.offset_bottom = 0
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 5)
	
	xp_bar = ProgressBar.new()
	xp_bar.custom_minimum_size = Vector2(0, 20)
	xp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xp_bar.show_percentage = false
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.1, 0.1, 0.1, 0.8)
	var fill_style = StyleBoxFlat.new()
	fill_style.bg_color = Color(0.2, 0.7, 1.0, 1.0)
	xp_bar.add_theme_stylebox_override("background", bg_style)
	xp_bar.add_theme_stylebox_override("fill", fill_style)
	
	xp_label = Label.new()
	xp_label.text = "LVL 1 - 0/10 XP"
	xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	xp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	xp_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	
	xp_bar.add_child(xp_label)
	margin.add_child(xp_bar)
	xp_panel.add_child(margin)
	$Control.add_child(xp_panel)


func _connect_to_player() -> void:
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_signal("weapon_attacked"):
		if not player.weapon_attacked.is_connected(_on_player_weapon_attacked):
			player.weapon_attacked.connect(_on_player_weapon_attacked)

func _on_player_weapon_attacked(weapon_type: int) -> void:
	trigger_crosshair_kickback(weapon_type)

func trigger_crosshair_kickback(weapon_type: int = -1, strength: float = 1.0) -> void:
	if crosshair and crosshair.has_method("trigger_kickback"):
		crosshair.trigger_kickback(weapon_type, strength)

func setup_weapon_slots_nodes() -> void:
	weapon_slot_nodes.clear()
	if weapons_container:
		for child in weapons_container.get_children():
			weapon_slot_nodes.append(child)

func update_stats(hp: float, max_hp: float, shield: float, max_shield: float, energy: float, max_energy: float) -> void:
	if hp_bar:
		hp_bar.max_value = max_hp
		hp_bar.value = hp
	if hp_label:
		hp_label.text = str(int(ceil(hp)))

	if shield_bar:
		shield_bar.max_value = max_shield
		shield_bar.value = shield
	if shield_label:
		shield_label.text = str(int(ceil(shield)))

	if energy_bar:
		energy_bar.max_value = max_energy
		energy_bar.value = energy
	if energy_label:
		energy_label.text = str(int(ceil(energy)))

func update_xp(level: int, current_xp: float, required_xp: float) -> void:
	if xp_bar:
		xp_bar.max_value = required_xp
		xp_bar.value = current_xp
	if xp_label:
		xp_label.text = "LVL %d - %d/%d XP" % [level, int(current_xp), int(required_xp)]

func update_weapons(active_index: int, weapons_list: Array) -> void:
	if weapon_slot_nodes.size() == 0:
		setup_weapon_slots_nodes()

	for i in range(weapons_list.size()):
		if i < weapon_slot_nodes.size():
			var slot_panel = weapon_slot_nodes[i]
			var w_info = weapons_list[i]
			var is_active = (i == active_index)

			# Show only the slots actually holding a weapon.
			slot_panel.visible = true

			var icon_label = slot_panel.get_node_or_null("Margin/VBox/HBox/IconLabel")
			var key_label = slot_panel.get_node_or_null("Margin/VBox/HBox/KeyLabel")
			var name_label = slot_panel.get_node_or_null("Margin/VBox/NameLabel")
			var cost_label = slot_panel.get_node_or_null("Margin/VBox/CostLabel")

			if icon_label: icon_label.text = w_info.get("icon", "⚔️")
			if key_label: key_label.text = "[" + str(i + 1) + "]"
			if name_label: name_label.text = w_info.get("name", "Arma")
			if cost_label:
				var max_ammo = w_info.get("max_ammo", 0)
				if max_ammo > 0:
					# Magazine weapon: show remaining rounds.
					var ammo = w_info.get("ammo", 0)
					cost_label.text = "🍄 x%d" % max(0, ammo)
				else:
					var cost = w_info.get("cost", 0)
					cost_label.text = (str(cost) + " MP") if cost > 0 else "0 MP"

			# Retro active / inactive styling
			var style = StyleBoxFlat.new()
			style.corner_radius_top_left = 6
			style.corner_radius_top_right = 6
			style.corner_radius_bottom_left = 6
			style.corner_radius_bottom_right = 6

			if is_active:
				style.bg_color = Color(0.14, 0.22, 0.36, 0.95)
				style.border_color = Color(1.0, 0.84, 0.0, 1.0) # Bright gold border
				style.set_border_width_all(3)
				slot_panel.modulate = Color(1.0, 1.0, 1.0, 1.0)
			else:
				style.bg_color = Color(0.06, 0.08, 0.12, 0.7)
				style.border_color = Color(0.2, 0.26, 0.36, 0.6)
				style.set_border_width_all(1)
				slot_panel.modulate = Color(0.65, 0.68, 0.78, 0.65)

			slot_panel.add_theme_stylebox_override("panel", style)

	# Hide any leftover slots that don't hold a weapon.
	for i in range(weapons_list.size(), weapon_slot_nodes.size()):
		weapon_slot_nodes[i].visible = false

## Shows/hides the reload progress bar while a magazine weapon is reloading.
func update_reload(_weapon_type: int, _ammo: int, _max_ammo: int, is_reloading: bool, progress: float) -> void:
	if reload_bar == null:
		return
	reload_bar.visible = is_reloading
	if is_reloading:
		reload_bar.max_value = 100.0
		reload_bar.value = progress * 100.0
		if reload_label:
			reload_label.text = "RECARGANDO " + str(int(progress * 100)) + "%"

func update_floor(sub_lvl: int) -> void:
	if floor_label:
		floor_label.text = "NIVEL 1-" + str(sub_lvl)

func update_gold(gold: int) -> void:
	if gold_label:
		gold_label.text = "🪙 " + str(gold)

func show_game_over() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if game_over_screen:
		game_over_screen.visible = true

func show_victory() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if victory_screen:
		victory_screen.visible = true

func _on_restart_button_pressed() -> void:
	emit_signal("restart_pressed")
