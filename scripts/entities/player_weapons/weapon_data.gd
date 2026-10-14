class_name WeaponData
extends Resource
## Passive data de un arma: daño, régimen de disparo, costes y parámetros de
## área/proyectil. La tabla canónica se arma en Player._build_weapon_table()
## con los MISMOS valores que el juego usaba hardcodeados en cada attack_*,
## para que este refactor sea neutro (no cambia el comportamiento).

## ids numéricos de cada arma (enum centralizado, antes vivía en Player).
@export var id: int = -1
@export var display_name: String = ""
@export var icon: String = ""
## "melee", "ranged" o "special".
@export var category: String = "melee"
## Coste de energía por disparo (0 = gratis).
@export var energy_cost: int = 0

# --- Stats de combate ------------------------------------------------------
@export var base_damage: float = 0.0
@export var base_cooldown: float = 0.5
## Multiplicador de daño durante Berserk (1.5 melee / 1.3 ranged histórico).
@export var berserk_mult: float = 1.5
## Velocidad de proyectil propia del arma (0 = no usa proyectil).
@export var projectile_speed: float = 0.0
## Disparos por activación (1 = normal). La dispersión real la define cada arma.
@export var pellet_count: int = 1
## Alcance efectivo / radio (m): cono melee, AOE radial o rayo.
@export var weapon_range: float = 3.0
## Semi-ángulo del cono frontal en grados (180 = 360° / sin cono).
@export var half_angle: float = 180.0
## Radio del rayo "beam" (Armas tipo railgun).
@export var beam_radius: float = 0.0

# --- Cargador (munición) ----------------------------------------------------
## 0 = munición infinita.
@export var mag_size: int = 0
@export var reload_time: float = 2.0

# --- Variante alterna (heavy / charged) -------------------------------------
## 0.0 = la variante no modifica ese campo y se usa el valor base.
@export var heavy_damage: float = 0.0
@export var heavy_cooldown: float = 0.0
@export var heavy_range: float = 0.0
@export var heavy_half_angle: float = 0.0


## ---------------------------------------------------------------------------
## WeaponType: la llave primaria de TODA la tabla de armas. Centralizado aquí
## (extraído de player.gd) para que player.gd y el componente de modelos
## compartan el mismo enum.
## ---------------------------------------------------------------------------
enum WeaponType {
	ENERGY_SWORD,
	FLAME_AXE,
	PLASMA_RIFLE,
	TRI_SHOTGUN,
	RAILGUN,
	SPEAR_LANCE,
	FLAME_THROWER,
	SPORE_BAZOOKA,
	DUAL_DAGGERS,
	AIR_FISTS,
	DUSTS,
	SERPENTS,
	SPINNING_AXE,
	ELEMENTS_CYCLE,
	ZOMBIE_ARM,
}

## ---------------------------------------------------------------------------
## Tabla canónica de armas (WeaponType -> WeaponData). Extraída de player.gd
## (refactor neutro): los attack_* del player leen aquí los mismos valores que
## antes tenían hardcodeados.
## ---------------------------------------------------------------------------
static var _weapon_table_cache: Dictionary = {}

## --- APLICACIÓN DEL PATRÓN BUILDER ---
static func _build_weapon_table() -> Dictionary:
	var table: Dictionary = {
		WeaponType.ENERGY_SWORD: WeaponBuilder.new(0, "Espada de Energía", "🗡️", "melee")\
			.set_combat(12.0, 0.45, 3.2)\
			.set_projectile(0.0, 1, 75.0)\
			.build(),
			
		WeaponType.FLAME_AXE: WeaponBuilder.new(1, "Hacha de Fuego", "🪓", "melee")\
			.set_combat(25.0, 0.90, 4.5)\
			.set_projectile(0.0)\
			.build(),
			
		WeaponType.PLASMA_RIFLE: WeaponBuilder.new(2, "Rifle de Plasma", "🔫", "ranged")\
			.set_combat(5.0, 0.35)\
			.set_projectile(42.0)\
			
			.build(),
			
		WeaponType.TRI_SHOTGUN: WeaponBuilder.new(3, "Escopeta de Humo", "💨", "ranged")\
			.set_combat(4.0, 0.80)\
			.set_projectile(36.0, 5)\
			
			.build(),
			
		WeaponType.RAILGUN: WeaponBuilder.new(4, "Cañón Railgun", "🔮", "ranged")\
			.set_combat(45.0, 1.50, 50.0)\
			
			.build(),
			
		WeaponType.SPEAR_LANCE: WeaponBuilder.new(5, "Espalanza de Mikeura", "🔱", "melee")\
			.set_combat(15.0, 0.50, 5.0)\
			.set_projectile(0.0, 1, 80.0)\
			.build(),
			
		WeaponType.FLAME_THROWER: WeaponBuilder.new(6, "Lanzallamas", "🔥", "melee")\
			.set_combat(2.0, 0.20, 11.0)\
			.set_projectile(0.0, 1, 35.0)\
			.build(),
			
		WeaponType.SPORE_BAZOOKA: WeaponBuilder.new(7, "Bazuca de Esporas", "🍄", "ranged")\
			.set_combat(25.0, 0.80, 2.6)\
			.set_projectile(10.0)\
			.set_ammo(1, 2.4)\
			.build(),
			
		WeaponType.DUAL_DAGGERS: WeaponBuilder.new(8, "Dagas Gemelas de Crane", "🔪", "melee")\
			.set_combat(6.0, 0.30, 2.6)\
			.set_projectile(0.0, 1, 75.0)\
			.set_heavy_attack(15.0, 0.8, 3.0, 90.0)\
			.build(),
			
		WeaponType.AIR_FISTS: WeaponBuilder.new(9, "Puños de Aire de Kaionz", "🌀", "melee")\
			.set_combat(9.0, 0.35, 2.8)\
			.set_projectile(0.0, 1, 55.0)\
			.set_heavy_attack(25.0, 0.8, 3.8, 0.0)\
			.build(),
			
		WeaponType.DUSTS: WeaponBuilder.new(10, "Polvos Alquímicos", "🧪", "special")\
			
			.build(),
			
		WeaponType.SERPENTS: WeaponBuilder.new(11, "Serpientes de Joel", "🐍", "ranged")\
			.set_combat(5.0, 1.0)\
			.set_projectile(24.0, 3, 15.0)\
			.build(),
			
		WeaponType.SPINNING_AXE: WeaponBuilder.new(12, "Hacha Giratoria", "🪓", "ranged")\
			.set_combat(9.0, 0.8, 10.0)\
			.set_projectile(20.0)\
			.build(),
			
		WeaponType.ELEMENTS_CYCLE: WeaponBuilder.new(13, "Ciclo Elemental", "🔮", "ranged")\
			.set_combat(7.0, 0.6)\
			.set_projectile(22.0)\
			.build(),
			
		WeaponType.ZOMBIE_ARM: WeaponBuilder.new(14, "Brazo Bumerán", "🧟", "ranged")\
			.set_combat(18.0, 0.8)\
			.set_projectile(20.0)\
			.build(),
	}
	return table
## ---------------------------------------------

static func get_weapon_table() -> Dictionary:
	if _weapon_table_cache.is_empty():
		_weapon_table_cache = _build_weapon_table()
	return _weapon_table_cache

## Devuelve la ficha del arma; ante un id desconocido, cae a la espada.
static func get_weapon_data(weapon_type: int) -> WeaponData:
	return get_weapon_table().get(weapon_type, get_weapon_table()[WeaponType.ENERGY_SWORD])

## Nombre por arma (UI / HUD / señales).
static var weapon_names: Dictionary = {
	WeaponType.ENERGY_SWORD: "Espada de Energía",
	WeaponType.FLAME_AXE: "Hacha de Fuego",
	WeaponType.PLASMA_RIFLE: "Rifle de Plasma",
	WeaponType.TRI_SHOTGUN: "Escopeta Triple",
	WeaponType.RAILGUN: "Cañón Railgun",
	WeaponType.SPEAR_LANCE: "Espalanza de Mikeura",
	WeaponType.FLAME_THROWER: "Lanzallamas",
	WeaponType.SPORE_BAZOOKA: "Bazuca de Esporas",
	WeaponType.DUAL_DAGGERS: "Dagas Gemelas de Crane",
	WeaponType.AIR_FISTS: "Puños de Aire de Kaionz",
	WeaponType.DUSTS: "Polvos Alquímicos",
	WeaponType.SERPENTS: "Serpientes de Joel",
	WeaponType.SPINNING_AXE: "Hacha Giratoria",
	WeaponType.ELEMENTS_CYCLE: "Ciclo Elemental",
	WeaponType.ZOMBIE_ARM: "Brazo Bumerán",
}

## Coste de energía por arma (UI / combate).
static var weapon_energy_costs: Dictionary = {
	WeaponType.ENERGY_SWORD: 0,
	WeaponType.FLAME_AXE: 0,
	WeaponType.PLASMA_RIFLE: 1,
	WeaponType.TRI_SHOTGUN: 3,
	WeaponType.RAILGUN: 5,
	WeaponType.SPEAR_LANCE: 0,
	WeaponType.FLAME_THROWER: 0,
	WeaponType.SPORE_BAZOOKA: 0,
	WeaponType.DUAL_DAGGERS: 0,
	WeaponType.AIR_FISTS: 0,
	WeaponType.DUSTS: 15,
	WeaponType.SERPENTS: 0,
	WeaponType.SPINNING_AXE: 0,
	WeaponType.ELEMENTS_CYCLE: 0,
	WeaponType.ZOMBIE_ARM: 0,
}

## Icono por arma (HUD / señales).
static var weapon_icons: Dictionary = {
	WeaponType.ENERGY_SWORD: "🗡️",
	WeaponType.FLAME_AXE: "🪓",
	WeaponType.PLASMA_RIFLE: "🔫",
	WeaponType.TRI_SHOTGUN: "💥",
	WeaponType.RAILGUN: "🔮",
	WeaponType.SPEAR_LANCE: "🔱",
	WeaponType.FLAME_THROWER: "🔥",
	WeaponType.SPORE_BAZOOKA: "🍄",
	WeaponType.DUAL_DAGGERS: "🔪",
	WeaponType.AIR_FISTS: "🌀",
	WeaponType.DUSTS: "🧪",
	WeaponType.SERPENTS: "🐍",
	WeaponType.SPINNING_AXE: "🪓",
	WeaponType.ELEMENTS_CYCLE: "🔮",
	WeaponType.ZOMBIE_ARM: "🧟",
}

## Daño con Berserk aplicado según la ficha (mismos valores que los literales).
static func weapon_damage(weapon_type: int, p_is_berserk: bool) -> float:
	var data := get_weapon_data(weapon_type)
	return data.base_damage * (data.berserk_mult if p_is_berserk else 1.0)

## Daño de la variante alterna (heavy / charged); cae al base si no hay heavy.
static func weapon_heavy_damage(weapon_type: int, p_is_berserk: bool) -> float:
	var data := get_weapon_data(weapon_type)
	var dmg: float = data.heavy_damage if data.heavy_damage > 0.0 else data.base_damage
	return dmg * (data.berserk_mult if p_is_berserk else 1.0)
