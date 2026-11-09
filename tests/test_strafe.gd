extends Node

## Paso lateral de Riva: clip solo de piernas, capa "legs" en el AnimationTree y peso según el movimiento
## lateral respecto a donde mira el cuerpo (derecha = el mismo clip al revés).

func _ready() -> void:
	print("--- TEST: PASO LATERAL ---")
	GameData.game_mode = "dungeon"
	var scene: Node = load("res://scenes/core/main_dungeon.tscn").instantiate()
	get_tree().root.add_child.call_deferred(scene)
	var player: Node = null
	var ac: PlayerAnimationController = null
	for i in 600:
		await get_tree().process_frame
		player = scene.get_node_or_null("Player")
		if player and player.get_node_or_null("PlayerAnimationController") and player.get_node("PlayerAnimationController").model:
			ac = player.get_node("PlayerAnimationController")
			break
	assert(ac != null and ac._has_strafe, "El controlador tiene la capa de paso lateral")
	var anim: Animation = ac.anim_player.get_animation(PlayerAnimationController.STRAFE_ANIM)
	assert(anim.get_track_count() > 0, "El clip tiene pistas")
	for i in anim.get_track_count():
		var bone := String(anim.track_get_path(i).get_concatenated_subnames()).trim_prefix("mixamorig_")
		assert(bone in PlayerAnimationController.LEG_BONES, "Solo piernas (%s)" % bone)
	print("CHECK 1 PASSED: clip de %d pistas, solo piernas" % anim.get_track_count())
	# El cuerpo mira hacia -Z: moverse a +X es ir a la derecha
	player.mesh.rotation.y = 0.0
	ac._update_strafe(1.0, Vector3(3, 0, 0), true)
	assert(ac._strafe_w > 0.9 and ac._strafe_side > 0.9, "Derecha: peso alto, clip al revés (%f %f)" % [ac._strafe_w, ac._strafe_side])
	ac._update_strafe(1.0, Vector3(-3, 0, 0), true)
	assert(ac._strafe_w > 0.9 and ac._strafe_side < 0.1, "Izquierda: clip normal")
	ac._update_strafe(1.0, Vector3(0, 0, -3), true)
	assert(ac._strafe_w < 0.1, "De frente: sin paso lateral")
	print("CHECK 2 PASSED: peso y lado del paso lateral")
	print("ALL STRAFE CHECKS PASSED")
	get_tree().quit(0)
