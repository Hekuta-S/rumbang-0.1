## ==============================================================================
## EJEMPLO DIDÁCTICO: ANTIPATRÓN "GOD CLASS / GOD METHOD" (PRE-FACADE)
## ==============================================================================
## Este archivo muestra la versión histórica de main.gd antes de refactorizar
## e introducir el patrón Facade (GameStartFacade).
##
## ¿POR QUÉ ERA UN ANTIPATRÓN?
## 1. Violación del Principio de Responsabilidad Única (SRP):
##    Main tenía que saber cómo crear, configurar, ordenar y conectar 5 subsistemas
##    diferentes (UI, Entorno, Oleadas, Botín/Loot y Plataforma/Hardware).
## 2. Alto Acoplamiento (Tight Coupling):
##    Si cambiaba la forma de instanciar o inicializar cualquiera de los Managers,
##    había que modificar Main directamente.
## 3. Falta de Encapsulamiento:
##    Main manipulaba nodos hijos por ruta directa ($UIManager, $LootManager, etc.)
##    y dependía de detalles de bajo nivel como coordenadas de spawn o reseteo de stats.
##
## NO es un archivo ejecutable del juego actual — sirve exclusivamente como
## material de estudio, documentación y contraste arquitectónico.
## ==============================================================================

extends Node3D

@onready var hud = $HUD
@onready var player = $Player

# ------------------------------------------------------------------------------
# [ANTIPATRÓN - GOD METHOD]: _ready()
# Aquí Main se encarga de TODO el bootstrapping del juego. En lugar de limitarse
# a ser el punto de entrada de la escena, actúa como orquestador masivo de 
# bajo nivel instanciando y vinculando cada subsistema paso a paso.
# ------------------------------------------------------------------------------
func _ready() -> void:
	# [MAL APORTADO / ALTO ACOPLAMIENTO 1]: Configuración manual de UIManager.
	# Main no debería preocuparse por instanciar la UI ni conectarla manualmente al Player.
	var ui_manager = UIManager.new()
	ui_manager.name = "UIManager"
	add_child(ui_manager)
	ui_manager.initialize(hud, player)
	ui_manager.restart_pressed.connect(start_game)
	if player.has_signal("player_died"):
		player.connect("player_died", _on_player_died)
	
	# [MAL APORTADO / MEZCLA DE RESPONSABILIDADES 2]: Configuración de Plataforma / Hardware.
	# Main contiene lógica de inspección de nodos de iluminación y viewports,
	# acoplándose a la lógica de si la plataforma es móvil o escritorio.
	var platform_factory: PlatformFactory = PlatformFactory.get_factory()
	
	if has_node("WorldEnvironment") and $WorldEnvironment.environment:
		platform_factory.configure_environment($WorldEnvironment.environment)
		
	platform_factory.configure_viewport(get_viewport())
	
	if has_node("DirectionalLight3D"):
		platform_factory.configure_light($DirectionalLight3D)
		
	var touch_controls = platform_factory.create_controls()
	if touch_controls:
		add_child(touch_controls)
		
	platform_factory.create_map(self)

	# [MAL APORTADO / ALTO ACOPLAMIENTO 3]: Generación de entorno.
	# Main gestiona directamente el ciclo de vida de EnvironmentManager.
	var env_manager = EnvironmentManager.new()
	env_manager.name = "EnvironmentManager"
	add_child(env_manager)
	env_manager.generation_finished.connect(start_game)
	env_manager.generate_environment()

	# [MAL APORTADO / ALTO ACOPLAMIENTO 4]: Gestión de oleadas y eventos de combate.
	# Main tiene que conectar y conocer individualmente cada señal de WaveManager.
	var wave_manager = WaveManager.new()
	wave_manager.name = "WaveManager"
	add_child(wave_manager)
	wave_manager.enemy_died.connect(_on_enemy_died)
	wave_manager.boss_died.connect(_on_boss_died)
	wave_manager.wave_cleared.connect(_on_wave_cleared)

	# [MAL APORTADO / ALTO ACOPLAMIENTO 5]: Sistema de economía y pickups (LootManager).
	# Otro manager más que Main debe conocer e inicializar explícitamente.
	var loot_manager = LootManager.new()
	loot_manager.name = "LootManager"
	add_child(loot_manager)
	loot_manager.initialize(player)


# ------------------------------------------------------------------------------
# [ANTIPATRÓN]: Manipulación directa de nodos internos ($UIManager)
# Main se acopla a la existencia de un nodo hijo por nombre en vez de usar una interfaz.
# ------------------------------------------------------------------------------
func _process(delta: float) -> void:
	if not get_tree().paused:
		GameState.get_instance().add_time(delta)
		if has_node("UIManager"):
			$UIManager.update_elapsed_time(GameState.get_instance().elapsed_time)


# ------------------------------------------------------------------------------
# [ANTIPATRÓN]: Fuga de abstracción
# Main tiene que servir como intermediario para consultar la altura del terreno
# preguntándole directamente a un nodo específico ($EnvironmentManager).
# ------------------------------------------------------------------------------
func get_floor_y(x: float, z: float) -> float:
	if has_node("EnvironmentManager"):
		return $EnvironmentManager.get_floor_y(x, z)
	return 0.0


# ------------------------------------------------------------------------------
# [ANTIPATRÓN]: Acceso directo a subsistemas desde inputs
# Main interactúa de forma cruda con el LootManager y con la creación directa del jefe.
# ------------------------------------------------------------------------------
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_Y:
			if has_node("LootManager"):
				$LootManager.spawn_debug_orbs()
		elif event.keycode == KEY_O:
			var boss = EnemyFactory.create_enemy("necromancer")
			if boss:
				add_child(boss)
				if is_instance_valid(player):
					boss.global_position = player.global_position + Vector3(0, 3.0, -10)
				if boss.has_signal("boss_died"):
					boss.boss_died.connect(_on_boss_died)


# ------------------------------------------------------------------------------
# [ANTIPATRÓN - GOD METHOD]: start_game()
# Main asume detalles internos de inicialización que no le corresponden:
# 1. Resetear múltiples pantallas y contadores de la UI manualmente.
# 2. Configurar la física y altura de spawn del jugador (+3.0 sobre el suelo).
# 3. Restaurar estadísticas (hp, shield, energy) y emitir señales internas del Player.
# 4. Orquestar manualmente la primera oleada y el spawn de pickups en el suelo.
# ------------------------------------------------------------------------------
func start_game() -> void:
	GameState.get_instance().reset_session()
	
	# [INFRACCIÓN DE ENCAPSULAMIENTO]: Manejo detallado de cada componente de la UI
	$UIManager.update_elapsed_time(GameState.get_instance().elapsed_time)
	$UIManager.update_floor(GameState.get_instance().sub_level)
	$UIManager.update_gold(GameState.get_instance().gold)
	$UIManager.reset_screens()
	
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# [ACOPLAMIENTO A LÓGICA DE JUGADOR]: Main aplica datos y resetea stats internamente
	GameData.apply_to_player(player)

	var start_x = 0.0
	var start_z = 0.0
	player.global_position = Vector3(start_x, get_floor_y(start_x, start_z) + 3.0, start_z)
	player.hp     = player.max_hp
	player.shield = player.max_shield
	player.energy = player.max_energy
	player.emit_signal("stats_changed", player.hp, player.max_hp, player.shield, player.max_shield, player.energy, player.max_energy)

	# [ACOPLAMIENTO CRUZADO]: Main debe recordar el orden exacto en que se reinicia cada subsistema
	$UIManager.refresh_weapon_ui()	
	$WaveManager.start_wave(GameState.get_instance().sub_level, player)
	$LootManager.spawn_weapon_pickup()
	$LootManager.spawn_item_pickup()


# ------------------------------------------------------------------------------
# [ACOPLAMIENTO EN MANEJO DE EVENTOS]:
# En vez de que una Fachada o mediador centralice la secuencia tras la muerte o
# avance de oleada, Main tiene que gestionar individualmente cada manager ($UIManager,
# $WaveManager, $LootManager, SaveManager, GameState).
# ------------------------------------------------------------------------------

func _on_enemy_died(pos: Vector3, gold_val: int) -> void:
	GameState.get_instance().add_gold(gold_val)
	$UIManager.update_gold(GameState.get_instance().gold)
	SaveManager.add_gold(gold_val)
	$LootManager.spawn_xp_orb(pos)

func _on_wave_cleared() -> void:
	GameState.get_instance().advance_level()
	$UIManager.update_floor(GameState.get_instance().sub_level)
	SaveManager.set_best_floor(_char_id(), GameState.get_instance().sub_level)
	$WaveManager.start_wave(GameState.get_instance().sub_level, player)
	$LootManager.spawn_weapon_pickup()
	$LootManager.spawn_item_pickup()

func _on_boss_died(pos: Vector3, gold_val: int) -> void:
	GameState.get_instance().add_gold(gold_val)
	$UIManager.update_gold(GameState.get_instance().gold)
	SaveManager.add_gold(gold_val)
	SaveManager.set_best_floor(_char_id(), GameState.get_instance().sub_level)

	if GameState.get_instance().sub_level >= 9:
		AudioManager.play("victory")
		$UIManager.show_victory()
	else:
		AudioManager.play("coin")
		GameState.get_instance().advance_level()
		$UIManager.update_floor(GameState.get_instance().sub_level)
		$WaveManager.start_wave(GameState.get_instance().sub_level, player)
		$LootManager.spawn_weapon_pickup()
		$LootManager.spawn_item_pickup()

func _char_id() -> String:
	var char_data: Dictionary = GameData.get_selected()
	return str(char_data.get("id", "unknown"))

func _on_player_died() -> void:
	SaveManager.set_best_floor(_char_id(), GameState.get_instance().sub_level)
