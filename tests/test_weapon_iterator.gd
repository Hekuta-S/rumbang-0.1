extends Node

## Patrón Iterator sobre las ranuras de arma (PlayerWeaponInventory + LinearSlotIterator/CyclicSlotIterator).

var _n: int = 0

func _check(ok: bool, msg: String) -> void:
	_n += 1
	if not ok:
		push_error("CHECK %d FAILED: %s" % [_n, msg])
		get_tree().quit(1)
	print("CHECK %d OK: %s" % [_n, msg])

func _ready() -> void:
	print("--- TEST: PATRÓN ITERATOR (ranuras de arma) ---")
	var T := WeaponData.WeaponType
	var inv := PlayerWeaponInventory.new()
	add_child(inv)
	inv.add_weapon(T.SPEAR_LANCE)
	inv.add_weapon(T.DAGGERS)
	inv.add_weapon(T.SWORD)

	# Recorrido lineal con for nativo
	var seen: Array = []
	for w in inv.create_iterator():
		seen.append(w)
	_check(seen == [T.SPEAR_LANCE, T.DAGGERS, T.SWORD], "for recorre las 3 armas en orden")

	# Recorrido explícito has_next/next + current_index
	var it := inv.create_iterator()
	var idx: Array = []
	while it.has_next():
		it.next()
		idx.append(it.current_index())
	_check(idx == [0, 1, 2], "has_next/next/current_index")
	it.reset()
	_check(it.has_next() and it.next() == T.SPEAR_LANCE, "reset vuelve al inicio")

	# Anillo hacia adelante y hacia atrás
	inv.current_slot = 0
	var fwd: Array = []
	for w in inv.create_cyclic_iterator(1):
		fwd.append(w)
	_check(fwd == [T.DAGGERS, T.SWORD, T.SPEAR_LANCE], "anillo +1 desde ranura 0")
	_check(inv.next_slot_index(-1) == 2, "anterior desde ranura 0 = ranura 2 (antes daba -1)")

	# cycle_slots: el bug antiguo impedía retroceder desde la ranura 0
	inv.cycle_slots(-1)
	_check(inv.current_slot == 2, "cycle_slots(-1) desde 0 salta a la última")
	inv.cycle_slots(1)
	_check(inv.current_slot == 0, "cycle_slots(+1) desde la última vuelve a 0")

	# Lista vacía
	var empty := PlayerWeaponInventory.new()
	add_child(empty)
	_check(not empty.create_iterator().has_next() and empty.next_slot_index(1) == -1, "inventario vacío")

	print("ALL %d CHECKS PASSED" % _n)
	get_tree().quit(0)
