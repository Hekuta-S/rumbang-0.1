class_name StatsComponent
extends Node

signal stats_changed(hp, max_hp)
signal entity_died
signal experience_gained(amount, current_xp, required_xp)
signal leveled_up(new_level)

@export var max_hp: float = 100.0

var hp: float

var level: int = 1
var experience: float = 0.0
var experience_required: float = 10.0

var time_since_damage: float = 0.0
var invincibility_time: float = 0.0
var _parent: Node

func _ready() -> void:
	hp = max_hp
	_parent = get_parent()

func _process(delta: float) -> void:
	if invincibility_time > 0:
		invincibility_time -= delta
		
	time_since_damage += delta

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
	hp = max(0, hp - amount)

func heal(amount: float) -> void:
	hp = min(max_hp, hp + amount)
	_emit_stats()

func _emit_stats() -> void:
	emit_signal("stats_changed", hp, max_hp)

func gain_experience(amount: float) -> void:
	experience += amount
	emit_signal("experience_gained", amount, experience, experience_required)
	
	while experience >= experience_required:
		experience -= experience_required
		level += 1
		experience_required *= 1.5 # Incremental difficulty, this can be customized
		emit_signal("leveled_up", level)
		emit_signal("experience_gained", 0, experience, experience_required)

