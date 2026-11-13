class_name DungeonRun
extends RefCounted

## Fase 3 del plan de loot/combate: estructura de la partida de la mazmorra (solo sin red).
##  - PERGAMINOS DE ENFOQUE (Dead Cells): Brutalidad / Táctica / Supervivencia. Cada pergamino sube
##    uno y cura un poco; al nivel FOCUS_PERK_AT de un enfoque se activa su ventaja propia.
##    Salen al limpiar una caverna marcada por nivel y junto al portal. GameState.focus.
##  - PLANOS (Dead Cells): algunas legendarias, fabricantes y rasgos empiezan bloqueados y no salen
##    en el botín hasta encontrar su plano (élites y jefes). Se guardan para siempre en
##    SaveManager.meta["blueprints"]. EquipmentDB filtra con known().
##  - CALOR (Borderlands Mayhem): camino opcional del portal; cada nivel de calor endurece a los
##    enemigos el resto de la partida a cambio de más élites, oro, botín y planos. GameState.heat.
##  - COFRE MALDITO (Dead Cells): desde el nivel 2 puede aparecer uno; abrirlo (hay que aceptarlo)
##    da una pieza rara y oro, pero recibes CURSE_DAMAGE_MULT de daño hasta lograr CURSE_KILLS bajas.

# ───────────────────────────── Enfoques ─────────────────────────────

const FOCUS := {
	"brutalidad": {"name": "Brutalidad", "icon": "🗡", "color": Color(1.0, 0.36, 0.3),
		"desc": "+8% daño cuerpo a cuerpo\n+10% aguante que quitas",
		"perk": "Carnicería", "perk_desc": "Cada baja: +5% daño 4 s (hasta x5)"},
	"tactica": {"name": "Táctica", "icon": "🎯", "color": Color(0.45, 0.7, 1.0),
		"desc": "+8% daño a distancia y especial\n-4% enfriamiento",
		"perk": "Sangre fría", "perk_desc": "El primer golpe tras esquivar hace +40%"},
	"supervivencia": {"name": "Supervivencia", "icon": "🛡", "color": Color(0.45, 1.0, 0.5),
		"desc": "+12 vida máxima\n+2% armadura",
		"perk": "Segundo aliento", "perk_desc": "Una vez por nivel, un golpe mortal te deja a 1 de vida"},
}
const FOCUS_PERK_AT := 3
const BRUT_DAMAGE := 0.08
const BRUT_STUN := 0.10
const TAC_DAMAGE := 0.08
const TAC_COOLDOWN := 0.96
const SURV_HP := 12.0
const SURV_ARMOR := 0.02
const SCROLL_HEAL := 0.15            ## cada pergamino cura esta fracción de la vida máxima
const CARNAGE_BONUS := 0.05
const CARNAGE_MAX := 5
const CARNAGE_TIME := 4.0
const COLD_BONUS := 0.4
const COLD_WINDOW := 1.5

static var _carnage := 0
static var _carnage_t := -100.0
static var _cold_used_for := -1.0    ## esquiva cuyo golpe de Sangre fría ya se gastó

static func enabled() -> bool:
	return GameData.game_mode == "dungeon" and not Net.is_online()

static func focus_level(id: String) -> int:
	return int(GameState.get_instance().focus.get(id, 0))

static func has_perk(id: String) -> bool:
	return enabled() and focus_level(id) >= FOCUS_PERK_AT

## Opción para DungeonChoiceUI.
static func focus_option(id: String) -> Dictionary:
	var f: Dictionary = FOCUS[id]
	var lv := focus_level(id)
	var desc := "%s\nNivel %d → %d" % [f["desc"], lv, lv + 1]
	if lv + 1 == FOCUS_PERK_AT:
		desc += "\n¡DESBLOQUEA %s!\n%s" % [String(f["perk"]).to_upper(), f["perk_desc"]]
	elif lv >= FOCUS_PERK_AT:
		desc += "\n%s activa" % f["perk"]
	else:
		desc += "\nAl %d: %s" % [FOCUS_PERK_AT, f["perk"]]
	return {"id": id, "icon": f["icon"], "title": f["name"], "desc": desc, "color": f["color"]}

## Sube un enfoque, cura SCROLL_HEAL y recalcula la vida máxima.
static func add_focus(id: String, player: Node) -> void:
	if not FOCUS.has(id):
		return
	var gs := GameState.get_instance()
	gs.focus[id] = focus_level(id) + 1
	RunLog.focus(id)
	if not is_instance_valid(player):
		return
	var sb = player.get("stat_block")
	if sb and sb.has_method("rebase_equipment_hp"):
		sb._recalculate()
	var hc = player.get("health_comp")
	if hc and player.has_method("heal"):
		player.heal(float(hc.max_hp) * SCROLL_HEAL)
	if focus_level(id) == FOCUS_PERK_AT:
		EquipmentPickup.toast(player, "¡%s!" % String(FOCUS[id]["perk"]).to_upper(), FOCUS[id]["color"])

## Estadística que suman los enfoques (PlayerStatBlock).
static func focus_stat(stat: String) -> float:
	if not enabled():
		return 0.0
	match stat:
		"armor": return SURV_ARMOR * focus_level("supervivencia")
		"max_hp": return SURV_HP * focus_level("supervivencia")
	return 0.0

## Daño y enfriamiento del arma según su categoría (Player.get_weapon_modifiers).
static func apply(w_id: int, mods: Dictionary) -> void:
	if not enabled():
		return
	var data = WeaponData.get_weapon_data(w_id)
	var melee: bool = data != null and String(data.category) == "melee"
	var lv := focus_level("brutalidad") if melee else focus_level("tactica")
	mods["damage"] = float(mods.get("damage", 0.0)) + (BRUT_DAMAGE if melee else TAC_DAMAGE) * lv
	var tac := focus_level("tactica")
	if tac > 0:
		mods["cooldown"] = maxf(float(mods.get("cooldown", 1.0)) * pow(TAC_COOLDOWN, tac), WeaponUpgrades.MIN_COOLDOWN_MULT)

## Multiplicador de aguante de Brutalidad (DungeonRunes.stun_mult).
static func stun_mult() -> float:
	return 1.0 + BRUT_STUN * focus_level("brutalidad") if enabled() else 1.0

## Bonificación de daño de las ventajas de enfoque para este golpe (LootHits.outgoing).
static func perk_bonus(eq) -> float:
	if not enabled():
		return 0.0
	var now := Time.get_ticks_msec() / 1000.0
	var bonus := 0.0
	if has_perk("brutalidad") and now - _carnage_t < CARNAGE_TIME:
		bonus += CARNAGE_BONUS * _carnage
	if has_perk("tactica") and eq != null and now - float(eq.last_dodge_t) < COLD_WINDOW and _cold_used_for != float(eq.last_dodge_t):
		_cold_used_for = float(eq.last_dodge_t)
		bonus += COLD_BONUS
	return bonus

static func carnage_stacks() -> int:
	return _carnage if Time.get_ticks_msec() / 1000.0 - _carnage_t < CARNAGE_TIME else 0

## Una baja: Carnicería y la maldición.
static func on_kill() -> void:
	if not enabled():
		return
	if has_perk("brutalidad"):
		_carnage = mini(carnage_stacks() + 1, CARNAGE_MAX)
		_carnage_t = Time.get_ticks_msec() / 1000.0
	var gs := GameState.get_instance()
	if gs.curse_kills > 0:
		gs.curse_kills -= 1

## Segundo aliento: si queda, el golpe que mataría deja al jugador a 1 de vida. Se conecta como
## último oyente de HealthComponent.damage_taking (después de la armadura). true si se usó.
static func second_wind_ready() -> bool:
	return has_perk("supervivencia") and not GameState.get_instance().second_wind_used

static func try_second_wind(data: Dictionary, hc: Node, player: Node) -> void:
	if not second_wind_ready() or float(data["amount"]) < float(hc.hp):
		return
	data["amount"] = maxf(float(hc.hp) - 1.0, 0.0)
	GameState.get_instance().second_wind_used = true
	EquipmentPickup.toast(player, "¡SEGUNDO ALIENTO!", FOCUS["supervivencia"]["color"])

# ───────────────────────────── Maldición ─────────────────────────────

const CURSE_KILLS := 12
const CURSE_DAMAGE_MULT := 2.5
const CURSED_CHEST_FROM := 2
const CURSED_CHEST_CHANCE := 0.5     ## por nivel (siempre con calor)
const CURSED_MIN_RARITY := 2
const CURSE_COLOR := Color(0.75, 0.3, 1.0)

static func cursed() -> bool:
	return enabled() and GameState.get_instance().curse_kills > 0

static func curse() -> void:
	GameState.get_instance().curse_kills = CURSE_KILLS
	RunLog.cursed()

## Daño que recibe el jugador (Player.take_damage).
static func incoming_mult() -> float:
	return CURSE_DAMAGE_MULT if cursed() else 1.0

static func cursed_gold(level: int) -> int:
	return 60 + 20 * level

# ───────────────────────────── Calor ─────────────────────────────

const HEAT_MAX := 5
const HEAT_HP := 0.2
const HEAT_DAMAGE := 0.15
const HEAT_ELITE := 0.1
const HEAT_GOLD := 0.25
const HEAT_DROP := 0.5               ## +50% probabilidad de botín de equipo por nivel
const HEAT_MIN_RARITY_AT := 2        ## desde aquí, el botín de equipo es poco común como mínimo
const HEAT_BLUEPRINT := 0.04
const HEAT_COLOR := Color(1.0, 0.5, 0.15)

static func heat() -> int:
	return int(GameState.get_instance().heat) if enabled() else 0

static func add_heat() -> void:
	var gs := GameState.get_instance()
	gs.heat = mini(gs.heat + 1, HEAT_MAX)
	RunLog.heat(gs.heat)

static func heat_option() -> Dictionary:
	var h := heat()
	return {"id": "calor", "icon": "♨", "title": "Calor %d → %d" % [h, h + 1], "color": HEAT_COLOR,
		"desc": "Toda la partida: enemigos +20% vida y +15% daño, más élites\n+25% oro, más botín y planos"}

## Endurece a un enemigo recién aparecido según el calor.
static func apply_heat(e: DungeonGoblin) -> void:
	var h := heat()
	if h <= 0 or not is_instance_valid(e):
		return
	e.max_hp *= 1.0 + HEAT_HP * h
	e.hp = e.max_hp
	e.damage_mult *= 1.0 + HEAT_DAMAGE * h

static func elite_bonus() -> float:
	return HEAT_ELITE * heat()

static func gold_mult() -> float:
	return 1.0 + HEAT_GOLD * heat()

static func drop_mult() -> float:
	return 1.0 + HEAT_DROP * heat()

static func min_rarity() -> int:
	return 1 if heat() >= HEAT_MIN_RARITY_AT else 0

# ───────────────────────────── Planos ─────────────────────────────

## Contenido que empieza bloqueado: id -> tipo (legendary / maker / cond). Solo una de las dos
## legendarias del mundo, para que el botín normal pueda dar alguna desde el principio.
const BLUEPRINTS := {
	"matadragones": "legendary",
	"conquistador": "maker", "mohan": "maker",
	"contra": "cond", "bailarin": "cond", "primer_golpe": "cond",
}
const BLUEPRINT_ELITE_CHANCE := 0.15
const BLUEPRINT_COLOR := Color(0.4, 0.9, 1.0)

## ¿Puede salir en el botín? (lo que no está en BLUEPRINTS siempre puede)
static func known(id: String) -> bool:
	return not BLUEPRINTS.has(id) or (SaveManager.meta.get("blueprints", []) as Array).has(id)

static func locked() -> Array:
	return BLUEPRINTS.keys().filter(func(id): return not known(id))

static func unlock(id: String) -> void:
	if known(id):
		return
	var got: Array = SaveManager.meta.get("blueprints", [])
	got.append(id)
	SaveManager.meta["blueprints"] = got
	RunLog.blueprint()
	SaveManager.save()

static func blueprint_name(id: String) -> String:
	match String(BLUEPRINTS.get(id, "")):
		"legendary": return String(EquipmentDB.LEGENDARIES[id]["name"])
		"maker": return String(EquipmentDB.MAKERS[id]["name"])
		"cond": return String(EquipmentDB.CONDITIONALS[id]["name"])
	return id

static func blueprint_kind_name(id: String) -> String:
	return {"legendary": "Legendaria", "maker": "Fabricante", "cond": "Rasgo"}.get(String(BLUEPRINTS.get(id, "")), "")

## Suelta un plano de algo aún bloqueado con probabilidad `chance` (más con calor).
static func maybe_blueprint(parent: Node, pos: Vector3, chance: float) -> RunPickup:
	if not enabled() or parent == null:
		return null
	var pool := locked()
	if pool.is_empty() or randf() >= chance + HEAT_BLUEPRINT * heat():
		return null
	var id: String = pool[randi() % pool.size()]
	var p := RunPickup.spawn(parent, pos, "PLANO\n" + blueprint_name(id), BLUEPRINT_COLOR)
	p.picked.connect(func(by):
		unlock(id)
		EquipmentPickup.toast(by, "PLANO: %s (%s)\nYa puede salir en el botín" % [blueprint_name(id), blueprint_kind_name(id)], BLUEPRINT_COLOR))
	return p

# ───────────────────────────── Garantía de botín (fase 4) ─────────────────────────────

const PITY_KILLS := 28               ## (antes 35) bajas seguidas sin pieza de equipo: la siguiente suelta una
const PITY_RARE_DROPS := 4           ## piezas seguidas sin una rara: la siguiente es rara como mínimo

## Cuenta una baja normal; true si toca botín garantizado.
static func note_kill_for_loot() -> bool:
	if not enabled():
		return false
	var gs := GameState.get_instance()
	gs.pity_kills += 1
	return gs.pity_kills >= PITY_KILLS

## Ha salido una pieza: reinicia los contadores que corresponda.
static func note_drop(item: Dictionary) -> void:
	if not enabled():
		return
	var gs := GameState.get_instance()
	gs.pity_kills = 0
	if int(item.get("rarity", 0)) >= ItemDB.Rarity.RARE:
		gs.pity_since_rare = 0
	else:
		gs.pity_since_rare += 1

static func pity_min_rarity() -> int:
	if enabled() and GameState.get_instance().pity_since_rare >= PITY_RARE_DROPS:
		return ItemDB.Rarity.RARE
	return 0
