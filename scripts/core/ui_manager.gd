extends Node
class_name UIManager

var hud: Node
var player: Node3D

var bg_music: AudioStreamPlayer
var level_up_sfx: AudioStreamPlayer

signal restart_pressed

func initialize(p_hud: Node, p_player: Node3D) -> void:
	hud = p_hud
	player = p_player
	
	bg_music = AudioStreamPlayer.new()
	bg_music.stream = load("res://assets/audio/main-soundtrack.mp3")
	bg_music.volume_db = -6.0
	bg_music.autoplay = true
	add_child(bg_music)

	level_up_sfx = AudioStreamPlayer.new()
	level_up_sfx.stream = load("res://assets/sfx/level-up.mp3")
	level_up_sfx.volume_db = 0.0
	add_child(level_up_sfx)
	
	player.stats_changed.connect(_on_player_stats_changed)
	player.player_died.connect(_on_player_died)
	if player.has_signal("weapon_attacked"):
		player.weapon_attacked.connect(_on_player_weapon_attacked)
	if player.has_signal("weapon_changed"):
		player.weapon_changed.connect(_on_player_weapon_changed)
	if player.has_signal("reload_state_changed"):
		player.reload_state_changed.connect(_on_player_reload_changed)
	if player.has_signal("experience_gained"):
		player.experience_gained.connect(_on_player_experience_gained)
	if player.has_signal("leveled_up"):
		player.leveled_up.connect(_on_player_leveled_up)
		
	hud.restart_pressed.connect(func(): restart_pressed.emit())
	
	var pause_menu = preload("res://scenes/ui/pause_menu.tscn").instantiate()
	add_child(pause_menu)

func update_floor(sub_level: int) -> void:
	hud.update_floor(sub_level)

func update_gold(gold: int) -> void:
	hud.update_gold(gold)

func reset_screens() -> void:
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

func _on_player_stats_changed(hp, max_hp, shield, max_shield, energy, max_energy) -> void:
	hud.update_stats(hp, max_hp, shield, max_shield, energy, max_energy)

func _on_player_experience_gained(amount, current_xp, required_xp) -> void:
	var stats = player.get_node_or_null("StatsComponent")
	var lvl = 1
	if stats:
		lvl = stats.level
	hud.update_xp(lvl, current_xp, required_xp)

func _on_player_leveled_up(new_level) -> void:
	print("Player leveled up to ", new_level)
	if level_up_sfx:
		level_up_sfx.play()
	if bg_music:
		bg_music.volume_db = -24.0
	if not has_node("UpgradeChoiceUI"):
		var ui_scene = preload("res://scenes/ui/upgrade_choice_ui.tscn")
		var ui = ui_scene.instantiate()
		add_child(ui)
		ui.choice_made.connect(_on_upgrade_choice_made)
	$UpgradeChoiceUI.present_choices(player)

func _on_upgrade_choice_made(choice_type: String, choice_id: String) -> void:
	if bg_music:
		bg_music.volume_db = -12.0
	print("El jugador eligio: ", choice_type, " - ", choice_id)
	var w_id = choice_id.to_int()
	if choice_type == "new_weapon":
		player.add_weapon(w_id)
	elif choice_type == "upgrade":
		player.upgrade_weapon(w_id)

func _on_player_died() -> void:
	show_game_over()

func _on_player_weapon_attacked(weapon_type: int) -> void:
	if hud and hud.has_method("trigger_crosshair_kickback"):
		hud.trigger_crosshair_kickback(weapon_type)

func _on_player_weapon_changed(_weapon_index: int, _weapon_name: String, _energy_cost: float) -> void:
	refresh_weapon_ui()

func _on_player_reload_changed(weapon_type: int, ammo: int, max_ammo: int, is_reloading: bool, progress: float) -> void:
	if hud:
		hud.update_reload(weapon_type, ammo, max_ammo, is_reloading, progress)

func refresh_weapon_ui() -> void:
	if hud and player:
		hud.update_weapons(player.current_slot, player.get_weapons_list())
