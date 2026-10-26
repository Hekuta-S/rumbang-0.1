class_name BaseWeaponDamage extends DamageSource

## ConcreteComponent del Decorator: daño base de la ficha del arma (golpe normal o variante heavy).

var _data: WeaponData
var _heavy: bool

func _init(data: WeaponData, heavy: bool = false) -> void:
	_data = data
	_heavy = heavy

func value() -> float:
	if _heavy and _data.heavy_damage > 0.0:
		return _data.heavy_damage
	return _data.base_damage
