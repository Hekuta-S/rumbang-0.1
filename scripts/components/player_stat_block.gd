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

var _player: Node
var _inventory: InventoryComponent
var _applied_regen: float = -1.0

func _ready() -> void:
	_player = get_parent()
	_inventory = _player.get("inventory") as InventoryComponent
	if _inventory:
		_inventory.item_added.connect(_on_item_added)
		_inventory.items_changed.connect(_recalculate)
	_recalculate()

# ───────────────────────────── Valores base ─────────────────────────────

func _total(stat: String) -> float:
	if _inventory == null:
		return 0.0
	return _inventory.get_stat_addition(stat, 0.0)

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

func gold_mult() -> float:
	return 1.0 + maxf(_total("gold"), 0.0)

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
	stats_recalculated.emit()

## Resumen legible para UI (ficha de pausa, debug).
func describe() -> Array[String]:
	var lines: Array[String] = []
	lines.append("Velocidad: x%.2f" % move_mult())
	lines.append("Salto: x%.2f  (saltos extra: %d)" % [jump_velocity_mult(), extra_jumps()])
	lines.append("Cooldown: x%.2f" % cooldown_mult())
	lines.append("Daño: x%.2f" % damage_mult())
	lines.append("Proyectiles extra: %d   Golpes melee extra: %d" % [extra_projectiles(), melee_extra_hits()])
	lines.append("Tamaño melee: x%.2f   Tamaño proyectil: x%.2f" % [melee_size(), ranged_size()])
	lines.append("Armadura: %d%%   Regen: %.2f/s" % [int(round(armor() * 100.0)), hp_regen()])
	lines.append("Imán: +%.1f m   Oro: x%.2f" % [magnet_bonus(), gold_mult()])
	if is_tryhard():
		lines.append("TRYHARD!! activo")
	return lines
