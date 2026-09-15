class_name HealthComponent
extends Node

signal health_changed(hp, max_hp, shield, max_shield)
signal entity_died

# Used to modify damage before it is applied. Listeners can modify data["amount"].
signal damage_taking(data: Dictionary)
# Used to check if shield regen is allowed. Listeners append true/false to results.
signal check_shield_regen(results: Array)
# Emitted when shield finishes recharging from 0 to full.
signal shield_recharged

@export var max_hp: float = 100.0
@export var max_shield: float = 50.0
@export var shield_regen_delay: float = 4.0

var hp: float
var shield: float
var time_since_damage: float = 0.0
var invincibility_time: float = 0.0

func _ready() -> void:
	hp = max_hp
	shield = max_shield

func _process(delta: float) -> void:
	if invincibility_time > 0:
		invincibility_time -= delta
		
	time_since_damage += delta
	_handle_shield_regen(delta)

func _handle_shield_regen(delta: float) -> void:
	var can_regen: bool = true
	var results: Array = []
	check_shield_regen.emit(results)
	for res in results:
		if res == false:
			can_regen = false
			
	if can_regen and time_since_damage >= shield_regen_delay and shield < max_shield:
		var was_empty := shield <= 0.0
		shield = min(max_shield, shield + delta * 2.5)
		if was_empty and shield >= max_shield:
			shield_recharged.emit()
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
	if shield > 0:
		if shield >= amount:
			shield -= amount
		else:
			var rem = amount - shield
			shield = 0
			hp = max(0.0, hp - rem)
	else:
		hp = max(0.0, hp - amount)

func heal(amount: float) -> void:
	hp = min(max_hp, hp + amount)
	_emit_stats()

func _emit_stats() -> void:
	health_changed.emit(hp, max_hp, shield, max_shield)
