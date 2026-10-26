class_name MenuBackground
extends Node3D

## Fondo panorámico del menú principal (estilo Minecraft): una cámara orbita
## lentamente sobre el mapa procedural y alterna entre la plaza de inicio y la
## cripta hundida, con un fundido a negro entre planos.
## Se monta dentro de un SubViewport (ver main_menu.gd).

signal fade_requested(to_black: bool, duration: float)

@export var map_seed: int = 1337
@export var orbit_speed: float = 0.07          ## rad/s
@export var shot_duration: float = 16.0        ## segundos por plano
@export var fade_time: float = 0.9

var _map: ProceduralMap
var _camera: Camera3D
var _shots: Array[Dictionary] = []
var _shot_index: int = 0
var _time_in_shot: float = 0.0
var _angle: float = 0.0
var _switching: bool = false

func _ready() -> void:
	_build_environment()
	_map = ProceduralMap.new()
	_map.map_seed = map_seed
	add_child(_map)

	_camera = Camera3D.new()
	_camera.fov = 62.0
	_camera.far = 400.0
	add_child(_camera)
	_camera.current = true

	var basin := _map.get_basin_center()
	_shots = [
		# Plaza de inicio con los braseros y el círculo ritual
		{"target": Vector3(0.0, 1.5, 0.0), "radius": 17.0, "height": 6.5, "look_y": 2.2},
		# Cripta hundida: cámara baja sobre el borde mirando al altar
		{"target": Vector3(basin.x, basin.y + 1.0, basin.z), "radius": 26.0, "height": 11.0, "look_y": 1.5},
	]
	_angle = randf() * TAU
	_apply_camera()

func _process(delta: float) -> void:
	if _camera == null:
		return
	_angle += orbit_speed * delta
	_time_in_shot += delta
	_apply_camera()
	if not _switching and _time_in_shot >= shot_duration:
		_switch_shot()

func _apply_camera() -> void:
	var shot: Dictionary = _shots[_shot_index]
	var target: Vector3 = shot["target"]
	var r: float = shot["radius"]
	var h: float = shot["height"]
	var pos := target + Vector3(cos(_angle) * r, h + sin(_time_in_shot * 0.35) * 0.6, sin(_angle) * r)
	# Nunca por debajo del suelo
	var floor_y := _map.get_height_at(pos.x, pos.z) + 2.5
	pos.y = maxf(pos.y, floor_y)
	_camera.global_position = pos
	_camera.look_at(target + Vector3(0.0, float(shot["look_y"]), 0.0), Vector3.UP)

func _switch_shot() -> void:
	_switching = true
	fade_requested.emit(true, fade_time)
	await get_tree().create_timer(fade_time).timeout
	_shot_index = (_shot_index + 1) % _shots.size()
	_time_in_shot = 0.0
	_angle = randf() * TAU
	_apply_camera()
	fade_requested.emit(false, fade_time)
	await get_tree().create_timer(fade_time).timeout
	_switching = false

func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.015, 0.02, 0.06)
	sky_mat.sky_horizon_color = Color(0.11, 0.09, 0.18)
	sky_mat.ground_bottom_color = Color(0.02, 0.02, 0.04)
	sky_mat.ground_horizon_color = Color(0.08, 0.07, 0.13)
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.16, 0.18, 0.30)
	env.ambient_light_energy = 1.35
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.08
	env.fog_enabled = true
	env.fog_light_color = Color(0.1, 0.11, 0.2)
	env.fog_density = 0.009
	env.fog_sky_affect = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.55, 0.65, 1.0)
	moon.light_energy = 1.1
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 70.0
	moon.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	add_child(moon)
