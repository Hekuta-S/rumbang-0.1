extends WeaponSlotIterator
class_name CyclicSlotIterator
## PATRÓN ITERATOR — rol: ConcreteIterator.
## Recorre las ranuras en anillo a partir de la ranura actual, avanzando `step`
## posiciones (+1 adelante, -1 atrás) y dando la vuelta en los extremos.
## Visita cada ranura una sola vez; la ranura de partida queda al final.
##
## Ejemplo con 3 ranuras, start=0, step=-1  →  2, 1, 0

var _start: int
var _step: int
var _visited: int = 0
var _index: int = -1


func _init(slots: Array, start_slot: int, step: int = 1) -> void:
	super(slots)
	_start = start_slot
	_step = 1 if step >= 0 else -1


func has_next() -> bool:
	return _visited < _slots.size()


func next() -> int:
	_visited += 1
	# posmod (y no %) para que el anillo funcione también hacia atrás desde la ranura 0
	_index = posmod(_start + _step * _visited, _slots.size())
	return _slots[_index]


func current_index() -> int:
	return _index


func reset() -> void:
	_visited = 0
	_index = -1
