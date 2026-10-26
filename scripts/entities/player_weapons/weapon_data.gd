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
	ENERGY_SWORD = 0,
	TRI_SHOTGUN = 3,
	RAILGUN = 4,
	SPEAR_LANCE = 5,
	FLAME_THROWER = 6,
	SPORE_BAZOOKA = 7,
	DUSTS = 10,
	SERPENTS = 11,
	SPINNING_AXE = 12,
	ELEMENTS_CYCLE = 13,
	ZOMBIE_ARM = 14,
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
		WeaponType.ENERGY_SWORD: WeaponDirector.construct_melee(
				WeaponBuilder.new(0, "Espada de Energía", "🗡️", "melee"), 12.0, 0.45, 3.2, 75.0),
			
		WeaponType.TRI_SHOTGUN: WeaponBuilder.new(3, "Escopeta de Humo", "💨", "ranged")\
			.set_combat(4.0, 0.80)\
			.set_projectile(36.0, 5)\
			
			.build(),
			
		WeaponType.RAILGUN: WeaponBuilder.new(4, "Cañón Railgun", "🔮", "ranged")\
			.set_combat(45.0, 1.50, 50.0)\
			
			.build(),
			
		WeaponType.SPEAR_LANCE: WeaponDirector.construct_melee(
				WeaponBuilder.new(5, "Espalanza de Mikeura", "🔱", "melee"), 15.0, 0.50, 5.0, 80.0),
			
		WeaponType.FLAME_THROWER: WeaponDirector.construct_melee(
				WeaponBuilder.new(6, "Lanzallamas", "🔥", "melee"), 2.0, 0.20, 11.0, 35.0),
			
		WeaponType.SPORE_BAZOOKA: WeaponBuilder.new(7, "Bazuca de Esporas", "🍄", "ranged")\
			.set_combat(70.0, 2.2, 2.6)\
			.set_projectile(10.0)\
			.build(),
			
		WeaponType.DUSTS: WeaponBuilder.new(10, "Polvos Alquímicos", "🧪", "special")\
			
			.build(),
			
		WeaponType.SERPENTS: WeaponBuilder.new(11, "Espíritus de Joel", "🦎", "melee")\
			.set_combat(14.0, 1.6)\
			.build(),

		WeaponType.SPINNING_AXE: WeaponDirector.construct_ranged(
				WeaponBuilder.new(12, "Hacha Giratoria", "🪓", "ranged"), 9.0, 1.0, 20.0, 10.0),
			
		WeaponType.ELEMENTS_CYCLE: WeaponDirector.construct_ranged(
				WeaponBuilder.new(13, "Ciclo Elemental", "🔮", "ranged"), 7.0, 0.6, 22.0),
			
		WeaponType.ZOMBIE_ARM: WeaponDirector.construct_ranged(
				WeaponBuilder.new(14, "Brazo Bumerán", "🧟", "ranged"), 18.0, 0.8, 20.0),
	}
	return table
## ---------------------------------------------

## ── Balance global (afinar aquí) ─────────────────────────────────────────────
## Las armas empiezan más débiles y lentas para que las mejoras por nivel importen.
const BASE_COOLDOWN_MULT := 1.5      ## ×1.5 tiempo entre ataques
const BASE_DAMAGE_MULT := 0.85       ## -15 % de daño base
const PROJECTILE_SPEED_MULT := 0.65  ## proyectiles un 35 % más lentos
const MIN_PROJECTILE_SPEED := 8.0    ## ningún proyectil baja de esta velocidad
## Armas de fuego continuo (ticks muy rápidos, p. ej. el lanzallamas) no se ralentizan
## ni se debilitan: su balance es por ticks, no por golpe.
const CONTINUOUS_COOLDOWN := 0.25

static func _apply_balance(table: Dictionary) -> void:
	for key in table:
		var d: WeaponData = table[key]
		if d.base_cooldown >= CONTINUOUS_COOLDOWN:
			d.base_cooldown *= BASE_COOLDOWN_MULT
			if d.heavy_cooldown > 0.0:
				d.heavy_cooldown *= BASE_COOLDOWN_MULT
			d.base_damage *= BASE_DAMAGE_MULT
			if d.heavy_damage > 0.0:
				d.heavy_damage *= BASE_DAMAGE_MULT
		if d.projectile_speed > 0.0:
			d.projectile_speed = maxf(d.projectile_speed * PROJECTILE_SPEED_MULT, MIN_PROJECTILE_SPEED)

## --- APLICACIÓN DEL PATRÓN PROTOTYPE ---
## Operación clone() del Prototype: copia independiente de la ficha (todos los campos son @export).
func clone() -> WeaponData:
	return duplicate() as WeaponData

static func get_weapon_table() -> Dictionary:
	if _weapon_table_cache.is_empty():
		# Los prototipos construidos quedan intactos en el registro; la tabla de juego son clones balanceados.
		WeaponPrototypeRegistry.register_all(_build_weapon_table())
		for key in WeaponType.values():
			if WeaponPrototypeRegistry.has_prototype(key):
				_weapon_table_cache[key] = WeaponPrototypeRegistry.clone_of(key)
		_apply_balance(_weapon_table_cache)
	return _weapon_table_cache

## Devuelve la ficha del arma; ante un id desconocido, cae a la espada.
static func get_weapon_data(weapon_type: int) -> WeaponData:
	return get_weapon_table().get(weapon_type, get_weapon_table()[WeaponType.ENERGY_SWORD])

## Nombre por arma (UI / HUD / señales).
static var weapon_names: Dictionary = {
	WeaponType.ENERGY_SWORD: "Espada de Energía",
	WeaponType.TRI_SHOTGUN: "Escopeta Triple",
	WeaponType.RAILGUN: "Cañón Railgun",
	WeaponType.SPEAR_LANCE: "Espalanza de Mikeura",
	WeaponType.FLAME_THROWER: "Lanzallamas",
	WeaponType.SPORE_BAZOOKA: "Bazuca de Esporas",
	WeaponType.DUSTS: "Polvos Alquímicos",
	WeaponType.SERPENTS: "Espíritus de Joel",
	WeaponType.SPINNING_AXE: "Hacha Giratoria",
	WeaponType.ELEMENTS_CYCLE: "Ciclo Elemental",
	WeaponType.ZOMBIE_ARM: "Brazo Bumerán",
}

## Icono por arma (HUD / señales).
static var weapon_icons: Dictionary = {
	WeaponType.ENERGY_SWORD: "🗡️",
	WeaponType.TRI_SHOTGUN: "💥",
	WeaponType.RAILGUN: "🔮",
	WeaponType.SPEAR_LANCE: "🔱",
	WeaponType.FLAME_THROWER: "🔥",
	WeaponType.SPORE_BAZOOKA: "🍄",
	WeaponType.DUSTS: "🧪",
	WeaponType.SERPENTS: "🦎",
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
