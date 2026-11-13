class_name PlayerEquipment
extends Node

## Equipo del jugador en la mazmorra (ver EquipmentDB): casco, pechera, pantalones, dos talismanes y
## el ARMA QUE LLEVAS EN LA MANO, que es una pieza más (sus stats solo cuentan mientras la empuñas).
## Lo que recoges y no cabe va a la mochila (BAG_MAX) y se pierde al acabar la partida.
## Lo EQUIPADO (armadura, talismanes y el arma en la mano) se guarda en SaveManager.meta["equipment"]
## en cuanto cambia, así que se conserva al morir, al ganar y al salir: es con lo que entras la próxima vez.
## PlayerStatBlock suma get_stat_addition() a los objetos de la partida.

signal equipment_changed
signal item_received(item: Dictionary, result: String)   ## result: "equipped" | "bag" | "full"
signal perk_triggered(item: Dictionary, perk: Dictionary)   ## un efecto especial acaba de activarse

const LOW_HP := 0.35    ## "hp_low": por debajo de esta fracción de vida
const FULL_HP := 0.9    ## "hp_full": a partir de esta fracción

const SLOTS := ["casco", "pechera", "pantalones", "talisman_1", "talisman_2"]
const BAG_MAX := 8
const SAVE_KEY := "equipment"
## Por ahora no se conserva ningún objeto al morir: cada partida empieza sin equipo. Ponlo en true para reactivarlo.
const PERSIST_LOADOUT := false

var player: Node
var equipped: Dictionary = {}        ## ranura -> pieza
var bag: Array = []                  ## piezas sin equipar (solo esta partida)
var weapon_items: Dictionary = {}    ## tipo de arma que llevas -> su pieza (stats y rareza)
var _buffs: Dictionary = {}          ## uid de la pieza -> {stats, until} (bonus temporales de sus efectos)
var _perk_ready: Dictionary = {}     ## uid -> instante en que su efecto vuelve a estar listo
## false en pruebas que no quieren tocar el guardado.
var persist := true

# Estado de los rasgos de la Fase 2 del plan de loot (ver LootHits)
var last_parry_t := -100.0            ## instante del último parry (rasgo "contra")
var last_dodge_t := -100.0            ## instante de la última esquiva (rasgo "bailarin")
var chain_stacks := 0                 ## golpes seguidos (fabricante Arriero)
var chain_last_t := -100.0
var vacio_ready_t := 0.0              ## regla "vacio": cuándo vuelve a absorber un golpe
var cazador_armed := false            ## regla "cazador": el siguiente golpe aturde

## ¿Lleva puesta (o en la mano) una legendaria con la regla `rule`?
func has_rule(rule: String) -> bool:
	for it in active_items():
		if EquipmentDB.rule_of(it) == rule:
			return true
	return false

## Daño extra de la cadena del Arriero (0 si el arma no es suya o se cortó).
func chain_bonus() -> float:
	var m := EquipmentDB.maker_of(weapon_in_hand())
	if String(weapon_in_hand().get("maker", "")) != "arriero" or _now() - chain_last_t > float(m["window"]):
		return 0.0
	return float(m["per"]) * mini(chain_stacks, int(m["max"]))

func add_chain() -> void:
	var m := EquipmentDB.maker_of(weapon_in_hand())
	if m.is_empty():
		return
	if _now() - chain_last_t > float(m.get("window", 1.5)):
		chain_stacks = 0
	chain_stacks = mini(chain_stacks + 1, int(m.get("max", 8)))
	chain_last_t = _now()

func reset_chain() -> void:
	chain_stacks = 0

## Regla "vacio": true si este golpe se absorbe (y la gasta durante 8 s).
func absorb_hit() -> bool:
	if not has_rule("vacio") or _now() < vacio_ready_t:
		return false
	vacio_ready_t = _now() + LootHits.VACIO_COOLDOWN
	return true

func _ready() -> void:
	if player == null:
		player = get_parent()
	start_run()
	_connect_parry.call_deferred()   # el controlador de parry se crea después del equipo
	if player and player.has_signal("weapon_changed"):
		player.weapon_changed.connect(func(_i, _n): _on_weapon_changed())

## Nueva partida: mochila vacía y vuelve lo que estaba equipado al salir de la anterior.
func start_run() -> void:
	bag.clear()
	weapon_items.clear()
	equipped.clear()
	_buffs.clear()
	_perk_ready.clear()
	var saved: Variant = SaveManager.meta.get(SAVE_KEY, {})
	if PERSIST_LOADOUT and saved is Dictionary:
		for slot in SLOTS:
			var it := EquipmentDB.sanitize(saved.get(slot))
			if not it.is_empty() and EquipmentDB.slots_for(it).has(slot):
				equipped[slot] = it
		var arma := EquipmentDB.sanitize(saved.get("arma"))
		if not arma.is_empty() and int(arma["weapon"]) == GameData.dungeon_weapon:
			weapon_items[int(arma["weapon"])] = arma
	equipment_changed.emit()

# ───────────────────────────── Consultas ─────────────────────────────

func current_weapon() -> int:
	var winv = player.get("weapon_inventory") if player else null
	return winv.get_current_weapon() if winv else -1

func carried_weapons() -> Array:
	var winv = player.get("weapon_inventory") if player else null
	return winv.weapon_slots if winv else []

## Pieza del arma que llevas en la mano (una común sin stats si no tiene pieza propia).
func weapon_in_hand() -> Dictionary:
	var w := current_weapon()
	if w < 0:
		return {}
	if not weapon_items.has(w):
		weapon_items[w] = EquipmentDB.weapon_item(w, 0)
	return weapon_items[w]

func get_item(slot: String) -> Dictionary:
	if slot == "arma":
		return weapon_in_hand()
	return equipped.get(slot, {})

## Piezas activas: armadura, talismanes y el arma en la mano.
func active_items() -> Array:
	var out: Array = []
	for slot in SLOTS:
		if equipped.has(slot):
			out.append(equipped[slot])
	var w := weapon_in_hand()
	if not w.is_empty():
		out.append(w)
	return out

## Piezas equipadas de cada set: {set_id: n}
func set_counts() -> Dictionary:
	var counts := {}
	for it in active_items():
		var s := String(it.get("set", ""))
		if s != "":
			counts[s] = int(counts.get(s, 0)) + 1
	return counts

## Bonus de sets activos (sumados).
func set_bonus() -> Dictionary:
	var out := {}
	var counts := set_counts()
	for s in counts:
		var bonus: Dictionary = EquipmentDB.SETS[s]["bonus"]
		for need in bonus:
			if int(counts[s]) >= int(need):
				for k in bonus[need]:
					if not k in EquipmentDB.SET_SPECIAL_KEYS:
						out[k] = float(out.get(k, 0.0)) + float(bonus[need][k])
	return out

## Suma de un bonus especial de set ("element_power") de los niveles alcanzados.
func set_special(key: String) -> float:
	var total := 0.0
	var counts := set_counts()
	for s in counts:
		var bonus: Dictionary = EquipmentDB.SETS[s]["bonus"]
		for need in bonus:
			if int(counts[s]) >= int(need) and bonus[need].has(key):
				total += float(bonus[need][key])
	return total

## Líneas para la UI: cada set con piezas, sus niveles y cuáles están activos.
func set_summary() -> Array[String]:
	var lines: Array[String] = []
	var counts := set_counts()
	for s in counts:
		var def: Dictionary = EquipmentDB.SETS[s]
		var tiers: Array = def["bonus"].keys()
		tiers.sort()
		lines.append("%s  %d/%d piezas" % [def["name"], counts[s], int(tiers[-1])])
		for need in tiers:
			var b: Dictionary = def["bonus"][need]
			var parts: Array = []
			var stats := {}
			for k in b:
				if not k in EquipmentDB.SET_SPECIAL_KEYS:
					stats[k] = b[k]
			parts.append_array(EquipmentDB.describe_stats(stats))
			if b.has("perk"):
				parts.append("★ " + String(EquipmentDB.PERKS[b["perk"]]["desc"]))
			if b.has("element_power"):
				parts.append("+%d%% fuerza del elemento" % int(round(float(b["element_power"]) * 100.0)))
			lines.append("%s[%d] %s" % ["✓ " if int(counts[s]) >= int(need) else "  ", need, ", ".join(parts)])
	return lines

func get_stat_addition(stat: String) -> float:
	var total := 0.0
	for it in active_items():
		total += float(it.get("stats", {}).get(stat, 0.0))
	total += float(set_bonus().get(stat, 0.0))
	for e in armor_element_counts():
		total += float(EquipmentDB.ARMOR_ELEMENT_STATS.get(e, {}).get(stat, 0.0)) * int(armor_element_counts()[e])
	return total + perk_stat(stat)

# ───────────────────────────── Elementos (EquipmentDB.ELEMENTS) ─────────────────────────────

## Piezas de armadura equipadas de cada elemento: {elemento: n}
func armor_element_counts() -> Dictionary:
	var out := {}
	for slot in ["pechera", "pantalones"]:
		var e := EquipmentDB.element_of(equipped.get(slot, {}))
		if e != "":
			out[e] = int(out.get(e, 0)) + 1
	return out

## Elemento que aplican ahora tus golpes: {id, power} o {} si ninguno.
## El del arma en la mano, +25 % de fuerza por pieza de armadura del mismo elemento; si el arma no
## tiene, 2 piezas de un elemento lo prestan a media fuerza.
func active_element() -> Dictionary:
	var counts := armor_element_counts()
	var w := EquipmentDB.element_of(weapon_in_hand())
	if w != "":
		return {"id": w, "power": 1.0 + EquipmentDB.RESONANCE_PER_PIECE * int(counts.get(w, 0)) + set_special("element_power")}
	for e in counts:
		if int(counts[e]) >= 2:
			return {"id": e, "power": 0.5}
	return {}

# ───────────────────────────── Efectos especiales (EquipmentDB.PERKS) ─────────────────────────────

## Se dispara un evento del jugador: "dodge" | "kill" | "finisher" | "parry" | "hurt".
## Cada pieza activa con un efecto de ese evento (y fuera de reposo) lo aplica.
func notify(event: String) -> void:
	if player == null:
		return
	var now := _now()
	match event:
		"parry": last_parry_t = now
		"dodge":
			last_dodge_t = now
			LootHits.on_dodge(self)
		"hurt": reset_chain()
	for src in perk_sources():
		var perk: Dictionary = src["perk"]
		if String(perk.get("trigger", "")) != event:
			continue
		var uid := String(src["uid"])
		if float(_perk_ready.get(uid, 0.0)) > now:
			continue
		_perk_ready[uid] = now + float(perk.get("cd", 0.0))
		_apply_perk(uid, perk, now)
		perk_triggered.emit(src["item"], perk)

## Efectos activos: los de cada pieza y los de los niveles de set alcanzados. [{uid, perk, item}]
func perk_sources() -> Array:
	var out: Array = []
	for it in active_items():
		var perk := EquipmentDB.perk_of(it)
		if not perk.is_empty():
			out.append({"uid": String(it.get("uid", "")), "perk": perk, "item": it})
	var counts := set_counts()
	for s in counts:
		var bonus: Dictionary = EquipmentDB.SETS[s]["bonus"]
		for need in bonus:
			if int(counts[s]) >= int(need) and bonus[need].has("perk"):
				out.append({"uid": "set:%s:%d" % [s, need], "perk": EquipmentDB.PERKS[bonus[need]["perk"]],
					"item": {"rarity": ItemDB.Rarity.LEGENDARY, "name": EquipmentDB.SETS[s]["name"]}})
	return out

func _apply_perk(uid: String, perk: Dictionary, now: float) -> void:
	if perk.has("buff") and perk.get("dur", 0.0) > 0.0:
		_buffs[uid] = {"stats": perk["buff"], "until": now + float(perk["dur"])}
	var hc: Node = player.get("health_comp")
	if perk.has("heal") and hc and player.has_method("heal"):
		player.heal(float(hc.max_hp) * float(perk["heal"]))
	if perk.has("nova"):
		_nova(perk["nova"])
	var res: Node = player.get("resources")
	if res:
		if perk.has("energy") and res.has_method("add_energy"):
			res.add_energy(float(perk["energy"]))
		if perk.has("mana") and res.has_method("add_mana"):
			res.add_mana(float(perk["mana"]))

## Onda alrededor del jugador: aplica el elemento a los enemigos a `radius` metros (efectos de set).
func _nova(nova: Dictionary) -> void:
	var el: String = nova.get("element", "")
	var radius: float = float(nova.get("radius", 4.0))
	var cfg: Dictionary = EquipmentDB.ELEMENTS.get(el, {})
	for e in player.get_tree().get_nodes_in_group("enemies"):
		if not (e is Node3D) or e.get("puppet") == true:
			continue
		if (e as Node3D).global_position.distance_to((player as Node3D).global_position) > radius:
			continue
		match el:
			"frio":
				if e.has_method("apply_chill"):
					e.apply_chill(float(cfg.get("slow", 0.55)), float(cfg.get("dur", 2.5)))
			"fuego":
				StatusEffects.apply_to(e, "burn", float(nova.get("dps", 5.0)), float(cfg.get("dur", 3.0)), player, current_weapon())
			"natural":
				StatusEffects.apply_to(e, "poison", float(nova.get("dps", 4.0)), float(cfg.get("dur", 4.0)), player, current_weapon())
	var root := player.get_tree().current_scene
	if root and cfg.has("color"):
		NecroVFX.shockwave(root, (player as Node3D).global_position + Vector3(0, 0.1, 0), radius, cfg["color"])

## Lo que suman ahora los efectos: bonus temporales (tras un evento) y condiciones de vida.
func perk_stat(stat: String) -> float:
	var total := 0.0
	var now := _now()
	for uid in _buffs.keys():
		var b: Dictionary = _buffs[uid]
		if float(b["until"]) <= now:
			_buffs.erase(uid)
		else:
			total += float(b["stats"].get(stat, 0.0))
	for src in perk_sources():
		var perk: Dictionary = src["perk"]
		if perk.has("buff") and _condition_met(String(perk.get("trigger", ""))):
			total += float(perk["buff"].get(stat, 0.0))
	return total

## Bonus temporales vivos: [{name, left}] (para el HUD).
func active_buffs() -> Array:
	var out: Array = []
	var now := _now()
	for src in perk_sources():
		var uid := String(src["uid"])
		if _buffs.has(uid) and float(_buffs[uid]["until"]) > now:
			out.append({"name": src["perk"].get("name", ""), "left": float(_buffs[uid]["until"]) - now})
	return out

func _condition_met(trigger: String) -> bool:
	match trigger:
		"always":
			return true
		"hp_low", "hp_full":
			var hp = player.get("hp") if player else null
			var mx = player.get("max_hp") if player else null
			if hp == null or mx == null or float(mx) <= 0.0:
				return false
			var ratio := float(hp) / float(mx)
			return ratio < LOW_HP if trigger == "hp_low" else ratio >= FULL_HP
	return false

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _connect_parry() -> void:
	var pc: Node = player.get("parry_controller") if player else null
	if pc and pc.has_signal("parried") and not pc.parried.is_connected(_on_parried):
		pc.parried.connect(_on_parried)

func _on_parried(_attacker: Node3D) -> void:
	notify("parry")

## Pieza que `item` sustituiría al equiparla ({} si la ranura está libre).
func equipped_for(item: Dictionary) -> Dictionary:
	return get_item(_target_slot(item))

## Lo que cambiarían las stats al equipar `item` (para la comparación de la UI).
func stat_delta(item: Dictionary, slot: String = "") -> Dictionary:
	if slot == "":
		slot = _target_slot(item)
	var old := get_item(slot)
	var out := {}
	for k in item.get("stats", {}):
		out[k] = float(item["stats"][k])
	for k in old.get("stats", {}):
		out[k] = float(out.get(k, 0.0)) - float(old["stats"][k])
	return out

# ───────────────────────────── Cambios ─────────────────────────────

## Recoge una pieza: si su ranura está libre se equipa, si no va a la mochila.
func receive(item: Dictionary) -> String:
	item = EquipmentDB.sanitize(item)
	if item.is_empty():
		return "full"
	var result := "bag"
	if String(item["slot"]) == "arma":
		var w := int(item["weapon"])
		var carried := carried_weapons()
		var winv = player.get("weapon_inventory") if player else null
		if not carried.has(w) and winv and carried.size() < winv.MAX_WEAPON_SLOTS:
			equip(item)
			result = "equipped"
		elif carried.has(w) and int(weapon_in_hand().get("rarity", 0)) == 0 and current_weapon() == w:
			equip(item)
			result = "equipped"
	else:
		for slot in EquipmentDB.slots_for(item):
			if not equipped.has(slot):
				equip(item, slot)
				result = "equipped"
				break
	if result != "full":
		RunLog.received(item)
	if result == "bag":
		if bag.size() >= BAG_MAX:
			result = "full"
		else:
			bag.append(item)
			equipment_changed.emit()
	item_received.emit(item, result)
	return result

## Equipa una pieza (de la mochila o nueva). Lo que había en esa ranura vuelve a la mochila.
## Las armas: si ya la llevas cambia su pieza; si no, entra en un hueco libre o sustituye a la de la mano.
func equip(item: Dictionary, slot: String = "") -> bool:
	if item.is_empty():
		return false
	RunLog.equipped(item)
	var idx := _bag_index(item)
	if idx >= 0:
		bag.remove_at(idx)
	if String(item["slot"]) == "arma":
		_equip_weapon(item)
	else:
		if slot == "" or not EquipmentDB.slots_for(item).has(slot):
			slot = _target_slot(item)
		if slot == "":
			return false
		if equipped.has(slot):
			_to_bag(equipped[slot])
		equipped[slot] = item
	_changed()
	return true

func _equip_weapon(item: Dictionary) -> void:
	var w := int(item["weapon"])
	var winv = player.get("weapon_inventory") if player else null
	if winv == null:
		return
	if winv.weapon_slots.has(w):
		if weapon_items.has(w) and int(weapon_items[w].get("rarity", 0)) > 0:
			_to_bag(weapon_items[w])
	elif winv.weapon_slots.size() >= winv.MAX_WEAPON_SLOTS:
		# Huecos llenos: sustituye al arma de la mano (su pieza va a la mochila)
		var old: int = winv.get_current_weapon()
		if weapon_items.has(old) and int(weapon_items[old].get("rarity", 0)) > 0:
			_to_bag(weapon_items[old])
		weapon_items.erase(old)
		winv.weapon_slots[winv.current_slot] = w
		if player.get("combat_controller"):
			player.combat_controller.weapon_slots = winv.weapon_slots
	else:
		if player.has_method("add_weapon"):
			player.add_weapon(w)
		else:
			winv.add_weapon(w)
	weapon_items[w] = item
	var slot_idx: int = winv.weapon_slots.find(w)
	if player.has_method("select_slot"):
		player.select_slot(slot_idx)
	else:
		winv.select_slot(slot_idx)

## Quita una pieza de armadura/talismán a la mochila.
func unequip(slot: String) -> bool:
	if not equipped.has(slot) or bag.size() >= BAG_MAX:
		return false
	bag.append(equipped[slot])
	equipped.erase(slot)
	_changed()
	return true

## Tira una pieza de la mochila.
func discard(item: Dictionary) -> void:
	var idx := _bag_index(item)
	if idx >= 0:
		bag.remove_at(idx)
		equipment_changed.emit()

func _target_slot(item: Dictionary) -> String:
	var slots := EquipmentDB.slots_for(item)
	if String(item.get("slot", "")) == "arma":
		return "arma"
	for s in slots:
		if not equipped.has(s):
			return s
	return slots[0] if not slots.is_empty() else ""

func _to_bag(item: Dictionary) -> void:
	if bag.size() < BAG_MAX:
		bag.append(item)

func _bag_index(item: Dictionary) -> int:
	for i in bag.size():
		if bag[i].get("uid") == item.get("uid"):
			return i
	return -1

func _on_weapon_changed() -> void:
	_changed()

func _changed() -> void:
	save()
	equipment_changed.emit()

# ───────────────────────────── Guardado ─────────────────────────────

## Guarda SOLO lo equipado (y el arma de la mano, que pasa a ser el arma inicial).
func save() -> void:
	if not PERSIST_LOADOUT or not persist or _is_test_with_real_save():
		return
	var data := {}
	for slot in equipped:
		data[slot] = equipped[slot]
	var w := current_weapon()
	if w >= 0 and not carried_weapons().is_empty():
		data["arma"] = weapon_in_hand()
		GameData.set_dungeon_weapon(w)
	SaveManager.meta[SAVE_KEY] = data
	SaveManager.save()

## Las pruebas de tests/ que no cambian SaveManager.save_path no deben tocar la partida real del jugador
## (cambian de arma y eso guardaría).
func _is_test_with_real_save() -> bool:
	if SaveManager.save_path != SaveManager.SAVE_PATH or not is_inside_tree():
		return false
	for c in get_tree().root.get_children():
		if String(c.scene_file_path).begins_with("res://tests/"):
			return true
	return false

## Lo guardado, para el Salón (sin jugador): {ranura: pieza}
static func saved_loadout() -> Dictionary:
	var out := {}
	var saved: Variant = SaveManager.meta.get(SAVE_KEY, {})
	if PERSIST_LOADOUT and saved is Dictionary:
		for slot in SLOTS + ["arma"]:
			var it := EquipmentDB.sanitize(saved.get(slot))
			if not it.is_empty():
				out[slot] = it
	return out
