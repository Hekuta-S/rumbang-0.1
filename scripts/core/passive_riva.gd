## PassiveRiva.gd
## Passive for the Riva character.
##
## Mechanics:
##  - "Pies Humeantes": mientras Riva se mueve su velocidad aumenta de forma
##    progresiva; al pasar el umbral entra en ráfaga (is_riva_fast) y deja una
##    estela de humo que quema a los enemigos por segundo.
## La lógica por-frame vive en RivaSpeedController (componente agregado como
## hijo del player).
class_name PassiveRiva
extends PassiveData

func apply_to_player(player: CharacterBody3D) -> void:
	# Remueve cualquier controller previo para que un reinicio no los apile.
	for child in player.get_children():
		if child.is_in_group("riva_speed_controllers"):
			child.queue_free()

	var controller: Node = (load("res://scripts/components/riva_speed_controller.gd") as GDScript).new()
	controller.name = "RivaSpeedController"
	player.add_child(controller)
