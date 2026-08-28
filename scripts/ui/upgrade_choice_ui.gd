extends CanvasLayer

signal choice_made(choice_type, weapon_id)

@onready var container = $Control/Panel/MarginContainer/HBoxContainer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED

func present_choices(player: Node) -> void:
	for child in container.get_children():
		child.queue_free()

	get_tree().paused = true
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var combat = player.get_node_or_null("PlayerCombatController")
	if not combat: return

	var equipped_weapons = combat.weapon_slots
	var WeaponDataClass = load("res://scripts/entities/player_weapons/weapon_data.gd")
	var all_weapons = WeaponDataClass.WeaponType.values()
	
	var unequipped_weapons = []
	for w in all_weapons:
		if not equipped_weapons.has(w):
			unequipped_weapons.append(w)

	var choices = []
	
	if unequipped_weapons.size() > 0:
		var new_w = unequipped_weapons[randi() % unequipped_weapons.size()]
		choices.append({"type": "new", "weapon": new_w})
		unequipped_weapons.erase(new_w)
	
	if equipped_weapons.size() > 0:
		var up_w = equipped_weapons[randi() % equipped_weapons.size()]
		choices.append({"type": "upgrade", "weapon": up_w})

	if randf() > 0.5 and unequipped_weapons.size() > 0:
		var new_w = unequipped_weapons[randi() % unequipped_weapons.size()]
		choices.append({"type": "new", "weapon": new_w})
	elif equipped_weapons.size() > 0:
		var up_w = equipped_weapons[randi() % equipped_weapons.size()]
		choices.append({"type": "upgrade", "weapon": up_w})
		
	if choices.is_empty() and unequipped_weapons.size() > 0:
		choices.append({"type": "new", "weapon": unequipped_weapons[0]})

	for choice in choices:
		var w_id = choice.weapon
		var data = WeaponDataClass.get_weapon_data(w_id)
		
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(200, 300)
		
		if choice.type == "new":
			btn.text = "Nueva Arma\n\n" + data.icon + " " + data.display_name
			btn.pressed.connect(_on_choice_selected.bind("new_weapon", str(w_id)))
		else:
			btn.text = "Mejorar Arma\n\n" + data.icon + " " + data.display_name + "\n(+ Daño/Área)"
			btn.pressed.connect(_on_choice_selected.bind("upgrade", str(w_id)))
			
		container.add_child(btn)

func _on_choice_selected(c_type: String, c_id: String) -> void:
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	emit_signal("choice_made", c_type, c_id)
