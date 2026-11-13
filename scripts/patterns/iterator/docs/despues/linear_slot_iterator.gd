extends WeaponSlotIterator
class_name LinearSlotIterator
## PATRÓN ITERATOR — rol: ConcreteIterator.
## Recorre las ranuras de arma en orden: 0, 1, 2 … n-1.

var _pos: int = 0


func has_next() -> bool:
	return _pos < _slots.size()


func next() -> int:
	var w: int = _slots[_pos]
	_pos += 1
	return w


func current_index() -> int:
	return _pos - 1


func reset() -> void:
	_pos = 0
