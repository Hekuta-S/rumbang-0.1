class_name UpgradeDamageDecorator extends DamageDecorator

## ConcreteDecorator: multiplicador de daño acumulado por las mejoras del arma (mods["damage"]).

var _mods: Dictionary

func _init(inner: DamageSource, mods: Dictionary) -> void:
	super(inner)
	_mods = mods

func value() -> float:
	return _inner.value() * float(_mods.get("damage", 1.0))
