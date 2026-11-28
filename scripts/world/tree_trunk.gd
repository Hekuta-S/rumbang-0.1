class_name TreeTrunk
extends StaticBody3D

## Cuerpo de un árbol de TreeField: estorba al jugador (capa 1) y, en el grupo "destructibles", recibe los golpes
## (MeleeHitbox, balas, flechas, explosiones) y se los pasa al campo, que lo dibuja y lo rompe.

var field: TreeField
var index: int = -1

func _ready() -> void:
	add_to_group("destructibles")

func take_damage(amount: float, dir: Vector3 = Vector3.ZERO) -> void:
	if field:
		field.damage_tree(index, amount, dir)

func is_broken() -> bool:
	return field != null and field.is_broken(index)
