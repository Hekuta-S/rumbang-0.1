extends Node
class_name PlayerWeaponInventory

signal weapon_changed(weapon_index, weapon_name)
signal reload_state_changed(weapon_type, ammo, max_ammo, is_reloading, progress)

const MAX_WEAPON_SLOTS: int = 4

var weapon_slots: Array = []
var current_slot: int = 0
var weapon_levels: Dictionary = {}
## Mejoras específicas por arma: {weapon_type: {upgrade_id: nivel}} (ver WeaponUpgrades)
var weapon_upgrades: Dictionary = {}
var weapon_ammo: Dictionary = {}
var reloading_weapon: int = -1
var reload_timer: float = 0.0
var total_reload_time: float = 1.0

## Armas con cargador (munición finita + recarga). Ninguna por ahora: el bazuca de
## esporas ya no recarga, solo dispara muy despacio.
var weapon_mag_size: Dictionary = {}

var weapon_reload_time: Dictionary = {}

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
	# Armas con mejoras propias: mientras la UI no deja elegir una concreta,
	# la subida genérica sortea una de las disponibles.
	if WeaponUpgrades.has_specific(w_id):
		var pool := get_available_upgrades(w_id)
		if not pool.is_empty():
			upgrade_weapon_stat(w_id, pool[randi() % pool.size()]["id"])
		return
	weapon_levels[w_id] = get_weapon_level(w_id) + 1

## Nueva partida: olvida niveles y mejoras de la anterior.
func reset_progress() -> void:
	weapon_levels.clear()
	weapon_upgrades.clear()
	_spirit_order.clear()

func get_upgrade_level(w_id: int, upgrade_id: String) -> int:
	return int(weapon_upgrades.get(w_id, {}).get(upgrade_id, 0))

func can_upgrade_stat(w_id: int, upgrade_id: String) -> bool:
	var def := WeaponUpgrades.get_def(w_id, upgrade_id)
	return not def.is_empty() and get_upgrade_level(w_id, upgrade_id) < int(def["max_level"])

## Sube un nivel la mejora específica; false si no existe o ya está al máximo.
func upgrade_weapon_stat(w_id: int, upgrade_id: String) -> bool:
	if not can_upgrade_stat(w_id, upgrade_id):
		return false
	if not weapon_upgrades.has(w_id):
		weapon_upgrades[w_id] = {}
	weapon_upgrades[w_id][upgrade_id] = get_upgrade_level(w_id, upgrade_id) + 1
	weapon_levels[w_id] = get_weapon_level(w_id) + 1   # el "nivel del arma" sigue contando mejoras
	return true

## Mejoras específicas que aún se pueden subir para esta arma.
func get_available_upgrades(w_id: int) -> Array:
	var out: Array = []
	for d in WeaponUpgrades.for_weapon(w_id):
		if d.has("spirit") and not get_owned_spirits().has(int(d["spirit"])):
			continue   # mejora de un animal que Joel aún no tiene
		if get_upgrade_level(w_id, d["id"]) < int(d["max_level"]):
			out.append(d)
	return out

## Espíritus de Joel: 0 Komodo, 1 Búho, 2 Hipopótamo. El orden se sortea una vez por partida;
## Joel empieza con el primero y cada "Nuevo espíritu" desbloquea el siguiente.
var _spirit_order: Array = []

func get_owned_spirits() -> Array:
	if _spirit_order.is_empty():
		_spirit_order = [0, 1, 2]
		_spirit_order.shuffle()
	var unlocked := 1 + get_upgrade_level(WeaponData.WeaponType.SERPENTS, "spirit_unlock")
	return _spirit_order.slice(0, clampi(unlocked, 1, _spirit_order.size()))

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
		"lifesteal": 0.0,
		"range": 1.0,
		"burst_time": 1.0,
	}

	# Armas con mejoras propias: solo cuentan esas (no la tabla genérica por nivel)
	if WeaponUpgrades.has_specific(w_id):
		WeaponUpgrades.apply(w_id, weapon_upgrades.get(w_id, {}), mods)
		mods.quantity_bonus = int(mods.quantity_bonus)
		return mods

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
	emit_signal("weapon_changed", slot_idx, name_value)

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
		}
		var mag: int = weapon_mag_size.get(wt, 0)
		if mag > 0:
			info["max_ammo"] = mag
			info["ammo"] = weapon_ammo.get(wt, mag)
		list.append(info)
	return list
