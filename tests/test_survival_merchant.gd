extends Node

## Supervivencia: los élites dan almas (SoulStats, para el yunque de la mazmorra) y Tatan aparece de paso
## (SurvivalMerchant) vendiendo un objeto, un tomo o una mejora; al comprarle una se va.
## Headless:  godot --headless --path . res://tests/test_survival_merchant.tscn

var _fails := 0

func _check(ok: bool, msg: String) -> void:
	print(("PASSED: " if ok else "FAILED: ") + msg)
	if not ok:
		_fails += 1

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _ready() -> void:
	print("--- TEST: ALMAS DE ELITES Y TATAN EN SUPERVIVENCIA ---")
	SaveManager.save_path = "user://test_save_merchant.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.save_path))
	SaveManager.load_save()
	GameData.armory_path = "user://test_armeria_merchant.cfg"
	GameData.game_mode = "survival"
	SaveManager.meta = {}
	var main: Node = load("res://scenes/core/main_procedural.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	get_tree().current_scene = main
	var p: Node3D = null
	var waves: WaveManager = null
	for i in 900:
		await get_tree().process_frame
		p = main.get_node_or_null("Player")
		waves = main.find_child("WaveManager", true, false)
		if p and waves and waves._running:
			break
	waves.stop_run()
	waves._running = true
	waves.set_process(false)
	p.health_comp.max_hp = 9999.0
	p.health_comp.hp = 9999.0
	var events: RunEvents = waves.events
	events.set_process(false)

	# 1. Almas: más con el minijefe y con los minutos
	var e0 := SoulStats.survival_elite_souls(false, 0.0)
	var e8 := SoulStats.survival_elite_souls(false, 480.0)
	var mb := SoulStats.survival_elite_souls(true, 0.0)
	_check(e0 > 0 and e8 > e0 and mb > e0, "almas élite %d, a los 8 min %d, minijefe %d" % [e0, e8, mb])

	# 2. Un élite muerto ingresa sus almas ya (sin esperar al fin de partida)
	var before := SoulStats.souls()
	var spawned: Array = waves._spawn_single_enemy(p.global_position + Vector3(6, 0, 0), EnemyData.EnemyType.NORMAL_GOBLIN, "")
	_check(not spawned.is_empty(), "sale un goblin")
	if not spawned.is_empty():
		var en: EnemyData = spawned[0]
		events.make_elite(en, "veloz")
		en.take_damage(en.max_hp * 10.0)
		await _frames(3)
		var got := SoulStats.souls() - before
		_check(got > 0 and got == RunStats.souls, "el élite da %d almas (RunStats %d)" % [got, RunStats.souls])
		_check(SoulStats.run_souls == 0, "no quedan pendientes de ingresar")
	# El élite suelta un objeto (ItemPickup): si el jugador lo pisa se abre la elección y pausa; fuera
	for n in main.find_children("*", "Area3D", true, false):
		if n.scene_file_path == RunEvents.ItemPickupScene.resource_path:
			n.queue_free()

	# 3. Tatan aparece con sus tres ofertas y su modelo
	var m := events.spawn_merchant()
	await _frames(2)
	_check(m != null and is_instance_valid(m), "Tatan aparece")
	if m == null:
		_finish()
		return
	var kinds := m.offers.map(func(o): return o["kind"])
	_check(kinds.has("item") and kinds.has("tome") and kinds.has("upgrade"), "vende objeto, tomo y mejora (%s)" % str(kinds))
	_check(m._model != null, "con el modelo de Tatan")

	# 4. Sin oro no compra nada y se queda
	var gs := GameState.get_instance()
	gs.gold = 0
	_check(not m.buy("tome") and not m._done, "sin oro no se compra")
	_check(m.options().all(func(o): return o["disabled"]), "las cartas salen bloqueadas sin oro")

	# 5. Comprar el tomo: lo recibe, paga y Tatan se va
	var tome: Dictionary = m.offers.filter(func(o): return o["kind"] == "tome")[0]
	var lvl := TomeDB.level(String(tome["id"]))
	gs.gold = int(tome["price"]) + 5
	m.open()
	await _frames(1)
	_check(get_tree().paused, "la tienda pausa el juego")
	_check(m.buy("tome"), "se compra el tomo")
	_check(TomeDB.level(String(tome["id"])) == lvl + 1, "el tomo sube de nivel")
	_check(gs.gold == 5, "se cobra el precio (%d)" % gs.gold)
	_check(not get_tree().paused, "la tienda se cierra")
	await get_tree().create_timer(0.6).timeout
	_check(not is_instance_valid(m), "Tatan desaparece tras la compra")

	# 6. Objeto y mejora también se entregan
	var m2 := events.spawn_merchant()
	await _frames(2)
	var inv = p.get("inventory")
	var item: Dictionary = m2.offers.filter(func(o): return o["kind"] == "item")[0]
	var n0: int = inv.count_item(String(item["id"]))
	gs.gold = 99999
	var okb: bool = m2.buy("item")
	_check(okb and inv.count_item(String(item["id"])) == n0 + 1, "el objeto va al inventario")
	await get_tree().create_timer(0.6).timeout
	var m3 := events.spawn_merchant()
	await _frames(2)
	_check(m3.buy("upgrade"), "la mejora de arma se aplica")
	await get_tree().create_timer(0.6).timeout

	# 7. Si nadie le compra, se va solo
	var m4 := events.spawn_merchant()
	await _frames(2)
	m4._t = SurvivalMerchant.LIFETIME
	for n in ["UpgradeChoiceUI", "ItemChoiceUI"]:
		var ui := main.find_child(n, true, false)
		if ui and ui.visible:
			print("NOTE: %s abierto (subida de nivel u objeto del élite): se cierra" % n)
			ui.visible = false
	get_tree().paused = false
	await get_tree().create_timer(0.6).timeout
	if is_instance_valid(m4):
		_check(not is_instance_valid(m4), "se va al acabar su tiempo")
	_finish()

func _finish() -> void:
	print("ALL MERCHANT CHECKS PASSED" if _fails == 0 else "FAILS: %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
