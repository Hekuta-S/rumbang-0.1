class_name MetaShop
extends RefCounted

## Tienda de mejoras permanentes (Salón > MEJORAS): se pagan con el oro acumulado entre partidas
## (SaveManager.total_gold) y afectan a TODAS las partidas de supervivencia.
##  - Las que tienen "stat" suman a PlayerStatBlock (daño, imán, suerte, XP, oro) vía stat_total().
##  - "vigor" suma vida máxima al empezar (apply_run_start).
##  - relanzar / descartar suman usos de cartas (GameState.reset_session).
##  - revivir: levantarse una vez con la mitad de la vida (GameState.try_revive).
## Los niveles se guardan en SaveManager.upgrades["ms_<id>"].

const ITEMS := {
	"poder": {"name": "Poder", "desc": "+3% de daño", "stat": "damage", "per": 0.03, "max": 10, "base": 250, "growth": 1.35},
	"vigor": {"name": "Vigor", "desc": "+10 de vida máxima", "stat": "", "per": 10.0, "max": 10, "base": 200, "growth": 1.30},
	"iman": {"name": "Imán", "desc": "+1,5 m para atraer gemas", "stat": "magnet", "per": 1.5, "max": 6, "base": 150, "growth": 1.40},
	"suerte": {"name": "Suerte", "desc": "+3% de suerte (cartas y cofres)", "stat": "luck", "per": 0.03, "max": 8, "base": 300, "growth": 1.40},
	"saber": {"name": "Saber", "desc": "+4% de XP", "stat": "xp", "per": 0.04, "max": 10, "base": 250, "growth": 1.35},
	"avaricia": {"name": "Avaricia", "desc": "+5% de oro", "stat": "gold", "per": 0.05, "max": 10, "base": 200, "growth": 1.30},
	"relanzar": {"name": "Relanzar", "desc": "+1 volver a tirar por partida", "stat": "", "per": 1.0, "max": 3, "base": 800, "growth": 1.80},
	"descarte": {"name": "Descarte", "desc": "+1 descartar por partida", "stat": "", "per": 1.0, "max": 3, "base": 800, "growth": 1.80},
	"revivir": {"name": "Segunda vida", "desc": "Te levantas una vez con la mitad de la vida", "stat": "", "per": 1.0, "max": 2, "base": 2000, "growth": 2.50},
}

static func key(id: String) -> String:
	return "ms_" + id

static func level(id: String) -> int:
	return int(SaveManager.upgrades.get(key(id), 0))

static func max_level(id: String) -> int:
	return int(ITEMS[id]["max"])

## Precio del siguiente nivel (redondeado a 10); -1 si ya está al máximo.
static func cost(id: String) -> int:
	var lvl := level(id)
	if lvl >= max_level(id):
		return -1
	return int(round(float(ITEMS[id]["base"]) * pow(float(ITEMS[id]["growth"]), lvl) / 10.0)) * 10

static func can_buy(id: String) -> bool:
	var c := cost(id)
	return c > 0 and SaveManager.total_gold >= c

static func buy(id: String) -> bool:
	if not can_buy(id):
		return false
	SaveManager.total_gold -= cost(id)
	SaveManager.upgrades[key(id)] = level(id) + 1
	SaveManager.save()
	return true

## Valor total de una mejora (nivel x valor por nivel).
static func value(id: String) -> float:
	return float(level(id)) * float(ITEMS[id]["per"])

## Suma de una estadística de PlayerStatBlock (solo supervivencia).
static func stat_total(stat: String) -> float:
	if GameData.game_mode != "survival":
		return 0.0
	var total := 0.0
	for id in ITEMS:
		if String(ITEMS[id]["stat"]) == stat:
			total += value(id)
	return total

static func bonus_rerolls() -> int:
	return level("relanzar")

static func bonus_banishes() -> int:
	return level("descarte")

static func revives() -> int:
	return level("revivir")

## Al empezar una partida de supervivencia: vida de Vigor y retos, tomo inicial del personaje y revivir.
static func apply_run_start(player: Node) -> void:
	if GameData.game_mode != "survival" or player == null:
		return
	var hp_bonus := value("vigor")
	player.max_hp = (float(player.max_hp) + hp_bonus) * RunModifiers.player_hp_mult()
	player.hp = player.max_hp
	var hc: Node = player.get("health_comp")
	if hc and hc.has_method("_emit_stats"):
		hc._emit_stats()
	var sb = player.get("stat_block")
	var tome := GameData.start_tome()
	if sb != null and tome != "":
		sb.add_tome(tome, TomeDB.Rarity.COMMON)
	GameState.get_instance().revives_left = revives()
