extends Node
class_name RivaSpeedController

var player: CharacterBody3D
var base_speed: float = 7.5

@export var max_speed_boost: float = 5.0
@export var fast_threshold_boost: float = 3.5  # Se activa un poco antes del máximo

@export var accel_rate: float = 2.5 # Se carga mucho más rápido (2 segundos)
@export var decay_rate: float = 1.5 # Tarda más en perderse al detenerse

@export var trail_interval: float = 0.15
@export var trail_lifetime: float = 3.5
@export var trail_dps: float = 15.0
@export var trail_radius: float = 1.5

var _trail_timer: float = 0.0
const _smoke_zone_script := preload("res://scripts/objects/smoke_trail_zone.gd")

var ui_layer: CanvasLayer
var speed_bar: ProgressBar

func _ready() -> void:
	add_to_group("riva_speed_controllers")
	player = get_parent() as CharacterBody3D
	if player:
		base_speed = player.move_speed

	# Create UI Bar
	ui_layer = CanvasLayer.new()
	add_child(ui_layer)

	var margin = MarginContainer.new()
	margin.anchor_top = 1.0
	margin.anchor_bottom = 1.0
	margin.anchor_left = 0.5
	margin.anchor_right = 0.5
	margin.offset_left = -200
	margin.offset_right = 200
	margin.offset_top = -140
	margin.offset_bottom = -90
	ui_layer.add_child(margin)

	var vbox = VBoxContainer.new()
	margin.add_child(vbox)

	var label = Label.new()
	label.text = "Pies Humeantes"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(label)

	speed_bar = ProgressBar.new()
	speed_bar.custom_minimum_size = Vector2(0, 12)
	speed_bar.show_percentage = false
	var bg = StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.1, 0.1, 0.6)
	bg.corner_radius_top_left = 4
	bg.corner_radius_top_right = 4
	bg.corner_radius_bottom_left = 4
	bg.corner_radius_bottom_right = 4
	var fill = StyleBoxFlat.new()
	fill.bg_color = Color(1.0, 0.4, 0.0)
	fill.corner_radius_top_left = 4
	fill.corner_radius_top_right = 4
	fill.corner_radius_bottom_left = 4
	fill.corner_radius_bottom_right = 4
	speed_bar.add_theme_stylebox_override("background", bg)
	speed_bar.add_theme_stylebox_override("fill", fill)
	vbox.add_child(speed_bar)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(player):
		return

	var moving: bool = player.input_controller.get_movement_vector().length_squared() > 0.0001
	if moving:
		player.move_speed = minf(player.move_speed + accel_rate * delta, base_speed + max_speed_boost)
	else:
		player.move_speed = maxf(player.move_speed - decay_rate * delta, base_speed)

	var boost: float = player.move_speed - base_speed
	var is_fast: bool = moving and boost >= fast_threshold_boost - 0.01
	player.is_riva_fast = is_fast

	if is_instance_valid(speed_bar):
		speed_bar.max_value = max_speed_boost
		speed_bar.value = boost
		if is_fast:
			speed_bar.get_theme_stylebox("fill").bg_color = Color(1.0, 0.9, 0.2)
		else:
			speed_bar.get_theme_stylebox("fill").bg_color = Color(1.0, 0.4, 0.0)

	if is_fast:
		_trail_timer += delta
		if _trail_timer >= trail_interval:
			_trail_timer = 0.0
			_spawn_trail_zone()

func _spawn_trail_zone() -> void:
	var parent := player.get_parent()
	if parent == null or not parent.is_inside_tree():
		return
	var zone: Area3D = _smoke_zone_script.new()
	zone.radius = trail_radius
	zone.damage_per_tick = trail_dps * 0.5
	zone.tick_interval = 0.5
	zone.lifetime = trail_lifetime
	parent.add_child(zone)
	zone.global_position = player.global_position + Vector3(0, 0.05, 0)
