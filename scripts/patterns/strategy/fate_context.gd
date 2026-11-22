class_name FateContext extends RefCounted

## PATRÓN STRATEGY (comportamiento) — datos compartidos con la estrategia
## Qué sabe el dado en el momento de resolver una tirada. Antes, apply() y apply12() recibían 4 parámetros
## sueltos y cada rama volvía a calcular `survival`, `enc`, `events` y `luck`. Ahora se calculan UNA vez aquí
## y cada FateOutcome los lee. (Así la estrategia no necesita conocer al FateDice.)
##
## Roles:
##   Context  : FateDice (elige la estrategia y le pasa este contexto)
##   Strategy : FateOutcome
##   Concrete : las clases de FateOutcomes (CurseOutcome, FuryOutcome, ...)

var player: Node3D
var scene: Node
var at: Vector3                 ## dónde cayó el dado
var survival: bool              ## true = supervivencia, false = mazmorra
var enc: Node                   ## DungeonEncounter (solo mazmorra; en supervivencia es null)
var events                      ## RunEvents (solo supervivencia; si no hay, null)
var luck: float
var col: Color                  ## color del resultado (el de la tabla OUTCOMES / OUTCOMES12)

static func make(p: Node3D, p_scene: Node, p_at: Vector3, p_col: Color) -> FateContext:
	var c := FateContext.new()
	c.player = p
	c.scene = p_scene
	c.at = p_at
	c.col = p_col
	c.survival = GameData.game_mode != "dungeon"
	c.enc = p_scene.get_node_or_null("DungeonEncounter")
	c.events = FateDice._events(p_scene)
	var sb = p.get("stat_block")
	c.luck = sb.luck() if sb != null else 0.0
	return c
