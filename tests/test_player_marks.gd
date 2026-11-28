extends Node

## Huellas del jugador (historia 009) y árboles dibujados destructibles, sobre la partida real de Supervivencia:
##  - los árboles son sprites (TreeField), no modelos 3D; se rompen a golpes y queda el tocón, que sigue estorbando;
##  - compuertas, tuberías y muros del Barrio del Desagüe se rompen y abren paso al jugador y a los enemigos;
##  - una compuerta rota inunda su desagüe con una ola que daña a los enemigos de dentro;
##  - cráteres y manchas de tinta se quedan en el suelo, con tope.
var _main: Node
var _fail := false
func _check(ok: bool, msg: String) -> void:
	print("%s: %s" % ["PASSED" if ok else "FAILED", msg])
	if not ok:
		_fail = true

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.game_mode = "survival"
	SaveManager.save_path = "user://test_save.json"
	SaveManager.meta = {}
	_main = load("res://scenes/core/main_procedural.tscn").instantiate()
	get_tree().root.add_child.call_deferred(_main)
	await get_tree().process_frame
	get_tree().current_scene = _main
	var p = null
	var waves: WaveManager = null
	for i in 900:
		await get_tree().process_frame
		p = _main.get_node_or_null("Player")
		waves = _main.find_child("WaveManager", true, false)
		if p and waves and waves._running:
			break
	_check(waves != null and waves._running, "arranca la partida")
	p.health_comp.max_hp = 100000.0
	p.health_comp.hp = 100000.0
	waves.stop_run()
	waves._running = true
	for e in EnemyRegistry.all().duplicate():
		if e is EnemyData and not e.recycled:
			e.take_damage(1.0e9, Vector3.ZERO)
	var map: ProceduralMap = _main.get_node("ProceduralMap")
	var trees: TreeField = map.trees
	var d: SewerDistrict = map.district

	# 1. Árboles dibujados: TreeField con todos los tree_a/tree_b, sin modelos 3D ni formas en PropColliders
	var tree_xfs: int = (map._instances.get("tree_a", []) as Array).size() + (map._instances.get("tree_b", []) as Array).size()
	var no_models := true
	for n in map.get_node("Props").get_children():
		if String(n.name).begins_with("tree_"):
			no_models = false
	var shapes := map.get_node("PropColliders").get_child_count()
	var expected := 0
	for kind in map._collide:
		if not (kind in ProceduralMap.TREE_KINDS):
			expected += (map._collide[kind] as Array).size()
	_check(trees != null and trees.count() == tree_xfs and tree_xfs > 100 and no_models and shapes == expected,
		"los árboles son dibujos (%d) y no modelos 3D" % tree_xfs)
	# 2. Cuerpos solo cerca del jugador
	await get_tree().physics_frame
	await get_tree().create_timer(0.6).timeout
	var near_ok := true
	for i in trees.count():
		var b := trees.body_of(i)
		if b != null and Vector2(b.global_position.x - p.global_position.x, b.global_position.z - p.global_position.z).length() > TreeField.BODY_RADIUS + 1.0:
			near_ok = false
	_check(near_ok and trees.body_count() < trees.count(), "solo hay cuerpos de los árboles cercanos (%d de %d)" % [trees.body_count(), trees.count()])
	# 3. Romper un árbol: tocón que sigue estorbando y obstáculos de los enemigos intactos
	var ti := _nearest_tree(trees, p.global_position)
	trees.ensure_bodies_near(trees.tree_position(ti), 1.0)
	var body := trees.body_of(ti)
	var obstacles_before := map.get_colliders().size()
	body.take_damage(10.0, Vector3.RIGHT)
	var wobbling := not trees.is_broken(ti)
	body.take_damage(1000.0, Vector3.RIGHT)
	await get_tree().physics_frame
	var cs := body.get_child(0) as CollisionShape3D
	var stump_ok := trees.is_broken(ti) and not body.is_in_group("destructibles") \
		and absf((cs.shape as CylinderShape3D).height - TreeField.STUMP_H) < 0.01 and body.collision_layer == 1
	_check(wobbling and stump_ok and map.get_colliders().size() == obstacles_before,
		"un árbol aguanta golpes, al romperse queda el tocón y los enemigos lo siguen esquivando")
	await get_tree().create_timer(TreeField.FALL_TIME + TreeField.FADE_TIME + 0.3).timeout
	_check(trees._falling.is_empty() and trees._fall_mm.visible_instance_count == 0, "la parte de arriba cae y desaparece")
	# 4. Una explosión rompe los árboles de alrededor y deja cráter
	var tj := _nearest_tree(trees, trees.tree_position(ti) + Vector3(12.0, 0.0, 0.0), ti)
	trees.ensure_bodies_near(trees.tree_position(tj), 1.0)
	var marks: MapMarks = _main.get_node_or_null("MapMarks")
	var craters0 := marks.count(MapMarks.Kind.CRATER) if marks else -1
	var barrel := ExplosiveBarrel.new()
	barrel.barrel_mesh = map._load_kind("barrel")
	_main.add_child(barrel)
	barrel.global_position = trees.tree_position(tj) + Vector3(1.5, 0.0, 0.0)
	await get_tree().physics_frame
	barrel.explode()
	_check(trees.is_broken(tj) and marks != null and marks.count(MapMarks.Kind.CRATER) == craters0 + 1,
		"un barril que estalla tala el árbol de al lado y deja un cráter")
	# 5. Tinta donde mueren los enemigos (no todas, sin amontonarse) y tope de marcas
	var ink0 := marks.count(MapMarks.Kind.INK)
	for k in 200:
		marks.on_enemy_died(p.global_position + Vector3(float(k % 20) * 2.0, 0.0, float(k / 20) * 2.0 + 30.0))
	var ink := marks.count(MapMarks.Kind.INK) - ink0
	for k in 300:
		marks.add(p.global_position + Vector3(randf_range(-40, 40), 0, randf_range(-40, 40)), MapMarks.Kind.CRATER, 2.0)
	_check(ink > 20 and ink < 160 and marks.count() == MapMarks.MAX_MARKS, "manchas de tinta al morir (%d de 200) y tope de %d marcas" % [ink, MapMarks.MAX_MARKS])

	# 6. Barrio: piezas rompibles
	var kinds := {}
	for bk in d.breakables:
		kinds[bk["kind"]] = int(kinds.get(bk["kind"], 0)) + 1
	_check(int(kinds.get("pipe", 0)) >= 1 and int(kinds.get("wall", 0)) >= 1 and int(kinds.get("gate", 0)) == d.canals.size() - 1,
		"el barrio tiene tuberías, muros y una compuerta por desagüe %s" % str(kinds))
	# 7. Un muro y una tubería cortan el paso a los enemigos; rotos, lo abren (y al jugador)
	for kind in ["wall", "pipe"]:
		var bi := -1
		for i in d.breakables.size():
			if d.breakables[i]["kind"] == kind:
				bi = i
				break
		var bk: Dictionary = d.breakables[bi]
		var a: Vector3 = bk["a"]
		var b: Vector3 = bk["b"]
		var mid := Vector2((a.x + b.x) * 0.5, (a.z + b.z) * 0.5)
		var along := Vector2(b.x - a.x, b.z - a.z).normalized()
		var across := Vector2(-along.y, along.x)
		var blocked := not _walk(mid - across * 3.0, mid + across * 3.0)
		var node: SewerBreakable = bk["node"]
		node.take_damage(5000.0, Vector3.FORWARD)
		await get_tree().physics_frame
		await get_tree().physics_frame
		var open := _walk(mid - across * 3.0, mid + across * 3.0)
		var player_free := true
		for c in node.get_children():
			if c is CollisionShape3D and not (c as CollisionShape3D).disabled:
				player_free = false
		_check(blocked and open and player_free and not node.is_in_group("destructibles"),
			"%s: antes corta el paso, roto lo abre a enemigos y jugador" % kind)
	# 8. Compuerta: el desagüe está seco; rota, se inunda y la ola daña a un enemigo de dentro
	var gi := -1
	for i in d.breakables.size():
		if d.breakables[i]["kind"] == "gate":
			gi = i
			break
	var ci: int = d.breakables[gi]["canal"]
	var rng: Array = d.local_range(d.canals[ci])
	var inside := d.to_world(lerpf((rng[0] as Vector2).x, (rng[0] as Vector2).y, 0.4), ((rng[1] as Vector2).x + (rng[1] as Vector2).y) * 0.5)
	var dry := not map.is_water(Vector3(inside.x, d.floor_y, inside.y))
	var victim: EnemyData = waves._spawn_single_enemy(Vector3(inside.x, d.floor_y, inside.y), EnemyData.EnemyType.NORMAL_GOBLIN)[0]
	victim.slow_multiplier = 0.0
	victim.slow_timer = 30.0
	await get_tree().physics_frame
	var hp0 := victim.hp
	(d.breakables[gi]["node"] as SewerBreakable).take_damage(5000.0, Vector3.FORWARD)
	await get_tree().create_timer(SewerDistrict.FLOOD_TIME + 0.4).timeout
	var wet := map.is_water(Vector3(inside.x, d.floor_y, inside.y))
	_check(dry and wet and not d.flooding(), "la compuerta rota inunda su desagüe (estaba seco)")
	_check(victim.recycled or victim.hp < hp0, "la ola daña al enemigo que había dentro")
	get_tree().quit(1 if _fail else 0)

func _nearest_tree(trees: TreeField, at: Vector3, skip: int = -1) -> int:
	var best := -1
	var bd := INF
	for i in trees.count():
		if i == skip or trees.is_broken(i):
			continue
		var dd := trees.tree_position(i).distance_squared_to(at)
		if dd < bd:
			bd = dd
			best = i
	return best

## Un enemigo va en línea recta de a a b (EnemyMotion: relieve y obstáculos). ¿Llega?
func _walk(a: Vector2, b: Vector2) -> bool:
	var q := a
	var y := EnemyMotion.height_at(q.x, q.y)
	for n in 600:
		if q.distance_to(b) < 0.3:
			return true
		var r := EnemyMotion.resolve_step(q, (b - q).limit_length(0.1), y)
		q = EnemyMotion._push_out_of_obstacles(Vector2(r.x, r.y))
		y = EnemyMotion.height_at(q.x, q.y)
	return false
