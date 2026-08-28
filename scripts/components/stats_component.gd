class_name StatsComponent
extends Node

signal stats_changed(hp, max_hp, shield, max_shield, energy, max_energy)
signal entity_died
signal experience_gained(amount, current_xp, required_xp)
signal leveled_up(new_level)

@export var max_hp: float = 100.0
@export var max_shield: float = 50.0
@export var max_energy: float = 200.0
@export var shield_regen_delay: float = 4.0

var hp: float
var shield: float
var energy: float

var level: int = 1
var experience: float = 0.0
var experience_required: float = 10.0

var time_since_damage: float = 0.0
var invincibility_time: float = 0.0
var _parent: Node

func _ready() -> void:
	hp = max_hp
	shield = max_shield
	energy = max_energy
	_parent = get_parent()

func _process(delta: float) -> void:
	if invincibility_time > 0:
		invincibility_time -= delta
		
	time_since_damage += delta
	_handle_shield_regen(delta)
	
	if energy < max_energy:
		energy = min(max_energy, energy + delta * 15.0)
		_emit_stats()

func _handle_shield_regen(delta: float) -> void:
	# If parent has a passive that blocks regen, check it
	var can_regen: bool = true
	if _parent and "passive" in _parent and _parent.passive != null:
		if _parent.passive.has_method("allow_shield_regen"):
			can_regen = _parent.passive.allow_shield_regen(_parent)
			
	if can_regen and time_since_damage >= shield_regen_delay and shield < max_shield:
		var was_empty := shield <= 0.0
		shield = min(max_shield, shield + delta * 2.5)
		if was_empty and shield >= max_shield and _parent and "passive" in _parent and _parent.passive != null:
			if _parent.passive.has_method("on_shield_recharged"):
				_parent.passive.on_shield_recharged()
		_emit_stats()

func take_damage(amount: float) -> void:
	if invincibility_time > 0:
		return
	invincibility_time = 1.0 # 1.0 seconds of i-frames
	time_since_damage = 0.0

	var hp_damage := amount
	
	if _parent and "passive" in _parent and _parent.passive != null:
		if _parent.passive.has_method("on_take_damage"):
			hp_damage = _parent.passive.on_take_damage(_parent, amount)
			hp = max(0.0, hp - hp_damage)
		else:
			_default_damage(amount)
	else:
		_default_damage(amount)

	_emit_stats()

	if hp <= 0:
		emit_signal("entity_died")

func _default_damage(amount: float) -> void:
	if shield > 0:
		if shield >= amount:
			shield -= amount
		else:
			var rem = amount - shield
			shield = 0
			hp = max(0, hp - rem)
	else:
		hp = max(0, hp - amount)

func heal(amount: float) -> void:
	hp = min(max_hp, hp + amount)
	_emit_stats()

func restore_energy(amount: float) -> void:
	energy = min(max_energy, energy + amount)
	_emit_stats()

func consume_energy(amount: float) -> bool:
	if energy >= amount:
		energy -= amount
		_emit_stats()
		return true
	return false

func _emit_stats() -> void:
	emit_signal("stats_changed", hp, max_hp, shield, max_shield, energy, max_energy)

func gain_experience(amount: float) -> void:
	experience += amount
	emit_signal("experience_gained", amount, experience, experience_required)
	
	while experience >= experience_required:
		experience -= experience_required
		level += 1
		experience_required *= 1.5 # Incremental difficulty, this can be customized
		emit_signal("leveled_up", level)
		emit_signal("experience_gained", 0, experience, experience_required)

