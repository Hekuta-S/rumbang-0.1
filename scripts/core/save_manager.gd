## SaveManager.gd — Autoload Singleton
## Persists progression to user://soul_knight_save.json:
## - best floor reached per character id
## - total gold collected across runs
## - meta: contadores, logros y códice de evoluciones (ver MetaProgress)
extends Node

const SAVE_PATH := "user://soul_knight_save.json"

## Las pruebas lo cambian para no tocar la partida guardada del jugador.
var save_path := SAVE_PATH
var best_floors: Dictionary = {}
var upgrades: Dictionary = {}
var total_gold: int = 0
var meta: Dictionary = {}
## Historia: el Nigromante raptó al mago en la intro. Hasta rescatarlo (jaula de Supervivencia) las
## mazmorras siguen cerradas. Un save viejo sin esta clave cuenta como rescatado: no bloquea a quien ya jugó.
var mago_rescatado := false
## Prisioneros de la mazmorra liberados (mundo -> true; ver WorldDefs "prisoner" y DungeonPrisoner). Cada uno
## abre una estación del salón. Un save viejo sin esta clave los cuenta todos liberados (no quita lo que ya había).
var prisoners: Dictionary = {}

signal mago_rescatado_changed(value: bool)

func _ready() -> void:
	load_save()

func load_save() -> void:
	best_floors = {}
	upgrades = {}
	total_gold = 0
	meta = {}
	mago_rescatado = false
	prisoners = {}
	if not FileAccess.file_exists(save_path):
		return
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		var data: Dictionary = parsed
		if data.get("best_floors") is Dictionary:
			var floors: Dictionary = data["best_floors"]
			for key in floors:
				if floors[key] is int:
					best_floors[str(key)] = floors[key]
		if data.get("upgrades") is Dictionary:
			var upgs: Dictionary = data["upgrades"]
			for key in upgs:
				if upgs[key] is float or upgs[key] is int:
					upgrades[str(key)] = int(upgs[key])
		if data.get("total_gold") is int or data.get("total_gold") is float:
			total_gold = int(data["total_gold"])
		mago_rescatado = bool(data.get("mago_rescatado", true))
		if data.get("prisoners") is Dictionary:
			for w in data["prisoners"]:
				if bool(data["prisoners"][w]):
					prisoners[str(w)] = true
		else:
			for w in WorldDefs.ORDER:
				prisoners[w] = true
		if data.get("meta") is Dictionary:
			meta = data["meta"]
			# JSON devuelve los números como float: los ids de las evoluciones vuelven a int
			meta["evolutions"] = (meta.get("evolutions", []) as Array).map(func(w): return int(w))

func save() -> void:
	_gold_dirty = false
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		return
	var payload := {
		"best_floors": best_floors,
		"upgrades": upgrades,
		"total_gold": total_gold,
		"meta": meta,
		"mago_rescatado": mago_rescatado,
		"prisoners": prisoners,
	}
	file.store_string(JSON.stringify(payload))

## Registers a reached floor for a character (only keeps the best).
func set_best_floor(char_id: String, floor_num: int) -> void:
	if floor_num <= 0:
		return
	var current: int = best_floors.get(char_id, 0)
	if floor_num > current:
		best_floors[str(char_id)] = floor_num
		save()

func get_best_floor(char_id: String) -> int:
	return best_floors.get(char_id, 0)

func get_upgrade(weapon_id: String) -> int:
	return upgrades.get(weapon_id, 0)

func buy_upgrade(weapon_id: String, cost: int) -> bool:
	var current = get_upgrade(weapon_id)
	if current >= 5: return false
	if total_gold >= cost:
		total_gold -= cost
		upgrades[str(weapon_id)] = current + 1
		save()
		return true
	return false

## Cada baja suma oro: escribir el archivo en cada una (decenas por frame en una oleada) daba tirones,
## sobre todo en el móvil. El oro se guarda agrupado, como mucho cada GOLD_SAVE_DELAY s, y siempre
## al salir o al pasar la app a segundo plano (ver _notification).
const GOLD_SAVE_DELAY := 3.0
var _gold_dirty := false

func add_gold(amount: int) -> void:
	if amount <= 0:
		return
	total_gold += amount
	if _gold_dirty:
		return
	_gold_dirty = true
	if is_inside_tree():
		get_tree().create_timer(GOLD_SAVE_DELAY, true, false, true).timeout.connect(_flush_gold)
	else:
		save()

func _flush_gold() -> void:
	if _gold_dirty:
		save()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED \
			or what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_PREDELETE:
		_flush_gold()

## Mazmorra abierta solo con el mago rescatado.
func dungeon_unlocked() -> bool:
	return mago_rescatado

func prisoner_free(world: String) -> bool:
	return prisoners.has(world)

func free_prisoner(world: String) -> void:
	if prisoners.has(world):
		return
	prisoners[world] = true
	save()

func set_mago_rescatado(value: bool) -> void:
	if mago_rescatado == value:
		return
	mago_rescatado = value
	save()
	mago_rescatado_changed.emit(value)

func get_total_gold() -> int:
	return total_gold