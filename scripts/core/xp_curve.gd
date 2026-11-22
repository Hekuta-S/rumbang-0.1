class_name XpCurve
extends RefCounted

## Curva de experiencia del modo supervivencia (compartida por ExperienceComponent y StatsComponent)
## y valor/aspecto de las gemas de XP.
##  - XP para pasar del nivel L al L+1: BASE + LINEAR·n + QUAD·n² (n = L-1). La parte cuadrática compensa
##    que cada vez salgan más enemigos: se sube de nivel a un ritmo estable (~18-25 s) durante casi toda la
##    partida, y el tramo final (wave_config "xp_rush") acelera las subidas antes del jefe.
##  - Gemas por tipo de enemigo (xp_for_type): relleno 1 · bruto/francotirador/mortero 5 ·
##    élite x25 · minijefe x100. El tier (gem_tier) fija color y tamaño de la gema.

const BASE := 5.0
const LINEAR := 4.0
const QUAD := 0.25

const XP_FILLER := 1.0
const XP_HEAVY := 5.0
const XP_ELITE := 25.0
const XP_MINIBOSS := 100.0

## Colores de gema por tier: 0 azul (1) · 1 verde (5+) · 2 roja (25+) · 3 dorada (100+).
const TIER_COLORS := [Color(0.2, 0.9, 1.0), Color(0.35, 1.0, 0.45), Color(1.0, 0.3, 0.25), Color(1.0, 0.82, 0.25)]
const TIER_SCALES := [1.0, 1.3, 1.7, 2.3]

## XP necesaria para subir del nivel `level` al siguiente.
static func required(level: int) -> float:
	var n := float(maxi(level, 1) - 1)
	return BASE + LINEAR * n + QUAD * n * n

## XP que suelta un enemigo normal según su tipo (EnemyData.EnemyType).
static func xp_for_type(type_val: int) -> float:
	match type_val:
		EnemyData.EnemyType.HEAVY_BRUTE, EnemyData.EnemyType.SNIPER_GOBLIN, EnemyData.EnemyType.MORTAR_GOBLIN:
			return XP_HEAVY
		_:
			return XP_FILLER

static func gem_tier(xp: float) -> int:
	if xp >= XP_MINIBOSS:
		return 3
	if xp >= XP_ELITE:
		return 2
	if xp >= XP_HEAVY:
		return 1
	return 0
