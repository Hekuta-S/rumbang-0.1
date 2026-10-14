extends Node
class_name PlayerWeaponInventory

signal weapon_changed(weapon_index, weapon_name, energy_cost)
signal reload_state_changed(weapon_type, ammo, max_ammo, is_reloading, progress)

const MAX_WEAPON_SLOTS: int = 4

var weapon_slots: Array = []
var current_slot: int = 0
var weapon_levels: Dictionary = {}
var weapon_ammo: Dictionary = {}
var reloading_weapon: int = -1
var reload_timer: float = 0.0
var total_reload_time: float = 1.0

var weapon_mag_size: Dictionary = {
	WeaponData.WeaponType.SPORE_BAZOOKA: 1,
}

var weapon_reload_time: Dictionary = {
	WeaponData.WeaponType.SPORE_BAZOOKA: 2.4,
}

func get_current_weapon() -> int:
	if weapon_slots.is_empty():
		return WeaponData.WeaponType.SPEAR_LANCE
	var slot = clamp(current_slot, 0, weapon_slots.size() - 1)
	return weapon_slots[slot]

func get_weapon_data(weapon_type: int) -> WeaponData:
	return WeaponData.get_weapon_data(weapon_type)

func get_weapon_level(w_id: int) -> int:
	return weapon_levels.get(w_id, 1)

func upgrade_weapon(w_id: int) -> void:
	weapon_levels[w_id] = get_weapon_level(w_id) + 1

func get_weapon_modifiers(w_id: int) -> Dictionary:
	var lvl = get_weapon_level(w_id)
	var data = get_weapon_data(w_id)
	var cat = data.category
	var mods = {
		"damage": 1.0,
		"size": 1.0,
		"cooldown": 1.0,
		"quantity_bonus": 0,
		"pierce_bonus": 0,
		"duration": 1.0,
	}
	
	if lvl >= 2: mods.damage += 0.15
	if lvl >= 3:
		if cat == "melee" or cat == "special": mods.size += 0.10
		elif cat == "ranged": mods.quantity_bonus += 1
	if lvl >= 4:
		mods.cooldown *= 0.85
	if lvl >= 5: mods.damage += 0.15
	if lvl >= 6:
		if cat == "ranged": mods.pierce_bonus += 1
		else: mods.quantity_bonus += 1
	if lvl >= 7:
		mods.size += 0.15
	
	return mods

func get_weapon_ammo(w_type: int) -> int:
	if weapon_mag_size.get(w_type, 0) > 0:
		return weapon_ammo.get(w_type, weapon_mag_size[w_type])
	return -1

func select_slot(slot_idx: int) -> void:
	if slot_idx < 0 or slot_idx >= weapon_slots.size():
		return
	current_slot = slot_idx
	var wt: int = weapon_slots[slot_idx]
	var name_value = WeaponData.weapon_names.get(wt, "Arma")
	var energy_cost = WeaponData.weapon_energy_costs.get(wt, 0)
	emit_signal("weapon_changed", slot_idx, name_value, energy_cost)

func cycle_slots(delta_idx: int) -> void:
	if weapon_slots.is_empty():
		return
	select_slot((current_slot + delta_idx) % weapon_slots.size())

func add_weapon(w_type: int) -> bool:
	if weapon_slots.size() >= MAX_WEAPON_SLOTS:
		return false
	weapon_slots.append(w_type)
	if weapon_slots.size() == 1:
		current_slot = 0
	return true

func start_reload(w_type: int = -1) -> void:
	var target = get_current_weapon() if w_type < 0 else w_type
	if weapon_mag_size.get(target, 0) <= 0:
		return
	if reloading_weapon == target:
		return
	reloading_weapon = target
	total_reload_time = weapon_reload_time.get(target, 2.0)
	reload_timer = 0.0
	emit_reload_state()

func emit_reload_state() -> void:
	var w: int = reloading_weapon if reloading_weapon >= 0 else get_current_weapon()
	var progress: float = 0.0
	if reloading_weapon >= 0:
		progress = clamp(reload_timer / total_reload_time, 0.0, 1.0)
	emit_signal("reload_state_changed", w, get_weapon_ammo(w), weapon_mag_size.get(w, 0), reloading_weapon >= 0, progress)

func advance_reload(delta: float) -> void:
	if reloading_weapon < 0:
		return
	reload_timer += delta
	if reload_timer >= total_reload_time:
		weapon_ammo[reloading_weapon] = weapon_mag_size[reloading_weapon]
		reloading_weapon = -1
		reload_timer = 0.0
	emit_reload_state()

func get_weapons_list() -> Array:
	var list: Array = []
	for wt in weapon_slots:
		var info: Dictionary = {
			"icon": WeaponData.weapon_icons.get(wt, "⚔️"),
			"name": WeaponData.weapon_names.get(wt, "Arma"),
			"cost": WeaponData.weapon_energy_costs.get(wt, 0),
		}
		var mag: int = weapon_mag_size.get(wt, 0)
		if mag > 0:
			info["max_ammo"] = mag
			info["ammo"] = weapon_ammo.get(wt, mag)
		list.append(info)
	return list
