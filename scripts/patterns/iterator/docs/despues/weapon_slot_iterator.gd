extends RefCounted
class_name WeaponSlotIterator
## PATRÓN ITERATOR — rol: Iterator (interfaz abstracta).
##
## Recorre las ranuras de arma de un PlayerWeaponInventory (el Aggregate) sin que
## el cliente conozca el Array interno ni haga aritmética de índices.
## Las subclases (LinearSlotIterator, CyclicSlotIterator) deciden el ORDEN del recorrido.
##
## También implementa el protocolo de iteración de GDScript (_iter_init/_iter_next/_iter_get),
## así que se puede usar directamente en un `for w in inventario.create_iterator():`.

var _slots: Array   # referencia de solo lectura a las ranuras del agregado


func _init(slots: Array) -> void:
	_slots = slots


## ¿Quedan elementos por recorrer?
func has_next() -> bool:
	push_error("WeaponSlotIterator.has_next() es abstracto")
	return false


## Avanza y devuelve el tipo de arma (WeaponData.WeaponType) de la siguiente ranura.
func next() -> int:
	push_error("WeaponSlotIterator.next() es abstracto")
	return -1


## Índice de ranura del último elemento devuelto por next() (-1 si aún no se llamó).
func current_index() -> int:
	push_error("WeaponSlotIterator.current_index() es abstracto")
	return -1


## Vuelve al inicio del recorrido.
func reset() -> void:
	push_error("WeaponSlotIterator.reset() es abstracto")


# --- Protocolo de iteración nativo de GDScript (permite usarlo en un for) ---

func _iter_init(_arg) -> bool:
	reset()
	return has_next()


func _iter_next(_arg) -> bool:
	return has_next()


func _iter_get(_arg) -> Variant:
	return next()
