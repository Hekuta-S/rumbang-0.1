## PassiveVangry.gd
## Passive for the Vangry character.
##
## Mechanics:
##  - Radiates a small radioactive zone around the player that damages
##    every enemy inside it continuously (damage-over-time aura).
class_name PassiveVangry
extends PassiveData

## Radius of the radiation aura around the player.
@export var aura_radius: float = 4.5

## Total damage per second dealt to each enemy inside the aura.
@export var aura_dps: float = 5.0

## Tick interval used by the zone node (must match RadiationZone.tick_interval).
const TICK_INTERVAL: float = 0.5

var _zone_scene = preload("res://scenes/objects/radiation_zone.tscn")

## Spawns the radiation zone as a child of the player (it follows automatically).
func apply_to_player(player: CharacterBody3D) -> void:
	# Remove any previous zone so restarting the game doesn't stack auras.
	for child in player.get_children():
		if child.is_in_group("radiation_zones"):
			child.queue_free()

	var zone: Area3D = _zone_scene.instantiate()
	zone.radius = aura_radius
	zone.damage_per_tick = aura_dps * TICK_INTERVAL
	player.add_child(zone)
	# Zone sits at the player's origin (feet level) and follows them.
