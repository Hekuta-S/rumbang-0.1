extends Node

## Voladores y combate aéreo: el murciélago planea y pica, el golpe dado saltando lanza al enemigo (AIRBORNE),
## los golpes en el aire lo mantienen arriba y hacen flotar al jugador, y aterriza tumbado e inmune un rato.

var _player: CharacterBody3D

func _ready() -> void:
	print("--- TEST: VOLADORES Y COMBATE AEREO ---")
	GameData.game_mode = "dungeon"
	GameData.world = "caves"
	var scene: Node = load(Net.game_scene()).instantiate()
	get_tree().root.add_child.call_deferred(scene)
	await get_tree().process_frame
	get_tree().current_scene = scene
	var enc: DungeonEncounter = null
	for i in 600:
		await get_tree().process_frame
		enc = scene.get_node_or_null("DungeonEncounter")
		if enc and enc.map and is_instance_valid(enc.player):
			break
	assert(enc != null, "Las cavernas crean DungeonEncounter")
	enc._pending.clear()
	_player = enc.player
	var c := enc.map.room_center(enc.map.arena_index)
	_player.global_position = c + Vector3(0, 0.3, 0)

	# 1. Murciélago: tipo de red, planea sobre el suelo y no se lanza
	var bat: DungeonBat = NetWorld.create_enemy("bat")
	assert(NetWorld.kind_of(bat) == "bat", "kind_of(bat)")
	bat.position = c + Vector3(6, 0.1, 0)
	scene.add_child(bat)
	for i in 90:
		await get_tree().physics_frame
		_player.global_position = c + Vector3(0, 0.3, 0)
	assert(bat.global_position.y - bat.ground_y() > 0.5, "El murciélago planea (h=%.2f)" % (bat.global_position.y - bat.ground_y()))
	assert(not bat.can_launch(), "No se lanza al murciélago")
	print("CHECK 1 PASSED: murciélago planea")

	# 2. Un golpe saltando lanza a un goblin; en el aire lo mantiene y el jugador flota
	bat.queue_free()
	var g: DungeonGoblin = NetWorld.create_enemy("goblin")
	g.position = c + Vector3(3, 0.1, 0)
	scene.add_child(g)
	await get_tree().physics_frame
	g.passive = true
	g.passive = false
	var hp0 := g.hp
	g.take_damage(1.0, Vector3.ZERO)
	assert(g.state != DungeonGoblin.State.AIRBORNE, "Un golpe desde el suelo no lanza")
	_player.velocity.y = 5.0
	_player.global_position.y += 0.6
	await get_tree().physics_frame
	g._land_immune_until = 0.0
	g.take_damage(1.0, Vector3.ZERO)
	assert(g.state == DungeonGoblin.State.AIRBORNE, "Un golpe saltando lanza al enemigo")
	var peak := 0.0
	for i in 30:
		await get_tree().physics_frame
		peak = maxf(peak, g.global_position.y)
	assert(peak > 1.5, "Sube lo bastante para el combo (pico %.2f)" % peak)
	var vy_before := g.velocity.y
	g.take_damage(1.0, Vector3.ZERO)
	assert(g.state == DungeonGoblin.State.AIRBORNE and g.velocity.y >= minf(vy_before, 4.0) - 0.01, "El golpe aéreo lo mantiene arriba")
	assert(_player.movement_controller.air_hovering() or _player.is_on_floor(), "El jugador flota con el golpe aéreo")
	print("CHECK 2 PASSED: lanzamiento y malabares")

	# 3. Aterriza tumbado e inmune un rato
	for i in 60 * 8:
		await get_tree().physics_frame
		_player.global_position.x = c.x
		_player.global_position.z = c.z
		if g.state != DungeonGoblin.State.AIRBORNE:
			break
	assert(g.state == DungeonGoblin.State.STAGGER, "Aterriza tumbado (%s)" % str(g.state))
	assert(not g.can_launch(), "Inmune tras aterrizar")
	print("CHECK 3 PASSED: aterrizaje")

	# 4. Supervivencia: el director de cuervos
	assert(WaveManager.flyer_cap(0.0) == 1 and WaveManager.flyer_cap(30.0) == 7, "Tope de cuervos")
	var crow := DungeonCrow.new()
	assert(crow.frames == Vector2i(1, 2) and crow.launch_mult == 0.0, "Cuervo: dibujo propio, no se lanza")
	crow.free()
	print("ALL AIR COMBAT CHECKS PASSED")
	get_tree().quit()
