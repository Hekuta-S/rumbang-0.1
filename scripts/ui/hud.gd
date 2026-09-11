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

@onready var crosshair: Control = $Control/Crosshair
@onready var game_over_screen: Control = $GameOverScreen
@onready var victory_screen: Control = $VictoryScreen

@onready var xp_bar: ProgressBar = $Control/HubImage/XPBar

var fps_label: Label

@onready var weapon_slots: Array = [
	$Control/HubImage/WeaponSlot1/Icon,
	$Control/HubImage/WeaponSlot2/Icon,
	$Control/HubImage/WeaponSlot3/Icon,
	$Control/HubImage/WeaponSlot4/Icon,
	$Control/HubImage/WeaponSlot5/Icon
]

var weapon_textures: Dictionary = {
	"Bazuca de Esporas": preload("res://assets/ui/ingame_hub/armas/bazoka_esporas.png"),
	"Escopeta Triple": preload("res://assets/ui/ingame_hub/armas/escopeta.png"),
	"Escopeta de Humo": preload("res://assets/ui/ingame_hub/armas/escopeta.png"),
	"Espalanza de Mikeura": preload("res://assets/ui/ingame_hub/armas/espalanza.png"),
	"Lanzallamas": preload("res://assets/ui/ingame_hub/armas/lanzallamas.png"),
	"Cañón Railgun": preload("res://assets/ui/ingame_hub/armas/magia-saimon.png"),
	"Rifle de Plasma": preload("res://assets/ui/ingame_hub/armas/pistola.png"),
	"Polvos Alquímicos": preload("res://assets/ui/ingame_hub/armas/polvos.png")
}
@onready var stats_panel: Control = $Control/StatsPanel
var _stats_base_pos: Vector2
var _last_camera_pos: Vector3
var _current_sway: Vector2 = Vector2.ZERO

func _ready() -> void:
	if stats_panel:
		_stats_base_pos = stats_panel.position
	_create_fps_label()
	call_deferred("_connect_to_player")

func _process(delta: float) -> void:
	if is_instance_valid(fps_label):
		fps_label.text = "FPS: %d" % Engine.get_frames_per_second()
		
	# Efecto de sway dinámico para la barra de estado
	if stats_panel:
		var cam = get_viewport().get_camera_3d()
		if cam:
			if _last_camera_pos == Vector3.ZERO:
				_last_camera_pos = cam.global_position
			
			var delta_pos = cam.global_position - _last_camera_pos
			_last_camera_pos = cam.global_position
			
			# Calculamos el empuje inverso (si la cámara va a la derecha, la UI se inclina a la izquierda)
			# Usamos Z para el eje Y de la pantalla (cámara top-down)
			var sway_push = Vector2(-delta_pos.x, -delta_pos.z) * 800.0
			
			# Integramos el empuje y lo suavizamos de vuelta a 0
			_current_sway = _current_sway.lerp(sway_push, 15.0 * delta)
			
			# Limitamos el sway máximo
			if _current_sway.length() > 30.0:
				_current_sway = _current_sway.normalized() * 30.0
				
			stats_panel.position = stats_panel.position.lerp(_stats_base_pos + _current_sway, 10.0 * delta)
		else:
			stats_panel.position = stats_panel.position.lerp(_stats_base_pos, 10.0 * delta)

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

func update_xp(_level: int, current_xp: float, required_xp: float) -> void:
	if xp_bar:
		xp_bar.max_value = required_xp
		xp_bar.value = current_xp



func update_weapons(active_index: int, weapons_list: Array) -> void:
	print("UPDATE WEAPONS CALLED, active: ", active_index, ", list size: ", weapons_list.size())
	for i in range(weapon_slots.size()):
		var slot_icon = weapon_slots[i]
		if i < weapons_list.size():
			var w_name = weapons_list[i].get("name", "")
			print("Slot ", i, " weapon: ", w_name)
			if weapon_textures.has(w_name):
				slot_icon.texture = weapon_textures[w_name]
			else:
				# Fallback a pistola si no hay imagen
				slot_icon.texture = preload("res://assets/ui/ingame_hub/armas/pistola.png")
				print("WARNING: Texture not found for ", w_name, ", using fallback")
			
			slot_icon.modulate = Color(1, 1, 1, 1.0)
			slot_icon.pivot_offset = slot_icon.size / 2.0
			
			if i == active_index:
				slot_icon.scale = Vector2(1.15, 1.15)
			else:
				slot_icon.scale = Vector2(0.85, 0.85)
		else:
			slot_icon.texture = null

func update_reload(_weapon_type: int, _ammo: int, _max_ammo: int, is_reloading: bool, progress: float) -> void:
	pass

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
