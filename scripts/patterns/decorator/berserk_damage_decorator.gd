class_name BerserkDamageDecorator extends DamageDecorator

## ConcreteDecorator: multiplicador de Berserk del arma (solo si el jugador está en Berserk).

var _data: WeaponData
var _active: bool

func _init(inner: DamageSource, data: WeaponData, active: bool) -> void:
	super(inner)
	_data = data
	_active = active

func value() -> float:
	return _inner.value() * (_data.berserk_mult if _active else 1.0)
