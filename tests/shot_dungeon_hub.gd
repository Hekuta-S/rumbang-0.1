extends Node

## Capturas del Salón de la Invocación (necesita ventana, no headless):
##   res://tests/shot_dungeon_hub.tscn -- <prefijo> [intro]
## Sin "intro": entra directo a explorar y captura <prefijo>_explorar, el yunque (panel y armero),
## los portales del mago, la puerta de la arena con su panel, el cofre y el portón.
## Con "intro": además reproduce la cinemática y guarda <prefijo>_<segundo>.png en los momentos clave.

const HUB := preload("res://scenes/ui/dungeon_hub.tscn")
const MOMENTS := [0.8, 6.5, 9.75, 12.6, 19.5]

var _prefix := "user://hub"

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_prefix = args[0]
	_run.call_deferred()

func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "%s_%s.png" % [_prefix, tag]
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT ", ProjectSettings.globalize_path(path))

func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _go(hub: DungeonHub, p: Vector3) -> void:
	hub.player.move_to(p)
	var t0 := Time.get_ticks_msec()
	while hub.player.move_target != null and Time.get_ticks_msec() - t0 < 8000:
		await get_tree().process_frame
	await _wait(0.8)

func _run() -> void:
	DungeonHub.config_path = "user://shot_dungeon_hub.cfg"
	GameData.armory_path = "user://shot_armeria.cfg"
	DungeonHub.portals_open = false
	var with_intro := OS.get_cmdline_user_args().has("intro")
	DungeonHub.force_intro = with_intro
	DungeonHub.set_intro_seen(not with_intro)
	var hub := HUB.instantiate() as DungeonHub
	add_child(hub)
	if with_intro:
		for t in MOMENTS:
			while hub.intro_time < t:
				await get_tree().process_frame
			await _shot("%04.1f" % t)
		while hub.state != "explore":
			await get_tree().process_frame
	await _wait(1.6)
	await _shot("explorar")
	# yunque
	await _go(hub, DungeonHub.STATIONS["yunque"]["pos"] + Vector3(-1.0, 0, 0.2))
	await _shot("yunque_aviso")
	hub.use_station("yunque")
	await _wait(1.2)
	hub.panels.equip(WeaponData.WeaponType.DAGGERS)
	await _wait(0.3)
	await _shot("yunque")
	hub.panels.close()
	# mago y portales
	await _go(hub, DungeonHub.MAGE_POS + Vector3(1.2, 0, 0.4))
	hub.use_station("mago")
	await _wait(2.8)
	await _shot("portales")
	await _go(hub, Vector3(-2.6, DungeonHub.FLOOR_Y, 1.2))
	hub.player.face(DungeonHub.PORTAL_SPOTS[1])
	await _wait(0.6)
	await _shot("portal_cerca")
	# arena (pasando por el centro: ir con clic no esquiva la fragua)
	await _go(hub, Vector3(2.5, DungeonHub.FLOOR_Y, -4.6))
	await _go(hub, DungeonHub.STATIONS["arena"]["pos"] + Vector3(-1.0, 0, 0))
	await _shot("arena_aviso")
	hub.use_station("arena")
	await _wait(2.0)
	await _shot("arena")
	hub.panels.close()
	# cofre y portón
	await _go(hub, DungeonHub.STATIONS["cofre"]["pos"] + Vector3(-1.0, 0, -0.2))
	await _shot("cofre_aviso")
	await _go(hub, DungeonHub.STATIONS["salir"]["pos"] + Vector3(0, 0, -1.2))
	await _shot("porton")
	DungeonHub.portals_open = false
	print("CHECK shot_dungeon_hub PASSED")
	get_tree().quit(0)
