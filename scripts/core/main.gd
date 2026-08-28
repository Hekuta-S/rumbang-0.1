extends Node3D

@onready var hud = $HUD
@onready var player = $Player

var sub_level: int = 1
var gold: int = 0

func _ready() -> void:
	var ui_manager = UIManager.new()
	ui_manager.name = "UIManager"
	add_child(ui_manager)
	ui_manager.initialize(hud, player)
	ui_manager.restart_pressed.connect(start_game)
	player.player_died.connect(_on_player_died)

	var env_manager = EnvironmentManager.new()
	env_manager.name = "EnvironmentManager"
	add_child(env_manager)
	env_manager.generation_finished.connect(start_game)
	env_manager.generate_environment()

	var wave_manager = WaveManager.new()
	wave_manager.name = "WaveManager"
	add_child(wave_manager)
	wave_manager.enemy_died.connect(_on_enemy_died)
	wave_manager.boss_died.connect(_on_boss_died)
	wave_manager.wave_cleared.connect(_on_wave_cleared)

	var loot_manager = LootManager.new()
	loot_manager.name = "LootManager"
	add_child(loot_manager)
	loot_manager.initialize(player)

func get_floor_y(x: float, z: float) -> float:
	if has_node("EnvironmentManager"):
		return $EnvironmentManager.get_floor_y(x, z)
	return 0.0

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_Y:
			$LootManager.spawn_debug_orbs()
		elif event.keycode == KEY_O:
			var necro_scene = load("res://scenes/entities/necromancer_boss.tscn")
			if necro_scene:
				var boss = necro_scene.instantiate()
				add_child(boss)
				if is_instance_valid(player):
					boss.global_position = player.global_position + Vector3(0, 0, -10)
				if boss.has_signal("boss_died"):
					boss.boss_died.connect(_on_boss_died)



func start_game() -> void:
	sub_level = 1
	gold = 0
	$UIManager.update_floor(sub_level)
	$UIManager.update_gold(gold)
	$UIManager.reset_screens()
	
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Apply selected character stats and passive BEFORE resetting hp/shield/energy
	GameData.apply_to_player(player)

	player.global_position = Vector3(0, get_floor_y(0, 10), 10)
	player.hp     = player.max_hp
	player.shield = player.max_shield
	player.energy = player.max_energy
	player.emit_signal("stats_changed", player.hp, player.max_hp, player.shield, player.max_shield, player.energy, player.max_energy)

	$UIManager.refresh_weapon_ui()	
	$WaveManager.start_wave(sub_level, player)
	$LootManager.spawn_weapon_pickup()
	$LootManager.spawn_item_pickup()

func _on_enemy_died(pos: Vector3, gold_val: int) -> void:
	gold += gold_val
	$UIManager.update_gold(gold)
	SaveManager.add_gold(gold_val)
	
	$LootManager.spawn_xp_orb(pos)

func _on_wave_cleared() -> void:
	sub_level += 1
	$UIManager.update_floor(sub_level)
	SaveManager.set_best_floor(_char_id(), sub_level)
	$WaveManager.start_wave(sub_level, player)
	$LootManager.spawn_weapon_pickup()
	$LootManager.spawn_item_pickup()

func _on_boss_died(pos: Vector3, gold_val: int) -> void:
	gold += gold_val
	$UIManager.update_gold(gold)
	SaveManager.add_gold(gold_val)
	SaveManager.set_best_floor(_char_id(), sub_level)

	if sub_level >= 9:
		AudioManager.play("victory")
		$UIManager.show_victory()
	else:
		AudioManager.play("coin")
		sub_level += 1
		$UIManager.update_floor(sub_level)
		$WaveManager.start_wave(sub_level, player)
		$LootManager.spawn_weapon_pickup()
		$LootManager.spawn_item_pickup()

func _char_id() -> String:
	var char_data: Dictionary = GameData.get_selected()
	return str(char_data.get("id", "unknown"))

func _on_player_died() -> void:
	SaveManager.set_best_floor(_char_id(), sub_level)
