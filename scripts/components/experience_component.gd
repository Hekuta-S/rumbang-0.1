class_name ExperienceComponent
extends Node

signal experience_gained(amount, current_xp, required_xp)
signal leveled_up(new_level)

var level: int = 1
var experience: float = 0.0
var experience_required: float = XpCurve.required(1)

func gain_experience(amount: float) -> void:
	var sb = get_parent().get("stat_block") if get_parent() else null
	if sb != null:
		amount *= sb.xp_mult()
	experience += amount
	experience_gained.emit(amount, experience, experience_required)
	
	while experience >= experience_required:
		experience -= experience_required
		level += 1
		experience_required = XpCurve.required(level)
		leveled_up.emit(level)
		experience_gained.emit(0.0, experience, experience_required)
