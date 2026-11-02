class_name CameraController
extends Node

@export_group("Camera Settings")
@export var camera_offset: Vector3 = Vector3(0.0, 0.1, 0.0)   # x = 0: personaje centrado en pantalla
@export var min_spring_length: float = 2.5
@export var max_spring_length: float = 10.0
@export var zoom_speed: float = 0.5
@export var camera_margin: float = 0.2
@export var camera_smoothness: float = 26.0

var camera_kick_z: float = 0.0
var target_yaw: float = 0.0
var target_pitch: float = 0.0
var target_spring_length: float = 4.0

@onready var player = get_parent()
@onready var spring_arm: SpringArm3D = player.get_node("SpringArm3D")
@onready var camera: Camera3D = player.get_node("SpringArm3D/Camera3D")
var camera_pivot: Node3D

## Mazmorra: brazo con esfera de colisión (no atraviesa paredes), regreso suave tras chocar,
## zoom con la rueda y seguimiento del objetivo fijado (TargetLockController).
## Estilo Deadlock: cámara pegada a la espalda y algo elevada, al hombro derecho, con campo de visión
## amplio y el punto de mira libre en el centro de la pantalla.
const DUNGEON_SPRING_LENGTH := 3.3
const DUNGEON_MIN_LENGTH := 2.2
const DUNGEON_MAX_LENGTH := 5.2
const DUNGEON_START_PITCH := -0.1    ## empieza mirando un poco hacia abajo (el horizonte queda sobre el crosshair)
const FOV_BASE := 80.0
const FOV_DODGE := 88.0              ## el campo de visión se abre un instante al rodar
const FOV_SPEED := 9.0
const ARM_RETURN_SPEED := 5.0        ## lo rápido que se aleja de nuevo tras acercarse por una pared
const LOCK_YAW_SPEED := 7.0
const LOCK_PITCH := -0.28           ## inclinación a la que tiende la cámara con objetivo fijado
## Cámara al hombro: el personaje queda a la izquierda y el crosshair libre en el centro.
const SHOULDER := Vector3(0.78, 0.5, 0.0)
const SHOULDER_MARGIN := 0.25       ## distancia mínima de la cámara a una pared lateral
var _dungeon := false
var _cam_len := -1.0
var _shoulder_x := SHOULDER.x

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

	_dungeon = GameData.game_mode == "dungeon"
	if _dungeon:
		var sphere := SphereShape3D.new()
		sphere.radius = 0.25
		spring_arm.shape = sphere
		target_spring_length = DUNGEON_SPRING_LENGTH
		spring_arm.spring_length = target_spring_length
		camera_offset = SHOULDER
		camera.fov = FOV_BASE
		target_pitch = DUNGEON_START_PITCH
		spring_arm.rotation.x = target_pitch

func handle_input(event: InputEvent) -> void:
	if _dungeon and event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var step := -zoom_speed if event.button_index == MOUSE_BUTTON_WHEEL_UP else zoom_speed
			target_spring_length = clampf(target_spring_length + step, DUNGEON_MIN_LENGTH, DUNGEON_MAX_LENGTH)
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if _locked():
			player.target_lock.feed_flick(event.relative.x)
		else:
			target_yaw -= event.relative.x * player.mouse_sensitivity * SettingsManager.look_sensitivity
		target_pitch = clampf(target_pitch - event.relative.y * player.mouse_sensitivity * SettingsManager.look_sensitivity, -1.2, 0.9)

func _physics_process(delta: float) -> void:
	var smooth := 1.0 - exp(-camera_smoothness * delta)
	
	var joy_look_x = Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var joy_look_y = Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	
	if abs(joy_look_x) > 0.1:
		if _locked():
			player.target_lock.feed_flick(joy_look_x * 900.0 * delta)
		else:
			target_yaw -= joy_look_x * 3.0 * delta * SettingsManager.look_sensitivity
	if abs(joy_look_y) > 0.1:
		target_pitch = clampf(target_pitch - joy_look_y * 3.0 * delta * SettingsManager.look_sensitivity, -1.2, 0.9)
		
	if VirtualInput.look_vector.length_squared() > 0.0:
		var touch_k: float = player.mouse_sensitivity * SettingsManager.touch_look_sensitivity
		if _locked():
			player.target_lock.feed_flick(VirtualInput.look_vector.x)
		else:
			target_yaw -= VirtualInput.look_vector.x * touch_k
		target_pitch = clampf(target_pitch - VirtualInput.look_vector.y * touch_k, -1.2, 0.9)
	
	if _locked():
		var to_t: Vector3 = player.target_lock.target_point() - spring_arm.global_position
		var lock_k := 1.0 - exp(-LOCK_YAW_SPEED * delta)
		target_yaw += angle_difference(target_yaw, atan2(-to_t.x, -to_t.z)) * lock_k
		target_pitch = lerpf(target_pitch, LOCK_PITCH, lock_k * 0.5)

	spring_arm.rotation.x = lerp_angle(spring_arm.rotation.x, target_pitch, smooth)
	spring_arm.rotation.y = lerp_angle(spring_arm.rotation.y, target_yaw, smooth)
	spring_arm.spring_length = lerp(spring_arm.spring_length, target_spring_length, 14.0 * delta)

	# Tras chocar con una pared el brazo se acorta al instante; aquí se suaviza el regreso
	var arm_pull := 0.0
	if _dungeon:
		var hit := spring_arm.get_hit_length()
		if _cam_len < 0.0 or hit < _cam_len:
			_cam_len = hit
		else:
			_cam_len = lerpf(_cam_len, hit, 1.0 - exp(-ARM_RETURN_SPEED * delta))
		arm_pull = _cam_len - hit
		_update_shoulder(delta)
		var rolling: bool = player.movement_controller != null and player.movement_controller.is_dodging()
		camera.fov = lerpf(camera.fov, FOV_DODGE if rolling else FOV_BASE, 1.0 - exp(-FOV_SPEED * delta))

	if abs(camera_kick_z) > 0.001:
		camera_kick_z = lerp(camera_kick_z, 0.0, delta * 14.0)
		camera.position = camera_offset + Vector3(0.0, 0.0, camera_kick_z + arm_pull)
	else:
		camera.position = camera_offset + Vector3(0.0, 0.0, arm_pull)

func apply_camera_recoil(pitch_amount: float, yaw_amount: float, kick_z: float = 0.08) -> void:
	target_pitch = clamp(target_pitch + pitch_amount, deg_to_rad(-65.0), deg_to_rad(45.0))
	target_yaw += yaw_amount
	camera_kick_z += kick_z

## Si hay pared a la derecha, la cámara se acerca al centro (y vuelve despacio).
func _update_shoulder(delta: float) -> void:
	var from := camera_pivot.global_position + camera_pivot.global_basis.y * SHOULDER.y
	var to := from + camera_pivot.global_basis.x * (SHOULDER.x + SHOULDER_MARGIN)
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	q.exclude = [player.get_rid()]
	var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(q)
	var want := SHOULDER.x
	if not hit.is_empty():
		want = clampf(from.distance_to(hit.position) - SHOULDER_MARGIN, 0.0, SHOULDER.x)
	if want < _shoulder_x:
		_shoulder_x = want
	else:
		_shoulder_x = lerpf(_shoulder_x, want, 1.0 - exp(-4.0 * delta))
	camera_offset.x = _shoulder_x

func _locked() -> bool:
	return _dungeon and player.target_lock != null and player.target_lock.has_target()
