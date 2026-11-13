extends Node

## Fase 2 de supervivencia: TomeDB (niveles, poder por rareza, suerte) y desbloqueo de armas por logros.
var _fail := false
func _check(ok: bool, msg: String) -> void:
	print("%s: %s" % ["PASSED" if ok else "FAILED", msg])
	if not ok:
		_fail = true

func _ready() -> void:
	SaveManager.save_path = "user://test_save.json"
	SaveManager.meta = {}
	GameState.get_instance().reset_session()
	_check(TomeDB.stat_total("damage") == 0.0, "sin tomos no hay bonus")
	TomeDB.add("poder", TomeDB.Rarity.COMMON)
	TomeDB.add("poder", TomeDB.Rarity.LEGENDARY)
	_check(TomeDB.level("poder") == 2, "dos subidas = nivel 2")
	_check(is_equal_approx(TomeDB.stat_total("damage"), 0.08 * 4.0), "poder acumulado 1 + 3 = 4 niveles de valor")
	_check(TomeDB.stat_total("max_hp") == 0.0, "la vida máxima no cuenta como stat continuo")
	for i in 10:
		TomeDB.add("poder", 0)
	_check(TomeDB.level("poder") == TomeDB.MAX_LEVEL, "tope de nivel")
	for id in ["celeridad", "area", "iman"]:
		TomeDB.add(id, 0)
	_check(TomeDB.owned().size() == 4 and not TomeDB.can_take("suerte"), "4 huecos llenos: no entra uno nuevo")
	_check(TomeDB.can_take("celeridad"), "uno que ya tienes sí sube")
	# Suerte: más rarezas altas
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var base_high := 0
	var luck_high := 0
	for i in 3000:
		if TomeDB.roll_rarity(0.0, rng) >= 2: base_high += 1
		if TomeDB.roll_rarity(0.6, rng) >= 2: luck_high += 1
	_check(luck_high > base_high * 1.3, "la suerte sube las épicas/legendarias (%d vs %d)" % [base_high, luck_high])
	# Evoluciones: cada una apunta a un tomo existente y no se repite
	var seen := {}
	for w in WeaponSynergies.EVOLUTIONS:
		var t: String = WeaponSynergies.EVOLUTIONS[w]["tome"]
		_check(TomeDB.TOMES.has(t) and not seen.has(t), "evolución %d usa un tomo único (%s)" % [w, t])
		seen[t] = true
	# Armas bloqueadas por logros
	_check(not MetaProgress.weapon_unlocked(WeaponData.WeaponType.RAILGUN), "cañón de riel bloqueado al empezar")
	_check(MetaProgress.weapon_unlocked(WeaponData.WeaponType.SPEAR_LANCE), "lanza siempre disponible")
	MetaProgress.record_survival_run(30)
	_check(MetaProgress.weapon_unlocked(WeaponData.WeaponType.RAILGUN), "nivel 30 desbloquea el cañón de riel")
	MetaProgress.record_survival_run(5)
	_check(MetaProgress.stat("survival_runs") == 1, "la misma partida no se cuenta dos veces")
	RunStats.reset()
	MetaProgress.record_survival_run(5)
	_check(MetaProgress.stat("survival_runs") == 2 and MetaProgress.weapon_unlocked(WeaponData.WeaponType.SERPENTS), "2 partidas desbloquean serpientes")
	SaveManager.meta = {}
	print("ALL PASSED" if not _fail else "SOME FAILED")
	get_tree().quit(1 if _fail else 0)
