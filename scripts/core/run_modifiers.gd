class_name RunModifiers
extends RefCounted

## Dificultad (5 niveles) y retos de la partida de supervivencia. Se eligen en el menú de JUGAR y se
## guardan en SaveManager.meta ("difficulty", "challenge"). Más dificultad = enemigos más duros y
## más oro. Vencer al Nigromante en un nivel desbloquea el siguiente ("diff_unlocked").
## Fuera de supervivencia todo devuelve el valor neutro.

const MAX_LEVEL := 4
## hp/damage: multiplican la vida y el daño de los enemigos · spawn: multiplica el intervalo entre
## lotes (menos = más enemigos) · gold: multiplica el oro obtenido.
const DIFFICULTIES := [
	{"name": "NORMAL", "hp": 1.0, "damage": 1.0, "spawn": 1.0, "gold": 1.0},
	{"name": "DIFICIL", "hp": 1.2, "damage": 1.15, "spawn": 0.9, "gold": 1.25},
	{"name": "BRUTAL", "hp": 1.45, "damage": 1.3, "spawn": 0.8, "gold": 1.5},
	{"name": "INFERNAL", "hp": 1.75, "damage": 1.5, "spawn": 0.7, "gold": 1.9},
	{"name": "RUMBANG", "hp": 2.1, "damage": 1.75, "spawn": 0.6, "gold": 2.5},
]
## player_hp: multiplica la vida del jugador · xp/gold: multiplican XP y oro · spawn: como arriba.
const CHALLENGES := {
	"": {"name": "NINGUNO", "desc": "", "player_hp": 1.0, "spawn": 1.0, "gold": 1.0, "xp": 1.0},
	"cristal": {"name": "CRISTAL", "desc": "La mitad de vida. Oro x1,5", "player_hp": 0.5, "spawn": 1.0, "gold": 1.5, "xp": 1.0},
	"horda": {"name": "HORDA", "desc": "30% más enemigos. XP x1,3 y oro x1,2", "player_hp": 1.0, "spawn": 0.7, "gold": 1.2, "xp": 1.3},
}

static func _active() -> bool:
	return GameData.game_mode == "survival"

static func unlocked_max() -> int:
	return clampi(int(SaveManager.meta.get("diff_unlocked", 0)), 0, MAX_LEVEL)

static func difficulty() -> int:
	return clampi(int(SaveManager.meta.get("difficulty", 0)), 0, unlocked_max())

static func set_difficulty(level: int) -> void:
	SaveManager.meta["difficulty"] = clampi(level, 0, unlocked_max())
	SaveManager.save()

static func difficulty_name() -> String:
	return String(DIFFICULTIES[difficulty()]["name"])

static func challenge() -> String:
	var c := String(SaveManager.meta.get("challenge", ""))
	return c if CHALLENGES.has(c) else ""

static func set_challenge(id: String) -> void:
	SaveManager.meta["challenge"] = id if CHALLENGES.has(id) else ""
	SaveManager.save()

## Siguiente dificultad / reto al pulsar el botón del menú (da la vuelta).
static func cycle_difficulty() -> void:
	set_difficulty((difficulty() + 1) % (unlocked_max() + 1))

static func cycle_challenge() -> void:
	var ids: Array = CHALLENGES.keys()
	set_challenge(ids[(ids.find(challenge()) + 1) % ids.size()])

static func enemy_hp_mult() -> float:
	return float(DIFFICULTIES[difficulty()]["hp"]) if _active() else 1.0

static func enemy_damage_mult() -> float:
	return float(DIFFICULTIES[difficulty()]["damage"]) if _active() else 1.0

static func spawn_interval_mult() -> float:
	if not _active():
		return 1.0
	return float(DIFFICULTIES[difficulty()]["spawn"]) * float(CHALLENGES[challenge()]["spawn"])

static func gold_mult() -> float:
	if not _active():
		return 1.0
	return float(DIFFICULTIES[difficulty()]["gold"]) * float(CHALLENGES[challenge()]["gold"])

static func xp_mult() -> float:
	return float(CHALLENGES[challenge()]["xp"]) if _active() else 1.0

static func player_hp_mult() -> float:
	return float(CHALLENGES[challenge()]["player_hp"]) if _active() else 1.0

## Victoria sobre el Nigromante: desbloquea la dificultad siguiente.
static func record_clear() -> void:
	var next := mini(difficulty() + 1, MAX_LEVEL)
	if next > unlocked_max():
		SaveManager.meta["diff_unlocked"] = next
		SaveManager.save()
