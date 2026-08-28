## PassiveKaionz.gd
## Kaionz's passive: Viento Perpetuo
## - Aumenta levemente la velocidad de movimiento.
## - El cooldown de habilidad se reduce un 15%.
class_name PassiveKaionz
extends PassiveData

func apply_to_player(player: CharacterBody3D) -> void:
	player.move_speed  = maxf(player.move_speed, 9.8)
	# Reduce skill cooldown by 15 %
	player.skill_cooldown = player.skill_cooldown * 0.85
