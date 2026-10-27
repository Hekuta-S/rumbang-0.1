extends Node
class_name GameStartFacade

## --- APLICACIÓN DEL PATRÓN FACADE ---
## Encapsula toda la lógica de inicio de partida: creación de managers,
## conexión de señales y la secuencia de arranque. Main solo habla con
## esta fachada en lugar de orquestar 4+ subsistemas directamente.

signal restart_pressed
signal enemy_died(pos: Vector3, gold_val: int)
signal boss_died(pos: Vector3, gold_val: int)

var ui_manager: UIManager
var environment_manager: EnvironmentManager
var wave_manager: WaveManager
var loot_manager: LootManager

var _player: Node3D
var _hud: Node
var _scene_root: Node3D
var _cover: CanvasLayer

# ─────────────────────────────────────────────────────────
#  Interfaz pública (lo único que Main necesita conocer)
# ─────────────────────────────────────────────────────────

## Inicializa todos los subsistemas del juego.
## Llama a esto desde Main._ready() pasando la raíz de la escena, el HUD y el Player.
func initialize(scene_root: Node3D, hud: Node, player: Node3D) -> void:
	_scene_root = scene_root
	_player = player
	_hud = hud

	_setup_cover()
	_setup_ui_manager()
	_setup_platform(scene_root)
	_setup_environment_manager()
	_setup_wave_manager()
	_setup_loot_manager()
	_setup_performance_governor()

## Inicia (o reinicia) una partida.
## Resetea estado, UI, jugador, oleadas y loot.
func start_game() -> void:
	_reset_game_state()
	_reset_ui()
	_apply_character_data()
	_reset_player_position_and_stats()
	ui_manager.refresh_weapon_ui()
	_prewarm_effects()
	# Modo mazmorra: por ahora solo exploración (los enemigos por sala llegan después)
	if GameData.game_mode != "dungeon":
		wave_manager.start_run(_player)
		loot_manager.spawn_weapon_pickup()
		loot_manager.spawn_item_pickup()
	_reveal_world()

## Tapa negra mientras se genera el mundo: evita ver la escena vacía y que la
## música/el jugador aparezcan antes que el entorno.
func _setup_cover() -> void:
	_cover = CanvasLayer.new()
	_cover.layer = 100
	var rect := ColorRect.new()
	rect.color = Color.BLACK
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cover.add_child(rect)
	var lbl := Label.new()
	lbl.text = "Generando mundo..."
	lbl.set_anchors_preset(Control.PRESET_CENTER)
	lbl.grow_horizontal = Control.GROW_DIRECTION_BOTH
	lbl.add_theme_font_size_override("font_size", 20)
	_cover.add_child(lbl)
	add_child(_cover)

## Quita la tapa, arranca la música y materializa al jugador ya sobre el piso.
func _reveal_world() -> void:
	ui_manager.start_music()
	if is_instance_valid(_player) and _player.has_method("hide_for_spawn"):
		_player.hide_for_spawn()
	# Un par de frames para que el mapa y las colisiones queden dibujados
	await _scene_root.get_tree().process_frame
	await _scene_root.get_tree().process_frame
	if is_instance_valid(_player) and _player.has_method("play_spawn_scan"):
		_player.play_spawn_scan()
	if is_instance_valid(_cover):
		var c := _cover
		_cover = null
		var tw := create_tween()
		tw.tween_property(c.get_child(0), "color:a", 0.0, 0.5)
		tw.parallel().tween_property(c.get_child(1), "modulate:a", 0.0, 0.3)
		tw.tween_callback(c.queue_free)

## Calienta shaders pesados de efectos para evitar tirones de compilación en el primer disparo.
func _prewarm_effects() -> void:
	var spore_vfx = preload("res://scripts/objects/spore_vfx.gd")
	spore_vfx.prewarm(_scene_root, preload("res://assets/shaders/spore_fbm_cloud.gdshader"))
	var dust_vfx = preload("res://scripts/objects/dust_vfx.gd")
	dust_vfx.prewarm(_scene_root, preload("res://assets/shaders/alchemical_clouds.gdshader"))
	Prewarm.run(_scene_root)

## Acceso al floor Y a través del EnvironmentManager.
func get_floor_y(x: float, z: float) -> float:
	if environment_manager:
		return environment_manager.get_floor_y(x, z)
	return 0.0

## Spawn de orbes de debug a través del LootManager.
func spawn_debug_orbs() -> void:
	loot_manager.spawn_debug_orbs()

## Spawn de XP al morir un enemigo.
func spawn_xp_orb(pos: Vector3) -> void:
	loot_manager.spawn_xp_orb(pos)

## Muestra pantalla de victoria.
func show_victory() -> void:
	ui_manager.show_victory()

## Actualiza la UI de oro.
func update_gold(gold: int) -> void:
	ui_manager.update_gold(gold)

## Actualiza el tiempo transcurrido en la UI.
func update_elapsed_time(elapsed: float) -> void:
	ui_manager.update_elapsed_time(elapsed)

# ─────────────────────────────────────────────────────────
#  Detalles internos (ocultos para Main)
# ─────────────────────────────────────────────────────────

func _setup_ui_manager() -> void:
	ui_manager = UIManager.new()
	ui_manager.name = "UIManager"
	_scene_root.add_child(ui_manager)
	ui_manager.initialize(_hud, _player)
	ui_manager.restart_pressed.connect(func(): restart_pressed.emit())

func _setup_platform(scene_root: Node3D) -> void:
	var platform_factory: PlatformFactory = PlatformFactory.get_factory()

	# Con mapa procedural, la escena define su propia niebla/ambiente: se respetan.
	var has_procedural_map := scene_root.has_node("ProceduralMap")
	if scene_root.has_node("WorldEnvironment") and scene_root.get_node("WorldEnvironment").environment:
		var env: Environment = scene_root.get_node("WorldEnvironment").environment
		var fog_was_on := env.fog_enabled
		platform_factory.configure_environment(env)
		if has_procedural_map:
			env.fog_enabled = fog_was_on

	platform_factory.configure_viewport(scene_root.get_viewport())

	if scene_root.has_node("DirectionalLight3D"):
		platform_factory.configure_light(scene_root.get_node("DirectionalLight3D"))

	var touch_controls = platform_factory.create_controls()
	if touch_controls:
		scene_root.add_child(touch_controls)

	if not has_procedural_map:
		platform_factory.create_map(scene_root)

func _setup_environment_manager() -> void:
	environment_manager = EnvironmentManager.new()
	environment_manager.name = "EnvironmentManager"
	_scene_root.add_child(environment_manager)
	environment_manager.generation_finished.connect(start_game)
	environment_manager.generate_environment()

func _setup_wave_manager() -> void:
	wave_manager = WaveManager.new()
	wave_manager.name = "WaveManager"
	_scene_root.add_child(wave_manager)
	wave_manager.enemy_died.connect(func(pos, gold_val): enemy_died.emit(pos, gold_val))
	wave_manager.boss_died.connect(func(pos, gold_val): boss_died.emit(pos, gold_val))

func _setup_performance_governor() -> void:
	var governor := PerformanceGovernor.new()
	governor.name = "PerformanceGovernor"
	add_child(governor)
	governor.setup(_scene_root.get_viewport())

func _setup_loot_manager() -> void:
	loot_manager = LootManager.new()
	loot_manager.name = "LootManager"
	_scene_root.add_child(loot_manager)
	loot_manager.initialize(_player)

func _reset_game_state() -> void:
	GameState.get_instance().reset_session()

func _reset_ui() -> void:
	var state = GameState.get_instance()
	ui_manager.update_elapsed_time(state.elapsed_time)
	ui_manager.update_gold(state.gold)
	ui_manager.reset_screens()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _apply_character_data() -> void:
	# Nueva partida: los objetos de la anterior no deben persistir
	var inv = _player.get("inventory")
	if inv and inv.has_method("clear_items"):
		inv.clear_items()
	var winv = _player.get("weapon_inventory")
	if winv and winv.has_method("reset_progress"):
		winv.reset_progress()
	GameData.apply_to_player(_player)

func _reset_player_position_and_stats() -> void:
	var start_x = 0.0
	var start_z = 0.0
	_player.global_position = Vector3(start_x, get_floor_y(start_x, start_z) + 0.3, start_z)
	_player.reset_physics_interpolation()
	if _player is CharacterBody3D:
		_player.velocity = Vector3.ZERO
	_player.hp     = _player.max_hp
	_player.shield = _player.max_shield
	_player.emit_signal("stats_changed", _player.hp, _player.max_hp, _player.shield, _player.max_shield)
