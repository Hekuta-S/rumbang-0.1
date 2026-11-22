class_name FateOutcomes extends RefCounted

## PATRÓN STRATEGY (comportamiento) — rol: ConcreteStrategy + registro de estrategias
## Cada clase interna es UNA conducta reutilizable. Las caras de los dados (6 y 12) se arman combinándolas.
## Ejemplos de lo que se elimina respecto al código ANTES (docs/strategy/ANTES_fate_dice.gd.txt):
##   · MALDICIÓN estaba escrita 3 veces  → ahora CurseOutcome, 1 clase usada por d6[2], d12[1] y d12[3].
##   · FURIA estaba escrita 4 veces      → ahora FuryOutcome (+ FuryOutcome.stack para el santuario de RunEvents).
##   · curar / oro / regalo duplicados   → HealFullOutcome / GoldOutcome / MapGiftOutcome.
##   · `if survival` dentro de cada rama → hay una tabla por modo (d6 mazmorra, d6 supervivencia, d12).
## Para añadir un resultado nuevo: crear la clase aquí y ponerla en la tabla. FateDice NO se toca.

# ───────────────────────────── estrategias concretas ─────────────────────────────

## -25 % de daño y de velocidad. CORRIGE: antes copiada en apply() caso 2 y en apply12() casos 1 y 3.
class CurseOutcome extends FateOutcome:
	func apply(ctx: FateContext) -> void:
		FateDice.add_mod("damage", -0.25, FateDice.CURSE_TIME, "MALDICIÓN", ctx.col)
		FateDice.add_mod("move_speed", -0.25, FateDice.CURSE_TIME, "", ctx.col)

## Mejora temporal de daño y velocidad. Parametrizada: sirve para FURIA, BENDICIÓN y JACKPOT.
## CORRIGE: antes copiada en apply() caso 4, apply12() casos 7, 11 y 12 y en RunEvents (santuario).
class FuryOutcome extends FateOutcome:
	var label: String
	var damage: float
	var speed: float
	var seconds: float

	func _init(p_label: String = "FURIA", p_damage: float = 0.5, p_speed: float = 0.2, p_seconds: float = FateDice.FURY_TIME) -> void:
		label = p_label
		damage = p_damage
		speed = p_speed
		seconds = p_seconds

	func apply(ctx: FateContext) -> void:
		stack(label, damage, speed, seconds, ctx.col)

	## Versión sin contexto: la usa también el santuario de furia de RunEvents (así deja de duplicar el código).
	static func stack(p_label: String, p_damage: float, p_speed: float, p_seconds: float, p_col: Color) -> void:
		FateDice.add_mod("damage", p_damage, p_seconds, p_label, p_col)
		FateDice.add_mod("move_speed", p_speed, p_seconds, "", p_col)

## Vida completa. CORRIGE: antes inline en apply() caso 6 y como _heal_full() en apply12().
class HealFullOutcome extends FateOutcome:
	func apply(ctx: FateContext) -> void:
		var p := ctx.player
		if p.has_method("heal") and p.get("health_comp"):
			p.heal(p.health_comp.max_hp)

## Oro fijo en supervivencia (actualiza el HUD). CORRIGE: antes inline en apply() caso 3 y _add_gold() en apply12().
class GoldOutcome extends FateOutcome:
	var amount: int

	func _init(p_amount: int = FateDice.GOLD_SURVIVAL) -> void:
		amount = p_amount

	func apply(ctx: FateContext) -> void:
		var gs := GameState.get_instance()
		gs.add_gold(amount)
		if ctx.scene.get("facade"):
			ctx.scene.facade.update_gold(gs.gold)

## Oro de la mazmorra: crece con el nivel. `base + per_level * nivel` (el original usa 30+15·n en la bolsa y 20·n en la fortuna).
class DungeonGoldOutcome extends FateOutcome:
	var base: int
	var per_level: int
	var min_level: int

	func _init(p_base: int = 30, p_per_level: int = 15, p_min_level: int = 0) -> void:
		base = p_base
		per_level = p_per_level
		min_level = p_min_level

	func apply(ctx: FateContext) -> void:
		if ctx.enc and ctx.enc.has_method("_add_gold"):
			ctx.enc._add_gold(base + per_level * maxi(min_level, int(ctx.enc.get("level"))))

## Enemigos en anillo alrededor del jugador (supervivencia). CORRIGE: el `if survival` que había dentro de _ambush().
class AmbushSurvivalOutcome extends FateOutcome:
	func apply(ctx: FateContext) -> void:
		var wm = ctx.scene.facade.wave_manager if ctx.scene.get("facade") else null
		if wm == null:
			return
		var c := ctx.player.global_position
		for k in FateDice.AMBUSH_SURVIVAL:
			var a := TAU * k / float(FateDice.AMBUSH_SURVIVAL)
			var pos := c + Vector3(cos(a), 0, sin(a)) * 9.0
			wm._spawn_single_enemy(ctx.events._ground(pos) if ctx.events else pos)

## Goblins (y un bruto desde el nivel 2) en la caverna donde está el jugador (mazmorra).
class AmbushDungeonOutcome extends FateOutcome:
	func apply(ctx: FateContext) -> void:
		var enc := ctx.enc
		if enc == null:
			return
		var c := ctx.player.global_position
		var map: DungeonMap = enc.get("map")
		var room := int(map._owner.get(map.world_to_cell(c), 0)) if map else 0
		var level := int(enc.get("level"))
		for k in FateDice.AMBUSH_DUNGEON + (1 if level >= 2 else 0):
			var a := TAU * k / float(FateDice.AMBUSH_DUNGEON + 1) + randf()
			var kind := "brute" if k == FateDice.AMBUSH_DUNGEON else "goblin"
			enc._spawn_at(room, c + Vector3(cos(a), 0, sin(a)) * 5.5, kind)

## Encola un élite en la próxima oleada (solo supervivencia con RunEvents).
class QueueEliteOutcome extends FateOutcome:
	var elite_id: String

	func _init(p_elite_id: String = "acorazado") -> void:
		elite_id = p_elite_id

	func apply(ctx: FateContext) -> void:
		if ctx.events:
			ctx.events._queue_elite(elite_id)

## Pierde un porcentaje de la vida actual (nunca baja del mínimo).
class WoundOutcome extends FateOutcome:
	func apply(ctx: FateContext) -> void:
		var hc = ctx.player.get("health_comp")
		if hc != null:
			hc.hp = maxf(hc.max_hp * FateDice.WOUND_MIN_HP_FRACTION, hc.hp * (1.0 - FateDice.WOUND_FRACTION))
			hc._emit_stats()

## Dos objetos del mapa (bomba, imán, comida, reloj). CORRIGE: antes copiado en apply() caso 5 y apply12() caso 6.
class MapGiftOutcome extends FateOutcome:
	func apply(ctx: FateContext) -> void:
		for k in 2:
			var a := TAU * k / 2.0 + randf()
			var spot := ctx.at + Vector3(cos(a), 0, sin(a)) * 1.6
			MapPickup.spawn(ctx.scene, FateDice._floor(ctx.scene, spot), MapPickup.roll_kind())

## Una pieza de equipo de la mazmorra con la rareza `tier`.
class EquipmentDropOutcome extends FateOutcome:
	var tier: int

	func _init(p_tier: int = 1) -> void:
		tier = p_tier

	func apply(ctx: FateContext) -> void:
		EquipmentPickup.try_drop(ctx.scene, ctx.at + Vector3(0, 0, 1.2), 1.0, tier)

## El botín de un cofre de supervivencia (con la suerte del jugador). `offset` separa varios cofres.
class ChestRewardOutcome extends FateOutcome:
	var offset: Vector3

	func _init(p_offset: Vector3 = Vector3.ZERO) -> void:
		offset = p_offset

	func apply(ctx: FateContext) -> void:
		if ctx.events:
			ctx.events._grant_rewards(ctx.at + offset, ChestRoulette.roll(ctx.luck))

## Lluvia de orbes de experiencia en círculo.
class XpRainOutcome extends FateOutcome:
	func apply(ctx: FateContext) -> void:
		if not ctx.scene.get("facade"):
			return
		for k in FateDice.XP_RAIN_ORBS:
			var a := TAU * k / float(FateDice.XP_RAIN_ORBS)
			var spot := ctx.at + Vector3(cos(a), 0, sin(a)) * 2.4
			ctx.scene.facade.spawn_xp_orb(FateDice._floor(ctx.scene, spot), FateDice.XP_RAIN_EACH)

## Ejecuta varias estrategias en orden (patrón Composite sobre Strategy). Sirve para CATÁSTROFE, BENDICIÓN y JACKPOT
## sin volver a escribir sus partes: son combinaciones de las clases de arriba.
class CompositeOutcome extends FateOutcome:
	var parts: Array[FateOutcome]

	func _init(p_parts: Array[FateOutcome] = []) -> void:
		parts = p_parts

	func apply(ctx: FateContext) -> void:
		for part in parts:
			part.apply(ctx)

# ───────────────────────────── tablas: valor del dado → estrategia ─────────────────────────────

static var _d6_dungeon: Dictionary = {}
static var _d6_survival: Dictionary = {}
static var _d12: Dictionary = {}

## Estrategias de cada cara. `faces` = 6 o 12; `survival` solo cambia las caras del dado de 6.
## CORRIGE: reemplaza los dos `match v` de FateDice (apply y apply12) y los `if survival` de cada rama.
static func table(faces: int, survival: bool) -> Dictionary:
	if faces == 12:
		if _d12.is_empty():
			_d12 = _build_d12()
		return _d12
	if survival:
		if _d6_survival.is_empty():
			_d6_survival = _build_d6_survival()
		return _d6_survival
	if _d6_dungeon.is_empty():
		_d6_dungeon = _build_d6_dungeon()
	return _d6_dungeon

static func _build_d6_survival() -> Dictionary:
	return {
		1: AmbushSurvivalOutcome.new(),
		2: CurseOutcome.new(),
		3: GoldOutcome.new(),
		4: FuryOutcome.new(),
		5: MapGiftOutcome.new(),
		6: CompositeOutcome.new([HealFullOutcome.new(), ChestRewardOutcome.new()] as Array[FateOutcome]),
	}

static func _build_d6_dungeon() -> Dictionary:
	return {
		1: AmbushDungeonOutcome.new(),
		2: CurseOutcome.new(),
		3: DungeonGoldOutcome.new(30, 15),
		4: FuryOutcome.new(),
		5: EquipmentDropOutcome.new(1),
		6: CompositeOutcome.new([HealFullOutcome.new(), EquipmentDropOutcome.new(2), DungeonGoldOutcome.new(0, 20, 1)] as Array[FateOutcome]),
	}

static func _build_d12() -> Dictionary:
	return {
		1: CompositeOutcome.new([AmbushSurvivalOutcome.new(), QueueEliteOutcome.new("acorazado"), CurseOutcome.new()] as Array[FateOutcome]),
		2: AmbushSurvivalOutcome.new(),
		3: CurseOutcome.new(),
		4: WoundOutcome.new(),
		5: GoldOutcome.new(),
		6: MapGiftOutcome.new(),
		7: FuryOutcome.new(),
		8: HealFullOutcome.new(),
		9: ChestRewardOutcome.new(),
		10: XpRainOutcome.new(),
		11: CompositeOutcome.new([HealFullOutcome.new(), FuryOutcome.new("BENDICIÓN", 1.0, 0.4, FateDice.BLESS_TIME)] as Array[FateOutcome]),
		12: CompositeOutcome.new([HealFullOutcome.new(), FuryOutcome.new("JACKPOT"), GoldOutcome.new(FateDice.GOLD_JACKPOT),
			ChestRewardOutcome.new(), ChestRewardOutcome.new(Vector3(2.5, 0, 0))] as Array[FateOutcome]),
	}
