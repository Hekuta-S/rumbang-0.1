class_name WeaponBuilder extends RefCounted

## FALENCIA DETECTADA EN EL PROYECTO (RESUELTA):
## Creación rígida de datos paramétricos. Al crear armas o mejoras (como en 
## weapon_data.gd), se manejan diccionarios grandes o constructores con 19 
## parámetros que no son escalables ni legibles.

## Builder Pattern
## Permite construir objetos complejos paso a paso. Útil para armas o 
## configuraciones que tienen muchos parámetros opcionales.

var weapon: WeaponData

func _init(id: int, name: String, icon: String, category: String) -> void:
	weapon = WeaponData.new()
	weapon.id = id
	weapon.display_name = name
	weapon.icon = icon
	weapon.category = category

func set_combat(damage: float, cooldown: float, range: float = 0.0) -> WeaponBuilder:
	weapon.base_damage = damage
	weapon.base_cooldown = cooldown
	weapon.weapon_range = range
	return self

func set_projectile(speed: float, pellets: int = 1, angle: float = 180.0) -> WeaponBuilder:
	weapon.projectile_speed = speed
	weapon.pellet_count = pellets
	weapon.half_angle = angle
	return self

func set_ammo(mag_size: int = 0, reload_time: float = 2.0) -> WeaponBuilder:
	weapon.mag_size = mag_size
	weapon.reload_time = reload_time
	return self

func set_heavy_attack(damage: float, cooldown: float, range: float = 0.0, angle: float = 0.0) -> WeaponBuilder:
	weapon.heavy_damage = damage
	weapon.heavy_cooldown = cooldown
	weapon.heavy_range = range
	weapon.heavy_half_angle = angle
	return self

func set_energy_cost(cost: int) -> WeaponBuilder:
	weapon.energy_cost = cost
	return self

func build() -> WeaponData:
	return weapon
