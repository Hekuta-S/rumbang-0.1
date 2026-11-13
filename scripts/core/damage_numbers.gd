class_name DamageNumbers
extends RefCounted

## Fase 4 del plan de loot: números de daño de la mazmorra que se leen de un vistazo (estilo Borderlands).
## El color y el tamaño dicen QUÉ ha pasado con el golpe, no solo cuánto:
##   bonus    naranja grande  — un rasgo, fabricante o enfoque subió el daño (LootHits.outgoing)
##   stunned  cian            — golpe a un enemigo aturdido
##   heavy    amarillo grande — golpe que tambalea
##   resisted gris pequeño    — escudo del blindado o aura del protector se comieron parte
##   dot      pequeño, color del estado — tick de quemadura/veneno
##   kill     rojo grande     — el golpe que mata
## Los daños pequeños llevan un decimal ("2.5") para que se note la diferencia entre armas.
## FloatingDamage dibuja; aquí solo se decide el estilo (classify es puro, para las pruebas).

const STYLES := {
	"normal": {"color": Color(1.0, 0.94, 0.8), "size": 1.0, "crit": false},
	"heavy": {"color": Color(1.0, 0.85, 0.2), "size": 1.15, "crit": true},
	"bonus": {"color": Color(1.0, 0.55, 0.15), "size": 1.3, "crit": true},
	"stunned": {"color": Color(0.4, 0.95, 1.0), "size": 1.2, "crit": true},
	"resisted": {"color": Color(0.62, 0.66, 0.76), "size": 0.85, "crit": false},
	"dot": {"color": Color(1.0, 0.62, 0.3), "size": 0.7, "crit": false},
	"kill": {"color": Color(1.0, 0.3, 0.25), "size": 1.35, "crit": true},
}
const DOT_COLORS := {"burn": Color(1.0, 0.55, 0.2), "poison": Color(0.55, 1.0, 0.35), "bleed": Color(0.9, 0.15, 0.2)}
const BONUS_AT := 1.1                ## raw > base * esto = golpe potenciado
const RESIST_AT := 0.9               ## final < raw * esto = golpe resistido
const DECIMALS_BELOW := 10.0

const FloatingDamage = preload("res://scripts/objects/floating_damage.gd")

## base: daño que llegó; raw: tras los rasgos del jugador; final: lo que quitó de vida.
static func classify(base: float, raw: float, final: float, dot: bool, stunned: bool, heavy: bool, killed: bool) -> String:
	if dot:
		return "dot"
	if killed:
		return "kill"
	if final < raw * RESIST_AT:
		return "resisted"
	if raw > base * BONUS_AT:
		return "bonus"
	if stunned:
		return "stunned"
	if heavy:
		return "heavy"
	return "normal"

static func text_for(amount: float) -> String:
	if amount < DECIMALS_BELOW and absf(amount - roundf(amount)) >= 0.05:
		return "%.1f" % amount
	return str(int(round(amount)))

## Dibuja el número de `enemy` con el estilo `kind`. `dot_id` (burn/poison/bleed) tiñe los ticks.
static func show(enemy: Node3D, amount: float, kind: String, dot_id: String = "") -> Label3D:
	var root := enemy.get_tree().current_scene if enemy.is_inside_tree() else null
	if root == null:
		return null
	var st: Dictionary = STYLES.get(kind, STYLES["normal"])
	var col: Color = DOT_COLORS.get(dot_id, st["color"]) if kind == "dot" else st["color"]
	var text := text_for(amount)
	if bool(st["crit"]):
		text += "!"
	var l := FloatingDamage.spawn(root, enemy.global_position + Vector3(0, 1.8, 0), amount, col, bool(st["crit"]), text)
	if l:
		l.font_size = int(round(l.font_size * float(st["size"])))
	return l
