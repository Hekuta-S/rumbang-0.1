extends Node3D

## Main — punto de entrada de la escena de juego.
## Ahora delega toda la orquestación de subsistemas al GameStartFacade.

@onready var hud = $HUD
@onready var player = $Player

var facade: GameStartFacade

func _ready() -> void:
	# --- APLICACIÓN DEL PATRÓN FACADE ---
	# En lugar de crear y conectar 4+ managers manualmente,
	# delegamos todo a la fachada.
	facade = GameStartFacade.new()
	facade.name = "GameStartFacade"
	add_child(facade)
	facade.initialize(self, hud, player)

	# Main solo escucha las señales que le interesan a través de la fachada
	facade.restart_pressed.connect(facade.start_game)
	facade.enemy_died.connect(_on_enemy_died)
	facade.boss_died.connect(_on_boss_died)
	facade.wave_cleared.connect(_on_wave_cleared)

	if player.has_signal("player_died"):
		player.connect("player_died", _on_player_died)

func _process(delta: float) -> void:
	if not get_tree().paused:
		GameState.get_instance().add_time(delta)
		facade.update_elapsed_time(GameState.get_instance().elapsed_time)

func get_floor_y(x: float, z: float) -> float:
	return facade.get_floor_y(x, z)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_Y:
			facade.spawn_debug_orbs()
		elif event.keycode == KEY_O:
			# --- APLICACIÓN DEL PATRÓN FACTORY METHOD ---
			var boss = EnemyFactory.create_enemy("necromancer")
			if boss:
				add_child(boss)
				if is_instance_valid(player):
					boss.global_position = player.global_position + Vector3(0, 3.0, -10)
				if boss.has_signal("boss_died"):
					boss.boss_died.connect(_on_boss_died)

func _on_enemy_died(pos: Vector3, gold_val: int) -> void:
	GameState.get_instance().add_gold(gold_val)
	facade.update_gold(GameState.get_instance().gold)
	SaveManager.add_gold(gold_val)
	facade.spawn_xp_orb(pos)

func _on_wave_cleared() -> void:
	GameState.get_instance().advance_level()
	facade.update_floor(GameState.get_instance().sub_level)
	SaveManager.set_best_floor(_char_id(), GameState.get_instance().sub_level)
	facade.start_next_wave(GameState.get_instance().sub_level)

func _on_boss_died(pos: Vector3, gold_val: int) -> void:
	GameState.get_instance().add_gold(gold_val)
	facade.update_gold(GameState.get_instance().gold)
	SaveManager.add_gold(gold_val)
	SaveManager.set_best_floor(_char_id(), GameState.get_instance().sub_level)

	if GameState.get_instance().sub_level >= 9:
		AudioManager.play("victory")
		facade.show_victory()
	else:
		AudioManager.play("coin")
		GameState.get_instance().advance_level()
		facade.update_floor(GameState.get_instance().sub_level)
		facade.start_next_wave(GameState.get_instance().sub_level)

func _char_id() -> String:
	var char_data: Dictionary = GameData.get_selected()
	return str(char_data.get("id", "unknown"))

func _on_player_died() -> void:
	SaveManager.set_best_floor(_char_id(), GameState.get_instance().sub_level)
