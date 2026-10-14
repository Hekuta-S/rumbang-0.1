class_name EnergyComponent
extends Node

signal energy_changed(current_energy, max_energy)

@export var max_energy: float = 200.0
var energy: float

func _ready() -> void:
	energy = max_energy

## Tries to consume the given amount of energy. Returns true if successful.
func consume_energy(amount: float) -> bool:
	if energy < amount:
		return false
	energy -= amount
	energy_changed.emit(energy, max_energy)
	return true

## Restores the given amount of energy, clamped to max.
func restore_energy(amount: float) -> void:
	energy = min(max_energy, energy + amount)
	energy_changed.emit(energy, max_energy)
