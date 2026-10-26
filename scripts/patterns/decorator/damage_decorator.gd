class_name DamageDecorator extends DamageSource

## Decorator (clase base): envuelve otro DamageSource y le delega por defecto.

var _inner: DamageSource

func _init(inner: DamageSource) -> void:
	_inner = inner

func value() -> float:
	return _inner.value()
