class_name WeaponPrototypeRegistry extends RefCounted

## PATRÓN PROTOTYPE (creacional) — rol: Client / registro de prototipos
## Problema previo: WeaponData._apply_balance() mutaba directamente las fichas canónicas, así que
## los valores originales de cada arma se perdían y no había forma de obtener una copia independiente.
## Ahora las fichas construidas por el Builder se registran como PROTOTIPOS inmutables y la tabla de
## juego se obtiene CLONÁNDOLOS (WeaponData.clone() = operación clone del Prototype).
##   Prototype          : WeaponData (clone())
##   ConcretePrototype  : cada ficha registrada (espada, railgun...)
##   Client             : WeaponPrototypeRegistry / WeaponData.get_weapon_table()

static var _prototypes: Dictionary = {}

static func register_all(prototypes: Dictionary) -> void:
	_prototypes = prototypes.duplicate()

static func has_prototype(weapon_type: int) -> bool:
	return _prototypes.has(weapon_type)

## Copia independiente (sin balance aplicado) del arma pedida; null si no hay prototipo.
static func clone_of(weapon_type: int) -> WeaponData:
	var proto: WeaponData = _prototypes.get(weapon_type)
	return proto.clone() if proto != null else null
