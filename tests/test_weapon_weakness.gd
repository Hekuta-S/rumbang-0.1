extends Node

## Puntos débiles de las armas: los golpes flojos rebotan en la armadura (mitad de daño, escudo sobre la cabeza)
## y el arco a quemarropa hace la mitad. Carga la mazmorra real con un bruto (armadura 15).

func _ready() -> void:
	print("--- TEST: PUNTOS DÉBILES DE LAS ARMAS ---")
	GameData.game_mode = "dungeon"
	var scene: Node = load("res://scenes/core/main_dungeon.tscn").instantiate()
	get_tree().root.add_child.call_deferred(scene)
	await get_tree().process_frame
	get_tree().current_scene = scene
	var enc: DungeonEncounter = null
	for i in 600:
		await get_tree().process_frame
		enc = scene.get_node_or_null("DungeonEncounter")
		if enc and enc.map and is_instance_valid(enc.player):
			break
	assert(enc != null, "La mazmorra debe crear DungeonEncounter")
	enc._pending.clear()
	var player: CharacterBody3D = enc.player
	var c := enc.map.room_center(enc.map.arena_index)
	player.global_position = c + Vector3(0, 0.3, 0)
	var b := enc.spawn_brute()
	await get_tree().physics_frame
	await get_tree().physics_frame
	b.set_physics_process(false)
	b.global_position = c + Vector3(6, 0.3, 0)

	# 1. Rebote: un golpe por debajo de la armadura quita la mitad
	assert(b.has_glance_armor(), "El bruto tiene armadura de rebote")
	b._set_state(DungeonGoblin.State.APPROACH)
	var hp0: float = b.hp
	b.take_damage(10.0, Vector3(0, 0, 1))
	var lost: float = hp0 - b.hp
	assert(is_equal_approx(lost, 10.0 * DungeonGoblin.ARMOR_GLANCE_MULT * b.damage_taken_mult), "Golpe de 10 rebota: quita %.1f" % lost)
	assert(b._shield_flash > 0.9, "El escudo destella al rebotar")
	assert(is_equal_approx(b._armor_dmg, 10.0), "La armadura acumula el golpe entero (%.1f)" % b._armor_dmg)
	print("CHECK 1 PASSED: golpe flojo rebota (%.1f de vida)" % lost)

	# 2. Golpe fuerte (>= armadura) entra entero
	b._set_state(DungeonGoblin.State.APPROACH)
	b._armor_dmg = 0.0
	hp0 = b.hp
	b.take_damage(20.0, Vector3(0, 0, 1))
	assert(is_equal_approx(hp0 - b.hp, 20.0 * b.damage_taken_mult), "Golpe de 20 entra entero")
	print("CHECK 2 PASSED: golpe fuerte entra entero")

	# 3. Aturdido no rebota y el escudo se oculta
	b._set_state(DungeonGoblin.State.STUNNED)
	b._update_stun_bar()
	assert(b._shield_icon != null and not b._shield_icon.visible, "Aturdido no muestra el escudo")
	hp0 = b.hp
	b.take_damage(10.0, Vector3.ZERO)
	assert(is_equal_approx(hp0 - b.hp, 10.0 * b.damage_taken_mult), "Aturdido el golpe flojo entra entero")
	b._set_state(DungeonGoblin.State.APPROACH)
	b._update_stun_bar()
	assert(b._shield_icon.visible, "Con armadura se ve el escudo")
	print("CHECK 3 PASSED: aturdido sin rebote ni escudo")

	# 4. Jefes (armadura 9999) y enemigos sin armadura: sin rebote ni escudo
	b.armor = 9999.0
	assert(not b.has_glance_armor(), "Armadura de jefe: no rebota")
	b._update_stun_bar()
	assert(not b._shield_icon.visible, "Sin armadura de rebote no hay escudo")
	b.armor = 0.0
	assert(not b.has_glance_armor(), "Sin armadura: no rebota")
	b.armor = 15.0
	print("CHECK 4 PASSED: jefes y enemigos sin armadura no rebotan")

	# 5. Arco a quemarropa: mitad de daño
	var arrow := BowArrow.new()
	arrow.source_player = player
	b.global_position = player.global_position + Vector3(1.5, 0, 0)
	assert(is_equal_approx(arrow.point_blank_mult(b), BowArrow.POINT_BLANK_MULT), "A 1,5 m: quemarropa")
	b.global_position = player.global_position + Vector3(6, 0, 0)
	assert(is_equal_approx(arrow.point_blank_mult(b), 1.0), "A 6 m: daño entero")
	arrow.free()
	print("CHECK 5 PASSED: arco a quemarropa")
	print("ALL WEAPON WEAKNESS CHECKS PASSED")
	get_tree().quit(0)
