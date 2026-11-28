class_name SewerBreakable
extends StaticBody3D

## Pieza rompible del Barrio del Desagüe (compuerta, tubería tumbada o muro de ladrillo): estorba al jugador
## (capa 1) y, en el grupo "destructibles", recibe golpes, balas y explosiones. Al romperse avisa a SewerDistrict,
## que abre el paso (colisión, obstáculos de EnemyMotion) y suelta el agua si es una compuerta.

var district: SewerDistrict
var id: int = -1
var hp: float = 60.0
var broken := false

func _ready() -> void:
	add_to_group("destructibles")

func take_damage(amount: float, dir: Vector3 = Vector3.ZERO) -> void:
	if broken:
		return
	hp -= amount
	if district:
		district.on_breakable_hit(id, dir)
	if hp <= 0.0:
		broken = true
		remove_from_group("destructibles")
		if district:
			district.on_breakable_broken(id, dir)

func is_broken() -> bool:
	return broken
