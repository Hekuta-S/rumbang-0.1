extends PassiveData
class_name PassiveHeckler

## Paso del Vacío: la habilidad (tecla E) de Heckler teletransporta 10 m en la dirección en la
## que se mueve (o a la que mira si está quieto). Antes se disparaba con el botón de correr, que ya no existe.

const TELEPORT_DISTANCE := 10.0

func apply_to_player(_player: CharacterBody3D) -> void:
	pass

## La llama Player.activate_skill() en lugar del Berserk genérico.
func on_skill(player: CharacterBody3D) -> void:
	var dir := _wish_direction(player)
	var space_state := player.get_world_3d().direct_space_state
	var target_pos := player.global_position + dir * TELEPORT_DISTANCE
	target_pos.y += 0.5
	var query := PhysicsRayQueryParameters3D.create(player.global_position + Vector3.UP, target_pos)
	query.collision_mask = 1
	var result := space_state.intersect_ray(query)

	if result:
		player.global_position = result.position - dir * 0.5
	else:
		player.global_position = target_pos
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	AudioManager.play("ataque-espalanza", -2.0, 1.2)

func _wish_direction(player: CharacterBody3D) -> Vector3:
	var inp: Vector2 = player.input_controller.get_movement_vector()
	if inp.length_squared() > 0.01:
		var cam_basis: Basis = player.spring_arm.global_transform.basis
		var wish: Vector3 = -cam_basis.z * -inp.y + cam_basis.x * inp.x
		wish.y = 0.0
		if wish.length_squared() > 0.0001:
			return wish.normalized()
	var fwd: Vector3 = -player.mesh.global_transform.basis.z
	fwd.y = 0.0
	return fwd.normalized() if fwd.length_squared() > 0.0001 else Vector3.FORWARD
