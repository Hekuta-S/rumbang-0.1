class_name GameManagerSingleton extends Node

## FALENCIA DETECTADA EN EL PROYECTO:
## Dependencia excesiva del árbol de Nodos (SceneTree) para estados lógicos globales. 
## En lugar de usar AutoLoads (que instancian nodos para simples contadores), 
## este patrón implementa un Singleton estricto puramente en código.

static var _instance: GameManagerSingleton = null

static func get_instance() -> GameManagerSingleton:
	if _instance == null:
		_instance = GameManagerSingleton.new()
	return _instance

var current_score: int = 0
var active_enemies: int = 0

func add_score(amount: int) -> void:
	current_score += amount
