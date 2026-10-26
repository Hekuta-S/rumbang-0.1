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

	if player.has_signal("player_died"):
		player.connect("player_died", _on_player_died)

	var bench := EnemyBenchmark.from_env()
	if bench != null:
		add_child(bench)

func _process(delta: float) -> void:
	if not get_tree().paused:
		GameState.get_instance().add_time(delta)
		facade.update_elapsed_time(GameState.get_instance().elapsed_time)

func get_floor_y(x: float, z: float) -> float:
	return facade.get_floor_y(x, z)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F9:
			var existing := get_node_or_null("EnemyBenchmark")
			if existing != null:
				existing.queue_free()
			else:
				var b := EnemyBenchmark.new()
				b.name = "EnemyBenchmark"
				add_child(b)
		elif event.keycode == KEY_Y:
			facade.spawn_debug_orbs()
		elif event.keycode == KEY_O:
			# --- APLICACIÓN DEL PATRÓN FACTORY METHOD ---
			var boss = NecromancerBossCreator.new().create_enemy()
			if boss:
				add_child(boss)
				if is_instance_valid(player):
					boss.global_position = player.global_position + Vector3(0, 3.0, -10)
				if boss.has_signal("boss_died"):
					boss.boss_died.connect(_on_boss_died)

## Aplica el multiplicador de oro ("Duende") del jugador.
func _gold_with_bonus(base: int) -> int:
	var sb = player.get("stat_block") if is_instance_valid(player) else null
	if sb == null:
		return base
	return maxi(base, int(round(float(base) * sb.gold_mult())))

func _on_enemy_died(pos: Vector3, gold_val: int) -> void:
	gold_val = _gold_with_bonus(gold_val)
	GameState.get_instance().add_gold(gold_val)
	facade.update_gold(GameState.get_instance().gold)
	SaveManager.add_gold(gold_val)
	facade.spawn_xp_orb(pos)

func _on_boss_died(pos: Vector3, gold_val: int) -> void:
	gold_val = _gold_with_bonus(gold_val)
	GameState.get_instance().add_gold(gold_val)
	facade.update_gold(GameState.get_instance().gold)
	SaveManager.add_gold(gold_val)
	_save_best_time()
	# Derrotar al Nigromante (7:10) termina la partida con victoria
	AudioManager.play("victory")
	facade.show_victory()

## SaveManager.best_floors guarda ahora el mejor tiempo sobrevivido (segundos) por personaje.
func _save_best_time() -> void:
	SaveManager.set_best_floor(_char_id(), int(GameState.get_instance().elapsed_time))

func _char_id() -> String:
	var char_data: Dictionary = GameData.get_selected()
	return str(char_data.get("id", "unknown"))

func _on_player_died() -> void:
	_save_best_time()
