extends PassiveData
class_name PassiveHeckler

var last_tp_time = 0

func apply_to_player(player: CharacterBody3D) -> void:
	pass

func override_run(player: CharacterBody3D, wish_dir: Vector3, delta: float) -> void:
	var current_time = Time.get_ticks_msec()
	if current_time - last_tp_time > 1200:
		if player.stats.consume_energy(40.0):
			var space_state = player.get_world_3d().direct_space_state
			var target_pos = player.global_position + wish_dir.normalized() * 10.0
			target_pos.y += 0.5
			var query = PhysicsRayQueryParameters3D.create(player.global_position + Vector3.UP, target_pos)
			query.collision_mask = 1
			var result = space_state.intersect_ray(query)
			
			if result:
				player.global_position = result.position - wish_dir.normalized() * 0.5
			else:
				player.global_position = target_pos
			
			last_tp_time = current_time
			player.velocity = Vector3.ZERO
			
			if AudioManager.has_method("play"):
				AudioManager.play("ataque-espalanza", -2.0, 1.2)
