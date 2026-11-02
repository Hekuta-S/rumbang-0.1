extends Node
## Capturas de las pantallas principales de la interfaz (para revisar el diseño). Necesita ventana (no headless).
## Uso: godot --path . res://tests/ui/ui_snapshots.tscn -- --out=<carpeta>
var out := "user://ui_snapshots/"
func _shot(name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + name + ".png")
	print("SNAP ", name)
func _show(path: String) -> Node:
	@warning_ignore("redundant_await")
	var n: Node = (load(path) as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(n)
	await get_tree().process_frame
	get_tree().current_scene = n
	return n
func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	var n: Node = await _show("res://scenes/ui/main_menu.tscn")
	await get_tree().create_timer(7.0).timeout
	await _shot("01_main_menu")
	n.queue_free()
	n = await _show("res://scenes/ui/character_select.tscn")
	await _shot("02_character_select")
	n.queue_free()
	n = await _show("res://scenes/ui/lobby_menu.tscn")
	await _shot("03_lobby")
	n.queue_free()
	var sm = load("res://scripts/ui/settings_menu.gd").new()
	get_tree().root.add_child(sm)
	await _shot("04_settings")
	sm.queue_free()
	# Partida de mazmorra: HUD
	GameData.game_mode = "dungeon"
	GameData.selected_index = 0
	var scene: Node = load("res://scenes/core/main_dungeon.tscn").instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	await get_tree().create_timer(4.0).timeout
	var p = scene.get_node("Player")
	p.take_damage(9.0)
	await _shot("05_hud")
	var pm = scene.find_children("*", "", true, false).filter(func(x): return x.get_script() != null and str(x.get_script().resource_path).ends_with("pause_menu.gd"))
	if not pm.is_empty():
		pm[0].open_menu()
		await _shot("06_pause")
		pm[0].close_menu()
	var ui := WeaponChoiceUI.present(scene, [WeaponData.WeaponType.SPORE_BAZOOKA, WeaponData.WeaponType.DUSTS], 1)
	await _shot("07_weapon_choice")
	ui.queue_free()
	get_tree().paused = false
	scene.get("facade").ui_manager.show_game_over()
	await _shot("08_game_over")
	get_tree().quit()
