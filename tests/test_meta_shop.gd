extends Node

## Fase 5 de supervivencia: tienda de mejoras permanentes, dificultad/retos y segunda vida.
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
	SaveManager.upgrades = {}
	SaveManager.total_gold = 0

	# 1. Tienda: precios crecientes, tope y pago con el oro guardado
	_check(MetaShop.cost("poder") == 250 and not MetaShop.can_buy("poder"), "sin oro no se compra")
	SaveManager.total_gold = 100000
	_check(MetaShop.buy("poder") and MetaShop.level("poder") == 1 and SaveManager.total_gold == 100000 - 250, "compra de Poder y cobro")
	_check(MetaShop.cost("poder") > 250, "el siguiente nivel es más caro (%d)" % MetaShop.cost("poder"))
	for i in 20:
		MetaShop.buy("poder")
	_check(MetaShop.level("poder") == MetaShop.max_level("poder") and MetaShop.cost("poder") == -1 and not MetaShop.buy("poder"), "tope de nivel")
	_check(is_equal_approx(MetaShop.stat_total("damage"), 0.03 * 10.0), "Poder suma +30%% de daño al máximo")
	GameData.game_mode = "dungeon"
	_check(MetaShop.stat_total("damage") == 0.0, "la mazmorra no recibe estas mejoras")
	GameData.game_mode = "survival"
	MetaShop.buy("relanzar")
	MetaShop.buy("descarte")
	GameState.get_instance().reset_session()
	_check(GameState.get_instance().card_rerolls == GameState.CARD_REROLLS + MetaProgress.bonus_rerolls() + 1, "Relanzar suma un uso de volver a tirar")
	_check(GameState.get_instance().card_banishes == GameState.CARD_BANISHES + MetaProgress.bonus_banishes() + 1, "Descarte suma un uso de descartar")

	# 2. Dificultad y retos
	_check(RunModifiers.unlocked_max() == 0 and RunModifiers.difficulty() == 0, "empieza en NORMAL")
	RunModifiers.set_difficulty(3)
	_check(RunModifiers.difficulty() == 0, "no se puede elegir una dificultad sin desbloquear")
	RunModifiers.record_clear()
	_check(RunModifiers.unlocked_max() == 1, "vencer al jefe desbloquea la siguiente")
	RunModifiers.set_difficulty(1)
	_check(RunModifiers.enemy_hp_mult() > 1.0 and RunModifiers.gold_mult() > 1.0 and RunModifiers.spawn_interval_mult() < 1.0, "DIFICIL: enemigos más duros y más oro")
	RunModifiers.set_challenge("cristal")
	_check(is_equal_approx(RunModifiers.player_hp_mult(), 0.5), "reto Cristal: mitad de vida")
	RunModifiers.cycle_challenge()
	_check(RunModifiers.challenge() == "horda" and RunModifiers.xp_mult() > 1.0, "se cambia de reto (Horda: más XP)")
	GameData.game_mode = "dungeon"
	_check(RunModifiers.enemy_hp_mult() == 1.0 and RunModifiers.gold_mult() == 1.0, "en la mazmorra todo es neutro")
	GameData.game_mode = "survival"
	RunModifiers.set_challenge("")
	RunModifiers.set_difficulty(0)

	# 3. En la partida: vida de Vigor, tomo inicial y segunda vida
	MetaShop.buy("vigor")
	MetaShop.buy("revivir")
	_main = load("res://scenes/core/main_procedural.tscn").instantiate()
	get_tree().root.add_child.call_deferred(_main)
	await get_tree().process_frame
	get_tree().current_scene = _main
	var p = null
	for i in 900:
		await get_tree().process_frame
		p = _main.get_node_or_null("Player")
		if p and p.weapon_inventory and not p.weapon_inventory.weapon_slots.is_empty() and p.stat_block:
			break
	_check(p != null, "arranca la partida")
	var base_hp: float = float(GameData.get_selected().get("stats", {}).get("max_hp", 0.0)) + GameData.BASE_HP_BONUS
	_check(is_equal_approx(p.max_hp, base_hp + 10.0), "Vigor suma 10 de vida máxima (%.0f)" % p.max_hp)
	var tome := GameData.start_tome()
	_check(tome == "" or TomeDB.level(tome) == 1, "el personaje empieza con su tomo (%s)" % tome)
	_check(GameState.get_instance().revives_left == 1, "queda 1 segunda vida")
	var died := [false]
	p.player_died.connect(func(): died[0] = true)
	p.health_comp.hp = 0.0
	p._on_entity_died()
	_check(not p.is_playing_death_scan and is_equal_approx(p.health_comp.hp, p.health_comp.max_hp * 0.5), "la segunda vida te levanta con el 50%")
	_check(GameState.get_instance().revives_left == 0, "se gasta la segunda vida")
	p.health_comp.hp = 0.0
	p._on_entity_died()
	await get_tree().create_timer(3.0, true, false, true).timeout
	print("time_scale=", Engine.time_scale, " scan=", p.is_playing_death_scan)
	_check(died[0], "sin segunda vida, mueres de verdad")
	SaveManager.upgrades = {}
	SaveManager.meta = {}
	print("ALL PASSED" if not _fail else "SOME FAILED")
	get_tree().quit(1 if _fail else 0)
