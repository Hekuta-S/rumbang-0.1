extends Node

## Fase 4 de supervivencia: objetos del mapa (imán, bomba, comida, reloj), ruleta del cofre y HUD de bajas/DPS.
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
	p.health_comp.max_hp = 1000.0
	p.health_comp.hp = 1000.0
	waves.stop_run()
	waves._running = true

	# 1. Ruleta: siempre empieza con un objeto, tope de 5 y la suerte da más recompensas
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var low := 0
	var high := 0
	var capped := true
	var first_item := true
	for i in 2000:
		var a := ChestRoulette.roll(0.0, rng)
		var b := ChestRoulette.roll(0.5, rng)
		low += a.size()
		high += b.size()
		if a.size() > ChestRoulette.MAX_REWARDS or b.size() > ChestRoulette.MAX_REWARDS:
			capped = false
		if a[0] != "item":
			first_item = false
	_check(first_item and capped, "ruleta: empieza con objeto y tope de %d" % ChestRoulette.MAX_REWARDS)
	_check(high > low * 1.3, "la suerte da más recompensas (%.2f vs %.2f de media)" % [low / 2000.0, high / 2000.0])
	_check(ChestRoulette.summary(["item", "gold"]) == "OBJETO + ORO", "resumen del cofre")
	var kinds := {}
	for i in 400:
		kinds[MapPickup.roll_kind(rng)] = true
	_check(kinds.size() == MapPickup.KINDS.size(), "salen los %d tipos de objeto" % MapPickup.KINDS.size())

	# 2. Bomba: los normales mueren, el élite pierde el 25 %
	var pos: Vector3 = p.global_position + Vector3(10, 0, 0)
	var normals: Array = []
	for i in 3:
		normals.append(waves._spawn_single_enemy(pos + Vector3(i, 0, 0), EnemyData.EnemyType.NORMAL_GOBLIN)[0])
	var elite: EnemyData = waves._spawn_single_enemy(pos, EnemyData.EnemyType.NORMAL_GOBLIN)[0]
	waves.events.make_elite(elite, "acorazado")
	var elite_hp := elite.hp
	var hit := MapPickup.bomb_blast(p.global_position, MapPickup.BOMB_RADIUS)
	_check(hit >= 4 and normals.all(func(e): return e.recycled), "la bomba mata a los normales (%d afectados)" % hit)
	_check(not elite.recycled and is_equal_approx(elite_hp - elite.hp, elite.max_hp * MapPickup.BOMB_ELITE_FRACTION), "el élite pierde el 25% de su vida")

	# 3. Reloj: congela a todos
	var e2: EnemyData = waves._spawn_single_enemy(pos, EnemyData.EnemyType.NORMAL_GOBLIN)[0]
	MapPickup.apply("clock", p, _main)
	_check(e2.slow_multiplier == 0.0 and e2.slow_timer >= MapPickup.CLOCK_SECONDS - 0.1, "el reloj congela %d s" % int(MapPickup.CLOCK_SECONDS))

	# 4. Comida: cura
	p.health_comp.hp = 100.0
	MapPickup.apply("food", p, _main)
	_check(p.health_comp.hp >= 100.0 + 1000.0 * MapPickup.FOOD_HEAL - 1.0, "la comida cura el %d%%" % int(MapPickup.FOOD_HEAL * 100.0))

	# 5. Imán: las gemas lejanas vuelan hacia el jugador
	for i in 3:
		_main.facade.spawn_xp_orb(p.global_position + Vector3(40 + i, 0, 0), 1.0)
	await get_tree().process_frame
	var orbs := get_tree().get_nodes_in_group("xp_orbs")
	MapPickup.apply("magnet", p, _main)
	_check(orbs.size() >= 3 and orbs.all(func(o): return o._magnetized and o.target == p), "el imán atrae las %d gemas" % orbs.size())

	# 6. Objeto en el mapa: se recoge al acercarse
	var pk := MapPickup.spawn(_main, p.global_position + Vector3(30, 0, 0), "food")
	await get_tree().process_frame
	_check(is_instance_valid(pk) and pk.is_in_group("map_pickups"), "el objeto aparece en el mapa")
	pk.global_position = p.global_position
	for i in 5:
		await get_tree().process_frame
	_check(not is_instance_valid(pk) or pk.is_queued_for_deletion(), "se recoge al acercarse")

	# 7. Cofre maldito con ruleta: aparecen sus recompensas
	var gold0 := GameState.get_instance().gold
	waves.events._grant_rewards(p.global_position + Vector3(5, 0, 0), ["gold", "gold", "xp"])
	await get_tree().create_timer(1.5, true, false, true).timeout
	_check(GameState.get_instance().gold == gold0 + 2 * ChestRoulette.GOLD_EACH, "la ruleta reparte oro")

	# 8. HUD: bajas y DPS
	var hud: Node = _main.find_child("HUD", true, false)
	if hud == null:
		for n in _main.get_children():
			if n.has_method("update_elapsed_time"):
				hud = n
	get_tree().paused = false        # las gemas del imán pudieron abrir la elección de mejora
	if hud != null:
		RunStats.kills = 7
		RunStats.add_damage(-1, 300.0)
		for i in 10:
			await get_tree().process_frame
		_check(hud.combat_label != null and hud.combat_label.text.begins_with("BAJAS 7"), "el HUD muestra las bajas (%s)" % (hud.combat_label.text if hud.combat_label else "sin etiqueta"))
	else:
		_check(false, "no se encontró el HUD")
	print("ALL PASSED" if not _fail else "SOME FAILED")
	get_tree().quit(1 if _fail else 0)
