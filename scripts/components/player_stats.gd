extends Node
class_name PlayerStats

signal stats_changed(hp, max_hp, shield, max_shield)
signal entity_died

@export var max_hp: float = 10.0
@export var max_shield: float = 5.0

@export var hp: float = 10.0
@export var shield: float = 5.0

func _ready() -> void:
    emit_stats()

func emit_stats() -> void:
    emit_signal("stats_changed", hp, max_hp, shield, max_shield)

func reset_to_full() -> void:
    hp = max_hp
    shield = max_shield
    emit_stats()

func heal(amount: float) -> void:
    if amount <= 0.0:
        return
    hp = min(max_hp, hp + amount)
    emit_stats()

func take_damage(amount: float) -> void:
    if amount <= 0.0:
        return

    var remaining = amount
    if shield > 0.0:
        var absorbed = min(shield, remaining)
        shield -= absorbed
        remaining -= absorbed

    hp = max(0.0, hp - remaining)
    if hp <= 0.0:
        emit_signal("entity_died")

    emit_stats()
