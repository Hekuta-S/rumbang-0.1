extends Node

## Fase 1 de supervivencia: curva de XP por tramos, valor de gemas y componentes.
var _n := 0
func _check(ok: bool, msg: String) -> void:
	_n += 1
	if not ok:
		push_error("FAILED: " + msg)
		print("CHECK %d FAILED: %s" % [_n, msg])
		get_tree().quit(1)
		await get_tree().process_frame
	else:
		print("CHECK %d PASSED: %s" % [_n, msg])

func _ready() -> void:
	_check(is_equal_approx(XpCurve.required(1), 5.0), "nivel 1 -> 2 cuesta 5")
	_check(XpCurve.required(2) > XpCurve.required(1), "la curva crece")
	_check(is_equal_approx(XpCurve.required(21) - XpCurve.required(20), XpCurve.SLOPE_2), "pendiente tramo 2")
	_check(is_equal_approx(XpCurve.required(41) - XpCurve.required(40), XpCurve.SLOPE_3), "pendiente tramo 3")
	var total := 0.0
	for l in range(1, 30):
		total += XpCurve.required(l)
	print("XP acumulada hasta nivel 30: ", total)
	_check(XpCurve.required(10) < 100.0, "nivel 10 barato (no x1.5 por nivel)")
	_check(XpCurve.xp_for_type(EnemyData.EnemyType.NORMAL_GOBLIN) == 1.0, "relleno = 1 XP")
	_check(XpCurve.xp_for_type(EnemyData.EnemyType.HEAVY_BRUTE) == 5.0, "bruto = 5 XP")
	_check(XpCurve.gem_tier(1.0) == 0 and XpCurve.gem_tier(7.0) == 1 and XpCurve.gem_tier(25.0) == 2 and XpCurve.gem_tier(100.0) == 3, "tiers de gema")
	var xp := ExperienceComponent.new()
	var levels := []
	xp.leveled_up.connect(func(l): levels.append(l))
	xp.gain_experience(5.0)
	_check(xp.level == 2 and levels == [2], "5 XP suben al nivel 2")
	xp.gain_experience(200.0)
	_check(xp.level > 5 and levels.size() == xp.level - 1, "XP grande encadena varias subidas")
	_check(is_equal_approx(xp.experience_required, XpCurve.required(xp.level)), "requisito sigue la curva")
	var orb := XPOrb.new()
	orb.xp_amount = 1.0
	orb.add_xp(5.0)
	_check(orb.xp_amount == 6.0, "fusion suma XP")
	orb.free()
	xp.free()
	print("ALL PASSED")
	get_tree().quit(0)
