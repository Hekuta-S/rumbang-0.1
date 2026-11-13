extends Node

## El menú principal construye el panel de MEJORAS PERMANENTES y los botones de dificultad/reto sin errores.
func _ready() -> void:
	SaveManager.save_path = "user://test_save.json"
	SaveManager.meta = {}
	var menu: Node = load("res://scenes/ui/main_menu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame
	menu._refresh_upgrades()
	await get_tree().process_frame
	var rows: int = menu.upgrades_container.get_child_count()
	var ok_rows: bool = rows >= MetaShop.ITEMS.size()
	var buttons: Array = menu._play_menu.find_children("*", "Button", true, false)
	var has_diff: bool = buttons.any(func(b): return String(b.text).contains("DIFICULTAD"))
	var has_chal: bool = buttons.any(func(b): return String(b.text).contains("RETO"))
	print("%s: panel con %d filas" % ["PASSED" if ok_rows else "FAILED", rows])
	print("%s: botones de dificultad y reto" % ["PASSED" if has_diff and has_chal else "FAILED"])
	var ids: Array = HubPanels.survival_characters().map(func(i): return GameData.CHARACTERS[i]["id"])
	var ok_char: bool = ids == ["mikeura"] and GameData.CHARACTERS[GameData.survival_index()]["id"] == "mikeura"
	print("%s: supervivencia solo con Mikeura (%s)" % ["PASSED" if ok_char else "FAILED", ids])
	ok_rows = ok_rows and ok_char
	print("ALL PASSED" if ok_rows and has_diff and has_chal else "SOME FAILED")
	get_tree().quit(0 if ok_rows and has_diff and has_chal else 1)
