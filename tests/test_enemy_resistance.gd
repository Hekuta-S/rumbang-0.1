extends Node

## Resistencia de los enemigos (spec de reorganización del HUD y resistencia): más armadura física y más
## aguante (cuesta más aturdirlos, interrumpirlos y empujarlos) SIN tocar su vida ni su daño.
## Solo los blindados de verdad (bruto, rata gorda) hacen rebotar los golpes flojos.

var _failed := false

func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failed = true
		push_error("FALLO: " + msg)
		print("FAILED: " + msg)

func _done(n: Variant, msg: String) -> bool:
	if _failed:
		print("TEST FAILED en el check %s" % str(n))
		get_tree().quit(1)
		return false
	print("CHECK %s PASSED: %s" % [str(n), msg])
	return true

func _slug_small() -> DungeonGoblin:
	return DungeonSlug.new().make_small()

func _ready() -> void:
	print("--- TEST: RESISTENCIA DE ENEMIGOS ---")
	# [nombre, constructor, armor, armor_break, stagger_damage, windup_poise, knock_scale, rebota, vida final de referencia]
	var table := [
		["goblin", func(): return DungeonGoblin.new(), 9.0, 26.0, 20.0, 18.0, 0.8, false, 112.0],
		["rata", func(): return DungeonRat.new(), 5.0, 18.0, 13.0, 5.0, 1.2, false, 22.4],
		["rata grande", func(): return DungeonBigRat.new(), 11.0, 38.0, 27.0, 20.0, 0.45, true, 84.0],
		["bruto", func(): return DungeonBrute.new(), 20.0, 44.0, 36.0, 36.0, 0.25, true, 228.0],
		["zombi", func(): return DungeonZombie.new(), 10.0, 30.0, 21.0, 20.0, 0.6, false, 70.4],
		["hinchado", func(): return DungeonBloater.new(), 12.0, 34.0, 23.0, 27.0, 0.7, false, 42.24],
		["babosa grande", func(): return DungeonSlug.new(), 9.0, 28.0, 25.0, 22.0, 0.45, false, 98.56],
		["babosa pequeña", _slug_small, 5.0, 18.0, 14.0, 9.0, 0.95, false, 28.16],
		["mago", func(): return DungeonMage.new(), 6.0, 20.0, 18.0, 11.0, 0.9, false, 89.6],
		["nigromante", func(): return DungeonNecromancer.new(), 9999.0, 170.0, 9999.0, 9999.0, 0.05, false, 840.0],
	]
	var nodes: Array = []
	# 1. Valores de armadura, aguante y empuje
	for row in table:
		var e: DungeonGoblin = (row[1] as Callable).call()
		nodes.append(e)
		var name: String = row[0]
		_check(is_equal_approx(e.armor, row[2]), "%s: armor %.1f (esperado %.1f)" % [name, e.armor, row[2]])
		_check(is_equal_approx(e.armor_break, row[3]), "%s: armor_break %.1f (esperado %.1f)" % [name, e.armor_break, row[3]])
		_check(is_equal_approx(e.stagger_damage, row[4]), "%s: stagger_damage %.1f (esperado %.1f)" % [name, e.stagger_damage, row[4]])
		_check(is_equal_approx(e.windup_poise, row[5]), "%s: windup_poise %.1f (esperado %.1f)" % [name, e.windup_poise, row[5]])
		_check(is_equal_approx(e.knock_scale, row[6]), "%s: knock_scale %.2f (esperado %.2f)" % [name, e.knock_scale, row[6]])
		_check(e.has_glance_armor() == row[7], "%s: rebote %s (esperado %s)" % [name, e.has_glance_armor(), row[7]])
	if not _done(1, "armadura, aguante y empuje de la tabla"): return

	# 2. La vida y el daño no cambian (vida final = tipo × hp_mult × TOUGHNESS_HP; daño del tipo sin multiplicar)
	for i in table.size():
		var e: DungeonGoblin = nodes[i]
		var fw = EnemyTypeFlyweightFactory.get_flyweight(e.enemy_type)
		fw.apply_to(e)
		var hp: float = e.max_hp * e.hp_mult * DungeonGoblin.TOUGHNESS_HP
		_check(absf(hp - float(table[i][8])) < 0.01, "%s: vida %.1f (referencia %.1f)" % [table[i][0], hp, table[i][8]])
		_check(is_equal_approx(e.damage, fw.damage) and is_equal_approx(e.damage_mult, 1.0), "%s: daño sin tocar" % table[i][0])
		_check(is_equal_approx(e.damage_taken_mult, 1.0), "%s: sin reducción de daño recibido" % table[i][0])
	if not _done(2, "vida y daño como antes"): return

	# 3. armor_break >= armor (salvo el jefe, que nunca se inmuta y se rompe por acumulación)
	for i in table.size():
		var e: DungeonGoblin = nodes[i]
		if e.armor >= DungeonGoblin.ARMOR_GLANCE_MAX:
			continue
		_check(e.armor_break >= e.armor, "%s: armor_break >= armor" % table[i][0])
	if not _done(3, "la armadura no se rompe de un golpe"): return
	for e in nodes:
		e.free()

	# 4. Supervivencia: resistencia al empujón por comportamiento; el bruto es el más pesado
	var beh := {
		"base": [EnemyBehavior.new(null), 0.85],
		"normal": [EnemyBehavior.NormalGoblinBehavior.new(null), 0.85],
		"mago": [EnemyBehavior.RangedGoblinBehavior.new(null), 0.8],
		"tirador": [EnemyBehavior.SniperGoblinBehavior.new(null), 0.75],
		"mortero": [EnemyBehavior.MortarGoblinBehavior.new(null), 0.6],
		"bruto": [EnemyBehavior.HeavyBruteBehavior.new(null), 0.2],
		"zombi": [EnemyBehavior.ZombieGoblinBehavior.new(null), 0.6],
	}
	var lowest := ""
	var low_v := INF
	for k in beh:
		var v: float = beh[k][0].get_knockback_resistance()
		_check(is_equal_approx(v, beh[k][1]), "Supervivencia %s: %.2f (esperado %.2f)" % [k, v, beh[k][1]])
		if v < low_v:
			low_v = v
			lowest = k
	_check(lowest == "bruto", "El bruto es el que menos se empuja (%s)" % lowest)
	# El rasgo splitter pesa más; mini no cambia; al reutilizarlo del pool vuelve a 1
	var d := EnemyData.new(EnemyData.EnemyType.NORMAL_GOBLIN)
	_check(is_equal_approx(d.knockback_resistance, 1.0), "EnemyData: 1.0 por defecto")
	d.apply_trait("splitter")
	_check(is_equal_approx(d.knockback_resistance, 0.6), "Splitter: 0.6")
	d.reactivate(Vector3.ZERO)
	_check(is_equal_approx(d.knockback_resistance, 1.0), "Reutilizado: vuelve a 1.0")
	d.apply_trait("mini")
	_check(is_equal_approx(d.knockback_resistance, 1.0), "Mini: 1.0")
	if not _done(4, "empujón en supervivencia"): return

	print("ALL ENEMY RESISTANCE CHECKS PASSED")
	get_tree().quit(0)
