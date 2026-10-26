class_name WeaponUpgrades
extends RefCounted

## Mejoras ESPECÍFICAS por arma. Cada arma define su propia lista; las armas
## sin lista usan la tabla genérica de PlayerWeaponInventory (por nivel de arma).
##
## Cada mejora: {id, name, desc, max_level, effect: {key, per_level, kind}}
##   key  : "damage" | "size" | "quantity_bonus" | "lifesteal" | "cooldown"
##   kind : "add" (suma per_level × nivel) | "mul" (multiplica per_level ^ nivel)
## PlayerWeaponInventory.get_weapon_modifiers() las combina en un único
## diccionario que ya consumen las estrategias de arma.

const MIN_COOLDOWN_MULT := 0.3

const TABLE := {
	WeaponData.WeaponType.SPEAR_LANCE: [
		{"id": "blade_count", "name": "Hoja extra", "max_level": 7,
			"desc": "+1 corte (máx. 8 en total)",
			"effect": {"key": "quantity_bonus", "per_level": 1.0, "kind": "add"}},
		{"id": "attack_speed", "name": "Filo veloz", "max_level": 5,
			"desc": "-10% enfriamiento del ataque",
			"effect": {"key": "cooldown", "per_level": 0.9, "kind": "mul"}},
		{"id": "size", "name": "Corte amplio", "max_level": 5,
			"desc": "+15% tamaño del corte",
			"effect": {"key": "size", "per_level": 0.15, "kind": "add"}},
		{"id": "damage", "name": "Filo templado", "max_level": 5,
			"desc": "+15% daño",
			"effect": {"key": "damage", "per_level": 0.15, "kind": "add"}},
		{"id": "lifesteal", "name": "Sed de vida", "max_level": 5,
			"desc": "+2% del daño infligido se convierte en vida",
			"effect": {"key": "lifesteal", "per_level": 0.02, "kind": "add"}},
	],
}

## Mejoras del Brazo Bumerán (Heckler); for_weapon()/has_specific() las exponen igual que TABLE.
const ZOMBIE_ARM_UPGRADES := [
	{"id": "arm_count", "name": "Brazo extra", "max_level": 4,
		"desc": "+1 brazo por lanzamiento (máx. 5, en abanico)",
		"effect": {"key": "quantity_bonus", "per_level": 1.0, "kind": "add"}},
	{"id": "attack_speed", "name": "Reflejos de ultratumba", "max_level": 5,
		"desc": "-10% enfriamiento del lanzamiento",
		"effect": {"key": "cooldown", "per_level": 0.9, "kind": "mul"}},
	{"id": "size", "name": "Brazo colosal", "max_level": 5,
		"desc": "+15% tamaño del brazo y su estela",
		"effect": {"key": "size", "per_level": 0.15, "kind": "add"}},
	{"id": "range", "name": "Largo alcance", "max_level": 5,
		"desc": "+12% distancia del lanzamiento",
		"effect": {"key": "range", "per_level": 0.12, "kind": "add"}},
	{"id": "damage", "name": "Mordida podrida", "max_level": 5,
		"desc": "+15% daño",
		"effect": {"key": "damage", "per_level": 0.15, "kind": "add"}},
	{"id": "lifesteal", "name": "Sed de vida", "max_level": 5,
		"desc": "+2% del daño infligido se convierte en vida",
		"effect": {"key": "lifesteal", "per_level": 0.02, "kind": "add"}},
]

## Mejoras del Hacha Giratoria (Riva): daño, tiempo girando en el sitio, tamaño y cantidad de hachas.
const SPINNING_AXE_UPGRADES := [
	{"id": "damage", "name": "Filo giratorio", "max_level": 5,
		"desc": "+15% daño",
		"effect": {"key": "damage", "per_level": 0.15, "kind": "add"}},
	{"id": "spin_time", "name": "Giro prolongado", "max_level": 5,
		"desc": "+20% tiempo girando en el sitio",
		"effect": {"key": "duration", "per_level": 0.20, "kind": "add"}},
	{"id": "size", "name": "Hacha colosal", "max_level": 5,
		"desc": "+15% tamaño del hacha y su área de giro",
		"effect": {"key": "size", "per_level": 0.15, "kind": "add"}},
	{"id": "axe_count", "name": "Hacha extra", "max_level": 4,
		"desc": "+1 hacha por lanzamiento (máx. 5, en abanico)",
		"effect": {"key": "quantity_bonus", "per_level": 1.0, "kind": "add"}},
]

## Mejoras del Ciclo Elemental (Saimon). Empieza con 4 orbes (fuego, agua, planta y tierra).
## "Nuevo elemento" desbloquea hielo y luego viento (con su orbe); "Nuevo orbe" es ilimitado y
## añade un orbe de un elemento desbloqueado al azar. ElementalOrbs sincroniza los orbes con estos niveles.
const UNLIMITED := 9999
const ELEMENTS_CYCLE_UPGRADES := [
	{"id": "damage", "name": "Poder elemental", "max_level": 5,
		"desc": "+15% daño de los orbes",
		"effect": {"key": "damage", "per_level": 0.15, "kind": "add"}},
	{"id": "orb_speed", "name": "Órbita veloz", "max_level": 5,
		"desc": "+15% velocidad de giro de los orbes",
		"effect": {"key": "orbit_speed", "per_level": 0.15, "kind": "add"}},
	{"id": "new_element", "name": "Nuevo elemento", "max_level": 2,
		"desc": "Desbloquea un elemento (hielo, luego viento) y su orbe",
		"effect": {"key": "element_unlock", "per_level": 1.0, "kind": "add"}},
	{"id": "new_orb", "name": "Nuevo orbe", "max_level": UNLIMITED,
		"desc": "+1 orbe de un elemento desbloqueado al azar",
		"effect": {"key": "orb_extra", "per_level": 1.0, "kind": "add"}},
]

## "3/5" o "3" cuando la mejora no tiene tope.
static func level_label(def: Dictionary, lvl: int) -> String:
	return str(lvl) if int(def["max_level"]) >= UNLIMITED else "%d/%d" % [lvl, int(def["max_level"])]

## Mejoras del Lanzallamas (Vangry). Dispara en ráfagas continuas: tras BURST_BASE_S segundos
## se recalienta y descansa un momento; "Ráfaga prolongada" alarga ese tiempo de fuego.
const FLAME_THROWER_UPGRADES := [
	{"id": "damage", "name": "Combustible concentrado", "max_level": 5,
		"desc": "+15% daño por tick",
		"effect": {"key": "damage", "per_level": 0.15, "kind": "add"}},
	{"id": "burst_duration", "name": "Ráfaga prolongada", "max_level": 5,
		"desc": "+25% duración de la ráfaga de fuego antes de recalentarse",
		"effect": {"key": "burst_time", "per_level": 0.25, "kind": "add"}},
	{"id": "size", "name": "Llamarada ancha", "max_level": 5,
		"desc": "+15% tamaño y alcance del fuego",
		"effect": {"key": "size", "per_level": 0.15, "kind": "add"}},
]

## Mejoras del Bazuca de Esporas (Bronch): una explosión enorme y muy lenta de recargar.
const SPORE_BAZOOKA_UPGRADES := [
	{"id": "size", "name": "Esporas colosales", "max_level": 5,
		"desc": "+15% tamaño de la explosión, la nube y el proyectil",
		"effect": {"key": "size", "per_level": 0.15, "kind": "add"}},
	{"id": "damage", "name": "Esporas virulentas", "max_level": 5,
		"desc": "+20% daño de la explosión y la nube",
		"effect": {"key": "damage", "per_level": 0.20, "kind": "add"}},
	{"id": "projectile_count", "name": "Racimo de esporas", "max_level": 4,
		"desc": "+1 proyectil por disparo (máx. 5, en abanico)",
		"effect": {"key": "quantity_bonus", "per_level": 1.0, "kind": "add"}},
]

## Mejoras de los Polvos Alquímicos (Tatan). Afectan al polvo arcano (explosión);
## "slow" es la fracción de velocidad que pierden los enemigos alcanzados.
const DUSTS_UPGRADES := [
	{"id": "blast_radius", "name": "Polvo expansivo", "max_level": 5,
		"desc": "+15% rango de la explosión",
		"effect": {"key": "size", "per_level": 0.15, "kind": "add"}},
	{"id": "damage", "name": "Polvo corrosivo", "max_level": 5,
		"desc": "+20% daño de la explosión",
		"effect": {"key": "damage", "per_level": 0.20, "kind": "add"}},
	{"id": "dust_count", "name": "Polvazo extra", "max_level": 3,
		"desc": "+1 polvazo por lanzamiento (máx. 4, en abanico)",
		"effect": {"key": "quantity_bonus", "per_level": 1.0, "kind": "add"}},
	{"id": "slow", "name": "Polvo viscoso", "max_level": 4,
		"desc": "Ralentiza a los enemigos alcanzados 3 s (-12% velocidad por nivel)",
		"effect": {"key": "slow", "per_level": 0.12, "kind": "add"}},
]

## Espíritus de Joel. Empieza con un animal al azar; "Nuevo espíritu" desbloquea otro al azar.
## Cada animal mejora por separado (daño + tamaño + recarga, con valores distintos según el animal;
## ver SerpentsStrategy.SPIRIT_PER_LEVEL). "spirit" = 0 Komodo, 1 Búho, 2 Hipopótamo: la mejora
## solo aparece cuando Joel ya tiene ese animal.
const SERPENTS_UPGRADES := [
	{"id": "spirit_unlock", "name": "Nuevo espíritu", "max_level": 2,
		"desc": "Desbloquea otro animal espiritual al azar",
		"effect": {"key": "spirit_unlock", "per_level": 1.0, "kind": "add"}},
	{"id": "komodo_up", "name": "Dragón de Komodo", "max_level": 5, "spirit": 0,
		"desc": "+12% daño, +8% tamaño, recarga -6%",
		"effect": {"key": "komodo_lvl", "per_level": 1.0, "kind": "add"}},
	{"id": "owl_up", "name": "Búho espiritual", "max_level": 5, "spirit": 1,
		"desc": "+8% daño, +6% tamaño, recarga -10% (rápido)",
		"effect": {"key": "owl_lvl", "per_level": 1.0, "kind": "add"}},
	{"id": "hippo_up", "name": "Hipopótamo espiritual", "max_level": 5, "spirit": 2,
		"desc": "+20% daño, +10% tamaño, recarga -4% (lento, muy fuerte)",
		"effect": {"key": "hippo_lvl", "per_level": 1.0, "kind": "add"}},
]

## Mejoras de la Escopeta de Humo: perdigones (cantidad), daño por perdigón, tamaño
## (alcance + apertura del cono + humo) y retroceso (empuje a los enemigos golpeados).
const TRI_SHOTGUN_UPGRADES := [
	{"id": "pellets", "name": "Perdigón extra", "max_level": 5,
		"desc": "+1 perdigón por disparo (máx. 10)",
		"effect": {"key": "quantity_bonus", "per_level": 1.0, "kind": "add"}},
	{"id": "damage", "name": "Pólvora cargada", "max_level": 5,
		"desc": "+15% daño por perdigón",
		"effect": {"key": "damage", "per_level": 0.15, "kind": "add"}},
	{"id": "size", "name": "Cono ampliado", "max_level": 5,
		"desc": "+15% alcance y apertura del cono, más humo",
		"effect": {"key": "size", "per_level": 0.15, "kind": "add"}},
	{"id": "knockback", "name": "Culata de mula", "max_level": 5,
		"desc": "+40% retroceso: empuja más lejos a los enemigos",
		"effect": {"key": "knockback", "per_level": 0.40, "kind": "add"}},
]

static func has_specific(weapon_type: int) -> bool:
	return TABLE.has(weapon_type) or weapon_type in [
		WeaponData.WeaponType.ZOMBIE_ARM, WeaponData.WeaponType.FLAME_THROWER,
		WeaponData.WeaponType.SPORE_BAZOOKA, WeaponData.WeaponType.DUSTS, WeaponData.WeaponType.SERPENTS,
		WeaponData.WeaponType.TRI_SHOTGUN, WeaponData.WeaponType.SPINNING_AXE,
		WeaponData.WeaponType.ELEMENTS_CYCLE]

static func for_weapon(weapon_type: int) -> Array:
	match weapon_type:
		WeaponData.WeaponType.ZOMBIE_ARM:
			return ZOMBIE_ARM_UPGRADES
		WeaponData.WeaponType.FLAME_THROWER:
			return FLAME_THROWER_UPGRADES
		WeaponData.WeaponType.SPORE_BAZOOKA:
			return SPORE_BAZOOKA_UPGRADES
		WeaponData.WeaponType.DUSTS:
			return DUSTS_UPGRADES
		WeaponData.WeaponType.SERPENTS:
			return SERPENTS_UPGRADES
		WeaponData.WeaponType.TRI_SHOTGUN:
			return TRI_SHOTGUN_UPGRADES
		WeaponData.WeaponType.SPINNING_AXE:
			return SPINNING_AXE_UPGRADES
		WeaponData.WeaponType.ELEMENTS_CYCLE:
			return ELEMENTS_CYCLE_UPGRADES
	return TABLE.get(weapon_type, [])

static func get_def(weapon_type: int, upgrade_id: String) -> Dictionary:
	for d in for_weapon(weapon_type):
		if d["id"] == upgrade_id:
			return d
	return {}

## Aplica los niveles {upgrade_id: nivel} sobre `mods` (en el sitio).
static func apply(weapon_type: int, levels: Dictionary, mods: Dictionary) -> void:
	for d in for_weapon(weapon_type):
		var lvl: int = int(levels.get(d["id"], 0))
		if lvl <= 0:
			continue
		var eff: Dictionary = d["effect"]
		var key: String = eff["key"]
		var per: float = float(eff["per_level"])
		if eff["kind"] == "mul":
			mods[key] = float(mods.get(key, 1.0)) * pow(per, lvl)
		else:
			mods[key] = mods.get(key, 0.0) + per * lvl
	if mods.has("cooldown"):
		mods["cooldown"] = maxf(float(mods["cooldown"]), MIN_COOLDOWN_MULT)
