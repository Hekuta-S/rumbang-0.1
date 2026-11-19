extends Node

## Vida de los mapas: sonido ambiente (MapAmbience) y reacciones al jugador (MapReactions).
## Carga una partida real. El mundo sale de la variable de entorno MAP_LIFE_WORLD:
##   caves (por defecto) · sewers · survival

func _ready() -> void:
	var world := OS.get_environment("MAP_LIFE_WORLD")
	if world == "":
		world = "caves"
	print("--- TEST: VIDA DEL MAPA (%s) ---" % world)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var survival := world == "survival"
	GameData.game_mode = "survival" if survival else "dungeon"
	if not survival:
		GameData.world = world
	var path := "res://scenes/core/main_procedural.tscn" if survival else Net.game_scene()
	var scene: Node = load(path).instantiate()
	get_tree().root.add_child.call_deferred(scene)
	await get_tree().process_frame
	get_tree().current_scene = scene
	var ambience: MapAmbience = null
	var reactions: MapReactions = null
	for i in 900:
		await get_tree().process_frame
		ambience = scene.get_node_or_null("MapAmbience")
		reactions = scene.get_node_or_null("MapReactions")
		if ambience and reactions and get_tree().get_first_node_in_group("player"):
			break
	assert(ambience != null and reactions != null, "GameStartFacade crea MapAmbience y MapReactions")
	var enc := scene.get_node_or_null("DungeonEncounter")
	if enc:
		enc._pending.clear()
	var map := scene.get_node("ProceduralMap") as ProceduralMap
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var hc = player.get("health_comp")
	if hc:
		hc.max_hp = 9999.0
		hc.hp = 9999.0

	# 1. Perfil, camas y presupuesto de emisores
	assert(ambience.profile_id == world, "perfil %s (es %s)" % [world, ambience.profile_id])
	assert(MapAmbience.profile_for(map) == world)
	assert(ambience.bed_count() == (MapAmbience.PROFILES[world]["beds"] as Array).size(), "una cama por entrada del perfil")
	assert(ambience.emitter_count() == MapAmbience.emitter_budget(), "emisores = presupuesto de calidad")
	for prof in MapAmbience.PROFILES.values():
		for b in prof["beds"]:
			var wav := MapAmbience._loop_stream(b[0]) as AudioStreamWAV
			assert(wav != null and wav.loop_mode == AudioStreamWAV.LOOP_FORWARD, "%s existe y va en bucle" % b[0])
		for s in prof["shots"]:
			assert(AudioManager.get_stream(s[0]) != null, "falta el sonido %s" % s[0])
	for k in MapAmbience.EMITTERS:
		assert(MapAmbience._loop_stream(MapAmbience.EMITTERS[k][0]) != null)
	for sfx in ["water_step", "grass_rustle", "spore_puff", "fire_whoosh"]:
		assert(AudioManager.get_stream(sfx) != null, "falta el sonido %s" % sfx)
	var shot := ambience.pick_shot()
	assert(not shot.is_empty() and (MapAmbience.PROFILES[world]["shots"] as Array).has(shot), "sonido suelto del perfil")
	await get_tree().create_timer(1.2).timeout
	var loud := 0
	for b in ambience._beds:
		if (b["player"] as AudioStreamPlayer).playing and (b["player"] as AudioStreamPlayer).volume_db > -40.0:
			loud += 1
			assert((b["player"] as AudioStreamPlayer).bus == &"Ambient")
	assert(loud >= 1, "al menos una cama suena")
	print("CHECK 1 PASSED: perfil %s, %d camas, %d emisores" % [world, ambience.bed_count(), ambience.emitter_count()])

	# 2. Emisores: se mudan a las fuentes cercanas y se callan lejos de todas
	var fires: PackedVector3Array = map.ambient_points.get("fire", PackedVector3Array())
	assert(fires.size() > 0, "el mapa declara sus fuegos")
	var fire: Vector3 = map.to_global(fires[0])
	player.global_position = fire + Vector3(1.5, 0.3 - fire.y + map.get_height_at(fire.x + 1.5, fire.z), 0.0)
	await get_tree().create_timer(0.8).timeout
	assert(ambience.active_emitters() >= 1, "suena el fuego de al lado")
	assert(ambience.active_emitters() <= MapAmbience.emitter_budget())
	var burning := false
	for e in ambience._emitters:
		if e["kind"] == "fire" and (e["player"] as AudioStreamPlayer3D).playing:
			burning = true
	assert(burning, "un emisor reproduce amb_fire")
	print("CHECK 2 PASSED: %d emisores activos junto a un fuego (%d fuegos en el mapa)" % [ambience.active_emitters(), fires.size()])

	# 3. Onda de golpe: el ataque la lanza, los uniformes globales la siguen y se apaga sola
	var before: int = reactions.counts.get("pulse", 0)
	player.emit_signal("weapon_attacked", 0)
	await get_tree().process_frame
	await get_tree().process_frame
	assert(int(reactions.counts.get("pulse", 0)) == before + 1, "el ataque lanza la onda")
	var pulse: Vector4 = reactions.pulse_now
	assert(pulse.w > 0.0 and pulse.z > 0.0, "la onda avanza (%s)" % str(pulse))
	assert(reactions.actor_now.distance_to(player.global_position) < 1.0, "los shaders saben dónde está el jugador")
	# El fuego cercano tiembla: alguna luz encendida baja, y saltan brasas
	var gusted := 0
	for i in map._lights.size():
		if map._light_gust[i] > 0.0:
			gusted += 1
	assert(gusted >= 1 or not _any_light_on(map, player.global_position, 5.0), "las luces cercanas acusan la ráfaga")
	assert(int(reactions.counts.get("ember", 0)) >= 1, "el fuego suelta brasas")
	# En supervivencia el jugador sigue atacando solo: la caducidad se comprueba avanzando el reloj de la onda a mano
	reactions.pulse(player.global_position, 1.0)
	reactions._tick_pulse(MapReactions.PULSE_TIME + 0.1)
	pulse = reactions.pulse_now
	assert(pulse.w == 0.0, "la onda termina")
	print("CHECK 3 PASSED: onda de golpe, %d luces con ráfaga" % gusted)

	# 4. Propio de cada mundo
	if world == "caves":
		var mush: PackedVector3Array = map.ambient_points.get("mush_big", PackedVector3Array())
		assert(mush.size() > 0, "hay grupos de hongos grandes")
		var at: Vector3 = map.to_global(mush[0])
		var spores: int = reactions.counts.get("spore", 0)
		reactions.disturb(at, 1.0)
		assert(int(reactions.counts.get("spore", 0)) > spores, "el golpe suelta esporas")
		spores = reactions.counts.get("spore", 0)
		reactions.disturb(at, 1.0)
		var again: int = reactions.counts.get("spore", 0)
		assert(again - spores <= 1, "el mismo grupo no repite hasta enfriarse")
		var grass: Array = (map as DungeonMap).grass_transforms()
		assert(grass.size() > 0 and reactions.in_grass(map.to_global((grass[0] as Transform3D).origin)), "rejilla de hierba")
		assert((GrassMesh.build().surface_get_material(0) as ShaderMaterial).shader.code.contains("world_actor_pos"))
		print("CHECK 4 PASSED: esporas con enfriamiento y hierba (%d mechones)" % grass.size())
	elif world == "sewers":
		var sewer := map as SewerMap
		assert(not sewer._water.is_empty(), "las cloacas tienen agua")
		var cell: Vector2i = sewer._water.keys()[0]
		var wp: Vector3 = sewer._cell_pos(cell)
		assert(reactions.water_material() != null, "material del agua")
		var ripples: int = reactions.counts.get("ripple", 0)
		player.global_position = wp + Vector3(0.0, 0.3, 0.0)
		await get_tree().create_timer(0.3).timeout
		assert(int(reactions.counts.get("ripple", 0)) > ripples, "entrar al agua deja un anillo")
		assert(reactions.active_ripples() >= 1)
		var sent: Array = reactions.water_material().get_shader_parameter("ripples")
		assert(sent.size() == MapReactions.RIPPLES and (sent[0] as Vector4).w > 0.0, "el shader recibe los anillos")
		assert(ambience.water_near() > 0.0 and ambience.gain_for("water") > MapAmbience.WATER_FLOOR, "el agua suena más cerca")
		await get_tree().create_timer(MapReactions.RIPPLE_LIFE + 0.3).timeout
		assert(reactions.active_ripples() <= 1, "los anillos caducan")
		print("CHECK 4 PASSED: anillos en el agua y cama de agua por cercanía")
	else:
		assert(is_equal_approx(ambience.gain_for("day") + ambience.gain_for("night"), 1.0), "día y noche se reparten el viento")
		var cycle := scene.get_node_or_null("DayNightCycle") as DayNightCycle
		assert(cycle != null)
		cycle.phase = 1.0
		assert(ambience.gain_for("night") == 1.0 and ambience.gain_for("day") == 0.0, "de noche suena el viento nocturno")
		cycle.phase = 0.0
		assert(ambience.gain_for("day") == 1.0)
		print("CHECK 4 PASSED: viento de día y de noche según el ciclo")

	print("TODOS LOS CHECKS PASARON")
	get_tree().quit(0)

func _any_light_on(map: ProceduralMap, pos: Vector3, radius: float) -> bool:
	for l in map._lights:
		if is_instance_valid(l) and l.visible and l.global_position.distance_to(pos) < radius:
			return true
	return false
