class_name ChestRoulette
extends RefCounted

## Ruleta del cofre maldito: de 1 a MAX_REWARDS recompensas. La primera siempre es un objeto; cada
## una extra se gana con probabilidad BASE_CHANCE + suerte x LUCK_SCALE (tope CAP_CHANCE).
## Las recompensas salen una a una, con un tono que sube, para que abrir el cofre se sienta.

const MAX_REWARDS := 5
const BASE_CHANCE := 0.30
const LUCK_SCALE := 1.5
const CAP_CHANCE := 0.85
const GOLD_EACH := 60
const XP_EACH := 25.0
const STAGGER := 0.35

const WEIGHTS := {"item": 30.0, "gold": 25.0, "xp": 20.0, "magnet": 6.0, "bomb": 6.0, "food": 7.0, "clock": 6.0}
const LABELS := {"item": "OBJETO", "gold": "ORO", "xp": "XP", "magnet": "IMAN", "bomb": "BOMBA", "food": "COMIDA", "clock": "RELOJ"}

static func extra_chance(luck: float) -> float:
	return clampf(BASE_CHANCE + maxf(luck, 0.0) * LUCK_SCALE, 0.0, CAP_CHANCE)

## Lista de recompensas (ids de WEIGHTS). Pura: se puede probar con un generador fijo.
static func roll(luck: float, rng: RandomNumberGenerator = null) -> Array:
	var out: Array = ["item"]
	var p := extra_chance(luck)
	while out.size() < MAX_REWARDS and (rng.randf() if rng else randf()) < p:
		out.append(_pick(rng))
	return out

static func _pick(rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for k in WEIGHTS:
		total += float(WEIGHTS[k])
	var roll := (rng.randf() if rng else randf()) * total
	for k in WEIGHTS:
		roll -= float(WEIGHTS[k])
		if roll <= 0.0:
			return k
	return "gold"

static func summary(rewards: Array) -> String:
	return " + ".join(rewards.map(func(r): return LABELS[r]))
