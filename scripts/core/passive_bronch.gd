## PassiveBronch.gd
## Passive for the Bronch character.
##
## Mechanics:
##  - Bronch's spores are stronger and last longer: the spore bazooka's
##    impact and cloud damage are boosted and its clouds linger more.
class_name PassiveBronch
extends PassiveData

## Damage multiplier applied to the spore bazooka's impact and cloud damage.
@export var spore_damage_mult: float = 1.5

## Base duration (seconds) of the spore clouds.
@export var spore_cloud_duration: float = 4.5

func apply_to_player(player: CharacterBody3D) -> void:
	player.spore_damage_mult = spore_damage_mult
	player.spore_cloud_duration = spore_cloud_duration
