class_name RunLog
extends RefCounted

## Fase 5 del plan de loot/combate: mide cuánto se repite una partida de la mazmorra (sin red).
## Cuenta combate (recetas, tipos, élites, tiempo por caverna), daño por arma, botín (rarezas,
## piezas que se llegaron a equipar), activaciones de rasgos/fabricantes/reglas, estructura (enfoques,
## calor, malditos, forja) y qué te mató. analyze() saca los indicadores de repetición; al morir,
## summary_lines() rellena la pantalla de caída y finish() guarda la partida en HISTORY_PATH
## (las últimas HISTORY_MAX) para ajustar números con datos. Lo reinicia GameState.reset_session().

const HISTORY_MAX := 20
const ONE_WEAPON_SHARE := 0.8        ## una sola arma hace más de esto del daño = partida monótona
const DEAD_TRAIT_ROOMS := 3          ## llevado al menos estas cavernas sin activarse = rasgo muerto
const CLONE_SHARE := 0.4             ## una receta en más de esto de las cavernas = combates clonados
const CLONE_MIN_ROOMS := 5
const UNUSED_LOOT_SHARE := 0.7       ## piezas recogidas que nunca se equiparon
const UNUSED_LOOT_MIN := 4

static var history_path := "user://dungeon_runs.json"

static var world := ""
static var level := 1
static var started_ms := 0
static var recipes: Dictionary = {}          ## receta -> cavernas
static var kinds: Dictionary = {}            ## tipo de enemigo -> aparecidos
static var elites: Dictionary = {}           ## modificador -> élites
static var room_times: Array = []            ## segundos por caverna
static var damage_by_weapon: Dictionary = {} ## WeaponType -> daño
static var kills := 0
static var drops: Dictionary = {}            ## rareza -> piezas soltadas
static var picked: Dictionary = {}           ## uid -> true: piezas que entraron a tu equipo o mochila
static var equipped_uids: Dictionary = {}    ## uid -> true: piezas que llegaste a llevar puestas
static var procs: Dictionary = {}            ## "cond:x" / "maker:x" / "rule:x" -> activaciones
static var worn: Dictionary = {}             ## mismo id -> cavernas limpiadas llevándolo
static var focus_picks: Dictionary = {}
static var heat_max := 0
static var cursed_opened := 0
static var forge: Dictionary = {}            ## acción -> veces (upgrade, reroll, scrap, buy)
static var gold_spent := 0
static var blueprints := 0
static var last_hit_by := ""
static var death_cause := ""
static var _room_start: Dictionary = {}      ## caverna -> ms
static var _finished := false

static func active() -> bool:
	return GameData.game_mode == "dungeon" and not Net.is_online()

static func reset() -> void:
	world = ""
	level = 1
	started_ms = Time.get_ticks_msec()
	for d in [recipes, kinds, elites, damage_by_weapon, drops, picked, equipped_uids, procs, worn, focus_picks, forge, _room_start]:
		d.clear()
	room_times.clear()
	kills = 0
	heat_max = 0
	cursed_opened = 0
	gold_spent = 0
	blueprints = 0
	last_hit_by = ""
	death_cause = ""
	_finished = false

## Empieza a contar una partida en `p_world` (DungeonEncounter.setup en el nivel 1).
static func begin(p_world: String) -> void:
	reset()
	world = p_world

# ───────────────────────────── Registro ─────────────────────────────

static func room_started(room: int, recipe: String, room_kinds: Array) -> void:
	if not active():
		return
	_room_start[room] = Time.get_ticks_msec()
	if recipe != "":
		recipes[recipe] = int(recipes.get(recipe, 0)) + 1
	for k in room_kinds:
		kinds[k] = int(kinds.get(k, 0)) + 1

static func room_cleared(room: int, eq) -> void:
	if not active() or not _room_start.has(room):
		return
	room_times.append((Time.get_ticks_msec() - int(_room_start[room])) / 1000.0)
	_room_start.erase(room)
	if eq != null:
		for id in worn_traits(eq):
			worn[id] = int(worn.get(id, 0)) + 1

static func elite(mod: String) -> void:
	if active():
		elites[mod] = int(elites.get(mod, 0)) + 1

static func add_damage(weapon: int, amount: float) -> void:
	if active() and amount > 0.0:
		damage_by_weapon[weapon] = float(damage_by_weapon.get(weapon, 0.0)) + amount

static func kill() -> void:
	if active():
		kills += 1

static func drop(item: Dictionary) -> void:
	if active():
		var r := int(item.get("rarity", 0))
		drops[r] = int(drops.get(r, 0)) + 1

static func received(item: Dictionary) -> void:
	if active() and item.has("uid") and int(item.get("rarity", 0)) > 0:
		picked[String(item["uid"])] = true

static func equipped(item: Dictionary) -> void:
	if active() and item.has("uid"):
		equipped_uids[String(item["uid"])] = true

static func proc(id: String) -> void:
	if active():
		procs[id] = int(procs.get(id, 0)) + 1

static func focus(id: String) -> void:
	if active():
		focus_picks[id] = int(focus_picks.get(id, 0)) + 1

static func heat(h: int) -> void:
	heat_max = maxi(heat_max, h)

static func cursed() -> void:
	cursed_opened += 1

static func forge_action(action: String, gold: int) -> void:
	if not active():
		return
	forge[action] = int(forge.get(action, 0)) + 1
	gold_spent += maxi(gold, 0)

static func blueprint() -> void:
	blueprints += 1

## Quién golpeó al jugador por última vez (para la causa de la muerte).
static func hit_by(enemy: Node) -> void:
	if not active() or not is_instance_valid(enemy):
		return
	# El nombre del nodo no sirve (los repetidos se renombran "@CharacterBody3D@12"): se usa su class_name
	var s: Script = enemy.get_script()
	var who := String(s.get_global_name()) if s and s.get_global_name() != &"" else String(enemy.name)
	who = who.trim_prefix("Dungeon")
	if enemy.get("elite") != null and String(enemy.elite) != "":
		who += " (%s)" % enemy.elite
	last_hit_by = who

## Ids de rasgos/fabricante/regla que lleva puestos `eq` ahora mismo.
static func worn_traits(eq) -> Array:
	var out: Array = []
	for it in eq.active_items():
		if it.has("cond"):
			out.append("cond:" + String(it["cond"]))
		if String(it.get("slot", "")) == "arma" and it.has("maker"):
			out.append("maker:" + String(it["maker"]))
		var rule := EquipmentDB.rule_of(it)
		if rule != "":
			out.append("rule:" + rule)
	return out

# ───────────────────────────── Indicadores ─────────────────────────────

## {top_weapon, top_share, one_weapon, dead_traits, top_recipe, recipe_share, clones,
##  unused_loot, unused_share, avg_room_s}
static func analyze() -> Dictionary:
	var out := {}
	var total := 0.0
	var top := -1
	for w in damage_by_weapon:
		total += float(damage_by_weapon[w])
		if top == -1 or float(damage_by_weapon[w]) > float(damage_by_weapon[top]):
			top = int(w)
	out["top_weapon"] = top
	out["top_share"] = float(damage_by_weapon.get(top, 0.0)) / total if total > 0.0 else 0.0
	out["one_weapon"] = total > 0.0 and damage_by_weapon.size() >= 1 and float(out["top_share"]) > ONE_WEAPON_SHARE
	var dead: Array = []
	for id in worn:
		if int(worn[id]) >= DEAD_TRAIT_ROOMS and int(procs.get(id, 0)) == 0:
			dead.append(id)
	dead.sort()
	out["dead_traits"] = dead
	var rooms := 0
	var top_r := ""
	for r in recipes:
		rooms += int(recipes[r])
		if top_r == "" or int(recipes[r]) > int(recipes[top_r]):
			top_r = String(r)
	out["top_recipe"] = top_r
	out["recipe_share"] = float(recipes.get(top_r, 0)) / rooms if rooms > 0 else 0.0
	out["clones"] = rooms >= CLONE_MIN_ROOMS and float(out["recipe_share"]) > CLONE_SHARE
	var unused := 0
	for uid in picked:
		if not equipped_uids.has(uid):
			unused += 1
	out["unused_loot"] = unused
	out["unused_share"] = float(unused) / picked.size() if not picked.is_empty() else 0.0
	out["unused_flag"] = picked.size() >= UNUSED_LOOT_MIN and float(out["unused_share"]) > UNUSED_LOOT_SHARE
	var sum := 0.0
	for t in room_times:
		sum += float(t)
	out["avg_room_s"] = sum / room_times.size() if not room_times.is_empty() else 0.0
	return out

static func trait_name(id: String) -> String:
	var parts := id.split(":")
	if parts.size() != 2:
		return id
	match parts[0]:
		"cond": return String(EquipmentDB.CONDITIONALS.get(parts[1], {}).get("name", parts[1]))
		"maker": return String(EquipmentDB.MAKERS.get(parts[1], {}).get("name", parts[1]))
		"rule":
			for l in EquipmentDB.LEGENDARIES:
				if String(EquipmentDB.LEGENDARIES[l].get("rule", "")) == parts[1]:
					return String(EquipmentDB.LEGENDARIES[l]["name"])
	return parts[1]

static func weapon_name(w: int) -> String:
	return "Otros" if w < 0 else String(WeaponData.weapon_names.get(w, "Arma"))

## Líneas del resumen para la pantalla de caída.
static func summary_lines() -> Array:
	var a := analyze()
	var lines: Array = []
	var mins := (Time.get_ticks_msec() - started_ms) / 60000
	lines.append("NIVEL %d     BAJAS %d     %d MIN" % [level, kills, mins])
	if death_cause != "":
		lines.append("Te derrotó: %s" % death_cause)
	var el := 0
	for m in elites:
		el += int(elites[m])
	lines.append("Cavernas %d (%.0f s de media)     Élites %d" % [room_times.size(), float(a["avg_room_s"]), el])
	if heat_max > 0 or cursed_opened > 0:
		lines.append("Calor %d     Cofres malditos %d" % [heat_max, cursed_opened])
	var total := 0.0
	for w in damage_by_weapon:
		total += float(damage_by_weapon[w])
	if total > 0.0:
		var order: Array = damage_by_weapon.keys()
		order.sort_custom(func(x, y): return damage_by_weapon[x] > damage_by_weapon[y])
		for w in order.slice(0, 3):
			lines.append("%s  %d  (%d%%)" % [weapon_name(int(w)), int(damage_by_weapon[w]), int(round(100.0 * float(damage_by_weapon[w]) / total))])
	var top_procs: Array = procs.keys()
	top_procs.sort_custom(func(x, y): return procs[x] > procs[y])
	if not top_procs.is_empty():
		lines.append("Más activado: %s x%d" % [trait_name(top_procs[0]), int(procs[top_procs[0]])])
	for w in warnings(a):
		lines.append("⚠ " + w)
	return lines

## Avisos de repetición legibles.
static func warnings(a: Dictionary = {}) -> Array:
	if a.is_empty():
		a = analyze()
	var out: Array = []
	if bool(a["one_weapon"]):
		out.append("El %d%% de tu daño fue con %s" % [int(round(float(a["top_share"]) * 100.0)), weapon_name(int(a["top_weapon"]))])
	if not (a["dead_traits"] as Array).is_empty():
		out.append("Nunca se activó: " + ", ".join((a["dead_traits"] as Array).map(func(id): return trait_name(id))))
	if bool(a["clones"]):
		out.append("La receta \"%s\" fue el %d%% de los combates" % [a["top_recipe"], int(round(float(a["recipe_share"]) * 100.0))])
	if bool(a["unused_flag"]):
		out.append("%d de %d piezas recogidas nunca te las pusiste" % [int(a["unused_loot"]), picked.size()])
	return out

# ───────────────────────────── Historial ─────────────────────────────

## Datos de la partida para el historial.
static func snapshot() -> Dictionary:
	var a := analyze()
	var dmg := {}
	for w in damage_by_weapon:
		dmg[weapon_name(int(w))] = int(damage_by_weapon[w])
	return {"date": Time.get_datetime_string_from_system(), "world": world, "level": level, "kills": kills,
		"minutes": snappedf((Time.get_ticks_msec() - started_ms) / 60000.0, 0.1), "death": death_cause,
		"recipes": recipes.duplicate(), "kinds": kinds.duplicate(), "elites": elites.duplicate(),
		"room_times": room_times.map(func(t): return snappedf(float(t), 0.1)), "damage": dmg,
		"drops": drops.duplicate(), "picked": picked.size(), "equipped": equipped_uids.size(),
		"procs": procs.duplicate(), "worn": worn.duplicate(), "focus": focus_picks.duplicate(),
		"heat": heat_max, "cursed": cursed_opened, "forge": forge.duplicate(), "gold_spent": gold_spent,
		"blueprints": blueprints, "warnings": warnings(a),
		"top_share": snappedf(float(a["top_share"]), 0.01), "dead_traits": a["dead_traits"]}

## Fin de la partida: guarda una vez en el historial (las últimas HISTORY_MAX).
static func finish(cause: String = "") -> void:
	if not active() or _finished:
		return
	_finished = true
	death_cause = cause if cause != "" else last_hit_by
	var runs := load_history()
	runs.append(snapshot())
	while runs.size() > HISTORY_MAX:
		runs.pop_front()
	var f := FileAccess.open(history_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(runs, "  "))

static func load_history() -> Array:
	if not FileAccess.file_exists(history_path):
		return []
	var f := FileAccess.open(history_path, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text()) if f else null
	return data if data is Array else []
