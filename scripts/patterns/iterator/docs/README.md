# Patrón Iterator — ranuras de arma del jugador

- `antes/`: copia de los archivos originales, con el antipatrón.
- `despues/`: los mismos archivos refactorizados, más las 3 clases nuevas del patrón.

La carpeta tiene un `.gdignore` para que Godot no cargue estas copias (si las cargara, los `class_name` estarían duplicados). Las clases que usa el juego están en `scripts/patterns/iterator/` y los clientes en `scripts/`.

## 1. El problema (antipatrón)

`PlayerWeaponInventory` expone su colección interna (`var weapon_slots: Array`), así que cada cliente la recorre a su manera:

- con `for w in winv.weapon_slots`, lo que acopla al cliente con el tipo `Array`;
- con aritmética de índices para pasar a la siguiente o a la anterior arma, **duplicada** en dos archivos.

**antes/player_weapon_inventory.gd**
```gdscript
func cycle_slots(delta_idx: int) -> void:
	if weapon_slots.is_empty():
		return
	select_slot((current_slot + delta_idx) % weapon_slots.size())
```

**antes/player.gd** (la misma lógica, copiada)
```gdscript
func cycle_slots(delta_idx: int) -> void:
	if not weapon_inventory or weapon_inventory.weapon_slots.is_empty():
		return
	select_slot((weapon_inventory.current_slot + delta_idx) % weapon_inventory.weapon_slots.size())
```

**antes/pause_menu.gd**
```gdscript
for w in winv.weapon_slots:
```

**Bug real que esto causaba:** en GDScript, `%` conserva el signo del dividendo. Con el arma 0 equipada, "arma anterior" (`delta = -1`) calcula `(0 - 1) % 3 = -1`. `select_slot(-1)` lo descarta y **no se puede retroceder desde la primera arma**.

## 2. La solución: Iterator (GoF, comportamiento)

| Rol GoF | Clase | Archivo |
|---|---|---|
| Iterator | `WeaponSlotIterator` (abstracta: `has_next`, `next`, `current_index`, `reset`) | `scripts/patterns/iterator/weapon_slot_iterator.gd` |
| ConcreteIterator | `LinearSlotIterator` (ranuras 0 → n-1) | `scripts/patterns/iterator/linear_slot_iterator.gd` |
| ConcreteIterator | `CyclicSlotIterator` (en anillo desde la ranura actual, +1 o -1, con `posmod`) | `scripts/patterns/iterator/cyclic_slot_iterator.gd` |
| Aggregate / ConcreteAggregate | `PlayerWeaponInventory` (`create_iterator()`, `create_cyclic_iterator()`) | `scripts/components/player_weapon_inventory.gd` |
| Client | `Player`, `PauseMenu` | `scripts/entities/player.gd`, `scripts/ui/pause_menu.gd` |

`WeaponSlotIterator` implementa además el protocolo nativo de GDScript (`_iter_init`, `_iter_next`, `_iter_get`), así que el iterador se puede usar directamente en un `for`.

```
Client ──► PlayerWeaponInventory ──create_iterator()──► WeaponSlotIterator (abstracta)
                                                          ▲              ▲
                                            LinearSlotIterator   CyclicSlotIterator
```

**despues/player_weapon_inventory.gd**
```gdscript
func create_iterator() -> WeaponSlotIterator:
	return LinearSlotIterator.new(weapon_slots)

func create_cyclic_iterator(step: int = 1) -> WeaponSlotIterator:
	return CyclicSlotIterator.new(weapon_slots, current_slot, step)

func next_slot_index(step: int) -> int:
	var it := create_cyclic_iterator(step)
	if not it.has_next():
		return -1
	it.next()
	return it.current_index()

func cycle_slots(delta_idx: int) -> void:
	var target := next_slot_index(delta_idx)
	if target >= 0:
		select_slot(target)
```

**despues/player.gd**: ya no hay aritmética de índices; se delega en el agregado.
```gdscript
func cycle_slots(delta_idx: int) -> void:
	if not weapon_inventory:
		return
	var target: int = weapon_inventory.next_slot_index(delta_idx)
	if target >= 0:
		select_slot(target)
```

**despues/pause_menu.gd**
```gdscript
for w in winv.create_iterator():
```

**despues/cyclic_slot_iterator.gd** (núcleo del recorrido en anillo)
```gdscript
func next() -> int:
	_visited += 1
	_index = posmod(_start + _step * _visited, _slots.size())
	return _slots[_index]
```

## 3. Beneficios

- **Responsabilidad única:** la lógica de recorrido vive en los iteradores, no repartida entre los clientes.
- **Se elimina la duplicación** de `cycle_slots` entre `Player` y `PlayerWeaponInventory`.
- **Abierto/cerrado:** un recorrido nuevo (por ejemplo, solo armas con munición) es otra subclase de `WeaponSlotIterator`, sin tocar a los clientes.
- **Se corrige el bug** de "arma anterior" desde la ranura 0.

## 4. Verificación

`tests/test_weapon_iterator.tscn` tiene 8 comprobaciones: recorrido lineal con `for`, `has_next`/`next`/`reset`, anillo hacia +1 y -1, el bug corregido e inventario vacío. Siguen pasando `test_synergies` y `test_equipment`.

```
--- TEST: PATRÓN ITERATOR (ranuras de arma) ---
CHECK 5 OK: anterior desde ranura 0 = ranura 2 (antes daba -1)
CHECK 6 OK: cycle_slots(-1) desde 0 salta a la última
ALL 8 CHECKS PASSED
```
