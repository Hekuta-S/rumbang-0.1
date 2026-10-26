class_name DamageSource extends RefCounted

## PATRÓN DECORATOR (estructural) — rol: Component
## Problema previo: Player._weapon_damage() y _weapon_heavy_damage() repetían la misma cadena de
## multiplicadores (berserk × mejoras × stats) escrita a mano; añadir un modificador obligaba a
## tocar ambas funciones. Ahora cada modificador es un Decorator apilable.

func value() -> float:
	return 0.0
