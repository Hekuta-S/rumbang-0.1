extends Node
class_name GameStartFacade

## --- APLICACIÓN DEL PATRÓN FACADE ---
## Encapsula toda la lógica de inicio de partida: creación de managers,
## conexión de señales y la secuencia de arranque. Main solo habla con
## esta fachada en lugar de orquestar 4+ subsistemas directamente.

signal restart_pressed
signal enemy_died(pos: Vector3, gold_val: int)
signal boss_died(pos: Vector3, gold_val: int)
signal wave_cleared

var ui_manager: UIManager
var environment_manager: EnvironmentManager
var wave_manager: WaveManager
var loot_manager: LootManager

var _player: Node3D
var _hud: Node
var _scene_root: Node3D

# ─────────────────────────────────────────────────────────
#  Interfaz pública (lo único que Main necesita conocer)
# ─────────────────────────────────────────────────────────

## Inicializa todos los subsistemas del juego.
## Llama a esto desde Main._ready() pasando la raíz de la escena, el HUD y el Player.
func initialize(scene_root: Node3D, hud: Node, player: Node3D) -> void:
	_scene_root = scene_root
	_player = player
	_hud = hud

	_setup_ui_manager()
	_setup_platform(scene_root)
	_setup_environment_manager()
	_setup_wave_manager()
	_setup_loot_manager()

## Inicia (o reinicia) una partida.
## Resetea estado, UI, jugador, oleadas y loot.
func start_game() -> void:
	_reset_game_state()
	_reset_ui()
	_apply_character_data()
	_reset_player_position_and_stats()
	ui_manager.refresh_weapon_ui()
	wave_manager.start_wave(GameState.get_instance().sub_level, _player)
	loot_manager.spawn_weapon_pickup()
	loot_manager.spawn_item_pickup()

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

## Inicia una nueva oleada (usado tras limpiar la anterior).
func start_next_wave(level: int) -> void:
	wave_manager.start_wave(level, _player)
	loot_manager.spawn_weapon_pickup()
	loot_manager.spawn_item_pickup()

## Muestra pantalla de victoria.
func show_victory() -> void:
	ui_manager.show_victory()

## Actualiza la UI de oro.
func update_gold(gold: int) -> void:
	ui_manager.update_gold(gold)

## Actualiza la UI de piso.
func update_floor(sub_level: int) -> void:
	ui_manager.update_floor(sub_level)

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

	if scene_root.has_node("WorldEnvironment") and scene_root.get_node("WorldEnvironment").environment:
		platform_factory.configure_environment(scene_root.get_node("WorldEnvironment").environment)

	platform_factory.configure_viewport(scene_root.get_viewport())

	if scene_root.has_node("DirectionalLight3D"):
		platform_factory.configure_light(scene_root.get_node("DirectionalLight3D"))

	var touch_controls = platform_factory.create_controls()
	if touch_controls:
		scene_root.add_child(touch_controls)

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
	wave_manager.wave_cleared.connect(func(): wave_cleared.emit())

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
	ui_manager.update_floor(state.sub_level)
	ui_manager.update_gold(state.gold)
	ui_manager.reset_screens()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _apply_character_data() -> void:
	GameData.apply_to_player(_player)

func _reset_player_position_and_stats() -> void:
	var start_x = 0.0
	var start_z = 0.0
	_player.global_position = Vector3(start_x, get_floor_y(start_x, start_z) + 3.0, start_z)
	_player.hp     = _player.max_hp
	_player.shield = _player.max_shield
	_player.energy = _player.max_energy
	_player.emit_signal("stats_changed", _player.hp, _player.max_hp, _player.shield, _player.max_shield, _player.energy, _player.max_energy)
