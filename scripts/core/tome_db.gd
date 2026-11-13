class_name TomeDB
extends RefCounted

## Tomos del modo supervivencia (estilo Megabonk): 4 huecos de pasivos que suben con las cartas
## de subida de nivel, aparte de los 4 huecos de arma.
##  - Cada tomo suma estadísticas de PlayerStatBlock (mismas claves que ItemDB) por nivel,
##    multiplicadas por la rareza con que salió cada carta (poder acumulado, no solo nivel).
##  - El tomo de Suerte desplaza el sorteo de rareza hacia lo raro.
##  - Cada evolución de arma pide su tomo (WeaponSynergies.EVOLUTIONS["tome"]).
## El estado vive en GameState.tomes: {id: {"lvl": int, "power": float}} (se reinicia por partida).

const SLOTS := 4
const MAX_LEVEL := 8

enum Rarity { COMMON, RARE, EPIC, LEGENDARY }
const RARITY_NAME := ["COMÚN", "RARO", "ÉPICO", "LEGENDARIO"]
const RARITY_NAME_ASCII := ["COMUN", "RARO", "EPICO", "LEGENDARIO"]   ## la fuente pixel no tiene Ú/É en mayúscula
const RARITY_MULT := [1.0, 1.5, 2.0, 3.0]
const RARITY_WEIGHT := [60.0, 28.0, 10.0, 2.0]
const RARITY_COLOR := [Color(0.78, 0.8, 0.85), Color(0.35, 0.65, 1.0), Color(0.72, 0.4, 1.0), Color(1.0, 0.78, 0.2)]

## stats: clave de PlayerStatBlock -> valor por nivel (x rareza). "max_hp" es puntual (se suma al coger la carta).
const TOMES := {
	"poder": {"name": "Tomo de Poder", "icon": "💪", "desc": "+8% daño", "stats": {"damage": 0.08}},
	"celeridad": {"name": "Tomo de Celeridad", "icon": "⏱", "desc": "-5% enfriamiento", "stats": {"cooldown_reduction": 0.05}},
	"area": {"name": "Tomo de Área", "icon": "⭕", "desc": "+8% tamaño de ataques", "stats": {"melee_size": 0.08, "ranged_size": 0.08}},
	"multiplicidad": {"name": "Tomo de Multiplicidad", "icon": "✴", "desc": "+1 golpe/proyectil cada 2 niveles", "stats": {"extra_projectiles": 0.5, "melee_hits": 0.5}},
	"iman": {"name": "Tomo de Imán", "icon": "🧲", "desc": "+2 m de atracción de gemas", "stats": {"magnet": 2.0}},
	"vitalidad": {"name": "Tomo de Vitalidad", "icon": "❤", "desc": "+15 vida máxima", "stats": {"max_hp": 15.0}},
	"regeneracion": {"name": "Tomo de Regeneración", "icon": "✚", "desc": "+0,4 vida/s", "stats": {"hp_regen": 0.4}},
	"armadura": {"name": "Tomo de Armadura", "icon": "🛡", "desc": "-3% daño recibido", "stats": {"armor": 0.03}},
	"zancada": {"name": "Tomo de Zancada", "icon": "👟", "desc": "+5% velocidad", "stats": {"move_speed": 0.05}},
	"suerte": {"name": "Tomo de Suerte", "icon": "🍀", "desc": "+10% suerte: más cartas raras", "stats": {"luck": 0.10}},
	"avaricia": {"name": "Tomo de Avaricia", "icon": "💰", "desc": "+12% oro", "stats": {"gold": 0.12}},
	"saber": {"name": "Tomo de Saber", "icon": "📖", "desc": "+10% XP", "stats": {"xp": 0.10}},
}

static func ids() -> Array:
	return TOMES.keys()

static func tome_name(id: String) -> String:
	return String(TOMES.get(id, {}).get("name", "?"))

## Armas que evolucionan con este tomo (para la pista de la carta).
static func weapons_for(id: String) -> Array:
	var out: Array = []
	for w in WeaponSynergies.EVOLUTIONS:
		if String(WeaponSynergies.EVOLUTIONS[w].get("tome", "")) == id:
			out.append(w)
	return out

# ── Estado de la partida ────────────────────────────────────────────

static func owned() -> Dictionary:
	return GameState.get_instance().tomes

static func level(id: String) -> int:
	return int(owned().get(id, {}).get("lvl", 0))

static func slots_free() -> bool:
	return owned().size() < SLOTS

static func can_take(id: String) -> bool:
	if not TOMES.has(id):
		return false
	var lvl := level(id)
	if lvl >= MAX_LEVEL:
		return false
	return lvl > 0 or slots_free()

## Sube un nivel el tomo con la rareza de la carta.
static func add(id: String, rarity: int) -> void:
	if not can_take(id):
		return
	var t: Dictionary = owned().get(id, {"lvl": 0, "power": 0.0})
	t["lvl"] = int(t["lvl"]) + 1
	t["power"] = float(t["power"]) + float(RARITY_MULT[clampi(rarity, 0, 3)])
	owned()[id] = t

## Suma de una estadística de todos los tomos (lo lee PlayerStatBlock). "max_hp" no cuenta aquí.
static func stat_total(stat: String) -> float:
	if stat == "max_hp":
		return 0.0
	var total := 0.0
	var all := owned()
	for id in all:
		var per: Dictionary = TOMES[id]["stats"]
		if per.has(stat):
			total += float(per[stat]) * float(all[id]["power"])
	return total

## Vida máxima que da una carta de Vitalidad (puntual).
static func hp_gain(id: String, rarity: int) -> float:
	return float(TOMES[id]["stats"].get("max_hp", 0.0)) * float(RARITY_MULT[clampi(rarity, 0, 3)])

# ── Rareza ──────────────────────────────────────────────────────────

## Rareza al repartir una carta de tomo. `luck` (0.1 = +10 %) multiplica el peso de lo no común.
static func roll_rarity(luck: float = 0.0, rng: RandomNumberGenerator = null) -> int:
	var weights: Array = []
	var total := 0.0
	for i in 4:
		var w: float = RARITY_WEIGHT[i] * (1.0 if i == 0 else 1.0 + maxf(luck, 0.0) * 3.0)
		weights.append(w)
		total += w
	var roll := (rng.randf() if rng else randf()) * total
	for i in 4:
		roll -= weights[i]
		if roll <= 0.0:
			return i
	return 0

static func describe(id: String, rarity: int) -> String:
	var def: Dictionary = TOMES[id]
	return "%s (x%s)" % [def["desc"], str(RARITY_MULT[clampi(rarity, 0, 3)])]

# ── Tomos de la mazmorra (antes "runas") ────────────────────────────
## Mismo catálogo que los tomos de supervivencia, otra entrega: en la mazmorra salen en el portal, la
## forja y los desafíos, sin huecos ni rareza (valor fijo por nivel). Los tomos compartidos (poder,
## celeridad, area) reutilizan nombre e icono de TOMES; el resto solo existen aquí. NO entran en TOMES
## ni en ids(), así que las cartas de supervivencia no cambian. Los niveles viven en GameState.runes
## (se reinician con reset_session) y no cuentan para las evoluciones de arma.
## mods: se suman a los modificadores de arma (Player.get_weapon_modifiers); "cooldown" multiplica.
const DUNGEON_COLOR := Color(0.55, 0.85, 1.0)
const DUNGEON := {
	"poder": {"desc": "+15% daño", "max": 5, "mods": {"damage": 0.15}},
	"celeridad": {"desc": "-10% enfriamiento", "max": 4, "mods": {"cooldown": 0.9}},
	"area": {"desc": "+15% tamaño de los ataques", "max": 4, "mods": {"size": 0.15}},
	"vampirismo": {"name": "Tomo de Vampirismo", "icon": "🩸", "desc": "+3% del daño se convierte en vida", "max": 3, "mods": {"lifesteal": 0.03}},
	"quebranto": {"name": "Tomo del Quebranto", "icon": "💫", "desc": "+30% aguante que quitas a los enemigos", "max": 3},
	"verdugo": {"name": "Tomo del Verdugo", "icon": "⚔", "desc": "Los remates curan un 8% más", "max": 3},
}

static func dungeon_has(id: String) -> bool:
	return DUNGEON.has(id)

static func dungeon_name(id: String) -> String:
	var d: Dictionary = DUNGEON.get(id, {})
	return String(d.get("name", TOMES.get(id, {}).get("name", "?")))

static func dungeon_icon(id: String) -> String:
	var d: Dictionary = DUNGEON.get(id, {})
	return String(d.get("icon", TOMES.get(id, {}).get("icon", "")))

static func dungeon_level(id: String) -> int:
	return int(GameState.get_instance().runes.get(id, 0))

static func dungeon_can_add(id: String) -> bool:
	return DUNGEON.has(id) and dungeon_level(id) < int(DUNGEON[id]["max"])

static func dungeon_add(id: String) -> void:
	if dungeon_can_add(id):
		GameState.get_instance().runes[id] = dungeon_level(id) + 1

## `count` tomos al azar que aún se pueden subir.
static func dungeon_roll(count: int) -> Array:
	var pool: Array = DUNGEON.keys().filter(func(t): return dungeon_can_add(t))
	pool.shuffle()
	return pool.slice(0, count)

## Opción para DungeonChoiceUI.
static func dungeon_option(id: String, price: int = -1) -> Dictionary:
	var lv := dungeon_level(id)
	return {"id": id, "icon": dungeon_icon(id), "title": dungeon_name(id), "price": price, "color": DUNGEON_COLOR,
		"desc": "%s\nNivel %d → %d / %d" % [DUNGEON[id]["desc"], lv, lv + 1, int(DUNGEON[id]["max"])]}

static func dungeon_stun_mult() -> float:
	return (1.0 + 0.3 * dungeon_level("quebranto")) * DungeonRun.stun_mult()

static func dungeon_finisher_heal_bonus() -> float:
	return 0.08 * dungeon_level("verdugo")

## Suma los tomos de la mazmorra sobre `mods` (en el sitio). Solo en la mazmorra.
static func dungeon_apply(mods: Dictionary) -> void:
	if GameData.game_mode != "dungeon":
		return
	for id in GameState.get_instance().runes:
		var lv := dungeon_level(id)
		var t: Dictionary = DUNGEON.get(id, {})
		for k in t.get("mods", {}):
			var v := float(t["mods"][k])
			if k == "cooldown":
				mods[k] = maxf(float(mods.get(k, 1.0)) * pow(v, lv), WeaponUpgrades.MIN_COOLDOWN_MULT)
			else:
				mods[k] = float(mods.get(k, 0.0)) + v * lv
