extends Area3D

## Floating weapon pickup. Grants its weapon when the player walks over it.
## The weapon_type must be a value from Player.WeaponType (see scripts/entities/player.gd).

@export var weapon_type: int = 0

var bob_offset: float = 0.0
var weapon_name: String = "Arma"

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	add_to_group("weapon_pickups")

func _physics_process(delta: float) -> void:
	bob_offset += delta * 2.0
	position.y = 1.1 + sin(bob_offset) * 0.2
	rotate_y(delta * 1.5)

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	if not body.has_method("add_weapon"):
		return
	if body.add_weapon(weapon_type):
		queue_free()
