class_name XpCurve
extends RefCounted

## Curva de experiencia del modo supervivencia (compartida por ExperienceComponent y StatsComponent)
## y valor/aspecto de las gemas de XP.
##  - XP para pasar del nivel L al L+1: lineal por tramos (pendiente creciente), no x1.5 por nivel:
##    así el nivel 30+ es alcanzable en una partida de 7 minutos y se ven varias evoluciones.
##  - Gemas por tipo de enemigo (xp_for_type): relleno 1 · bruto/francotirador/mortero 5 ·
##    élite x25 · minijefe x100. El tier (gem_tier) fija color y tamaño de la gema.

const BASE := 5.0
const SLOPE_1 := 8.0     ## niveles 1..TIER_2_LEVEL-1
const SLOPE_2 := 10.0    ## niveles TIER_2_LEVEL..TIER_3_LEVEL-1
const SLOPE_3 := 13.0    ## niveles TIER_3_LEVEL+
const TIER_2_LEVEL := 20
const TIER_3_LEVEL := 40

const XP_FILLER := 1.0
const XP_HEAVY := 5.0
const XP_ELITE := 25.0
const XP_MINIBOSS := 100.0

## Colores de gema por tier: 0 azul (1) · 1 verde (5+) · 2 roja (25+) · 3 dorada (100+).
const TIER_COLORS := [Color(0.2, 0.9, 1.0), Color(0.35, 1.0, 0.45), Color(1.0, 0.3, 0.25), Color(1.0, 0.82, 0.25)]
const TIER_SCALES := [1.0, 1.3, 1.7, 2.3]

## XP necesaria para subir del nivel `level` al siguiente.
static func required(level: int) -> float:
	var l := maxi(level, 1)
	var total := BASE
	for n in range(1, l):                 # incrementos acumulados hasta `level`
		if n < TIER_2_LEVEL:
			total += SLOPE_1
		elif n < TIER_3_LEVEL:
			total += SLOPE_2
		else:
			total += SLOPE_3
	return total

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
