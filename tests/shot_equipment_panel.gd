extends Node

## Captura del menú EQUIPO (necesita ventana): res://tests/shot_equipment_panel.tscn -- <archivo.png>
func _ready() -> void:
	var out := "user://equipo.png"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var eq := PlayerEquipment.new()
	add_child(eq)
	var sb := PlayerStatBlock.new()
	add_child(sb)
	for s in ["casco", "pechera", "talisman"]:
		eq.equip(EquipmentDB.roll(s, 3, rng, 0, false))
	for s in ["casco", "pantalones", "talisman", "pechera"]:
		eq.bag.append(EquipmentDB.roll(s, rng.randi_range(1, 4), rng, 0, false))
	eq.equipment_changed.emit()
	var panel := EquipmentPanel.create(eq, sb)
	add_child(panel)
	await get_tree().create_timer(1.0).timeout
	panel.select_bag_index(0)
	await get_tree().create_timer(0.5).timeout
	get_viewport().get_texture().get_image().save_png(out)
	print("guardado ", ProjectSettings.globalize_path(out))
	get_tree().quit()
