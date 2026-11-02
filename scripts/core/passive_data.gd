## PassiveData.gd
## Base class for all character passives.
## Each character's passive extends this Resource and overrides the relevant hooks.
class_name PassiveData
extends Resource

## Called once when the player enters the scene (use to override base stats).
func apply_to_player(_player: CharacterBody3D) -> void:
	pass

## Called before damage is applied. Returns the final damage after passive logic.
## Modify hp directly on player inside here if needed; return remaining hp damage.
func on_take_damage(_player: CharacterBody3D, amount: float) -> float:
	return amount
