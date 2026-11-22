extends Node

## Hongos trampolín (MushroomBouncer): lógica pura de acierto y de velocidad de rebote.

func _ready() -> void:
	print("--- TEST: HONGOS REBOTAN ---")
	var list := [[Vector3(10, 2, 5), 1.0], [Vector3(-4, 0, 3), 1.6]]
	assert(MushroomBouncer.hit_index(list, Vector3(10.2, 2.0, 5.1)) == 0, "Pisar el hongo 0 acierta")
	assert(MushroomBouncer.hit_index(list, Vector3(10.2, 3.5, 5.1)) == -1, "Por encima de su altura no acierta")
	assert(MushroomBouncer.hit_index(list, Vector3(12.0, 2.0, 5.0)) == -1, "Lejos no acierta")
	assert(MushroomBouncer.hit_index(list, Vector3(-4.8, 0.5, 3.0)) == 1, "El hongo grande tiene más alcance")
	assert(MushroomBouncer.bounce_velocity(0.0) > 8.5, "Rebota más que un salto normal")
	assert(MushroomBouncer.bounce_velocity(-12.0) > MushroomBouncer.bounce_velocity(0.0), "Caer rebota más alto")
	assert(MushroomBouncer.bounce_velocity(-100.0) <= MushroomBouncer.MAX_V, "El rebote tiene tope")
	print("ALL MUSHROOM CHECKS PASSED")
	get_tree().quit(0)
