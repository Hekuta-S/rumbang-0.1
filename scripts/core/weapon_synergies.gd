class_name WeaponSynergies
extends RefCounted

## Sinergias y evoluciones de arma (modo supervivencia, al estilo Megabonk).
##  - Etiquetas: cada arma tiene 1 o 2 (TAGS). Con 2 armas de la misma etiqueta se activa el
##    primer bono de SYNERGIES para todas ellas; con 3 o más, también el segundo.
##  - Evolución: un arma de nivel EVOLVE_LEVEL o más (cada mejora sube un nivel) más su tomo
##    (TomeDB, campo "tome" de EVOLUTIONS) ofrece la carta "EVOLUCIÓN" (UpgradeChoiceUI). Al elegirla, el arma suma
##    los mods de EVOLUTIONS y cambia de nombre. Se guarda como la mejora "evolved" del arma en
##    PlayerWeaponInventory.weapon_upgrades, así que reset_progress() también la olvida.
## Player.get_weapon_modifiers() aplica ambas cosas encima de las mejoras propias del arma.
## Las claves de los mods son las mismas que devuelve PlayerWeaponInventory.get_weapon_modifiers.

const W := WeaponData.WeaponType
const EVOLVED_KEY := "evolved"
const EVOLVE_LEVEL := 8

const TAG_INFO := {
	"filo": {"name": "Filo", "icon": "⚔", "color": Color(0.85, 0.9, 1.0)},
	"fuego": {"name": "Fuego", "icon": "🔥", "color": Color(1.0, 0.5, 0.2)},
	"explosivo": {"name": "Explosivo", "icon": "💥", "color": Color(1.0, 0.8, 0.25)},
	"arcano": {"name": "Arcano", "icon": "🌀", "color": Color(0.7, 0.5, 1.0)},
	"naturaleza": {"name": "Naturaleza", "icon": "🌿", "color": Color(0.45, 1.0, 0.45)},
}

const TAGS := {
	W.ENERGY_SWORD: ["filo", "arcano"],
	W.TRI_SHOTGUN: ["explosivo"],
	W.RAILGUN: ["arcano"],
	W.SPEAR_LANCE: ["filo"],
	W.FLAME_THROWER: ["fuego"],
	W.SPORE_BAZOOKA: ["explosivo", "naturaleza"],
	W.DUSTS: ["explosivo", "arcano"],
	W.SERPENTS: ["naturaleza", "arcano"],
	W.SPINNING_AXE: ["filo"],
	W.ELEMENTS_CYCLE: ["arcano", "fuego"],
	W.ZOMBIE_ARM: ["filo", "naturaleza"],
	W.DAGGERS: ["filo"],
	W.MACE: ["arcano"],
	W.GREATSWORD: ["filo"],
	W.SWORD: ["filo"],
	W.KATANA: ["filo", "fuego"],
	W.BOW: ["filo", "naturaleza"],
}

## [bono con 2 armas, bono extra con 3 o más]. "add" en todas las claves (cooldown multiplica).
const SYNERGIES := {
	"filo": [{"damage": 0.15}, {"size": 0.2, "quantity_bonus": 1}],
	"fuego": [{"damage": 0.2}, {"size": 0.25, "burst_time": 0.3}],
	"explosivo": [{"size": 0.2}, {"damage": 0.25}],
	"arcano": [{"cooldown": 0.88}, {"damage": 0.2}],
	"naturaleza": [{"lifesteal": 0.03}, {"duration": 0.25, "size": 0.15}],
}
const SYNERGY_DESC := {
	"filo": ["+15% daño", "+20% tamaño y +1 golpe"],
	"fuego": ["+20% daño", "+25% tamaño y ráfagas más largas"],
	"explosivo": ["+20% tamaño", "+25% daño"],
	"arcano": ["-12% enfriamiento", "+20% daño"],
	"naturaleza": ["+3% robo de vida", "+25% duración y +15% tamaño"],
}

const EVOLUTIONS := {
	W.SPEAR_LANCE: {"tome": "zancada", "name": "Lanza del Trueno",
		"desc": "+60% daño, +30% tamaño, +2 cortes", "mods": {"damage": 0.6, "size": 0.3, "quantity_bonus": 2}},
	W.FLAME_THROWER: {"tome": "celeridad", "name": "Aliento de Dragón",
		"desc": "+50% daño, +40% alcance, ráfagas el doble de largas", "mods": {"damage": 0.5, "size": 0.4, "burst_time": 1.0}},
	W.SPORE_BAZOOKA: {"tome": "area", "name": "Hongo Atómico",
		"desc": "+60% daño y +50% tamaño de la explosión", "mods": {"damage": 0.6, "size": 0.5}},
	W.SPINNING_AXE: {"tome": "armadura", "name": "Torbellino de Acero",
		"desc": "+2 hachas, +60% tiempo girando, +25% tamaño", "mods": {"quantity_bonus": 2, "duration": 0.6, "size": 0.25}},
	W.TRI_SHOTGUN: {"tome": "multiplicidad", "name": "Trueno de Humo",
		"desc": "+4 perdigones, +30% daño, mucho más retroceso", "mods": {"quantity_bonus": 4, "damage": 0.3, "knockback": 1.0}},
	W.ZOMBIE_ARM: {"tome": "vitalidad", "name": "Mano de la Llorona",
		"desc": "+2 brazos, +50% daño, +6% robo de vida", "mods": {"quantity_bonus": 2, "damage": 0.5, "lifesteal": 0.06}},
	W.ELEMENTS_CYCLE: {"tome": "avaricia", "name": "Tormenta Elemental",
		"desc": "+2 orbes, +50% daño, giro +50% más rápido", "mods": {"orb_extra": 2, "damage": 0.5, "orbit_speed": 0.5}},
	W.DUSTS: {"tome": "saber", "name": "Polvo de Estrellas",
		"desc": "+50% daño, +40% radio, +1 polvazo", "mods": {"damage": 0.5, "size": 0.4, "quantity_bonus": 1}},
	W.SERPENTS: {"tome": "regeneracion", "name": "Guardianes Ancestrales",
		"desc": "+60% daño y +25% tamaño de los espíritus", "mods": {"damage": 0.6, "size": 0.25}},
	W.ENERGY_SWORD: {"tome": "poder", "name": "Espada Solar",
		"desc": "+70% daño, +30% tamaño", "mods": {"damage": 0.7, "size": 0.3}},
	W.RAILGUN: {"tome": "suerte", "name": "Cañón Celestial",
		"desc": "+60% daño, +2 perforaciones", "mods": {"damage": 0.6, "pierce_bonus": 2}},
}

static func tags_of(weapon: int) -> Array:
	return TAGS.get(weapon, [])

## Línea "⚔ Filo · 🌀 Arcano" para las cartas.
static func tags_label(weapon: int) -> String:
	var parts: Array = []
	for t in tags_of(weapon):
		parts.append("%s %s" % [TAG_INFO[t]["icon"], TAG_INFO[t]["name"]])
	return " · ".join(parts)

## {etiqueta: nº de armas equipadas con ella}
static func tag_counts(slots: Array) -> Dictionary:
	var out := {}
	for w in slots:
		for t in tags_of(w):
			out[t] = int(out.get(t, 0)) + 1
	return out

## Nivel de una sinergia: 0 (inactiva), 1 (2 armas) o 2 (3 o más).
static func tier(count: int) -> int:
	return 2 if count >= 3 else (1 if count >= 2 else 0)

## Sinergias activas: [{tag, count, tier}], de más a menos armas.
static func active(slots: Array) -> Array:
	var out: Array = []
	var counts := tag_counts(slots)
	for t in counts:
		if tier(counts[t]) > 0:
			out.append({"tag": t, "count": counts[t], "tier": tier(counts[t])})
	out.sort_custom(func(a, b): return a["count"] > b["count"])
	return out

## "⚔ Filo 2/3: +15% daño" de una sinergia activa.
static func describe(s: Dictionary) -> String:
	var t: String = s["tag"]
	var desc: Array = SYNERGY_DESC[t].slice(0, s["tier"])
	return "%s %s %d: %s" % [TAG_INFO[t]["icon"], TAG_INFO[t]["name"], s["count"], ", ".join(desc)]

## Qué sinergias sube equipar `weapon` además de `slots`: ["⚔ Filo → 2", ...] (para la carta).
static func preview_new_weapon(slots: Array, weapon: int) -> Array:
	var counts := tag_counts(slots)
	var out: Array = []
	for t in tags_of(weapon):
		var n := int(counts.get(t, 0)) + 1
		if tier(n) > tier(n - 1):
			out.append("%s %s ×%d: %s" % [TAG_INFO[t]["icon"], TAG_INFO[t]["name"], n, SYNERGY_DESC[t][tier(n) - 1]])
	return out

static func is_evolved(winv, weapon: int) -> bool:
	return winv != null and winv.get_upgrade_level(weapon, EVOLVED_KEY) > 0

## Nombre del arma, el de su evolución si ya evolucionó.
static func weapon_name(winv, weapon: int) -> String:
	if is_evolved(winv, weapon):
		return String(EVOLUTIONS[weapon]["name"])
	return String(WeaponData.weapon_names.get(weapon, "Arma"))

## true si el arma puede evolucionar ya: nivel suficiente, su tomo (cualquier nivel) y sin evolucionar.
static func can_evolve(winv, _items, weapon: int) -> bool:
	if not EVOLUTIONS.has(weapon) or winv == null or is_evolved(winv, weapon):
		return false
	if not winv.weapon_slots.has(weapon) or winv.get_weapon_level(weapon) < EVOLVE_LEVEL:
		return false
	return TomeDB.level(String(EVOLUTIONS[weapon]["tome"])) > 0

static func catalyst_name(weapon: int) -> String:
	if not EVOLUTIONS.has(weapon):
		return ""
	return TomeDB.tome_name(String(EVOLUTIONS[weapon]["tome"]))

static func evolve(winv, weapon: int) -> void:
	if not winv.weapon_upgrades.has(weapon):
		winv.weapon_upgrades[weapon] = {}
	winv.weapon_upgrades[weapon][EVOLVED_KEY] = 1

## Suma sinergias y evolución sobre `mods` (en el sitio). Solo en supervivencia: la mazmorra
## tiene su propio equilibrio (y no hay cartas de mejora).
static func apply(winv, weapon: int, mods: Dictionary) -> void:
	if winv == null or GameData.game_mode == "dungeon":
		return
	var counts := tag_counts(winv.weapon_slots)
	for t in tags_of(weapon):
		for i in tier(int(counts.get(t, 0))):
			_add(mods, SYNERGIES[t][i])
	if is_evolved(winv, weapon):
		_add(mods, EVOLUTIONS[weapon]["mods"])
	if mods.has("cooldown"):
		mods["cooldown"] = maxf(float(mods["cooldown"]), WeaponUpgrades.MIN_COOLDOWN_MULT)

static func _add(mods: Dictionary, bonus: Dictionary) -> void:
	for k in bonus:
		if k == "cooldown":
			mods[k] = float(mods.get(k, 1.0)) * float(bonus[k])
		elif k == "quantity_bonus" or k == "pierce_bonus" or k == "orb_extra":
			mods[k] = int(mods.get(k, 0)) + int(bonus[k])
		else:
			mods[k] = float(mods.get(k, 0.0)) + float(bonus[k])
