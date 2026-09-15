class_name CameraController
extends Node

@export_group("Camera Settings")
@export var camera_offset: Vector3 = Vector3(0.6, 0.4, 0.0)
@export var min_spring_length: float = 2.5
@export var max_spring_length: float = 10.0
@export var zoom_speed: float = 0.5
@export var camera_margin: float = 0.2
@export var camera_smoothness: float = 26.0

var camera_kick_z: float = 0.0
var target_yaw: float = 0.0
var target_pitch: float = 0.0
var target_spring_length: float = 5.5

@onready var player = get_parent()
@onready var spring_arm: SpringArm3D = player.get_node("SpringArm3D")
@onready var camera: Camera3D = player.get_node("SpringArm3D/Camera3D")
var camera_pivot: Node3D

func _ready() -> void:
	spring_arm.margin = camera_margin
	target_spring_length = clamp(spring_arm.spring_length, min_spring_length, max_spring_length)
	spring_arm.spring_length = target_spring_length
	target_yaw = spring_arm.rotation.y
	target_pitch = spring_arm.rotation.x
	
	camera_pivot = Node3D.new()
	spring_arm.add_child(camera_pivot)
	camera.get_parent().remove_child(camera)
	camera_pivot.add_child(camera)
	camera.position = camera_offset

func handle_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		target_yaw -= event.relative.x * player.mouse_sensitivity
		target_pitch = clampf(target_pitch - event.relative.y * player.mouse_sensitivity, -1.2, 0.9)

func _physics_process(delta: float) -> void:
	var smooth := 1.0 - exp(-camera_smoothness * delta)
	
	var joy_look_x = Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var joy_look_y = Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	
	if abs(joy_look_x) > 0.1:
		target_yaw -= joy_look_x * 3.0 * delta
	if abs(joy_look_y) > 0.1:
		target_pitch = clampf(target_pitch - joy_look_y * 3.0 * delta, -1.2, 0.9)
		
	if VirtualInput.look_vector.length_squared() > 0.0:
		target_yaw -= VirtualInput.look_vector.x * player.mouse_sensitivity
		target_pitch = clampf(target_pitch - VirtualInput.look_vector.y * player.mouse_sensitivity, -1.2, 0.9)
	
	spring_arm.rotation.x = lerp_angle(spring_arm.rotation.x, target_pitch, smooth)
	spring_arm.rotation.y = lerp_angle(spring_arm.rotation.y, target_yaw, smooth)
	spring_arm.spring_length = lerp(spring_arm.spring_length, target_spring_length, 14.0 * delta)

	if abs(camera_kick_z) > 0.001:
		camera_kick_z = lerp(camera_kick_z, 0.0, delta * 14.0)
		camera.position = camera_offset + Vector3(0.0, 0.0, camera_kick_z)
	else:
		camera.position = camera_offset

func apply_camera_recoil(pitch_amount: float, yaw_amount: float, kick_z: float = 0.08) -> void:
	target_pitch = clamp(target_pitch + pitch_amount, deg_to_rad(-65.0), deg_to_rad(45.0))
	target_yaw += yaw_amount
	camera_kick_z += kick_z
