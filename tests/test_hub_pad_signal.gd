extends Node

## Regresión: el salón conectaba una lambda a GamepadUI.device_changed (autoload) y no la desconectaba. Al salir del
## salón, tocar el mando llamaba a la lambda con la etiqueta ya liberada ("Lambda capture at index 0 was freed" y
## "Invalid assignment of property 'text' ... on Nil", dungeon_hub.gd). Liberar el salón debe dejar la señal como
## estaba y cambiar de dispositivo después no debe romper nada.
## Headless:  Godot --headless --path . res://tests/test_hub_pad_signal.tscn

const HUB := preload("res://scenes/ui/dungeon_hub.tscn")

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	print("--- TEST: SALÓN Y SEÑAL DEL MANDO ---")
	DungeonHub.config_path = "user://test_dungeon_hub.cfg"
	GameData.armory_path = "user://test_armeria.cfg"
	SaveManager.save_path = "user://test_save.json"
	# Arrange
	var before := GamepadUI.device_changed.get_connections().size()
	var hub := HUB.instantiate() as DungeonHub
	add_child(hub)
	for i in 5:
		await get_tree().process_frame
	assert(GamepadUI.device_changed.get_connections().size() > before, "El salón escucha el cambio de mando")
	# Act
	hub.queue_free()
	for i in 3:
		await get_tree().process_frame
	# Assert
	var after := GamepadUI.device_changed.get_connections().size()
	assert(after == before, "Al liberar el salón se desconecta (%d conexiones, antes %d)" % [after, before])
	GamepadUI._set_pad(not GamepadUI._pad_active)
	GamepadUI._set_pad(not GamepadUI._pad_active)
	print("CHECK 1 PASSED: el salón suelta la señal del mando al liberarse")
	print("ALL HUB PAD SIGNAL CHECKS PASSED")
	get_tree().quit(0)
