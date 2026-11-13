# Guion de sustentación: patrón Iterator

## Antipatrones que había

1. **Intimidad inapropiada (Inappropriate Intimacy):** `PlayerWeaponInventory` dejaba a la vista su `Array` interno (`weapon_slots`). `Player` y `PauseMenu` lo leían directamente, lo que rompe el encapsulamiento.
2. **Envidia de funcionalidad (Feature Envy):** `Player` calculaba qué ranura del inventario venía después usando los datos del inventario. Ese trabajo le correspondía al inventario.
3. **Código duplicado (Copy-Paste Programming):** la misma fórmula de "siguiente/anterior arma" estaba escrita en `Player` y en `PlayerWeaponInventory`, así que el bug se repetía en las dos.

**En una frase:** la clase exponía su colección y cada cliente la recorría a su manera, con lógica duplicada. Iterator lo resuelve sacando el recorrido a un objeto propio.

**Antes:** cada clase leía el `Array` interno y calculaba el índice siguiente o anterior por su cuenta. Desde la primera arma no se podía volver a la última, porque `(0 - 1) % 3 = -1`.
**Ahora:** el inventario entrega un iterador (en orden o en anillo) y los clientes solo le piden el siguiente. La lógica está en un único lugar y el bug quedó corregido.

---

## Parte 1: Diagrama ANTES (`diagrama_antes.puml`)

**1. Contexto (señalar `PlayerWeaponInventory`)**
"Esta clase guarda las armas del jugador: hasta 4 ranuras en un `Array` llamado `weapon_slots`, más `current_slot`, que indica cuál está activa."

**2. Colección expuesta (flechas que llegan al inventario)**
"El inventario no controla cómo se recorren sus armas: deja a la vista su `Array` interno. `PauseMenu` hace `for w in weapon_slots` y `Player` lee el arreglo, su tamaño y el índice actual. Eso rompe el encapsulamiento: si cambio la estructura interna, tengo que modificar a todos los clientes."

**3. Flujo de cambio de arma**
"El jugador pulsa Q. `PlayerInputController` emite `weapon_cycle` con +1 o -1. `Player.cycle_slots` calcula él mismo `(current_slot + delta) % size` y llama a `select_slot`."

**4. Lógica duplicada (nota de `Player`)**
"Esa misma fórmula también está en `PlayerWeaponInventory.cycle_slots`. La misma lógica de recorrido aparece en dos clases, lo que viola los principios DRY y de responsabilidad única."

**5. Bug real (nota del inventario)**
"En GDScript, `%` conserva el signo. Desde la ranura 0, 'arma anterior' calcula `(0 - 1) % 3 = -1`. `select_slot(-1)` se descarta y no pasa nada: no se puede volver de la primera arma a la última."

**6. Cierre**
"Hay tres problemas: una colección expuesta, una lógica de recorrido duplicada y un bug provocado por esa duplicación. Es justo el caso que resuelve Iterator."

---

## Parte 2: Diagrama DESPUÉS (`diagrama_despues.puml`)

**1. La idea del patrón**
"Iterator, un patrón de comportamiento del GoF, saca la forma de recorrer una colección fuera de la colección y de sus clientes. El cliente solo pregunta '¿hay siguiente?' y pide 'dame el siguiente'."

**2. Iterator (`WeaponSlotIterator`)**
"Es la interfaz abstracta: `has_next()`, `next()`, `current_index()` y `reset()`. También implementa el protocolo de GDScript (`_iter_init`, `_iter_next`, `_iter_get`), así que cualquier iterador se puede usar en un `for`."

**3. ConcreteIterator (`LinearSlotIterator` y `CyclicSlotIterator`)**
"`LinearSlotIterator` recorre las armas en orden; se usa en el HUD, en el menú de pausa y al buscar munición. `CyclicSlotIterator` las recorre en anillo desde el arma actual, hacia adelante o hacia atrás; se usa para cambiar de arma. Los dos heredan de `WeaponSlotIterator` y son intercambiables."

**4. ConcreteAggregate (`PlayerWeaponInventory`)**
"El inventario fabrica sus iteradores con `create_iterator()` y `create_cyclic_iterator(step)`, y ofrece `next_slot_index(step)`. Solo él sabe qué iterador concreto crear."

**5. Nuevo flujo**
"Al pulsar Q se emite `weapon_cycle(-1)`. `Player.cycle_slots` solo pide `weapon_inventory.next_slot_index(-1)`. El inventario crea un `CyclicSlotIterator` que avanza un paso, y `Player` recibe el índice correcto y llama a `select_slot`."

**6. Bug corregido (nota de `CyclicSlotIterator`)**
"El índice se calcula con `posmod(_start + _step * _visited, size)`, que siempre devuelve un valor positivo: desde la ranura 0 con -1 da la última. El bug se corrigió en un solo lugar."

**7. `PauseMenu`**
"Ya no sabe que existe un `Array`: escribe `for w in winv.create_iterator()`."

**8. Beneficios**
1. Encapsulamiento: los clientes no dependen del `Array`.
2. Responsabilidad única: recorrer es trabajo del iterador.
3. Sin duplicación.
4. Abierto/cerrado: un recorrido nuevo, por ejemplo solo armas con munición, es otra subclase.
5. Bug corregido y probado: `tests/test_weapon_iterator.tscn` (8 comprobaciones), y los tests de equipo y sinergias siguen pasando.

**Si preguntan por qué no se migraron todos los usos de `weapon_slots`:**
"Apliqué el patrón primero donde había un problema concreto: la duplicación, el bug y el recorrido en la interfaz. Así el cambio es pequeño y comprobable. El resto se puede migrar poco a poco, porque el agregado ya ofrece los iteradores."

---

## Dónde está en el código

| Rol | Archivo |
|---|---|
| Iterator | `scripts/patterns/iterator/weapon_slot_iterator.gd` |
| ConcreteIterator | `scripts/patterns/iterator/linear_slot_iterator.gd` |
| ConcreteIterator | `scripts/patterns/iterator/cyclic_slot_iterator.gd` (línea 29: `posmod`) |
| ConcreteAggregate | `scripts/components/player_weapon_inventory.gd` (`create_iterator`, `create_cyclic_iterator`, `next_slot_index`) |
| Client | `scripts/entities/player.gd` (`cycle_slots`, cambio de arma con Q) |
| Client | `scripts/ui/pause_menu.gd` (`for w in winv.create_iterator()`) |
| Test | `tests/test_weapon_iterator.tscn` |
