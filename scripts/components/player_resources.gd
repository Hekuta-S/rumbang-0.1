class_name PlayerResources
extends Node

## Recursos del jugador (solo en la mazmorra; en supervivencia no gastan nada):
##  - ENERGÍA: ataques cuerpo a cuerpo, rodar y saltar. Se recupera sola tras una breve pausa.
##  - MANÁ: magia (polvos, espíritus, orbes elementales y el futuro bastón). Regenera despacio.
##  - BALAS: reserva por arma de fuego (escopeta, lanzallamas, bazuca, railgun). No se regeneran:
##    se recogen de los enemigos y se rellenan en parte al bajar de nivel.
## Todo el gasto pasa por spend() / spend_energy(): si no alcanza devuelve false y emite `denied`.
## El equipo (PlayerStatBlock: max_energy, energy_regen, energy_cost, max_mana, mana_regen) sube los
## máximos y la recarga y abarata la energía: usa energy_max() / mana_max(), no las constantes.

signal changed
signal denied(kind: int)

enum Kind { NONE, ENERGY, MANA, AMMO }

const W := WeaponData.WeaponType

const ENERGY_MAX := 100.0
const ENERGY_REGEN := 24.0           ## por segundo
const ENERGY_DELAY := 0.65           ## pausa tras gastar antes de empezar a recuperar (s)
const MANA_MAX := 100.0
const MANA_REGEN := 5.0
const MANA_DELAY := 1.4

const DODGE_COST := 22.0
const JUMP_COST := 12.0
const SLAM_COST := 40.0              ## clavado con salto de la espalanza
const CHARGE_COST := 20.0            ## lanzamiento cargado de la espalanza

## Arma -> qué recurso gasta, coste del ataque normal y del especial (click derecho). 0 = gratis.
const TABLE := {
	W.SPEAR_LANCE: {"kind": Kind.ENERGY, "cost": 14.0, "alt": 0.0},      ## su especial se cobra aparte
	W.ENERGY_SWORD: {"kind": Kind.ENERGY, "cost": 12.0, "alt": 20.0},
	W.SPINNING_AXE: {"kind": Kind.ENERGY, "cost": 18.0, "alt": 30.0},
	W.ZOMBIE_ARM: {"kind": Kind.ENERGY, "cost": 16.0, "alt": 0.0},
	W.DAGGERS: {"kind": Kind.ENERGY, "cost": 7.0, "alt": 24.0},           ## golpes baratos; la embestida
	W.MACE: {"kind": Kind.ENERGY, "cost": 20.0, "alt": 40.0},             ## golpes caros; el mazazo al suelo
	W.GREATSWORD: {"kind": Kind.ENERGY, "cost": 16.0, "alt": 0.0},      ## tres tajos pesados; sin especial
	W.SWORD: {"kind": Kind.ENERGY, "cost": 10.0, "alt": 0.0},           ## cuatro golpes ligeros; sin especial
	W.SERPENTS: {"kind": Kind.MANA, "cost": 14.0, "alt": 25.0},
	W.DUSTS: {"kind": Kind.MANA, "cost": 10.0, "alt": 14.0},
	W.ELEMENTS_CYCLE: {"kind": Kind.MANA, "cost": 8.0, "alt": 16.0},
	W.TRI_SHOTGUN: {"kind": Kind.AMMO, "cost": 1.0, "alt": 3.0},
	W.FLAME_THROWER: {"kind": Kind.AMMO, "cost": 1.0, "alt": 12.0},
	W.SPORE_BAZOOKA: {"kind": Kind.AMMO, "cost": 1.0, "alt": 3.0},
	W.RAILGUN: {"kind": Kind.AMMO, "cost": 1.0, "alt": 0.0},
}
## Capacidad de la reserva de balas de cada arma de fuego.
const AMMO_MAX := {
	W.TRI_SHOTGUN: 36,
	W.FLAME_THROWER: 150,
	W.SPORE_BAZOOKA: 24,
	W.RAILGUN: 20,
}

var active := false                  ## solo en mazmorra
var energy := ENERGY_MAX
var mana := MANA_MAX
var ammo: Dictionary = {}            ## arma -> balas en reserva
var _energy_wait := 0.0
var _mana_wait := 0.0

func _ready() -> void:
	active = GameData.game_mode == "dungeon"
	for w in AMMO_MAX:
		ammo[w] = AMMO_MAX[w]

func _stats() -> PlayerStatBlock:
	var p := get_parent()
	return p.get("stat_block") as PlayerStatBlock if p else null

## Energía máxima con el equipo.
func energy_max() -> float:
	var sb := _stats()
	return ENERGY_MAX + (sb.energy_max_bonus() if sb else 0.0)

func mana_max() -> float:
	var sb := _stats()
	return MANA_MAX + (sb.mana_max_bonus() if sb else 0.0)

func _process(delta: float) -> void:
	if not active:
		return
	var dirty := false
	var sb := _stats()
	var e_max := energy_max()
	var m_max := mana_max()
	if energy > e_max or mana > m_max:   # al quitarse equipo
		energy = minf(energy, e_max)
		mana = minf(mana, m_max)
		dirty = true
	if _energy_wait > 0.0:
		_energy_wait -= delta
	elif energy < e_max:
		energy = minf(energy + ENERGY_REGEN * (sb.energy_regen_mult() if sb else 1.0) * delta, e_max)
		dirty = true
	if _mana_wait > 0.0:
		_mana_wait -= delta
	elif mana < m_max:
		mana = minf(mana + MANA_REGEN * (sb.mana_regen_mult() if sb else 1.0) * delta, m_max)
		dirty = true
	if dirty:
		changed.emit()

# ───────────────────────────── Consulta ─────────────────────────────

func kind_of(weapon: int) -> int:
	return int(TABLE.get(weapon, {}).get("kind", Kind.NONE))

func cost_of(weapon: int, alt: bool = false) -> float:
	return float(TABLE.get(weapon, {}).get("alt" if alt else "cost", 0.0))

## Balas de un arma de fuego (-1 si el arma no usa balas).
func ammo_of(weapon: int) -> int:
	return int(ammo.get(weapon, 0)) if AMMO_MAX.has(weapon) else -1

func max_ammo_of(weapon: int) -> int:
	return int(AMMO_MAX.get(weapon, 0))

func can_spend(weapon: int, alt: bool = false) -> bool:
	if not active:
		return true
	var cost := cost_of(weapon, alt)
	if cost <= 0.0:
		return true
	match kind_of(weapon):
		Kind.ENERGY:
			var sb := _stats()
			return energy >= cost * (sb.energy_cost_mult() if sb else 1.0)
		Kind.MANA: return mana >= cost
		Kind.AMMO: return float(ammo.get(weapon, 0)) >= cost
	return true

# ───────────────────────────── Gasto ─────────────────────────────

## Cobra un ataque del arma (normal o especial). false = no alcanza el recurso (no se cobra nada).
func spend(weapon: int, alt: bool = false) -> bool:
	if not active:
		return true
	var cost := cost_of(weapon, alt)
	if cost <= 0.0:
		return true
	var kind := kind_of(weapon)
	match kind:
		Kind.ENERGY: return spend_energy(cost)
		Kind.MANA: return spend_mana(cost)
		Kind.AMMO:
			if float(ammo.get(weapon, 0)) < cost:
				denied.emit(kind)
				return false
			ammo[weapon] = int(ammo[weapon]) - int(cost)
			changed.emit()
	return true

func spend_energy(cost: float) -> bool:
	if not active or cost <= 0.0:
		return true
	var sb := _stats()
	if sb:
		cost *= sb.energy_cost_mult()
	if energy < cost:
		denied.emit(Kind.ENERGY)
		return false
	energy -= cost
	_energy_wait = ENERGY_DELAY
	changed.emit()
	return true

func spend_mana(cost: float) -> bool:
	if not active or cost <= 0.0:
		return true
	if mana < cost:
		denied.emit(Kind.MANA)
		return false
	mana -= cost
	_mana_wait = MANA_DELAY
	changed.emit()
	return true

# ───────────────────────────── Recarga ─────────────────────────────

func add_energy(amount: float) -> void:
	energy = minf(energy + amount, energy_max())
	changed.emit()

func add_mana(amount: float) -> void:
	mana = minf(mana + amount, mana_max())
	changed.emit()

## Suma `fraction` de la capacidad de cada arma de fuego que el jugador lleva. Devuelve cuántas balas entraron.
func add_ammo_fraction(fraction: float, owned_weapons: Array) -> int:
	var added := 0
	for w in AMMO_MAX:
		if not owned_weapons.has(w):
			continue
		var before: int = int(ammo.get(w, 0))
		ammo[w] = mini(before + int(ceil(AMMO_MAX[w] * fraction)), int(AMMO_MAX[w]))
		added += int(ammo[w]) - before
	if added > 0:
		changed.emit()
	return added

func has_any_ammo_weapon(owned_weapons: Array) -> bool:
	for w in owned_weapons:
		if AMMO_MAX.has(w):
			return true
	return false

## Al bajar de nivel: energía y maná llenos, y la mitad de la reserva de balas.
func refresh_for_new_level() -> void:
	energy = energy_max()
	mana = mana_max()
	for w in AMMO_MAX:
		ammo[w] = mini(int(ammo.get(w, 0)) + int(ceil(AMMO_MAX[w] * 0.5)), int(AMMO_MAX[w]))
	changed.emit()
