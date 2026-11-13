extends Node
class_name UIManager

var hud: Node
var player: Node3D

var bg_music: AudioStreamPlayer
var level_up_sfx: AudioStreamPlayer

signal restart_pressed

const DUNGEON_THEME := "res://assets/audio/dungeon_theme.wav"

func start_music() -> void:
	MusicDirector.stop()
	if bg_music and not bg_music.playing:
		bg_music.play()

func initialize(p_hud: Node, p_player: Node3D) -> void:
	hud = p_hud
	player = p_player
	
	bg_music = AudioStreamPlayer.new()
	if GameData.game_mode == "dungeon" and ResourceLoader.exists(DUNGEON_THEME):
		# Mazmorra: tema darksynth sintetizado (tools/generate_soundtrack.gd), en bucle desde la importación
		bg_music.stream = load(DUNGEON_THEME)
		bg_music.volume_db = -8.0
	else:
		bg_music.stream = load("res://assets/audio/main-soundtrack.mp3")
		bg_music.volume_db = -6.0
	bg_music.bus = "Music"   # lo regula el volumen de música de los ajustes
	add_child(bg_music)   # se reproduce con start_music() cuando el mundo está listo

	level_up_sfx = AudioStreamPlayer.new()
	level_up_sfx.stream = load("res://assets/sfx/level-up.mp3")
	level_up_sfx.volume_db = 0.0
	add_child(level_up_sfx)
	
	if player.has_signal("stats_changed"):
		player.connect("stats_changed", _on_player_stats_changed)
	if player.has_signal("player_died"):
		player.connect("player_died", _on_player_died)
	if player.has_signal("weapon_attacked"):
		player.connect("weapon_attacked", _on_player_weapon_attacked)
	if player.has_signal("weapon_changed"):
		player.connect("weapon_changed", _on_player_weapon_changed)
	if player.has_signal("reload_state_changed"):
		player.connect("reload_state_changed", _on_player_reload_changed)
	if player.has_signal("experience_gained"):
		player.connect("experience_gained", _on_player_experience_gained)
	if player.has_signal("leveled_up"):
		player.connect("leveled_up", _on_player_leveled_up)
		
	hud.restart_pressed.connect(func(): restart_pressed.emit())
	
	var pause_menu = preload("res://scenes/ui/pause_menu.tscn").instantiate()
	pause_menu.name = "PauseMenu"
	add_child(pause_menu)
	pause_menu.restart_requested.connect(func(): restart_pressed.emit())
	refresh_weapon_ui()

func update_elapsed_time(elapsed_seconds: float) -> void:
	if hud and hud.has_method("update_elapsed_time"):
		hud.update_elapsed_time(elapsed_seconds)

func update_gold(gold: int) -> void:
	hud.update_gold(gold)

func reset_screens() -> void:
	_pending_level_ups = 0
	hud.game_over_screen.visible = false
	hud.victory_screen.visible = false

func show_victory() -> void:
	hud.show_victory()

func show_game_over() -> void:
	hud.show_game_over()

func show_item_choice() -> void:
	if not has_node("ItemChoiceUI"):
		var ui_scene = preload("res://scenes/ui/item_choice_ui.tscn")
		var ui = ui_scene.instantiate()
		add_child(ui)
		ui.item_selected.connect(_on_item_selected)
	$ItemChoiceUI.present_choices()

func _on_item_selected(item_id: String) -> void:
	player.inventory.add_item(item_id)

func _on_player_stats_changed(hp, max_hp) -> void:
	hud.update_stats(hp, max_hp)

func _on_player_experience_gained(amount, current_xp, required_xp) -> void:
	var exp_comp = player.get_node_or_null("ExperienceComponent")
	var lvl = 1
	if exp_comp:
		lvl = exp_comp.level
	else:
		var stats = player.get_node_or_null("StatsComponent")
		if stats:
			lvl = stats.level
	hud.update_xp(lvl, current_xp, required_xp)

## Subidas de nivel que llegaron con el menú de cartas ya abierto (varias gemas de golpe):
## cada una reparte su propia mano al elegir la anterior.
var _pending_level_ups: int = 0

func _on_player_leveled_up(new_level) -> void:
	var existing := get_node_or_null("UpgradeChoiceUI")
	if existing and existing.visible:
		_pending_level_ups += 1
		return
	if level_up_sfx:
		var xpc = player.get("experience_comp") if player else null
		level_up_sfx.pitch_scale = 1.0 + minf(float(xpc.level if xpc else 1), 40.0) * 0.012   # sube de tono con el nivel
		level_up_sfx.play()
	if bg_music:
		bg_music.volume_db = -24.0
	# Destello dorado y onda de luz bajo el jugador
	UiJuice.flash(self, Color(1.0, 0.85, 0.35), 0.4, 0.5)
	if is_instance_valid(player) and player.is_inside_tree():
		NecroVFX.shockwave(player.get_parent(), player.global_position + Vector3(0, 0.1, 0), 3.5, Color(1.0, 0.8, 0.3))
	if not has_node("UpgradeChoiceUI"):
		var ui_scene = preload("res://scenes/ui/upgrade_choice_ui.tscn")
		var ui = ui_scene.instantiate()
		add_child(ui)
		ui.choice_made.connect(_on_upgrade_choice_made)
	$UpgradeChoiceUI.present_choices(player)
	if hud and hud.has_method("play_level_up_confetti"):
		hud.play_level_up_confetti()

func _on_upgrade_choice_made(choice_type: String, choice_id: String) -> void:
	if bg_music and _pending_level_ups == 0:
		bg_music.volume_db = -12.0
	print("El jugador eligio: ", choice_type, " - ", choice_id)
	var w_id = choice_id.to_int()
	if choice_type == "new_weapon":
		player.add_weapon(w_id)
	elif choice_type == "weapon_stat":
		# id = "arma:mejora"
		var parts := choice_id.split(":")
		if parts.size() == 2:
			player.weapon_inventory.upgrade_weapon_stat(parts[0].to_int(), parts[1])
	elif choice_type == "upgrade":
		player.upgrade_weapon(w_id)
	elif choice_type == "tome":
		# id = "tomo:rareza"
		var tp := choice_id.split(":")
		if tp.size() == 2 and player and player.get("stat_block"):
			player.stat_block.add_tome(tp[0], tp[1].to_int())
	elif choice_type == "evolution":
		WeaponSynergies.evolve(player.weapon_inventory, w_id)
		MetaProgress.discover_evolution(w_id)
		_screen_flash(Color(1.0, 0.85, 0.3, 0.6))
		AudioManager.play("kill_burst", -2.0, 0.7)
		if hud and hud.has_method("play_level_up_confetti"):
			hud.play_level_up_confetti()
	# Nivel(es) acumulado(s) mientras elegías: siguiente mano
	if _pending_level_ups > 0:
		_pending_level_ups -= 1
		_on_player_leveled_up.call_deferred(0)

## Destello de pantalla (evolución de arma): se desvanece solo, también con el juego en pausa.
func _screen_flash(col: Color) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 90
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	var rect := ColorRect.new()
	rect.color = col
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(rect)
	add_child(layer)
	var tw := rect.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(rect, "color:a", 0.0, 0.6)
	tw.tween_callback(layer.queue_free)

func _on_player_died() -> void:
	show_game_over()

func _on_player_weapon_attacked(weapon_type: int) -> void:
	if hud and hud.has_method("trigger_crosshair_kickback"):
		hud.trigger_crosshair_kickback(weapon_type)

func _on_player_weapon_changed(_weapon_index: int, _weapon_name: String) -> void:
	refresh_weapon_ui()

func _on_player_reload_changed(weapon_type: int, ammo: int, max_ammo: int, is_reloading: bool, progress: float) -> void:
	if hud:
		hud.update_reload(weapon_type, ammo, max_ammo, is_reloading, progress)

func refresh_weapon_ui() -> void:
	if hud and player:
		hud.update_weapons(player.current_slot, player.get_weapons_list())
