extends Node3D

## Main — punto de entrada de la escena de juego.
## Ahora delega toda la orquestación de subsistemas al GameStartFacade.

@onready var hud = $HUD
@onready var player = $Player

var facade: GameStartFacade

func _enter_tree() -> void:
	# Supervivencia se juega con Mikeura aunque la escena se abra directamente o venga de otra seleccion
	# (se hace aqui porque el Player, hijo de esta escena, elige su modelo en su propio _ready)
	if GameData.game_mode == "survival" and not GameData.is_survival_unlocked(String(GameData.get_selected().get("id", ""))):
		GameData.selected_index = GameData.survival_index()

func _ready() -> void:
	# --- APLICACIÓN DEL PATRÓN FACADE ---
	# En lugar de crear y conectar 4+ managers manualmente,
	# delegamos todo a la fachada.
	facade = GameStartFacade.new()
	facade.name = "GameStartFacade"
	add_child(facade)
	facade.initialize(self, hud, player)

	# Main solo escucha las señales que le interesan a través de la fachada
	facade.restart_pressed.connect(restart)
	facade.enemy_died.connect(_on_enemy_died)
	facade.boss_died.connect(_on_boss_died)

	if player.has_signal("player_died"):
		player.connect("player_died", _on_player_died)
	# Resumen de la partida (supervivencia) en las pantallas de victoria y caída
	# (en la mazmorra, RunLog: indicadores de repetición de la fase 5)
	for screen in [hud.victory_screen, hud.game_over_screen]:
		if screen:
			screen.visibility_changed.connect(_fill_run_summary.bind(screen))

	var bench := EnemyBenchmark.from_env()
	if bench != null:
		add_child(bench)

## Reintentar: recarga la escena entera. Reiniciar a mano el jugador dejaba restos de la partida anterior
## (estado de muerte, jefe y enemigos vivos, armas, nivel de mazmorra, efectos, proyectiles...), así que
## se parte siempre de una escena limpia; lo único que sobrevive es lo guardado (oro, personaje elegido).
func restart() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	EnemyRegistry.clear()
	GameState.get_instance().reset_session()
	# Recargar congela un frame largo: la tapa se dibuja antes y la escena nueva la quita al estar lista
	SceneLoader.next_scene_path = scene_file_path
	SceneLoader.hold_cover("Reiniciando...")
	SceneLoader.claim_cover()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().reload_current_scene.call_deferred()

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

## Elección de objeto (la piden ItemPickup y los eventos de RunEvents).
func show_item_choice() -> void:
	facade.ui_manager.show_item_choice()

## Añade (o rellena) el resumen de la partida bajo las estadísticas de la pantalla de fin.
func _fill_run_summary(screen: Control) -> void:
	if not screen.visible:
		return
	var stats := screen.find_child("Stats", true, false) as Label
	if stats == null:
		return
	var vb := stats.get_parent()
	var summary := vb.get_node_or_null("RunSummary") as Label
	if summary == null:
		summary = Label.new()
		summary.name = "RunSummary"
		summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		summary.add_theme_color_override("font_color", RumbangStyle.TEXT)
		summary.add_theme_font_size_override("font_size", 10)
		vb.add_child(summary)
		vb.move_child(summary, stats.get_index() + 1)
	if GameData.game_mode == "dungeon":
		RunLog.finish()
		summary.text = "\n".join(RunLog.summary_lines())
		return
	summary.text = "
".join(RunStats.summary_lines(player.get("weapon_inventory") if is_instance_valid(player) else null))
	# Tras vencer al jefe se puede seguir: modo infinito
	if screen == hud.victory_screen and RunStats.endless_from < 0.0 and vb.get_node_or_null("EndlessBtn") == null:
		var btn := Button.new()
		btn.name = "EndlessBtn"
		btn.text = "♾ MODO INFINITO"
		btn.pressed.connect(_start_endless)
		vb.add_child(btn)
		vb.move_child(btn, summary.get_index() + 1)

## Sigue la partida tras la victoria: la aparición vuelve y cada minuto es más duro.
func _start_endless() -> void:
	RunStats.endless_from = GameState.get_instance().elapsed_time
	hud.victory_screen.visible = false
	var btn: Node = hud.victory_screen.find_child("EndlessBtn", true, false)
	if btn:
		btn.queue_free()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var waves: WaveManager = facade.wave_manager
	waves.continue_endless()
	waves.events.announce("MODO INFINITO", RumbangStyle.NEON_CYAN, "¿Cuánto aguantas?")

## Aplica el multiplicador de oro ("Duende") del jugador.
func _gold_with_bonus(base: int) -> int:
	var sb = player.get("stat_block") if is_instance_valid(player) else null
	if sb == null:
		return base
	return maxi(base, int(round(float(base) * sb.gold_mult())))

func _on_enemy_died(pos: Vector3, gold_val: int, xp: float = 1.0) -> void:
	gold_val = _gold_with_bonus(gold_val)
	GameState.get_instance().add_gold(gold_val)
	facade.update_gold(GameState.get_instance().gold)
	SaveManager.add_gold(gold_val)
	facade.spawn_xp_orb(pos, xp)
	MapPickup.roll_kill_drop(self, pos)

func _on_boss_died(pos: Vector3, gold_val: int) -> void:
	gold_val = _gold_with_bonus(gold_val)
	GameState.get_instance().add_gold(gold_val)
	facade.update_gold(GameState.get_instance().gold)
	SaveManager.add_gold(gold_val)
	_save_best_time()
	if RunStats.endless_from >= 0.0:
		return                        # en el modo infinito un jefe más no termina la partida
	if GameData.game_mode != "dungeon":
		MetaProgress.record("survival_boss_kills")
		RunModifiers.record_clear()
		_record_survival_run()
	# Derrotar al Nigromante (7:10) termina la partida con victoria
	AudioManager.play("victory")
	facade.show_victory()

## SaveManager.best_floors guarda ahora el mejor tiempo sobrevivido (segundos) por personaje.
func _save_best_time() -> void:
	SaveManager.set_best_floor(_char_id(), int(GameState.get_instance().elapsed_time))

func _char_id() -> String:
	var char_data: Dictionary = GameData.get_selected()
	return str(char_data.get("id", "unknown"))

## Cuenta la partida de supervivencia y el nivel alcanzado (desbloqueo de armas, ver MetaProgress).
func _record_survival_run() -> void:
	var xp: Node = player.get("experience_comp") if is_instance_valid(player) else null
	MetaProgress.record_survival_run(int(xp.level) if xp else 1)

func _on_player_died() -> void:
	if GameData.game_mode == "dungeon":
		RunLog.finish()   # fase 5: guarda la partida en el historial
	else:
		_record_survival_run()
	_save_best_time()
	if RunStats.endless_from >= 0.0:
		MetaProgress.record_max("best_endless_s", int(GameState.get_instance().elapsed_time - RunStats.endless_from))
