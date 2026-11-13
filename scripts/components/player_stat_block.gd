class_name PlayerStatBlock
extends Node

## Resuelve las estadísticas "de partida" del jugador a partir de los objetos
## recogidos (InventoryComponent) y del modo Tryhard. Es la ÚNICA fuente de
## verdad: movimiento, combate, supervivencia y economía le preguntan a este
## nodo en lugar de leer ItemDB por su cuenta.
##
## Convenciones de ItemDB (claves de "stats"):
##   move_speed        +fracción de velocidad        (0.12 = +12 %)
##   jump_height       +fracción de altura de salto
##   extra_jumps       +saltos aéreos extra (entero)
##   attack_speed      +fracción de velocidad de ataque (cooldown = 1 / (1 + x))
##   cooldown_reduction fracción de cooldown eliminada
##   extra_projectiles +proyectiles extra por disparo (armas "ranged")
##   melee_hits        +golpes extra por ataque (armas "melee")
##   melee_size        +fracción de tamaño de ataques melee
##   ranged_size       +fracción de tamaño de proyectiles
##   damage            +fracción de daño
##   armor             fracción de daño recibido que se anula (tope 85 %)
##   max_hp            +vida máxima (se aplica una sola vez al recoger)
##   hp_regen          +vida por segundo
##   magnet            +metros de radio de atracción de XP
##   gold              +fracción de oro obtenido
##   tryhard           nivel de Tryhard (0 = apagado)
##   max_energy        +energía máxima (mazmorra, PlayerResources)
##   energy_regen      +fracción de recarga de energía
##   energy_cost       fracción de energía ahorrada en cada gasto (tope 50 %)
##   max_mana          +maná máximo
##   mana_regen        +fracción de recarga de maná
##   luck              +fracción de suerte (rareza de cartas, TomeDB)
##   xp                +fracción de XP de gemas (TomeDB)
## En la MAZMORRA no cuentan el tamaño de ataque ni los golpes/proyectiles extra (DUNGEON_IGNORED).

signal stats_recalculated

const TRYHARD_SPEED := 0.25
const TRYHARD_DAMAGE := 0.40
const TRYHARD_ARMOR := 0.20
const TRYHARD_SPAWN_RATE := 1.5     ## más enemigos por oleada
const TRYHARD_SPAWN_INTERVAL := 0.65 ## intervalo de spawn multiplicado

const CAP_MOVE := 1.0               ## +100 % de velocidad como máximo
const CAP_JUMP := 0.8
const CAP_EXTRA_JUMPS := 3
const CAP_EXTRA_PROJECTILES := 5
const CAP_MELEE_HITS := 3
const CAP_SIZE := 1.0
const CAP_ARMOR := 0.85
const MIN_COOLDOWN_MULT := 0.3
const CAP_TRYHARD := 1
const CAP_ENERGY_BONUS := 100.0     ## +energía máxima como mucho (el doble de la base)
const CAP_MANA_BONUS := 100.0
const CAP_REGEN := 1.0              ## recarga de energía/maná: +100 % como mucho
const CAP_ENERGY_SAVE := 0.5
## Stats que no se usan en la mazmorra (allí se juega con energía y maná, no con tamaño ni golpes extra).
const DUNGEON_IGNORED := ["melee_size", "ranged_size", "melee_hits", "extra_projectiles"]

var _player: Node
var _inventory: InventoryComponent
var _equipment: PlayerEquipment       ## solo en la mazmorra (ver PlayerEquipment)
var _applied_regen: float = -1.0
var _equip_hp_applied: float = 0.0    ## vida máxima que suma ahora el equipo

func _ready() -> void:
	_player = get_parent()
	_inventory = _player.get("inventory") as InventoryComponent
	if _inventory:
		_inventory.item_added.connect(_on_item_added)
		_inventory.items_changed.connect(_recalculate)
	_equipment = _player.get("equipment") as PlayerEquipment
	if _equipment:
		_equipment.equipment_changed.connect(_recalculate)
	_recalculate()

# ───────────────────────────── Valores base ─────────────────────────────

func _total(stat: String) -> float:
	if stat in DUNGEON_IGNORED and GameData.game_mode == "dungeon":
		return 0.0
	var t := 0.0
	if _inventory:
		t += _inventory.get_stat_addition(stat, 0.0)
	if _equipment:
		t += _equipment.get_stat_addition(stat)
	if GameData.game_mode != "dungeon":
		t += TomeDB.stat_total(stat) + MetaShop.stat_total(stat)
	return t + DungeonRun.focus_stat(stat)

## Tras fijar la vida base del personaje (GameData.apply_to_player) se vuelve a sumar la del equipo.
func rebase_equipment_hp() -> void:
	_equip_hp_applied = 0.0
	_recalculate()

func tryhard_tier() -> int:
	return clampi(int(_total("tryhard")), 0, CAP_TRYHARD)

func is_tryhard() -> bool:
	return tryhard_tier() > 0

# ───────────────────────────── Movilidad ─────────────────────────────

func move_mult() -> float:
	return 1.0 + minf(_total("move_speed") + TRYHARD_SPEED * tryhard_tier(), CAP_MOVE)

## Multiplicador de la VELOCIDAD de salto (la altura crece con v²).
func jump_velocity_mult() -> float:
	return sqrt(1.0 + minf(_total("jump_height"), CAP_JUMP))

func extra_jumps() -> int:
	return clampi(int(_total("extra_jumps")), 0, CAP_EXTRA_JUMPS)

# ───────────────────────────── Combate ─────────────────────────────

func cooldown_mult() -> float:
	var speed := 1.0 / (1.0 + maxf(_total("attack_speed"), 0.0))
	var reduction := 1.0 - clampf(_total("cooldown_reduction"), 0.0, 0.7)
	return maxf(MIN_COOLDOWN_MULT, speed * reduction)

func extra_projectiles() -> int:
	return clampi(int(_total("extra_projectiles")), 0, CAP_EXTRA_PROJECTILES)

func melee_extra_hits() -> int:
	return clampi(int(_total("melee_hits")), 0, CAP_MELEE_HITS)

func melee_size() -> float:
	return 1.0 + minf(_total("melee_size"), CAP_SIZE)

func ranged_size() -> float:
	return 1.0 + minf(_total("ranged_size"), CAP_SIZE)

func damage_mult() -> float:
	return 1.0 + _total("damage") + TRYHARD_DAMAGE * tryhard_tier()

# ───────────────────────────── Supervivencia / economía ─────────────────────────────

func armor() -> float:
	return clampf(_total("armor") + TRYHARD_ARMOR * tryhard_tier(), 0.0, CAP_ARMOR)

func hp_regen() -> float:
	return maxf(_total("hp_regen"), 0.0)

func magnet_bonus() -> float:
	return maxf(_total("magnet"), 0.0)

## Suerte (tomo): desplaza el sorteo de rareza de las cartas.
func luck() -> float:
	return maxf(_total("luck"), 0.0)

## Multiplicador de XP de las gemas (tomo de Saber).
func xp_mult() -> float:
	return (1.0 + maxf(_total("xp"), 0.0)) * RunModifiers.xp_mult()

## Coge una carta de tomo: sube su nivel, cura/sube la vida si es de Vitalidad y recalcula.
func add_tome(id: String, rarity: int) -> void:
	TomeDB.add(id, rarity)
	var gain := TomeDB.hp_gain(id, rarity)
	if gain > 0.0 and _player:
		_player.max_hp += gain
		_player.hp = minf(_player.max_hp, _player.hp + gain)
		var hc: Node = _player.get("health_comp")
		if hc and hc.has_method("_emit_stats"):
			hc._emit_stats()
	_recalculate()

func gold_mult() -> float:
	return (1.0 + maxf(_total("gold"), 0.0)) * RunModifiers.gold_mult()

# ───────────────────────────── Recursos (mazmorra) ─────────────────────────────

func energy_max_bonus() -> float:
	return clampf(_total("max_energy"), 0.0, CAP_ENERGY_BONUS)

func energy_regen_mult() -> float:
	return 1.0 + clampf(_total("energy_regen"), 0.0, CAP_REGEN)

## Multiplicador del coste de energía (ataques, rodar, saltar).
func energy_cost_mult() -> float:
	return 1.0 - clampf(_total("energy_cost"), 0.0, CAP_ENERGY_SAVE)

func mana_max_bonus() -> float:
	return clampf(_total("max_mana"), 0.0, CAP_MANA_BONUS)

func mana_regen_mult() -> float:
	return 1.0 + clampf(_total("mana_regen"), 0.0, CAP_REGEN)

# ───────────────────────────── Reacciones ─────────────────────────────

func _on_item_added(item_id: String) -> void:
	var stats: Dictionary = ItemDB.get_item(item_id).get("stats", {})
	# La vida máxima es un efecto puntual: sube el tope y cura lo ganado.
	if stats.has("max_hp") and _player:
		var gain: float = float(stats["max_hp"])
		_player.max_hp += gain
		_player.hp = minf(_player.max_hp, _player.hp + gain)
		var hc: Node = _player.get("health_comp")
		if hc and hc.has_method("_emit_stats"):
			hc._emit_stats()

func _recalculate() -> void:
	var regen := hp_regen()
	if not is_equal_approx(regen, _applied_regen) and _player:
		var hc: Node = _player.get("health_comp")
		if hc:
			hc.hp_regen = regen
			_applied_regen = regen
	_apply_equipment_hp()
	stats_recalculated.emit()

## La vida máxima del equipo se aplica como diferencia: al equipar sube (y cura lo ganado), al quitar baja.
func _apply_equipment_hp() -> void:
	if _equipment == null or _player == null or _player.get("health_comp") == null:
		return
	var want := maxf(_equipment.get_stat_addition("max_hp") + DungeonRun.focus_stat("max_hp"), 0.0)
	var delta := want - _equip_hp_applied
	if is_zero_approx(delta):
		return
	_equip_hp_applied = want
	_player.max_hp = maxf(1.0, _player.max_hp + delta)
	_player.hp = clampf(_player.hp + maxf(delta, 0.0), 1.0, _player.max_hp)
	var hc: Node = _player.get("health_comp")
	if hc.has_method("_emit_stats"):
		hc._emit_stats()

## Resumen legible para UI (ficha de pausa, debug).
func describe() -> Array[String]:
	var lines: Array[String] = []
	lines.append("Velocidad: x%.2f" % move_mult())
	lines.append("Salto: x%.2f  (saltos extra: %d)" % [jump_velocity_mult(), extra_jumps()])
	lines.append("Cooldown: x%.2f" % cooldown_mult())
	lines.append("Daño: x%.2f" % damage_mult())
	if GameData.game_mode == "dungeon":
		lines.append("Energía: +%d máx.   Recarga: x%.2f   Gasto: x%.2f" % [int(energy_max_bonus()), energy_regen_mult(), energy_cost_mult()])
		lines.append("Maná: +%d máx.   Recarga: x%.2f" % [int(mana_max_bonus()), mana_regen_mult()])
	else:
		lines.append("Proyectiles extra: %d   Golpes melee extra: %d" % [extra_projectiles(), melee_extra_hits()])
		lines.append("Tamaño melee: x%.2f   Tamaño proyectil: x%.2f" % [melee_size(), ranged_size()])
	lines.append("Armadura: %d%%   Regen: %.2f/s" % [int(round(armor() * 100.0)), hp_regen()])
	lines.append("Imán: +%.1f m   Oro: x%.2f" % [magnet_bonus(), gold_mult()])
	if _equipment:
		for s_id in _equipment.set_counts():
			lines.append("Set %s: %d piezas" % [EquipmentDB.SETS[s_id]["name"], _equipment.set_counts()[s_id]])
	if is_tryhard():
		lines.append("TRYHARD!! activo")
	return lines
