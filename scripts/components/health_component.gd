class_name HealthComponent
extends Node

signal health_changed(hp, max_hp)
signal entity_died

# Used to modify damage before it is applied. Listeners can modify data["amount"].
signal damage_taking(data: Dictionary)
@export var max_hp: float = 100.0

var hp: float
var time_since_damage: float = 0.0
var invincibility_time: float = 0.0
var hp_regen: float = 0.0          ## vida por segundo (la fija PlayerStatBlock)
var _regen_accum: float = 0.0

func _ready() -> void:
	hp = max_hp

func _process(delta: float) -> void:
	if invincibility_time > 0:
		invincibility_time -= delta
		
	time_since_damage += delta
	_handle_hp_regen(delta)

func is_invincible() -> bool:
	return invincibility_time > 0.0

func set_invincibility(duration: float) -> void:
	invincibility_time = maxf(invincibility_time, duration)

func _handle_hp_regen(delta: float) -> void:
	if hp_regen <= 0.0 or hp <= 0.0 or hp >= max_hp:
		_regen_accum = 0.0
		return
	_regen_accum += hp_regen * delta
	if _regen_accum >= 0.1: # curar a golpes de 0.1 para no emitir señales cada frame
		var amount := _regen_accum
		_regen_accum = 0.0
		hp = min(max_hp, hp + amount)
		_emit_stats()

func take_damage(amount: float) -> void:
	if invincibility_time > 0:
		return
	invincibility_time = 1.0 # 1.0 seconds of i-frames
	time_since_damage = 0.0

	var data = {"amount": amount}
	damage_taking.emit(data)
	var final_amount: float = data["amount"]
	
	_default_damage(final_amount)
	_emit_stats()

	if hp <= 0:
		entity_died.emit()

func _default_damage(amount: float) -> void:
	hp = max(0.0, hp - amount)

func heal(amount: float) -> void:
	hp = min(max_hp, hp + amount)
	_emit_stats()

func _emit_stats() -> void:
	health_changed.emit(hp, max_hp)
