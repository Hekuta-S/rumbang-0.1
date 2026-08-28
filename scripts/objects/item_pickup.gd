extends Area3D
class_name ItemPickup

@onready var visual = $MeshInstance3D
var t: float = 0.0

func _ready():
	body_entered.connect(_on_body_entered)
	add_to_group("item_pickups")

func _process(delta):
	t += delta
	visual.position.y = 1.0 + sin(t * 3.0) * 0.2
	visual.rotation_degrees.y += 45.0 * delta

func _on_body_entered(body):
	if body.is_in_group("player"):
		# Show the UI to choose an item
		if get_tree().current_scene.has_method("show_item_choice"):
			get_tree().current_scene.show_item_choice()
		queue_free()
