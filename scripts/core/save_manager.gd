## SaveManager.gd — Autoload Singleton
## Persists progression to user://soul_knight_save.json:
## - best floor reached per character id
## - total gold collected across runs
extends Node

const SAVE_PATH := "user://soul_knight_save.json"

var best_floors: Dictionary = {}
var total_gold: int = 0

func _ready() -> void:
	load_save()

func load_save() -> void:
	best_floors = {}
	total_gold = 0
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
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
		if data.get("total_gold") is int:
			total_gold = data["total_gold"]

func save() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return
	var payload := {
		"best_floors": best_floors,
		"total_gold": total_gold,
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

func add_gold(amount: int) -> void:
	if amount <= 0:
		return
	total_gold += amount
	save()

func get_total_gold() -> int:
	return total_gold