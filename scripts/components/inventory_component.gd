extends Node
class_name InventoryComponent

signal items_changed
signal item_added(item_id: String)
signal active_replaced(old_id: String, new_id: String)

var collected_items: Array = []

func add_item(item_id: String) -> void:
	if ItemDB.get_item(item_id).is_empty():
		return
	if count_item(item_id) >= ItemDB.get_max_stacks(item_id):
		return
	# Hueco único de objeto activo: el nuevo sustituye al que hubiera
	if ItemDB.is_active(item_id):
		var old := active_item()
		if old != "":
			collected_items.erase(old)
			active_replaced.emit(old, item_id)
	collected_items.append(item_id)
	item_added.emit(item_id)
	items_changed.emit()

func remove_item(item_id: String) -> void:
	var idx = collected_items.find(item_id)
	if idx != -1:
		collected_items.remove_at(idx)
		items_changed.emit()

func clear_items() -> void:
	collected_items.clear()
	items_changed.emit()

## Id del objeto activo que llevas ("" si ninguno).
func active_item() -> String:
	for id in collected_items:
		if ItemDB.is_active(id):
			return id
	return ""

func has_item(item_id: String) -> bool:
	return collected_items.has(item_id)

func count_item(item_id: String) -> int:
	return collected_items.count(item_id)

func get_stat_multiplier(stat_name: String, base_value: float = 1.0) -> float:
	var mult: float = base_value
	for item_id in collected_items:
		var item_data = ItemDB.get_item(item_id)
		if item_data.has("stats") and item_data["stats"].has(stat_name):
			mult += item_data["stats"][stat_name]
	return mult

func get_stat_addition(stat_name: String, base_value: float = 0.0) -> float:
	var total: float = base_value
	for item_id in collected_items:
		var item_data = ItemDB.get_item(item_id)
		if item_data.has("stats") and item_data["stats"].has(stat_name):
			total += item_data["stats"][stat_name]
	return total
