class_name SoulStats
extends RefCounted

## Estadísticas permanentes tipo Dark Souls (SOLO mazmorra).
##  - En la mazmorra cada baja da ALMAS (DungeonEncounter._award_souls): se guardan en run_souls.
##  - Al acabar la partida se ingresan (bank_run): al morir solo DEATH_KEEP; al retirarse o salir, todas.
##  - En el yunque del Salón (HubPanels, pestaña NIVEL) se gastan para subir un punto de una estadística.
##  - Cada punto sube el nivel del personaje en 1 y el precio del siguiente nivel crece (level_cost).
## Efectos (los lee PlayerStatBlock solo con GameData.game_mode == "dungeon"):
##   vigor     -> vida máxima               aguante  -> energía máxima y recarga
##   fuerza    -> daño de armas de FUE      destreza -> daño de armas de DES y algo de velocidad de ataque
##   intelecto -> maná máximo y recarga     suerte   -> oro, botín de equipo y almas
## Cada arma reparte el bono de daño entre Fuerza y Destreza según WEAPON_SCALING (letra S..E en la UI).
## Guardado en SaveManager.meta["souls"] = {"almas": int, "pts": {stat: puntos}}.

const BASE := 10                     ## valor que se muestra con 0 puntos (como en Dark Souls)
const MAX_POINTS := 50               ## tope por estadística (valor 60)
const DEATH_KEEP := 0.5              ## fracción de las almas de la partida que se conserva al morir
const SOFT_CAP_1 := 20               ## puntos hasta el primer tope blando
const SOFT_CAP_2 := 40

const ORDER := ["vigor", "aguante", "fuerza", "destreza", "intelecto", "suerte"]
const STATS := {
	"vigor": {"name": "Vigor", "short": "VIG",
		"desc": "Aguante del cuerpo. Sube la vida máxima."},
	"aguante": {"name": "Aguante", "short": "AGU",
		"desc": "Resistencia. Sube la energía máxima y su recarga (ataques, rodar, saltar)."},
	"fuerza": {"name": "Fuerza", "short": "FUE",
		"desc": "Sube el daño de las armas que escalan con Fuerza (maza, espadón, espada...)."},
	"destreza": {"name": "Destreza", "short": "DES",
		"desc": "Sube el daño de las armas que escalan con Destreza (dagas, katana, arco...) y algo la velocidad de ataque."},
	"intelecto": {"name": "Intelecto", "short": "INT",
		"desc": "Sube el maná máximo y su recarga."},
	"suerte": {"name": "Suerte", "short": "SUE",
		"desc": "Más oro, más botín de equipo y más almas por baja."},
}

## Peso de Fuerza / Destreza de cada arma en el bono de daño (1.0 = escalado A).
const WEAPON_SCALING := {
	WeaponData.WeaponType.SPEAR_LANCE: [0.55, 0.55],
	WeaponData.WeaponType.DAGGERS: [0.1, 1.0],
	WeaponData.WeaponType.MACE: [1.0, 0.1],
	WeaponData.WeaponType.GREATSWORD: [1.1, 0.0],
	WeaponData.WeaponType.SWORD: [0.7, 0.45],
	WeaponData.WeaponType.BOW: [0.0, 1.0],
	WeaponData.WeaponType.KATANA: [0.2, 1.1],
	WeaponData.WeaponType.FISTS: [0.45, 0.7],
}
const DEFAULT_SCALING := [0.5, 0.5]

# Por punto (antes del primer tope blando; luego la mitad y, tras el segundo, un sexto)
const HP_PER := 6.0
const ENERGY_PER := 3.0
const ENERGY_REGEN_PER := 0.015
const DAMAGE_PER := 0.03            ## con escalado 1.0
const DEX_ATTACK_SPEED_PER := 0.004
const MANA_PER := 4.0
const MANA_REGEN_PER := 0.02
const LUCK_GOLD_PER := 0.02
const LUCK_DROP_PER := 0.02
const LUCK_SOULS_PER := 0.01

## Almas de la partida en curso (aún no ingresadas).
static var run_souls: int = 0
## Lo que se ingresó al acabar la última partida (lo enseña la pantalla de fin).
static var last_banked: int = 0
static var last_lost: int = 0

# ───────────────────────────── Guardado ─────────────────────────────

static func _data() -> Dictionary:
	var d = SaveManager.meta.get("souls")
	if not (d is Dictionary):
		d = {"almas": 0, "pts": {}}
		SaveManager.meta["souls"] = d
	if not (d.get("pts") is Dictionary):
		d["pts"] = {}
	return d

static func souls() -> int:
	return int(_data().get("almas", 0))

static func points(stat: String) -> int:
	return int((_data()["pts"] as Dictionary).get(stat, 0))

## Valor mostrado (BASE + puntos).
static func value(stat: String) -> int:
	return BASE + points(stat)

## Nivel del personaje: 1 + todos los puntos repartidos.
static func level() -> int:
	var t := 1
	for s in ORDER:
		t += points(s)
	return t

## Almas que cuesta pasar del nivel `lvl` al siguiente (redondeado a 10).
static func level_cost(lvl: int = -1) -> int:
	if lvl < 0:
		lvl = level()
	var l := float(lvl)
	return int(round((60.0 + 12.0 * l + 0.6 * l * l) / 10.0)) * 10

static func can_level(stat: String) -> bool:
	return STATS.has(stat) and points(stat) < MAX_POINTS and souls() >= level_cost()

## Gasta almas en un punto de `stat`. Devuelve true si se pudo.
static func level_up(stat: String) -> bool:
	if not can_level(stat):
		return false
	var d := _data()
	d["almas"] = souls() - level_cost()
	(d["pts"] as Dictionary)[stat] = points(stat) + 1
	SaveManager.save()
	return true

static func add_souls(amount: int) -> void:
	if amount <= 0:
		return
	var d := _data()
	d["almas"] = souls() + amount
	SaveManager.save()

# ───────────────────────────── Partida ─────────────────────────────

## Nueva partida. Si quedaban almas sin ingresar (se salió por el menú de pausa), se ingresan enteras.
static func start_run() -> void:
	if run_souls > 0:
		bank_run(false)
	run_souls = 0
	last_banked = 0
	last_lost = 0

## Almas de una baja en la mazmorra (base por tipo de enemigo, nivel de mazmorra y Suerte).
static func kill_souls(is_boss: bool, is_elite: bool, dungeon_level: int) -> int:
	var base := 400.0 if is_boss else (40.0 if is_elite else 10.0)
	var lvl_mult := 1.0 + 0.15 * float(maxi(dungeon_level, 1) - 1)
	return maxi(1, int(round(base * lvl_mult * (1.0 + _curve(points("suerte")) * LUCK_SOULS_PER))))

static func add_run_souls(amount: int) -> void:
	run_souls += maxi(amount, 0)

## Ingresa las almas de la partida. died = true: solo se conserva DEATH_KEEP.
## Devuelve lo ingresado; last_banked / last_lost quedan para la pantalla de fin.
static func bank_run(died: bool) -> int:
	var keep := int(floor(float(run_souls) * (DEATH_KEEP if died else 1.0)))
	last_banked = keep
	last_lost = run_souls - keep
	run_souls = 0
	add_souls(keep)
	return keep

# ───────────────────────────── Efectos ─────────────────────────────

## Puntos efectivos con topes blandos: 1 por punto hasta 20, 0,5 hasta 40 y 1/6 después.
static func _curve(p: int) -> float:
	var a := float(mini(p, SOFT_CAP_1))
	var b := float(clampi(p - SOFT_CAP_1, 0, SOFT_CAP_2 - SOFT_CAP_1)) * 0.5
	var c := float(maxi(p - SOFT_CAP_2, 0)) / 6.0
	return a + b + c

static func scaling(weapon: int) -> Array:
	return WEAPON_SCALING.get(weapon, DEFAULT_SCALING)

## Letra de escalado como en Dark Souls (S, A, B, C, D, E o "-").
static func grade(weight: float) -> String:
	if weight >= 1.05: return "S"
	if weight >= 0.9: return "A"
	if weight >= 0.65: return "B"
	if weight >= 0.4: return "C"
	if weight >= 0.15: return "D"
	if weight > 0.0: return "E"
	return "-"

static func scaling_text(weapon: int) -> String:
	var s := scaling(weapon)
	return "FUE %s   DES %s" % [grade(float(s[0])), grade(float(s[1]))]

static func hp_bonus() -> float:
	return _curve(points("vigor")) * HP_PER

## Bono de daño (fracción) con el arma `weapon` según Fuerza y Destreza.
static func damage_bonus(weapon: int) -> float:
	var s := scaling(weapon)
	return (_curve(points("fuerza")) * float(s[0]) + _curve(points("destreza")) * float(s[1])) * DAMAGE_PER

static func gold_bonus() -> float:
	return _curve(points("suerte")) * LUCK_GOLD_PER

static func drop_bonus() -> float:
	return _curve(points("suerte")) * LUCK_DROP_PER

## Suma de una estadística de PlayerStatBlock (solo mazmorra). "max_hp" va aparte (hp_bonus).
static func stat_total(stat: String, weapon: int) -> float:
	if GameData.game_mode != "dungeon":
		return 0.0
	match stat:
		"damage":
			return damage_bonus(weapon)
		"attack_speed":
			return _curve(points("destreza")) * DEX_ATTACK_SPEED_PER
		"max_energy":
			return _curve(points("aguante")) * ENERGY_PER
		"energy_regen":
			return _curve(points("aguante")) * ENERGY_REGEN_PER
		"max_mana":
			return _curve(points("intelecto")) * MANA_PER
		"mana_regen":
			return _curve(points("intelecto")) * MANA_REGEN_PER
	return 0.0

## Lo que da ahora la estadística y lo que daría con un punto más (para la UI del yunque).
static func effect_lines(stat: String, extra: int = 0) -> Array[String]:
	var p := points(stat) + extra
	var k := _curve(p)
	var out: Array[String] = []
	match stat:
		"vigor":
			out.append("Vida máxima +%d" % int(round(k * HP_PER)))
		"aguante":
			out.append("Energía máxima +%d" % int(round(k * ENERGY_PER)))
			out.append("Recarga de energía +%d%%" % int(round(k * ENERGY_REGEN_PER * 100.0)))
		"fuerza":
			out.append("Daño (escalado A) +%d%%" % int(round(k * DAMAGE_PER * 100.0)))
		"destreza":
			out.append("Daño (escalado A) +%d%%" % int(round(k * DAMAGE_PER * 100.0)))
			out.append("Velocidad de ataque +%.1f%%" % (k * DEX_ATTACK_SPEED_PER * 100.0))
		"intelecto":
			out.append("Maná máximo +%d" % int(round(k * MANA_PER)))
			out.append("Recarga de maná +%d%%" % int(round(k * MANA_REGEN_PER * 100.0)))
		"suerte":
			out.append("Oro +%d%%   Botín +%d%%" % [int(round(k * LUCK_GOLD_PER * 100.0)), int(round(k * LUCK_DROP_PER * 100.0))])
			out.append("Almas +%d%%" % int(round(k * LUCK_SOULS_PER * 100.0)))
	return out
