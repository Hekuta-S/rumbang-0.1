class_name GameState extends RefCounted

## --- APLICACIÓN DEL PATRÓN SINGLETON ---
## Mantiene el estado de la partida actual sin necesidad de ser un Nodo en el SceneTree.

static var _instance: GameState = null

static func get_instance() -> GameState:
	if _instance == null:
		_instance = GameState.new()
	return _instance

var sub_level: int = 1
var gold: int = 0
var elapsed_time: float = 0.0

func reset_session() -> void:
	sub_level = 1
	gold = 0
	elapsed_time = 0.0

func add_time(delta: float) -> void:
	elapsed_time += delta

func add_gold(amount: int) -> void:
	gold += amount

func advance_level() -> void:
	sub_level += 1
