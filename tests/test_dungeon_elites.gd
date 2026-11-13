extends Node

## Fase 1 del plan de combate: recetas de encuentro (WorldDefs "recipes") y élites (DungeonElites).

func _ready() -> void:
	print("--- TEST: DUNGEON ELITES & RECIPES ---")
	GameData.game_mode = "dungeon"
	SaveManager.save_path = "user://test_save.json"
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
	var player: Node3D = enc.player
	player.set_physics_process(false)
	var arena := enc.map.room_center(enc.map.arena_index)
	player.global_position = arena + Vector3(0, 0.3, 12)

	# 1. Receta: fijos recortados al grupo y relleno
	var muro: Dictionary = WorldDefs.WORLDS["caves"]["recipes"][1]
	var k6 := DungeonEncounter.recipe_kinds(muro, 6)
	assert(k6.count("brute") == 1 and k6.count("mage") == 2 and k6.count("goblin") == 3, "Muro x6: %s" % [k6])
	var k2 := DungeonEncounter.recipe_kinds(muro, 2)
	assert(k2.size() == 2 and not k2.has("goblin"), "Muro x2 se recorta a los fijos: %s" % [k2])
	print("CHECK 1 PASSED: recipe_kinds")

	# 2. Caverna normal: receta registrada, sin repetir en el nivel y orden por roles (magos al fondo, brutos delante)
	var normal := -1
	for i in enc.map.rooms.size():
		var t: String = enc.map.rooms[i]["type"]
		if t != "start" and t != "treasure" and t != "end" and i != enc.map.arena_index:
			normal = i
			break
	assert(normal >= 0, "Hace falta una caverna normal")

	# 1b. Comienzo suave: en el nivel 1 las primeras cavernas normales solo traen goblins normales y sin élites
	assert(enc.level == 1 and enc._starter_left == DungeonEncounter.STARTER_ROOMS, "El nivel 1 empieza con cavernas de inicio")
	for n in DungeonEncounter.STARTER_ROOMS:
		var sk := enc._kinds_for(normal, 6)
		assert(sk.size() == 6 and sk.count("goblin") == 6, "Caverna de inicio solo con goblins: %s" % [sk])
		assert(enc.elite_count(normal) == 0, "Caverna de inicio sin élites")
	enc._starter_rooms.clear()
	var after := enc._kinds_for(normal, 7)
	assert(String(enc.room_recipe[normal]) != "inicio", "Después vuelven las recetas mezcladas (%s)" % [after])
	print("CHECK 1b PASSED: comienzo solo con goblins normales")
	enc._used_recipes.clear()
	var roles: Dictionary = WorldDefs.WORLDS["caves"]["roles"]
	var seen := {}
	for n in 4:
		var kinds := enc._kinds_for(normal, 7)
		var id: String = enc.room_recipe[normal]
		assert(not seen.has(id), "La receta %s se repite antes de agotar las del nivel" % id)
		seen[id] = true
		for j in kinds.size() - 1:
			assert(int(roles.get(kinds[j], 1)) <= int(roles.get(kinds[j + 1], 1)), "Orden por roles: %s" % [kinds])
	print("CHECK 2 PASSED: recetas sin repetir y ordenadas por rol (%s)" % [seen.keys()])

	# 3. Blindado: escudo hasta el aturdimiento
	var g := _spawn(enc, arena)
	DungeonElites.make(g, "blindado")
	var hp0 := g.hp
	assert(is_equal_approx(g.max_hp, hp0) and g.get_node_or_null("EliteMarker") != null, "Marca y vida de élite")
	g.take_damage(10.0)
	assert(absf((hp0 - g.hp) - 10.0 * DungeonElites.SHIELD_TAKEN) < 0.01, "El escudo reduce el daño (%.2f)" % (hp0 - g.hp))
	g.add_stun_fraction(1.0)
	assert(g.state == DungeonGoblin.State.STUNNED, "Debe quedar aturdido")
	assert(is_equal_approx(g.damage_taken_mult, 1.0), "Aturdido rompe el escudo")
	print("CHECK 3 PASSED: blindado")

	# 4. Protector: los aliados cercanos reciben la mitad; muerto el protector, todo
	var prot := _spawn(enc, arena + Vector3(2, 0, 0))
	DungeonElites.make(prot, "protector")
	var ally := _spawn(enc, arena + Vector3(3, 0, 0))
	await get_tree().physics_frame
	var a0 := ally.hp
	ally.take_damage(4.0)
	assert(absf((a0 - ally.hp) - 2.0) < 0.01, "Aliado protegido recibe la mitad (%.2f)" % (a0 - ally.hp))
	prot.take_damage(prot.hp + 1.0)
	a0 = ally.hp
	ally.take_damage(4.0)
	assert(absf((a0 - ally.hp) - 4.0) < 0.01, "Sin protector recibe todo (%.2f)" % (a0 - ally.hp))
	print("CHECK 4 PASSED: protector")

	# 5. Vampírico: se cura al golpear
	var v := _spawn(enc, arena + Vector3(-3, 0, 0))
	DungeonElites.make(v, "vampirico")
	v.hp = v.max_hp * 0.5
	DungeonElites.on_hit_player(v, 1.0)
	assert(absf(v.hp - v.max_hp * (0.5 + DungeonElites.VAMP_HEAL)) < 0.01, "Vampírico se cura")
	print("CHECK 5 PASSED: vampirico")

	# 6. Furioso: a media vida acelera y pega más
	var f := _spawn(enc, arena + Vector3(-3, 0, 3))
	DungeonElites.make(f, "furioso")
	var spd := f.speed
	var dm := f.damage_mult
	f.take_damage(f.max_hp * 0.6)
	assert(f.has_meta("fury") and f.speed > spd and f.damage_mult > dm, "Furioso se enfurece")
	print("CHECK 6 PASSED: furioso")

	# 7. Explosivo: deja una carga al morir y suelta equipo
	var e := _spawn(enc, arena + Vector3(0, 0, -3))
	DungeonElites.make(e, "explosivo")
	var blasts_before := _count(scene, "GroundBlast")
	var drops_before := get_tree().get_nodes_in_group("equipment_pickups").size()
	e.take_damage(e.hp + 1.0)
	await get_tree().process_frame
	assert(_count(scene, "GroundBlast") > blasts_before, "El explosivo deja una carga")
	assert(get_tree().get_nodes_in_group("equipment_pickups").size() > drops_before, "El élite suelta equipo")
	print("CHECK 7 PASSED: explosivo y botin")

	# 8. Veloz y número de élites por nivel
	var q := _spawn(enc, arena + Vector3(3, 0, 3))
	var qs := q.speed
	DungeonElites.make(q, "veloz")
	assert(q.speed > qs and q.windup_scale < 1.0, "Veloz")
	var end_room := -1
	for i in enc.map.rooms.size():
		if enc.map.rooms[i]["type"] == "end":
			end_room = i
	enc.level = 2
	for n in 10:
		assert(enc.elite_count(end_room) >= 1, "La escolta del jefe lleva élite desde el nivel 2")
	assert(enc.elite_count(enc.map.arena_index) == 0, "La arena no tiene élites")
	print("CHECK 8 PASSED: veloz y reparto de élites")

	print("ALL ELITE CHECKS PASSED")
	get_tree().quit(0)

func _spawn(enc: DungeonEncounter, pos: Vector3) -> DungeonGoblin:
	var g := enc._spawn_at(enc.map.arena_index, pos, "goblin")
	g.set_physics_process(false)
	return g

func _count(root: Node, cls: String) -> int:
	var n := 0
	for c in root.get_children():
		if c.get_script() and c.get_script().get_global_name() == cls:
			n += 1
	return n
