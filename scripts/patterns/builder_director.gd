class_name WeaponDirector extends RefCounted

## PATRÓN BUILDER (creacional) — rol: Director
## Problema previo: cada arma repetía a mano el orden de pasos del WeaponBuilder
## (set_combat + set_projectile...), con riesgo de olvidar un paso o ponerlo mal.
## El Director encapsula las "recetas" de construcción y recibe un WeaponBuilder (Builder).

## Arma cuerpo a cuerpo: sin proyectil, con semi-ángulo de cono.
static func construct_melee(builder: WeaponBuilder, damage: float, cooldown: float, reach: float, cone_angle: float) -> WeaponData:
	return builder.set_combat(damage, cooldown, reach).set_projectile(0.0, 1, cone_angle).build()

## Arma a distancia: con proyectil.
static func construct_ranged(builder: WeaponBuilder, damage: float, cooldown: float, projectile_speed: float, reach: float = 0.0, pellets: int = 1) -> WeaponData:
	return builder.set_combat(damage, cooldown, reach).set_projectile(projectile_speed, pellets).build()
