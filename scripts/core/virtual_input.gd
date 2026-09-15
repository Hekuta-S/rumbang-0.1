extends Node

var movement_vector: Vector2 = Vector2.ZERO
var look_vector: Vector2 = Vector2.ZERO
var is_attacking: bool = false
var is_jumping: bool = false
var is_running: bool = false
var is_alt_attack: bool = false
var is_skill: bool = false
var is_reloading: bool = false

var just_pressed_skill: bool = false
var just_pressed_reload: bool = false
var just_pressed_cycle_next: bool = false
var just_pressed_cycle_prev: bool = false

func _physics_process(delta: float) -> void:
	# Clear the "just pressed" flags at the end of the physics frame
	call_deferred("_clear_just_pressed")

func _clear_just_pressed() -> void:
	look_vector = Vector2.ZERO
	just_pressed_skill = false
	just_pressed_reload = false
	just_pressed_cycle_next = false
	just_pressed_cycle_prev = false

