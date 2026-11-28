extends Node

## Criaturas de las cloacas en Supervivencia: ratas, babosas y babosa roja son EnemyData (los mueve la simulación en
## C++, o el GDScript si RUMBANG_NATIVE_SIM=0) dibujados como sprites 2D horneados. Comprueba que salen, persiguen,
## muerden, embisten, que la roja avisa y revienta, que la babosa se divide y que el director las suelta.
var _main: Node
var _fail := false
func _check(ok: bool, msg: String) -> void:
	print("%s: %s" % ["PASSED" if ok else "FAILED", msg])
	if not ok:
		_fail = true

## Un tick de física sin pausa: matar enemigos da XP y las subidas de nivel pausan el juego.
func _tick() -> void:
	get_tree().paused = false
	await get_tree().physics_frame

## Mayor estado especial (0 nada, 1 avisando, 2 en marcha) entre los sprites visibles de un modelo (solo con el C++).
func _peek_state(model: int) -> float:
	var sim: Object = EnemyManager.sim
	if sim == null:
		var m := 0.0
		for e in EnemyRegistry.all():
			if e is EnemyData and not e.recycled and e.vat_idx == model:
				m = maxf(m, float(e.special_state))
		return m
	var buf: PackedFloat32Array = sim.vis_buffer(model)
	var best := 0.0
	for i in sim.vis_count(model):
		best = maxf(best, buf[i * EnemyVisuals.STRIDE + 15])
	return best

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
	await _tick()
	print("simulación nativa: ", EnemyManager.using_native_sim())

	_check(EnemyVisuals.creatures_available(), "atlas horneados de las 4 criaturas")
	_check(EnemyVisuals.any != null and EnemyVisuals.any.creature_count() >= 0, "EnemyVisuals dibuja criaturas")

	# 1. Cada tipo sale como EnemyData con casilla de dibujo propia
	var base: Vector3 = p.global_position
	var made := {}
	for k in ["rat", "slug", "bloater", "rat_big"]:
		var at := base + Vector3(9.0, 0.0, randf_range(-3.0, 3.0))
		var arr: Array = waves.spawn_critter_pack(k, at)
		made[k] = arr[0]
	await _tick()
	await get_tree().process_frame
	var idx_ok := true
	for k in made:
		if not EnemyVisuals.is_creature_idx((made[k] as EnemyData).vat_idx):
			idx_ok = false
	_check(idx_ok, "las 4 clases usan modelo de criatura")
	_check(waves.critter_count() >= 4, "cuentan como criaturas vivas (%d)" % waves.critter_count())
	_check(EnemyVisuals.any.creature_count() >= 4, "se dibujan (%d instancias)" % EnemyVisuals.any.creature_count())
	_check(made["rat"].hit_height < 1.0 and made["rat"].hit_radius < 0.4, "la rata tiene el impacto pequeño")

	# 2. Persiguen: la rata se acerca; la babosa también, más despacio
	var rat: EnemyData = made["rat"]
	rat.alert()
	var d0 := rat.global_position.distance_to(p.global_position)
	var saw_lunge := false
	var hp0: float = p.health_comp.hp
	rat.lunger = true
	for i in 360:
		await _tick()
		if rat.special_state > 0:
			saw_lunge = true
	_check(rat.global_position.distance_to(p.global_position) < d0 - 3.0 or p.health_comp.hp < hp0, "la rata persigue (%.1f m -> %.1f m)" % [d0, rat.global_position.distance_to(p.global_position)])
	_check(p.health_comp.hp < hp0, "la rata muerde (%.1f -> %.1f)" % [hp0, p.health_comp.hp])
	# Embestida: un grupo que llega de lejos pasa por la franja de 4,5 a 9,5 m con la habilidad lista
	var far: Array = []
	for i in 3:
		far.append_array(waves.spawn_critter_pack("rat", base + Vector3(26.0, 0.0, -4.0 + 4.0 * i)))
	for e: EnemyData in far:
		e.alert()
		e.special_cd = 0.0
		e.lunger = true
		EnemyManager.mark_dirty(e)
	var lunge_seen := 0
	for i in 600:
		await _tick()
		if _peek_state(EnemyVisuals.KEYS.size() + 0) > 0.5 or _peek_state(EnemyVisuals.KEYS.size() + 1) > 0.5:
			lunge_seen += 1
	_check(lunge_seen > 0, "las ratas se agazapan y embisten (poses de aviso: %d ticks)" % lunge_seen)
	for e: EnemyData in far:
		if not e.recycled:
			e.take_damage(1.0e9, Vector3.ZERO)

	# 3. La babosa roja avisa y revienta (daña al jugador con un círculo) sin dejar el enemigo vivo
	for e in EnemyRegistry.all().duplicate():
		if e is EnemyData and not e.recycled and e.type == EnemyData.EnemyType.BLOATER:
			e.take_damage(1.0e9, Vector3.ZERO)
	await _tick()
	await get_tree().create_timer(1.2).timeout            # (la roja que mata el golpe revienta tras su mecha)
	var bl: EnemyData = waves._spawn_single_enemy(p.global_position + Vector3(4.0, 0.0, 0.0), EnemyData.EnemyType.BLOATER)[0]
	bl.max_hp = 1.0e6              # que el arma del jugador no la mate antes de reventar
	bl.hp = bl.max_hp
	bl.alert()
	bl.global_position = p.global_position + Vector3(4.0, 0.0, 0.0)
	EnemyManager.mark_dirty(bl)
	var frames := 0
	var warn_ticks := 0
	for i in 400:
		await _tick()
		if bl.recycled:
			break
		frames += 1
		if _peek_state(EnemyVisuals.KEYS.size() + 3) > 0.5:
			warn_ticks += 1
	var blasts := 0
	for n in _main.get_children():
		if n is GroundBlast:
			blasts += 1
	_check(bl.recycled, "la roja revienta y desaparece")
	_check(blasts >= 1, "y suelta el círculo de estallido (GroundBlast)")
	_check(warn_ticks >= 20, "y antes se hincha un rato (%d ticks de aviso)" % warn_ticks)

	# 4. La babosa grande suelta crías al morir
	for e in EnemyRegistry.all().duplicate():
		if e is EnemyData and not e.recycled:
			e.take_damage(1.0e9, Vector3.ZERO)
	await get_tree().create_timer(1.0).timeout
	var slug: EnemyData = waves._spawn_single_enemy(p.global_position + Vector3(14.0, 0.0, 0.0), EnemyData.EnemyType.SLUG)[0]
	await _tick()
	var before := waves.critter_count()
	var smalls_before := 0
	for e in EnemyRegistry.all():
		if e is EnemyData and not e.recycled and e.trait_id == "slug_small":
			smalls_before += 1
	slug.max_hp = 1.0e6
	slug.hp = 1.0e6
	slug.take_damage(1.0e9, Vector3.ZERO)
	for i in 4:
		await _tick()
		await get_tree().process_frame
	var smalls := 0
	for e in EnemyRegistry.all():
		if e is EnemyData and not e.recycled and e.trait_id == "slug_small":
			smalls += 1
	smalls -= smalls_before
	print("  vivos=", EnemyRegistry.count(), " tope=", waves._alive_cap(), " pendientes=", waves._pending_spawns)
	_check(smalls == WaveManager.SLUG_SPLIT, "la babosa suelta %d crías" % smalls)
	_check(waves.critter_count() >= before - 1 + smalls - 1, "las crías cuentan como criaturas")
	var small: EnemyData
	for e in EnemyRegistry.all():
		if e is EnemyData and e.trait_id == "slug_small":
			small = e
	_check(small != null and small.scale.x < 0.7 and small.hit_radius < 0.4, "las crías son más pequeñas")

	# 5. Matar da XP / bajas
	var kills := RunStats.kills
	for e in EnemyRegistry.all().duplicate():
		if e is EnemyData and not e.recycled:
			e.take_damage(1.0e9, Vector3.ZERO)
	await _tick()
	_check(RunStats.kills > kills, "las muertes cuentan (+%d)" % (RunStats.kills - kills))

	# 6. El director
	_check(WaveManager.critter_cap(0.0) >= 4 and WaveManager.critter_cap(10.0) > WaveManager.critter_cap(1.0), "el tope sube con el tiempo")
	_check(waves._pick_critter_kind(0.5) == "rat", "al principio solo salen ratas")
	var kinds := {}
	for i in 300:
		kinds[waves._pick_critter_kind(4.0)] = true
	_check(kinds.size() == 4, "más tarde salen las cuatro clases")

	print("TEST_DONE ", "FAIL" if _fail else "OK")
	get_tree().quit(1 if _fail else 0)
