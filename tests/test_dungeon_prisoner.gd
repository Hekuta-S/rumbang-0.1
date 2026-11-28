extends Node

## Historia: prisioneros de la mazmorra (DungeonPrisoner, WorldDefs "prisoner"). Enjaulado en una caverna normal,
## su jaula se abre al limpiarla; liberarlo se guarda y abre una estación del salón (DungeonHub.station_locked).
## Headless:  godot --headless --path . res://tests/test_dungeon_prisoner.tscn

var _fails := 0

func _check(ok: bool, msg: String) -> void:
	print(("PASSED: " if ok else "FAILED: ") + msg)
	if not ok:
		_fails += 1

func _ready() -> void:
	print("--- TEST: PRISIONEROS DE LA MAZMORRA ---")
	SaveManager.save_path = "user://test_save_prisoner.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.save_path))
	SaveManager.load_save()
	GameData.armory_path = "user://test_armeria_prisoner.cfg"

	# 1. Partida nueva: nadie liberado, cofre y NIVEL apagados
	_check(SaveManager.prisoners.is_empty(), "partida nueva: sin prisioneros liberados")
	SaveManager.mago_rescatado = true
	_check(DungeonHub.station_locked("cofre") and DungeonHub.station_locked("nivel"), "cofre y NIVEL apagados")
	_check(DungeonHub.prisoner_world_for("cofre") == "caves" and DungeonHub.prisoner_world_for("nivel") == "sewers", "minero -> cofre, ladrona -> NIVEL")
	_check(DungeonHub.locked_hint("cofre").contains("Minero") and DungeonHub.locked_hint("nivel").contains("Cloacas"), "el aviso dice a quién liberar y dónde")

	# 2. En las Cavernas el minero sale enjaulado en una caverna con enemigos
	GameData.game_mode = "dungeon"
	GameData.world = "caves"
	var scene: Node = load("res://scenes/core/main_dungeon.tscn").instantiate()
	get_tree().root.add_child.call_deferred(scene)
	await get_tree().process_frame
	get_tree().current_scene = scene
	var enc: DungeonEncounter = null
	for i in 600:
		await get_tree().process_frame
		enc = scene.get_node_or_null("DungeonEncounter")
		if enc and enc.map and is_instance_valid(enc.player):
			break
	var player: Node3D = enc.player
	player.set_physics_process(false)
	enc._setup_level_extras()
	var pr := enc.prisoner
	_check(is_instance_valid(pr) and enc.prisoner_room >= 0, "hay prisionero en el nivel 1")
	if not is_instance_valid(pr):
		_finish()
		return
	_check(enc._pending.has(enc.prisoner_room) and enc.map.rooms[enc.prisoner_room]["type"] == "normal", "su caverna es normal y tiene enemigos")
	_check(pr.world == "caves" and pr._model != null, "es el minero, con modelo")
	_check(not pr.is_open, "la jaula empieza cerrada")
	pr.interact()
	_check(not pr.is_freed, "cerrada no se puede liberar")

	# 3. Limpiar la caverna abre la jaula; acercarse y usar (E) lo libera y se guarda
	for d in enc._dice:     # un dado cerca abriría su elección y pausaría el juego
		if is_instance_valid(d):
			d.queue_free()
	enc._room_cleared(enc.prisoner_room)
	_check(pr.is_open, "limpiar su caverna abre la jaula")
	player.global_position = pr.global_position + Vector3(1.2, 0.3, 0)
	for i in 3:
		await get_tree().process_frame
	_check(player.get("interact_target") == pr, "al lado, la tecla de habilidad lo libera")
	var got := [""]
	pr.freed.connect(func(w): got[0] = w)
	pr.interact()
	_check(pr.is_freed and got[0] == "caves", "liberado")
	_check(SaveManager.prisoner_free("caves"), "se guarda")
	SaveManager.load_save()
	SaveManager.mago_rescatado = true
	_check(SaveManager.prisoner_free("caves") and not SaveManager.prisoner_free("sewers"), "sigue en el save tras recargar")
	_check(not DungeonHub.station_locked("cofre") and DungeonHub.station_locked("nivel"), "el cofre se abre; NIVEL sigue apagado")
	_check(pr._speech.visible and pr._speech.text != "", "cuenta su historia")
	get_tree().paused = false
	await get_tree().create_timer(DungeonPrisoner.LINE_TIME * 3.0 + DungeonPrisoner.LEAVE_AFTER + 0.8).timeout
	_check(not is_instance_valid(pr), "se va al salón")

	# 4. Ya liberado no vuelve a salir; sin el mago tampoco sale ninguno
	enc._setup_level_extras()
	_check(enc.prisoner == null, "liberado: no vuelve a salir")
	SaveManager.prisoners.erase("caves")
	SaveManager.mago_rescatado = false
	enc._setup_level_extras()
	_check(enc.prisoner == null, "sin el mago rescatado no hay prisionero")
	SaveManager.mago_rescatado = true
	enc._setup_level_extras()
	_check(is_instance_valid(enc.prisoner), "sin liberar vuelve a salir (otro nivel / otra partida)")

	# 5. Save viejo sin la clave: todos liberados (no se quita lo que ya había)
	var f := FileAccess.open(SaveManager.save_path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"total_gold": 3}))
	f.close()
	SaveManager.load_save()
	_check(SaveManager.prisoner_free("caves") and SaveManager.prisoner_free("sewers"), "save viejo: estaciones abiertas")
	_finish()

func _finish() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.save_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameData.armory_path))
	SaveManager.save_path = SaveManager.SAVE_PATH
	SaveManager.load_save()
	print("ALL PRISONER TESTS PASSED" if _fails == 0 else "PRISONER TESTS FAILED: %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
