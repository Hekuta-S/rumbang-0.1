extends Node

## Estadísticas tipo Dark Souls (SoulStats): almas por baja, ingreso al acabar la partida (la mitad al
## morir), subir de nivel con coste creciente, efectos solo en la mazmorra, escalado por arma y la
## pestaña NIVEL del yunque.
## Headless:  Godot --headless --path . res://tests/test_soul_stats.tscn

const W := WeaponData.WeaponType

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	print("--- TEST: ESTADISTICAS TIPO DARK SOULS ---")
	SaveManager.save_path = "user://test_save_souls.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.save_path))
	SaveManager.load_save()
	GameData.armory_path = "user://test_armeria_souls.cfg"
	var prev_mode := GameData.game_mode

	# 1. Estado inicial
	assert(SoulStats.souls() == 0 and SoulStats.level() == 1, "Empieza en nivel 1 sin almas")
	for s in SoulStats.ORDER:
		assert(SoulStats.value(s) == SoulStats.BASE, "%s empieza en %d" % [s, SoulStats.BASE])
	print("CHECK 1 PASSED: nivel 1, todo a %d" % SoulStats.BASE)

	# 2. Almas por baja y ingreso: al morir se conserva la mitad, al retirarse todo
	var normal := SoulStats.kill_souls(false, false, 1)
	var elite := SoulStats.kill_souls(false, true, 1)
	var boss := SoulStats.kill_souls(true, false, 1)
	assert(normal < elite and elite < boss, "Normal < élite < jefe (%d, %d, %d)" % [normal, elite, boss])
	assert(SoulStats.kill_souls(false, false, 5) > normal, "Más almas en niveles más hondos")
	SoulStats.start_run()
	SoulStats.add_run_souls(300)
	assert(SoulStats.bank_run(true) == 150 and SoulStats.souls() == 150 and SoulStats.last_lost == 150, "Al morir, la mitad")
	SoulStats.start_run()
	SoulStats.add_run_souls(300)
	SoulStats.start_run()   # partida abandonada: la siguiente ingresa lo pendiente entero
	assert(SoulStats.souls() == 450 and SoulStats.run_souls == 0, "Al retirarse se guarda todo (%d)" % SoulStats.souls())
	print("CHECK 2 PASSED: almas %d/%d/%d, muerte = mitad" % [normal, elite, boss])

	# 3. Subir de nivel: cuesta almas, el precio crece y se guarda
	var c1 := SoulStats.level_cost()
	assert(c1 > 0 and SoulStats.level_cost(10) > c1, "El nivel cuesta más cuanto más alto")
	assert(SoulStats.level_up("vigor"), "Se puede subir Vigor")
	assert(SoulStats.value("vigor") == SoulStats.BASE + 1 and SoulStats.level() == 2, "Vigor 11, nivel 2")
	assert(SoulStats.souls() == 450 - c1, "Se gastan las almas")
	(SaveManager.meta["souls"] as Dictionary)["almas"] = 0
	assert(not SoulStats.level_up("fuerza"), "Sin almas no se sube")
	assert(not SoulStats.level_up("inventada"), "Estadística desconocida")
	SaveManager.save()
	SaveManager.load_save()
	assert(SoulStats.points("vigor") == 1, "Los puntos se guardan")
	print("CHECK 3 PASSED: coste %d -> %d, guardado" % [c1, SoulStats.level_cost()])

	# 4. Efectos: solo en la mazmorra; Fuerza/Destreza según el arma
	var pts: Dictionary = SaveManager.meta["souls"]["pts"]
	pts["fuerza"] = 10
	pts["destreza"] = 0
	pts["aguante"] = 5
	GameData.game_mode = "survival"
	assert(SoulStats.stat_total("damage", W.MACE) == 0.0, "En supervivencia no cuenta")
	GameData.game_mode = "dungeon"
	var mace := SoulStats.stat_total("damage", W.MACE)
	var daggers := SoulStats.stat_total("damage", W.DAGGERS)
	assert(mace > daggers * 5.0 and is_equal_approx(mace, 10.0 * SoulStats.DAMAGE_PER), "Fuerza: maza %.2f >> dagas %.2f" % [mace, daggers])
	assert(SoulStats.stat_total("max_energy", W.MACE) > 0.0, "Aguante da energía")
	assert(SoulStats.hp_bonus() > 0.0, "Vigor da vida")
	assert(SoulStats.grade(1.0) == "A" and SoulStats.grade(1.1) == "S" and SoulStats.grade(0.0) == "-", "Letras de escalado")
	assert(SoulStats._curve(30) < 30.0 and SoulStats._curve(30) > SoulStats._curve(20), "Tope blando")
	print("CHECK 4 PASSED: maza +%d%%, dagas +%d%%, %s" % [int(mace * 100), int(daggers * 100), SoulStats.scaling_text(W.MACE)])

	# 5. Yunque: pestaña ARMAS en lista y NIVEL que sube con almas
	var panels := HubPanels.new()
	add_child(panels)
	panels.open("yunque")
	await get_tree().process_frame
	assert(panels.anvil_tab == "armas" and panels._cards.size() >= GameData.DUNGEON_WEAPONS.size(), "Listado de armas")
	assert(panels._detail.find_child("Escalado", true, false) != null, "Detalle con escalado")
	panels.show_anvil_tab("nivel")
	assert(panels._stat_buttons.size() == SoulStats.ORDER.size(), "Seis estadísticas")
	SoulStats.add_souls(SoulStats.level_cost())
	var before := SoulStats.value("destreza")
	assert(panels.level_up("destreza") and SoulStats.value("destreza") == before + 1, "SUBIR en el yunque")
	assert(panels._sel_stat == "destreza", "Queda marcada la que se subió")
	panels.show_anvil_tab("armas")
	panels.equip(W.DAGGERS)
	panels.close()
	print("CHECK 5 PASSED: yunque con pestañas ARMAS y NIVEL")

	GameData.game_mode = prev_mode
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.save_path))
	print("ALL SOUL STATS CHECKS PASSED")
	get_tree().quit(0)
