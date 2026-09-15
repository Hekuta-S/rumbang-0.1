class_name EnergyComponent
extends Node

signal energy_changed(energy, max_energy)

@export var max_energy: float = 200.0
@export var energy_regen_rate: float = 15.0

var energy: float

func _ready() -> void:
	energy = max_energy

func _process(delta: float) -> void:
	if energy < max_energy:
		energy = min(max_energy, energy + delta * energy_regen_rate)
		energy_changed.emit(energy, max_energy)

func restore_energy(amount: float) -> void:
	energy = min(max_energy, energy + amount)
	energy_changed.emit(energy, max_energy)

func consume_energy(amount: float) -> bool:
	if energy >= amount:
		energy -= amount
		energy_changed.emit(energy, max_energy)
		return true
	return false
