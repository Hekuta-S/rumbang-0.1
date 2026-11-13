extends Node

## Enemigos de las cloacas: ratas, babosas y Rey Rata. Contrato, grupos con enjambres, división de
## la babosa contada por el encuentro y presión (daño por segundo) frente al goblin normal.
## Carga las cloacas reales (GameData.world = "sewers").

var _player: CharacterBody3D
var _hp_lost := 0.0

func _ready() -> void:
	print("--- TEST: SEWER ENEMIES ---")
	GameData.game_mode = "dungeon"
	GameData.world = "sewers"
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
	assert(enc != null and enc.map is SewerMap, "Las cloacas deben crear DungeonEncounter con SewerMap")
	enc._pending.clear()
	_player = enc.player
	var room: int = enc.map.arena_index
	var c := enc.map.room_center(room)
	_player.global_position = c + Vector3(0, 0.3, 0)

	# 1. Contrato: vida, velocidad y clips de cada tipo
	var expect := {"rat": [16.0, 5.625], "slug": [70.0, 2.25], "slug_small": [20.0, 3.0], "rat_king": [720.0, 2.7],
		"rat_big": [60.0, 2.925], "slug_red": [30.0, 3.0]}
	for kind in expect:
		var e: DungeonGoblin = NetWorld.create_enemy(kind)
		e.position = c + Vector3(6, 0.1, 6)
		scene.add_child(e)
		await get_tree().physics_frame
		assert(is_equal_approx(e.max_hp, expect[kind][0]), "Vida de %s: %s (es %s)" % [kind, expect[kind][0], e.max_hp])
		assert(absf(e.speed - float(expect[kind][1])) < 0.01, "Velocidad de %s: %s (es %s)" % [kind, expect[kind][1], e.speed])
		for n in e.attacks:
			var a: Dictionary = e.attacks[n]
			assert(e._anim.has_animation(a["windup_clip"]), "%s: falta el clip %s" % [kind, a["windup_clip"]])
			assert(a["attack_clip"] == "" or e._anim.has_animation(a["attack_clip"]), "%s: falta el clip %s" % [kind, a["attack_clip"]])
		for s in [e.warn_sfx, e.hurt_sfx, e.die_sfx]:
			assert(AudioManager.get_stream(s) != null, "%s: falta el sonido %s" % [kind, s])
		assert(NetWorld.kind_of(e) == kind, "NetWorld.kind_of(%s)" % kind)
		e.queue_free()
	await get_tree().physics_frame
	print("CHECK 1 PASSED: vida, velocidad, clips, sonidos y tipo de red de ratas, babosas y Rey Rata")

	# 2. Grupos: enjambres de ratas, receta de encuentro (WorldDefs "recipes") y tope de enemigos por caverna
	var sizes := {}
	var max_size := 0
	var rats := 0
	var total := 0
	for i in 300:
		var n: int = [4, 5, 6, 10][i % 4]
		var r_idx: int = room + 1 if room + 1 < enc.map.rooms.size() else 0
		var kinds: Array = enc._kinds_for(r_idx, n)
		max_size = maxi(max_size, kinds.size())
		sizes[n] = sizes.get(n, 0) + kinds.size()
		var rid: String = enc.room_recipe[r_idx]
		var recipe: Dictionary = (WorldDefs.WORLDS["sewers"]["recipes"] as Array).filter(func(x): return x["id"] == rid)[0]
		for fk in recipe["fixed"]:
			assert(kinds.count(fk) >= mini(int(recipe["fixed"][fk]), n), "Un grupo %s de %d debe llevar %s" % [rid, n, fk])
		for k in kinds:
			assert(k in ["rat", "rat_big", "slug", "slug_red"], "En las cloacas solo hay ratas y babosas (salió %s)" % k)
			rats += 1 if k == "rat" else 0
			total += 1
	for n in sizes:
		sizes[n] = snappedf(float(sizes[n]) / 75.0, 0.1)
	print("  tamaño medio por elecciones: ", sizes, "  máximo: ", max_size, "  ratas: %d %%" % (100 * rats / total))
	assert(max_size <= DungeonEncounter.MAX_SWARM, "Un grupo no pasa de %d enemigos (salió %d)" % [DungeonEncounter.MAX_SWARM, max_size])
	var arena: Array = enc._kinds_for(room, 3)
	assert(arena == ["slug", "slug", "slug"], "La arena de las cloacas no tiene goblins (salió %s)" % [arena])
	print("CHECK 2 PASSED: enjambres con tope y arena sin goblins")

	# 3. La división de la babosa la cuenta el encuentro: la caverna no se da por limpia antes de tiempo
	var slug := enc._spawn_at(room, c + Vector3(3, 0, 0), "slug") as DungeonSlug
	await get_tree().physics_frame
	assert(enc._alive[room] == 1, "Una babosa viva")
	slug.take_damage(999.0, Vector3.ZERO)
	await get_tree().physics_frame
	assert(enc._alive[room] == 2, "Al morir, sus 2 hijas cuentan (vivos %d)" % enc._alive[room])
	var kids := EnemyRegistry.all().filter(func(e): return e is DungeonSlug and e.small)
	assert(kids.size() == 2, "Nacen 2 babosas pequeñas (hay %d)" % kids.size())
	for k in kids:
		k.take_damage(999.0, Vector3.ZERO)
	await get_tree().physics_frame
	assert(enc._alive[room] == 0, "Muertas las hijas, la caverna queda vacía")
	print("CHECK 3 PASSED: la división cuenta para la caverna")
	for i in 120:
		await get_tree().physics_frame

	# 4. Presión: daño por segundo a un jugador quieto, frente al goblin normal
	var dps := {}
	for setup in [["goblin", 1], ["rat", 3], ["rat_big", 1], ["slug", 1], ["necro", 1], ["rat_king", 1]]:
		dps[setup[0] + " x%d" % setup[1]] = await _pressure(scene, c, setup[0], setup[1], 25.0)
	print("  daño por segundo (jugador quieto, 25 s): ", dps)
	var base: float = dps["goblin x1"]
	assert(base > 0.0, "El goblin debe hacer daño")
	assert(dps["rat x3"] > base * 0.7 and dps["rat x3"] < base * 1.6, "Tres ratas aprietan como un goblin (0,7–1,6×)")
	assert(dps["slug x1"] > base * 0.35 and dps["slug x1"] < base * 1.1, "Una babosa aprieta menos que un goblin")
	# El Nigromante (referencia, solo se imprime) varía mucho entre ejecuciones; el goblin no
	assert(dps["rat_king x1"] > base * 0.9 and dps["rat_king x1"] < base * 1.6, "El Rey Rata aprieta algo más que un goblin (0,9–1,6×), como el Nigromante")
	assert(dps["rat_big x1"] > base * 0.7 and dps["rat_big x1"] < base * 1.4, "Una rata gorda aprieta como un goblin (0,7–1,4×)")
	print("CHECK 4 PASSED: presión equilibrada")

	# 5. Babosa roja: se acerca, se infla y revienta (muere); matada de lejos revienta igual, tarde,
	# y su estallido revienta en cadena a otra roja cercana
	_player.global_position = c + Vector3(0, 0.3, 0)
	_player.health_comp.hp = _player.health_comp.max_hp
	var red: DungeonBloater = NetWorld.create_enemy("slug_red")
	red.position = c + Vector3(4, 0.1, 0)
	scene.add_child(red)
	var lost := 0.0
	var popped_at := -1
	for i in 60 * 8:
		await get_tree().physics_frame
		_player.global_position.x = c.x
		_player.global_position.z = c.z
		var hc = _player.health_comp
		if hc.hp < hc.max_hp:
			lost += hc.max_hp - hc.hp
			hc.hp = hc.max_hp
		if red.is_dead() and popped_at < 0:
			popped_at = i
		if popped_at >= 0 and i > popped_at + 30:
			break
	print("  roja: revienta a los %.1f s, daño al jugador %.1f" % [popped_at / 60.0, lost])
	assert(popped_at > 0 and red._popped, "La roja llega y revienta sola")
	assert(lost >= 4.0, "Su reventón daña al jugador pegado (%.1f)" % lost)
	var a: DungeonBloater = NetWorld.create_enemy("slug_red")
	var b2: DungeonBloater = NetWorld.create_enemy("slug_red")
	a.position = c + Vector3(9, 0.1, 9)
	b2.position = c + Vector3(10.2, 0.1, 9)
	scene.add_child(a)
	scene.add_child(b2)
	await get_tree().physics_frame
	b2.set_physics_process(false)       # que no se aparte durante la mecha
	a.take_damage(999.0, Vector3.ZERO)
	assert(not b2.is_dead(), "La vecina aún no revienta: hay mecha")
	await get_tree().create_timer(DungeonBloater.DEATH_FUSE + 0.2).timeout   # la mecha es un temporizador
	await get_tree().physics_frame
	assert(b2.is_dead(), "El estallido revienta a la roja vecina")
	print("CHECK 5 PASSED: babosa roja revienta, con mecha al matarla y en cadena")
	print("ALL SEWER ENEMY CHECKS PASSED")
	get_tree().quit()

## Pone `count` enemigos de `kind` alrededor del jugador y mide el daño que le hacen por segundo.
func _pressure(scene: Node, c: Vector3, kind: String, count: int, secs: float) -> float:
	_player.global_position = c + Vector3(0, 0.3, 0)
	_player.health_comp.hp = _player.health_comp.max_hp
	_hp_lost = 0.0
	var list: Array = []
	for i in count:
		var e: DungeonGoblin = NetWorld.create_enemy(kind)
		var ang := TAU * i / count
		e.position = c + Vector3(cos(ang), 0, sin(ang)) * 5.0 + Vector3(0, 0.1, 0)
		e.map = (scene.get_node("ProceduralMap") as DungeonMap)
		scene.add_child(e)
		list.append(e)
	var used := {}
	var prev := -1
	for t in int(secs * 60.0):
		await get_tree().physics_frame
		var lead: DungeonGoblin = list[0]
		if is_instance_valid(lead) and lead.state != prev:
			prev = lead.state
			if lead.state == DungeonGoblin.State.WINDUP:
				used[lead._atk_name] = used.get(lead._atk_name, 0) + 1
		_player.global_position.x = c.x
		_player.global_position.z = c.z
		var hc = _player.health_comp
		if hc.hp < hc.max_hp:
			_hp_lost += hc.max_hp - hc.hp
			hc.hp = hc.max_hp
	for e in list:
		if is_instance_valid(e):
			if e.has_method("_die") and not e.is_dead():
				e.take_damage(99999.0, Vector3.ZERO)
	for e in EnemyRegistry.all():
		if is_instance_valid(e) and not e.is_dead():
			e.take_damage(99999.0, Vector3.ZERO)
	for i in 150:
		await get_tree().physics_frame
	print("  %s x%d: ataques %s" % [kind, count, used])
	return snappedf(_hp_lost / secs, 0.01)
