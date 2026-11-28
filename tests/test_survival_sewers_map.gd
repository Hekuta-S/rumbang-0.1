extends Node

## Mapa de Cloacas de Supervivencia (ProceduralMap theme "sewers") y portal entre mapas (SurvivalMapSwitch):
##  1-6: generación (dos barrios enfrentados, depósito y mesetas en la franja de en medio, sin árboles,
##       vertederos, suelo de cloaca, misma semilla = mismo mapa)
##  7-8: perfil de sonido/fauna y horda con sobre todo fauna
##  9-13: partida real: abrir el portal, cruzarlo (regenera el mapa sin cortar la partida) y volver
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
	GameData.survival_map = "sewers"
	var two_ok := true
	var mesa_ok := true
	var plaza_ok := true
	var trees_ok := true
	var junk_ok := true
	var basin_ok := true
	var gen_ms := 0.0
	var seeds := [3, 27, 91, 202, 377]
	for s in seeds:
		var t0 := Time.get_ticks_usec()
		var map := ProceduralMap.new()
		map.map_seed = s
		add_child(map)
		gen_ms += float(Time.get_ticks_usec() - t0) / 1000.0
		await get_tree().process_frame
		var ds: Array = map.districts
		if map.get_theme() != "sewers" or ds.size() != 2:
			two_ok = false
			print("  barrios ", s, ": ", ds.size(), " tema ", map.get_theme())
		else:
			var a: SewerDistrict = ds[0]
			var b: SewerDistrict = ds[1]
			if a.axis != b.axis or a.side_sign == b.side_sign or a.canals.size() < 3 or b.canals.size() < 3:
				two_ok = false
				print("  barrios mal enfrentados ", s)
		for m in map.get_mesas():
			if map.in_district(m["c"], float(m["r"])):
				mesa_ok = false
				print("  meseta en un barrio ", s, " ", m["c"])
		if map.in_district(Vector2.ZERO, 20.0):
			plaza_ok = false
		var bc := map.get_basin_center()
		if map.in_district(Vector2(bc.x, bc.z), map.basin_rim_radius):
			basin_ok = false
			print("  depósito dentro de un barrio ", s, " ", bc)
		var inst: Dictionary = map.get("_instances")
		if inst.has("tree_a") or inst.has("tree_b") or map.trees != null:
			trees_ok = false
		if (inst.get("trash_pile", []) as Array).size() < 10 or (inst.get("grave_a", []) as Array).size() > 0:
			junk_ok = false
			print("  vertederos ", s, ": ", (inst.get("trash_pile", []) as Array).size(), " montones")
		map.queue_free()
		await get_tree().process_frame
	_check(two_ok, "Cloacas: dos barrios de canales, uno a cada lado")
	_check(mesa_ok and plaza_ok and basin_ok, "plaza, depósito y mesetas quedan en la franja de en medio")
	_check(trees_ok, "sin árboles en las Cloacas")
	_check(junk_ok, "vertederos en vez de cementerios")
	_check(gen_ms / float(seeds.size()) < 1500.0, "genera en %.0f ms de media" % (gen_ms / float(seeds.size())))

	# 6. Misma semilla, mismo mapa (LAN / reintento)
	var m1 := ProceduralMap.new()
	m1.map_seed = 4242
	add_child(m1)
	var m2 := ProceduralMap.new()
	m2.map_seed = 4242
	add_child(m2)
	var same := m1.get_height_at(90.0, 30.0) == m2.get_height_at(90.0, 30.0) and m1.get_height_at(-95.0, -60.0) == m2.get_height_at(-95.0, -60.0)
	same = same and (m1.districts[0] as SewerDistrict).canals.size() == (m2.districts[0] as SewerDistrict).canals.size()
	_check(same, "la misma semilla da el mismo mapa de Cloacas")
	# 7. Sonido y fauna propios
	_check(MapAmbience.profile_for(m1) == "survival_sewers", "perfil de sonido y fauna de Cloacas")
	m1.queue_free()
	m2.queue_free()
	GameData.survival_map = "forest"
	var f := ProceduralMap.new()
	f.map_seed = 4242
	add_child(f)
	_check(f.get_theme() == "forest" and f.districts.size() == 1 and f.trees != null and MapAmbience.profile_for(f) == "survival",
		"el Bosque sigue igual (un barrio, árboles)")
	f.queue_free()
	await get_tree().process_frame
	# 8. Horda: sobre todo fauna en Cloacas
	_check(WaveManager.sewer_fauna_share(0.0) >= 0.7 and WaveManager.sewer_fauna_share(10.0) <= 0.8, "la horda de Cloacas es 70-80 % fauna")

	# 9-13. Partida real en el Bosque: portal, cruce a Cloacas y vuelta
	GameData.survival_map = "forest"
	var main: Node = load("res://scenes/core/main_procedural.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	get_tree().current_scene = main
	var p = null
	var waves: WaveManager = null
	var sw: SurvivalMapSwitch = null
	for i in 900:
		await get_tree().process_frame
		p = main.get_node_or_null("Player")
		waves = main.find_child("WaveManager", true, false)
		sw = main.get_node_or_null("SurvivalMapSwitch")
		if p and waves and waves._running and sw:
			break
	_check(sw != null and waves != null and waves._running, "la partida arranca con el portal preparado")
	p.health_comp.max_hp = 100000.0
	p.health_comp.hp = 100000.0
	var map: ProceduralMap = main.get_node("ProceduralMap")
	_check(map.get_theme() == "forest", "empieza en el mapa elegido (Bosque)")
	var portal := sw.open_portal()
	var pp: Vector3 = p.global_position
	var ok_spot := portal != null and Vector2(portal.global_position.x - pp.x, portal.global_position.z - pp.z).length() >= SurvivalMapSwitch.SPOT_DIST.x - 0.1 \
		and not map.is_water(portal.global_position)
	_check(ok_spot, "el portal se abre en suelo seco, lejos del jugador")
	for i in 6:
		waves._spawn_single_enemy(pp + Vector3(6, 0, float(i)), EnemyData.EnemyType.NORMAL_GOBLIN)
	var level_before = p.get("level")
	sw.switch_to("sewers")
	for i in 30:                          # la fauna recoge sus sitios en su propio _process
		await get_tree().process_frame
	var amb := main.get_node_or_null("MapAmbience") as MapAmbience
	var crit := main.get_node_or_null("AmbientCritters") as AmbientCritters
	if crit:
		crit._collect_spots()             # en partida lo hace su _process cada SPOT_TICK s
	if amb and crit:
		print("  perfil ", amb.profile_id, " / ", crit.profile_id, " ratas ", crit.spot_count("rat"), " moscas ", crit.spot_count("fly"))
	var on_floor := absf(p.global_position.y - map.get_height_at(p.global_position.x, p.global_position.z)) < 1.0
	_check(map.get_theme() == "sewers" and map.districts.size() == 2 and EnemyManager.active_count() == 0 and on_floor,
		"cruzar lleva a Cloacas: mapa nuevo, horda atrás, jugador en el suelo")
	_check(amb != null and amb.profile_id == "survival_sewers" and crit != null and crit.profile_id == "survival_sewers" \
		and crit.spot_count("rat") > 20 and crit.spot_count("fly") > 10, "sonido y fauna de Cloacas tras cruzar")
	_check(waves._running and p.get("level") == level_before and not is_instance_valid(sw.portal),
		"la partida sigue (mismo nivel, portal cerrado)")
	# EnemyMotion usa las alturas nuevas: el fondo de un canal
	var c0: Dictionary = (map.districts[0] as SewerDistrict).canals[0]
	var cm: Vector2 = ((c0["min"] as Vector2) + (c0["max"] as Vector2)) * 0.5
	_check(absf(EnemyMotion.height_at(cm.x, cm.y) - map.get_height_at(cm.x, cm.y)) < 0.05, "los enemigos ven el relieve nuevo")
	sw.switch_to("forest")
	await get_tree().process_frame
	_check(map.get_theme() == "forest" and map.districts.size() == 1 and sw.switches == 2, "y se puede volver al Bosque")
	GameData.survival_map = "forest"
	get_tree().quit(1 if _fail else 0)
