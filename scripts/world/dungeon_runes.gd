class_name DungeonRunes
extends RefCounted

## Runas de la mazmorra: mejoras de la partida que valen para todas las armas (y algunas para el
## aturdimiento y los remates de la Fase 1). Se consiguen en los desafíos, en la forja (DungeonShop)
## y eligiendo el camino "Runa" en el portal. Se acumulan hasta max; viven en GameState.runes
## (se reinician con reset_session). Player.get_weapon_modifiers() aplica las de armas.

const RUNES := {
	"furia": {"name": "Runa de Furia", "icon": "🔥", "desc": "+15% daño", "max": 5, "mods": {"damage": 0.15}},
	"vendaval": {"name": "Runa del Vendaval", "icon": "🌪", "desc": "-10% enfriamiento", "max": 4, "mods": {"cooldown": 0.9}},
	"coloso": {"name": "Runa del Coloso", "icon": "⛰", "desc": "+15% tamaño de los ataques", "max": 4, "mods": {"size": 0.15}},
	"vampiro": {"name": "Runa Vampírica", "icon": "🩸", "desc": "+3% del daño se convierte en vida", "max": 3, "mods": {"lifesteal": 0.03}},
	"quebranto": {"name": "Runa del Quebranto", "icon": "💫", "desc": "+30% aguante que quitas a los enemigos", "max": 3},
	"verdugo": {"name": "Runa del Verdugo", "icon": "⚔", "desc": "Los remates curan un 8% más", "max": 3},
}
const COLOR := Color(0.55, 0.85, 1.0)

static func level(id: String) -> int:
	return int(GameState.get_instance().runes.get(id, 0))

static func can_add(id: String) -> bool:
	return RUNES.has(id) and level(id) < int(RUNES[id]["max"])

static func add(id: String) -> void:
	if can_add(id):
		GameState.get_instance().runes[id] = level(id) + 1

## `count` runas al azar que aún se pueden subir.
static func roll(count: int) -> Array:
	var pool: Array = RUNES.keys().filter(func(r): return can_add(r))
	pool.shuffle()
	return pool.slice(0, count)

## Opción para DungeonChoiceUI.
static func option(id: String, price: int = -1) -> Dictionary:
	var r: Dictionary = RUNES[id]
	return {"id": id, "icon": r["icon"], "title": r["name"], "price": price, "color": COLOR,
		"desc": "%s\nNivel %d → %d / %d" % [r["desc"], level(id), level(id) + 1, int(r["max"])]}

## Multiplicador del aguante que quitan los golpes (DungeonGoblin).
static func stun_mult() -> float:
	return 1.0 + 0.3 * level("quebranto")

## Vida extra (fracción de la máxima) que cura un remate (PlayerFinisherController).
static func finisher_heal_bonus() -> float:
	return 0.08 * level("verdugo")

## Suma las runas de armas sobre `mods` (en el sitio). Solo en la mazmorra.
static func apply(mods: Dictionary) -> void:
	if GameData.game_mode != "dungeon":
		return
	for id in GameState.get_instance().runes:
		var lv := level(id)
		var r: Dictionary = RUNES.get(id, {})
		for k in r.get("mods", {}):
			var v := float(r["mods"][k])
			if k == "cooldown":
				mods[k] = maxf(float(mods.get(k, 1.0)) * pow(v, lv), WeaponUpgrades.MIN_COOLDOWN_MULT)
			else:
				mods[k] = float(mods.get(k, 0.0)) + v * lv
