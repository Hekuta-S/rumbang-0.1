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
	
	if OS.get_name() in ["Android", "iOS"]:
		if has_node("WorldEnvironment") and $WorldEnvironment.environment:
			var env = $WorldEnvironment.environment
			env.volumetric_fog_enabled = false
			env.sdfgi_enabled = false
			env.ssao_enabled = false
			env.glow_enabled = false # Glow causa crashes en muchos móviles con Vulkan
			# Activamos niebla clásica en lugar de volumétrica para no perder el ambiente
			env.fog_enabled = true
			env.fog_density = 0.015
			
		# [Optimizacion] Reducir la resolucion interna del 3D al 65% para duplicar FPS sin afectar los botones 2D
		get_viewport().scaling_3d_scale = 0.65
			
		if has_node("DirectionalLight3D"):
			$DirectionalLight3D.shadow_enabled = false # Sombras 3D direccionales causan picos enormes en móvil
	else:
		if has_node("WorldEnvironment") and $WorldEnvironment.environment:
			var env = $WorldEnvironment.environment
			env.volumetric_fog_enabled = true
			env.fog_enabled = false
	
	# Instantiate Touch Controls
	var MobileControls = load("res://scripts/ui/mobile_controls.gd")
	if MobileControls:
		add_child(MobileControls.new())

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
					boss.global_position = player.global_position + Vector3(0, 3.0, -10)
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

	# Toma la posición X y Z donde ubicaste al jugador en el editor, y solo ajusta la altura (Y) al nivel del suelo
	var start_x = player.global_position.x
	var start_z = player.global_position.z
	player.global_position = Vector3(start_x, get_floor_y(start_x, start_z) + 3.0, start_z)
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
