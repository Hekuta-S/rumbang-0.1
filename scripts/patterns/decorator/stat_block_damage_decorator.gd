class_name StatBlockDamageDecorator extends DamageDecorator

## ConcreteDecorator: multiplicador de daño global del jugador (objetos / pasivas, PlayerStatBlock).

var _stat_block

func _init(inner: DamageSource, stat_block) -> void:
	super(inner)
	_stat_block = stat_block

func value() -> float:
	return _inner.value() * (_stat_block.damage_mult() if _stat_block else 1.0)
