class_name SpiritKomodo
extends SpiritAnimal

## Dragón de Komodo espiritual (melee): se invoca delante del jugador mirando HACIA ATRÁS
## y ataca con la cola, que acaba sobre los enemigos dejándolos sangrando. Cada invocación
## hace una de tres animaciones (sin repetir la anterior):
## Es el "Stand" de Joel (estilo JoJo): brota diminuto de su espalda, sube por encima de su cabeza
## creciendo, se lanza en picado hacia delante girando hasta quedar con la cola hacia el enemigo y
## ataca; al terminar vuelve a meterse en la espalda de Joel encogiéndose (StandAura pone el aura
## y los ゴゴゴ):
##   latigazo   — se enrosca y chasquea la cola de lado a lado.
##   torbellino — salta y gira tres vueltas con la cola extendida (3 golpes, 360°).
##   martillazo — se alza, arquea la cola sobre sí mismo y la estrella contra el suelo.
## Solo en la mazmorra: en supervivencia sigue la animación y el golpe de siempre (LEGACY).

const MODEL = preload("res://assets/models/spirits/komodo.glb")
const TAIL_ROOT := 0.9            ## m desde el centro del komodo hasta el inicio de la cola
const TAIL_LENGTH := 3.4          ## m de cola
const BLEED_DPS_FACTOR := 0.35    ## dps de sangrado = daño del golpe × factor
const BLEED_TIME := 4.0

## fan: semiángulo del abanico (≥180 = círculo completo) · dmg: × daño del espíritu por golpe ·
## kb: empuje (m/s) · strikes: segundos (desde que empieza la animación) de cada golpe ·
## shake: temblor de cámara en el golpe · land: s hasta que aterriza (polvo y temblor).
const VARIANTS := [
	{"anim": "latigazo", "strikes": [0.71], "fan": 80.0, "reach": 1.0, "dmg": 1.0, "kb": 13.0, "shake": 0.3, "land": 0.42, "whoosh": 0.9},
	{"anim": "torbellino", "strikes": [0.75, 1.17, 1.59], "fan": 180.0, "reach": 0.95, "dmg": 0.6, "kb": 9.0, "shake": 0.22, "land": 0.42, "whoosh": 1.2},
	{"anim": "martillazo", "strikes": [0.75], "fan": 55.0, "reach": 1.15, "dmg": 1.5, "kb": 20.0, "shake": 0.65, "land": 0.42, "whoosh": 0.6, "slam": true},
]
## Supervivencia: exactamente el ataque original (sin polvo al aterrizar ni sonido de latigazo).
const LEGACY := {"anim": "attack", "strikes": [0.42], "fan": 80.0, "reach": 1.0, "dmg": 1.0, "kb": 13.0, "shake": 0.0, "land": 9999.0, "whoosh": 0.0}
static var _last_variant := -1

var swing_dir: Vector3 = Vector3.FORWARD   ## hacia dónde azota la cola
var hits: int = 0
var variant: Dictionary = {}
var _extra_strikes: Array = []
var _landed := false

## Elige la animación de la próxima invocación (0 latigazo, 1 torbellino, 2 martillazo), sin repetir
## la anterior. Joel hace el gesto con el mismo índice.
static func pick_variant() -> int:
	var idx := randi() % VARIANTS.size()
	if idx == _last_variant:
		idx = (idx + 1 + randi() % (VARIANTS.size() - 1)) % VARIANTS.size()
	_last_variant = idx
	return idx

## Invoca un komodo: `at` posición del komodo, `dir` hacia donde debe azotar la cola.
## `variant_idx` fuerza la animación (-1 = sortear). Solo se usa en la mazmorra.
static func summon(parent: Node, p: Node3D, at: Vector3, dir: Vector3, dmg: float, size: float, weapon: int, variant_idx: int = -1) -> SpiritKomodo:
	var k := SpiritKomodo.new()
	k.player = p
	k.damage = dmg
	k.scale_mult = size
	k.source_weapon = weapon
	var dungeon: bool = GameData.game_mode == "dungeon"
	if dungeon:
		k.variant = VARIANTS[variant_idx if variant_idx >= 0 else pick_variant()]
		k.fade_in = 0.06                 # brota de Joel: tiene que verse enseguida
		k.fade_out = 0.15                # ya ha vuelto a meterse en Joel: solo queda desaparecer
	else:
		k.variant = LEGACY
	k.attack_anim = k.variant["anim"]
	var strikes: Array = k.variant["strikes"]
	k.strike_time = float(strikes[0])
	k._extra_strikes = strikes.slice(1)
	k.swing_dir = Vector3(dir.x, 0.0, dir.z).normalized()
	parent.add_child(k)
	k.global_position = at
	# el modelo mira a -Z y su cola está en +Z: mirar al lado contrario del golpe
	k.look_at(at - k.swing_dir, Vector3.UP)
	k.build(MODEL)
	if dungeon:
		AudioManager.play_at("ataque-espalanza", at, -6.0, float(k.variant["whoosh"]) + 0.3)
	return k

## Cuánto está fuera el Stand (hasta que termina de volver a Joel).
func stand_time() -> float:
	return _total

## Al volver a Joel no deja la nube de motas en su sitio: el destello ya lo hace StandAura.
func _start_vanish() -> void:
	if variant == LEGACY:
		super._start_vanish()

func _motion(_delta: float) -> void:
	if not _landed and _elapsed >= float(variant.get("land", 0.13)):
		_landed = true
		_on_land()
	while not _extra_strikes.is_empty() and _elapsed >= float(_extra_strikes[0]):
		_extra_strikes.pop_front()
		_strike()

## Termina el derrape y queda plantado: polvo, un golpe seco y temblor.
func _on_land() -> void:
	spawn_vanish_burst(get_parent(), global_position + Vector3(0, 0.15, 0), 1.6 * scale_mult)
	AudioManager.play_at("hit", global_position, -6.0, 0.55)
	HitFeedback.shake(0.12 * scale_mult)

func _on_strike() -> void:
	_strike()

func _strike() -> void:
	var origin := global_position
	var reach := (TAIL_ROOT + TAIL_LENGTH) * scale_mult * float(variant["reach"])
	var inner := TAIL_ROOT * 0.3 * scale_mult
	var fan: float = variant["fan"]
	var full_circle := fan >= 180.0
	var cos_half := cos(deg_to_rad(fan))
	var dmg: float = damage * float(variant["dmg"])
	var kb_force: float = variant["kb"]
	var landed_any := false
	for e in EnemyRegistry.all():
		if not is_instance_valid(e):
			continue
		var to_e: Vector3 = e.global_position - origin
		to_e.y = 0.0
		var d := to_e.length()
		if d > reach:
			continue
		if not full_circle and d > inner:
			if to_e.normalized().dot(swing_dir) < cos_half:
				continue
		var kb := to_e.normalized() * kb_force if d > 0.05 else swing_dir * kb_force
		if hit_enemy(e, dmg, kb):
			hits += 1
			landed_any = true
			if is_instance_valid(e) and e.has_method("apply_status"):
				e.apply_status("bleed", dmg * BLEED_DPS_FACTOR, BLEED_TIME, player, source_weapon)
	if variant.get("slam", false):
		# El martillazo: onda de polvo donde cae la cola, se note o no a un enemigo
		var impact := origin + swing_dir * (TAIL_ROOT + TAIL_LENGTH * 0.9) * scale_mult
		spawn_vanish_burst(get_parent(), impact + Vector3(0, 0.15, 0), 2.2 * scale_mult)
		AudioManager.play_at("explosion", impact, -8.0, 1.2)
	AudioManager.play_at("hit", global_position, -8.0, 0.8)
	HitFeedback.shake(float(variant["shake"]) * (1.0 if landed_any else 0.6))
