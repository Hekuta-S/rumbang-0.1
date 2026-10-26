class_name EnemyTypeFlyweight extends RefCounted

## PATRÓN FLYWEIGHT (estructural) — rol: Flyweight
## Estado INTRÍNSECO (compartido e inmutable) de un tipo de enemigo: vida, velocidad, alcance, daño,
## recompensa, color y escala. Antes cada EnemyData escribía estos valores literales en su
## `apply_config()`; ahora todas las instancias del mismo tipo comparten UN solo flyweight.
## El estado EXTRÍNSECO (posición, hp actual, cooldowns, IA) sigue viviendo en cada EnemyData.

var max_hp: float
var speed: float
var attack_range: float
var damage: float
var gold_reward: int
var scale: Vector3
var base_color: Color = Color.WHITE

func _init(p_hp: float, p_speed: float, p_range: float, p_damage: float, p_gold: int, p_scale: Vector3 = Vector3.ONE) -> void:
	max_hp = p_hp
	speed = p_speed
	attack_range = p_range
	damage = p_damage
	gold_reward = p_gold
	scale = p_scale

## Copia el estado intrínseco al enemigo (el enemigo conserva su propio estado extrínseco).
func apply_to(enemy) -> void:
	enemy.max_hp = max_hp
	enemy.hp = max_hp
	enemy.speed = speed
	enemy.attack_range = attack_range
	enemy.damage = damage
	enemy.gold_reward = gold_reward
	enemy.base_color = base_color
	enemy.scale = scale
