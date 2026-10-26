class_name SpiritKomodo
extends SpiritAnimal

## Dragón de Komodo espiritual (melee): se invoca delante del jugador mirando HACIA ATRÁS
## y azota con la cola en abanico sobre los enemigos, que quedan sangrando.

const MODEL = preload("res://assets/models/spirits/komodo.glb")
const TAIL_ROOT := 0.9            ## m desde el centro del komodo hasta el inicio de la cola
const TAIL_LENGTH := 3.4          ## m de cola
const FAN_HALF_ANGLE := 80.0      ## grados a cada lado del eje de la cola
const BLEED_DPS_FACTOR := 0.35    ## dps de sangrado = daño del golpe × factor
const BLEED_TIME := 4.0
const KNOCKBACK := 13.0

var swing_dir: Vector3 = Vector3.FORWARD   ## hacia dónde azota la cola
var hits: int = 0

## Invoca un komodo: `at` posición del komodo, `dir` hacia donde debe azotar la cola.
static func summon(parent: Node, p: Node3D, at: Vector3, dir: Vector3, dmg: float, size: float, weapon: int) -> SpiritKomodo:
	var k := SpiritKomodo.new()
	k.player = p
	k.damage = dmg
	k.scale_mult = size
	k.source_weapon = weapon
	k.strike_time = 0.42
	k.swing_dir = Vector3(dir.x, 0.0, dir.z).normalized()
	parent.add_child(k)
	k.global_position = at
	# el modelo mira a -Z y su cola está en +Z: mirar al lado contrario del golpe
	k.look_at(at - k.swing_dir, Vector3.UP)
	k.build(MODEL)
	return k

func _on_strike() -> void:
	var origin := global_position
	var reach := (TAIL_ROOT + TAIL_LENGTH) * scale_mult
	var inner := TAIL_ROOT * 0.3 * scale_mult
	var cos_half := cos(deg_to_rad(FAN_HALF_ANGLE))
	for e in EnemyRegistry.all():
		if not is_instance_valid(e):
			continue
		var to_e: Vector3 = e.global_position - origin
		to_e.y = 0.0
		var d := to_e.length()
		if d > reach:
			continue
		if d > inner:
			if to_e.normalized().dot(swing_dir) < cos_half:
				continue
		var kb := to_e.normalized() * KNOCKBACK if d > 0.05 else swing_dir * KNOCKBACK
		if hit_enemy(e, damage, kb):
			hits += 1
			if is_instance_valid(e) and e.has_method("apply_status"):
				e.apply_status("bleed", damage * BLEED_DPS_FACTOR, BLEED_TIME, player, source_weapon)
	AudioManager.play_at("hit", global_position, -8.0, 0.8)
