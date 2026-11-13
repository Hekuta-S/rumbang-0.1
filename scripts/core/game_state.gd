class_name GameState extends RefCounted

## --- APLICACIÓN DEL PATRÓN SINGLETON ---
## Mantiene el estado de la partida actual sin necesidad de ser un Nodo en el SceneTree.

static var _instance: GameState = null

static func get_instance() -> GameState:
	if _instance == null:
		_instance = GameState.new()
	return _instance

var sub_level: int = 1
var gold: int = 0
var elapsed_time: float = 0.0

## Cartas de mejora (UpgradeChoiceUI): usos que quedan en la partida, cartas descartadas
## ("tipo:id", no vuelven a salir) y la carta bloqueada para la siguiente subida de nivel.
const CARD_REROLLS := 3
const CARD_BANISHES := 2
var card_rerolls: int = CARD_REROLLS
var card_banishes: int = CARD_BANISHES
var banished_cards: Array = []
var locked_card: Dictionary = {}
## Runas de la mazmorra: {id: nivel} (ver DungeonRunes).
var runes: Dictionary = {}
## Estructura de partida de la mazmorra (ver DungeonRun): enfoques {id: nivel}, calor, maldición.
var focus: Dictionary = {}
var heat: int = 0
var curse_kills: int = 0
var second_wind_used := false
## Tomos de la partida de supervivencia: {id: {lvl, power}} (ver TomeDB).
var tomes: Dictionary = {}
## Segundas vidas que quedan (MetaShop "revivir"); las fija MetaShop.apply_run_start.
var revives_left: int = 0
## Garantía de botín (DungeonRun.PITY_*): bajas sin pieza de equipo y piezas seguidas sin una rara.
var pity_kills: int = 0
var pity_since_rare: int = 0

func reset_session() -> void:
	sub_level = 1
	gold = 0
	elapsed_time = 0.0
	card_rerolls = CARD_REROLLS + MetaProgress.bonus_rerolls() + MetaShop.bonus_rerolls()
	card_banishes = CARD_BANISHES + MetaProgress.bonus_banishes() + MetaShop.bonus_banishes()
	banished_cards.clear()
	locked_card = {}
	runes.clear()
	focus.clear()
	heat = 0
	curse_kills = 0
	second_wind_used = false
	tomes = {}
	revives_left = 0
	pity_kills = 0
	pity_since_rare = 0
	RunStats.reset()
	RunLog.reset()

func add_time(delta: float) -> void:
	elapsed_time += delta

func add_gold(amount: int) -> void:
	gold += amount

func advance_level() -> void:
	sub_level += 1
