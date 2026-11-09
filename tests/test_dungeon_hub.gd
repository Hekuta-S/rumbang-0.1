extends Node

## Salón de la Invocación = menú principal caminable: modelos, la intro (se ve una vez, se salta y acaba
## siguiendo al héroe), andar por el salón con colisiones, y las estaciones: yunque (arma de la
## mazmorra), mago (portales por mundo), arena (personajes de supervivencia), cofre (mejoras) y salir.
## Headless:  Godot --headless --path . res://tests/test_dungeon_hub.tscn

const HUB := preload("res://scenes/ui/dungeon_hub.tscn")

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	print("--- TEST: SALÓN DE LA INVOCACIÓN ---")
	DungeonHub.config_path = "user://test_dungeon_hub.cfg"
	DungeonHub.portals_open = false
	GameData.armory_path = "user://test_armeria.cfg"
	SaveManager.save_path = "user://test_save.json"
	for p in [DungeonHub.config_path, GameData.armory_path]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	GameData.load_armory()
	assert(not DungeonHub.intro_seen(), "Sin ajuste guardado la intro no se ha visto")
	assert(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/ui/title_screen.tscn", "Se abre en la pantalla de título")

	# 0. Pantalla de título: panorama del mapa, logo y "presiona cualquier tecla"; cualquier tecla continúa
	var title := (load("res://scenes/ui/title_screen.tscn") as PackedScene).instantiate() as TitleScreen
	add_child(title)
	await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	assert(title.find_children("*", "MenuBackground", true, false).size() == 1, "Panorama del mapa de fondo")
	assert(title.prompt.text == "Presiona cualquier tecla para continuar", "Aviso en PC: %s" % title.prompt.text)
	var cont := [false]
	title.continued.connect(func(): cont[0] = true)
	var key := InputEventKey.new()
	key.keycode = KEY_A
	key.pressed = true
	assert(title.leaving == false, "Aún no ha continuado")
	title.continue_to_hub(false)
	assert(cont[0] and title.leaving, "Cualquier tecla pasa al salón")
	title.queue_free()
	await get_tree().process_frame
	print("CHECK 0 PASSED: pantalla de título")

	# 1. Modelos exportados de Blender
	for p in [DungeonHub.SALON_PATH, DungeonHub.KING_PATH, DungeonHub.MAGE_PATH]:
		assert(ResourceLoader.exists(p), "Falta " + p + " (tools/blender_salon_invocacion.py)")
	print("CHECK 1 PASSED: salón, rey y mago exportados")

	# 2. Primera vez: intro; materiales, puertas/tapa, clips y piel del rey y el mago
	var hub := HUB.instantiate() as DungeonHub
	add_child(hub)
	await get_tree().process_frame
	assert(hub.state == "intro", "La primera vez se ve la intro (estado %s)" % hub.state)
	assert(not hub.player.visible and hub.player.locked, "El héroe aún no ha llegado")
	var names := {}
	for mi in hub.get_node("Salon").find_children("*", "MeshInstance3D", true, false):
		for i in (mi as MeshInstance3D).mesh.get_surface_count():
			var m := (mi as MeshInstance3D).get_surface_override_material(i)
			assert(m is StandardMaterial3D, "Material del juego en cada superficie del salón")
			names[m.resource_name] = m
	for k in ["salon_floor", "salon_brick", "salon_glow_rune", "salon_gold", "salon_carpet", "salon_steel", "salon_glow_crystal"]:
		assert(names.has(k), "El salón tiene " + k)
	for n in ["porton_izq", "porton_der", "puerta_arena_izq", "puerta_arena_der", "cofre_tapa"]:
		assert(hub._movers.has(n), "Pieza móvil " + n)
	var clips := {"rey": ["rey_idle", "rey_invocar", "rey_hablar", "rey_sorpresa"],
		"mago": ["mago_idle", "mago_conjurar", "mago_sorpresa", "mago_reverencia"]}
	for who in clips:
		var npc: Node3D = hub.king if who == "rey" else hub.mage
		var ap := hub._anim(npc)
		for c in clips[who]:
			assert(ap and ap.has_animation(c), "%s tiene el clip %s" % [who, c])
		var la := npc.get_node("LookApplier") as CharacterLookApplier
		assert(la and la.mesh_instance.get_surface_override_material(0) is ShaderMaterial, who + ": piel de Riva")
	assert(hub.player.has_clip("walk") and hub.player.has_clip("run"), "El héroe anda y corre")
	print("CHECK 2 PASSED: intro arrancada; salón, puertas, rey y mago listos")

	# 3. Murmullos
	var a := Murmur.make("¡Bienvenido, héroe!", "rey")
	var b := Murmur.make("¡Bienvenido, héroe!", "mago")
	var peak := 0
	for i in range(0, a.data.size() - 1, 2):
		peak = maxi(peak, absi(a.data.decode_s16(i)))
	assert(a.data.size() > 22050 and peak > 2000 and peak < 32000 and a.data != b.data, "Murmullos (pico %d)" % peak)
	print("CHECK 3 PASSED: murmullos (pico %d)" % peak)

	# 4. Tras el destello aparece el héroe en el círculo
	await _wait_intro(hub, DungeonHub.FLASH_AT + 0.6)
	assert(hub.player.visible and hub.player.global_position.distance_to(DungeonHub.CIRCLE) < 0.3, "El héroe en el círculo")
	assert(hub.player_model.get_node_or_null("LookApplier") != null, "Con su CharacterLook")
	print("CHECK 4 PASSED: el héroe aparece a los %.1f s" % hub.intro_time)

	# 5. Saltar (dos pulsaciones) -> se explora el salón
	var ev := InputEventKey.new()
	ev.keycode = KEY_SPACE
	ev.pressed = true
	hub._unhandled_input(ev)
	assert(hub.state == "intro", "Una pulsación solo avisa")
	hub._unhandled_input(ev)
	await _until(func(): return hub.state == "explore", 6.0)
	assert(hub.state == "explore" and not hub.player.locked, "Saltar lleva a explorar")
	assert(DungeonHub.intro_seen(), "Intro marcada como vista")
	print("CHECK 5 PASSED: intro saltada -> explorar")

	# 6. Andar: con clic/toque hasta el yunque; las columnas bloquean
	var anvil: Vector3 = DungeonHub.STATIONS["yunque"]["pos"]
	hub.player.move_to(anvil + Vector3(-0.9, 0, 0.3))
	await _until(func(): return hub.near_station == "yunque", 8.0)
	assert(hub.near_station == "yunque" and hub._prompt.visible, "Junto al yunque sale el aviso (%s)" % hub.near_station)
	var pillar := Vector3(6.2, DungeonHub.FLOOR_Y, 1.0)
	hub.player.position = Vector3(4.8, DungeonHub.FLOOR_Y, 1.0)
	hub.player.move_to(pillar)
	await _until(func(): return hub.player.move_target == null, 4.0)
	assert(hub.player.global_position.distance_to(pillar) > 0.6, "La columna no se atraviesa")
	print("CHECK 6 PASSED: se anda por el salón con colisiones")

	# 7. Yunque: equipar la maza (se guarda y es el arma inicial en la mazmorra)
	hub.use_station("yunque")
	assert(hub.state == "panel" and hub.panels.current == "yunque", "Se abre el yunque")
	assert(hub.panels._cards.size() == 5, "Espalanza, dagas, maza, espadón y espada")
	hub.panels.equip(WeaponData.WeaponType.MACE)
	assert(GameData.dungeon_weapon == WeaponData.WeaponType.MACE, "Maza equipada")
	GameData.dungeon_weapon = WeaponData.WeaponType.SPEAR_LANCE
	GameData.load_armory()
	assert(GameData.dungeon_weapon == WeaponData.WeaponType.MACE, "La elección se guarda")
	GameData.game_mode = "dungeon"
	GameData.selected_index = GameData.custom_index()
	assert(GameData.initial_weapons() == [WeaponData.WeaponType.MACE], "En la mazmorra se empieza con la maza")
	GameData.game_mode = "survival"
	assert(GameData.initial_weapons() == GameData.CHARACTERS[GameData.custom_index()]["initial_weapons"], "En supervivencia, la de siempre")
	hub.panels.close()
	assert(hub.state == "explore", "Cerrar el panel vuelve a explorar")
	print("CHECK 7 PASSED: yunque -> maza (guardada)")

	# 8. Mago: abre un portal por mundo
	hub.player.position = DungeonHub.MAGE_POS + Vector3(1.0, 0, 0.3)
	await get_tree().process_frame
	await get_tree().process_frame
	assert(hub.near_station == "mago", "Junto al mago (%s)" % hub.near_station)
	hub.use_station("mago")
	await get_tree().create_timer(2.0).timeout
	assert(DungeonHub.portals_open and hub.portals.size() == WorldDefs.ORDER.size(), "Portales abiertos")
	for p in hub.portals:
		assert(p["open"] and (p["node"] as Node3D).visible, "Portal de " + String(p["world"]))
		assert(hub._portal_at((p["node"] as Node3D).position) == String(p["world"]), "Se entra al portal de " + String(p["world"]))
	assert(hub._sub_panel.visible, "El mago habla")
	print("CHECK 8 PASSED: el mago abre %d portales" % hub.portals.size())

	# 9. Arena: los personajes de supervivencia de siempre
	hub.player.position = DungeonHub.STATIONS["arena"]["pos"] + Vector3(-0.8, 0, 0)
	await get_tree().process_frame
	await get_tree().process_frame
	assert(hub.near_station == "arena", "Junto a la puerta de la arena (%s)" % hub.near_station)
	hub.use_station("arena")
	var chars := HubPanels.survival_characters()
	assert(chars.size() >= 3, "Varios personajes en supervivencia (%d)" % chars.size())
	var ids := []
	for i in chars:
		ids.append(GameData.CHARACTERS[i]["id"])
	assert(ids.has("mikeura") and ids.has("vangry"), "Personajes de siempre: %s" % [ids])
	await get_tree().process_frame
	assert(chars.has(hub.panels.selected_survivor()), "Hay uno elegido")
	hub.panels.close()
	print("CHECK 9 PASSED: arena con %d personajes" % chars.size())

	# 10. Cofre (mejoras del menú de siempre) y salir (confirmación)
	hub.player.position = DungeonHub.STATIONS["cofre"]["pos"] + Vector3(-0.9, 0, 0)
	await get_tree().process_frame
	await get_tree().process_frame
	hub.use_station("cofre")
	assert(hub.panels._menu != null and (hub.panels._menu.get("upgrades_panel") as Control).visible, "El cofre abre las mejoras")
	hub.panels.close()
	assert(hub.state == "explore" and not (hub.panels._menu.get("upgrades_panel") as Control).visible, "Y se cierran")
	hub.player.position = DungeonHub.STATIONS["salir"]["pos"] + Vector3(0, 0, -1.0)
	await get_tree().process_frame
	await get_tree().process_frame
	assert(hub.near_station == "salir", "Junto al portón (%s)" % hub.near_station)
	hub.use_station("salir")
	assert(hub.panels.current == "salir" and hub.panels._panel.find_child("Salir", true, false) != null, "Confirmación de salida")
	hub.panels.close()
	print("CHECK 10 PASSED: cofre y portón")
	var esc := InputEventAction.new()
	esc.action = "ui_cancel"
	esc.pressed = true
	assert(hub.state == "explore", "Explorando antes de Esc")
	hub.back_to_title(false)
	assert(hub.state == "leaving" and hub.player.locked, "Esc vuelve a la pantalla de título")
	print("CHECK 10b PASSED: Esc -> pantalla de título")
	hub.queue_free()
	await get_tree().process_frame

	# 11. Segunda vez: directo a explorar, con los portales ya abiertos
	var hub2 := HUB.instantiate() as DungeonHub
	add_child(hub2)
	await get_tree().process_frame
	assert(hub2.state == "explore" and hub2.player.visible, "Ya vista: directo a explorar")
	assert(hub2.portals[0]["open"], "Los portales siguen abiertos en la sesión")
	hub2.queue_free()
	await get_tree().process_frame
	print("CHECK 11 PASSED: segunda visita")

	# 12. La intro completa acaba sola siguiendo al héroe
	DungeonHub.force_intro = true
	var hub3 := HUB.instantiate() as DungeonHub
	add_child(hub3)
	await get_tree().process_frame
	await _wait_intro(hub3, DungeonHub.INTRO_LENGTH + 30.0, true)
	assert(hub3.state == "explore", "La intro termina sola (%.1f s)" % hub3.intro_time)
	print("CHECK 12 PASSED: intro completa en %.1f s" % hub3.intro_time)
	DungeonHub.force_intro = false
	DungeonHub.portals_open = false
	for p in [DungeonHub.config_path, GameData.armory_path]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	GameData.armory_path = "user://armeria.cfg"
	GameData.load_armory()
	print("ALL DUNGEON HUB TESTS PASSED")
	get_tree().quit(0)

func _until(cond: Callable, secs: float) -> void:
	var t0 := Time.get_ticks_msec()
	while not cond.call() and Time.get_ticks_msec() - t0 < secs * 1000.0:
		await get_tree().process_frame

## Avanza la intro a toda velocidad hasta `t` (o hasta que acabe si until_explore).
func _wait_intro(hub: DungeonHub, t: float, until_explore: bool = false) -> void:
	Engine.time_scale = 8.0
	while hub.state == "intro" and hub.intro_time < t:
		await get_tree().process_frame
	if until_explore:
		while hub.state != "explore" and hub.intro_time < t:
			await get_tree().process_frame
	Engine.time_scale = 1.0
