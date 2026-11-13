class_name DungeonMage
extends DungeonGoblin

## Magoblin de la mazmorra: frágil, ataca de lejos y no deja que se le acerquen. Comparte la
## máquina de estados de DungeonGoblin; cambia el repertorio, el modelo y cómo se mueve.
##
## Movimiento: se mantiene entre KEEP_MIN y KEEP_MAX del jugador rodeándole de lado; si se acerca,
## retrocede; si lo pierde de vista o se aleja, se acerca por el campo de flujo.
## Cinco hechizos, todos con aviso morado y esquivables:
##  - bolt (orbe): un proyectil recto y lento; la franja muestra su recorrido → apartarse de lado.
##  - fan (abanico): tres orbes en abanico → meterse entre dos o salir de la cuña.
##  - rune (runa): un círculo sigue al jugador y se fija antes de estallar → salir del círculo.
##  - nova: si el jugador se le pega, onda a su alrededor que empuja → alejarse o esquivar.
##  - blink (destello): sin daño; si le acorralan, desaparece y reaparece lejos.
## Se le interrumpe fácil mientras conjura (`windup_poise` bajo): presionarle es la respuesta.

const MAGE_DIR := MODEL_DIR + "dungeon/mago/"
const MAGE_CLIPS := {
	"walk": MODEL_DIR + "caminar_magoblin.fbx",
	"cast_windup": MAGE_DIR + "mage_cast_windup.fbx",
	"cast": MAGE_DIR + "mage_cast.fbx",
	"fan_windup": MAGE_DIR + "mage_fan_windup.fbx",
	"fan": MAGE_DIR + "mage_fan.fbx",
	"rune_windup": MAGE_DIR + "mage_rune_windup.fbx",
	"rune": MAGE_DIR + "mage_rune.fbx",
	"nova_windup": MAGE_DIR + "mage_nova_windup.fbx",
	"nova": MAGE_DIR + "mage_nova.fbx",
	"blink_windup": MAGE_DIR + "mage_blink_windup.fbx",
	"blink": MAGE_DIR + "mage_blink.fbx",
	"recover": MAGE_DIR + "mage_recover.fbx",
	"hurt": MAGE_DIR + "mage_hurt.fbx",
	"death": MAGE_DIR + "mage_death.fbx",
}
## Mismo formato que DungeonGoblin.ATTACKS, más:
##  ranged: sin golpe cuerpo a cuerpo (lo hacen los orbes) · orbs / spread / orb_speed: proyectiles
##  needs_sight: solo con línea de visión · at_target: círculo en el suelo donde está el jugador
##  blink: se teletransporta al empezar la ventana · shape "none": sin aviso en el suelo
const MAGE_ATTACKS := {
	"bolt": {"range": [3.0, 14.0], "weight": 3, "cooldown": 0.0, "shape": "line", "reach": 12.0, "width": 0.7,
		"needs_sight": true, "ranged": true, "orbs": 1, "spread": 0.0, "orb_speed": 11.0,
		"windup_clip": "cast_windup", "attack_clip": "cast", "windup": 0.6, "track": 0.5,
		"attack_time": 0.4, "window": Vector2(0.1, 0.12), "lunge": 0.0, "dash": 0.0,
		"damage": 2.0, "recover": 0.5},
	"fan": {"range": [3.0, 10.0], "weight": 2, "cooldown": 3.0, "shape": "cone", "reach": 10.0, "half_angle": 20.0,
		"needs_sight": true, "ranged": true, "orbs": 3, "spread": 18.0, "orb_speed": 9.0,
		"windup_clip": "fan_windup", "attack_clip": "fan", "windup": 0.8, "track": 0.6,
		"attack_time": 0.47, "window": Vector2(0.14, 0.16), "lunge": 0.0, "dash": 0.0,
		"damage": 2.0, "recover": 0.7},
	"rune": {"range": [5.0, 16.0], "weight": 2, "cooldown": 6.0, "shape": "circle", "radius": 1.8, "at_target": true,
		"needs_sight": true,
		"windup_clip": "rune_windup", "attack_clip": "rune", "windup": 1.1, "track": 0.7,
		"attack_time": 0.53, "window": Vector2(0.14, 0.24), "lunge": 0.0, "dash": 0.0,
		"damage": 4.0, "recover": 0.8, "shake": 0.3},
	"nova": {"range": [0.0, 2.6], "weight": 3, "cooldown": 3.5, "shape": "circle", "radius": 2.6, "center": 0.0,
		"windup_clip": "nova_windup", "attack_clip": "nova", "windup": 0.5, "track": 0.0,
		"attack_time": 0.5, "window": Vector2(0.1, 0.2), "lunge": 0.0, "dash": 0.0,
		"damage": 1.5, "recover": 0.6, "shake": 0.2},
	"blink": {"range": [0.0, 3.2], "weight": 2, "cooldown": 7.0, "shape": "none", "ranged": true, "blink": true,
		"windup_clip": "blink_windup", "attack_clip": "blink", "windup": 0.37, "track": 0.0,
		"attack_time": 0.3, "window": Vector2(0.05, 0.06), "lunge": 0.0, "dash": 0.0,
		"damage": 0.0, "recover": 0.2},
}
const COLOR := Color(0.6, 0.3, 1.0)
const KEEP_MIN := 5.5                 ## por debajo retrocede (m)
const KEEP_MAX := 10.0                ## por encima (o sin verle) se acerca
const STRAFE_SWITCH := 2.5            ## cada cuánto cambia el lado hacia el que rodea (s, aprox.)
const BLINK_DIST := Vector2(6.5, 9.0) ## distancia al jugador del punto de reaparición

var _strafe_side := 1.0
var _strafe_t := 0.0

func _init() -> void:
	attacks = MAGE_ATTACKS
	clips = MAGE_CLIPS
	idle_model = MODEL_DIR + "idle_magoblin.fbx"
	texture = "res://assets/textures/enemigos/textura_mago_goblin.png"
	model_height = 1.4
	enemy_type = EnemyData.EnemyType.GOBLIN_RANGED
	hp_mult = 2.0                 # 30 × 2 = 60
	speed_mult = 1.7              # 3,4 m/s
	hit_radius = 0.45
	hit_height = 1.4
	stagger_damage = 18.0
	armor = 6.0
	armor_break = 20.0
	knock_scale = 0.9
	windup_poise = 11.0
	telegraph_color = COLOR
	swing_sfx = "impact_magic"
	warn_sfx = "mage_warn"
	hurt_sfx = "mage_hurt"
	die_sfx = "mage_die"
	sfx_pitch = 1.0
	attack_rest = 1.0
	face_player_dist = KEEP_MAX + 4.0
	uses_attack_token = false     # a distancia / jefe: no consume ficha de ataque

func _approach_dir(to_p: Vector3, dist: float, sees: bool) -> Vector3:
	if not sees or dist > KEEP_MAX:
		return super(to_p, dist, sees)
	var away := -to_p.normalized()
	if dist < KEEP_MIN:
		return _avoid(away)
	# Dentro de la banda: rodear al jugador de lado, a media velocidad
	_strafe_t -= get_physics_process_delta_time()
	if _strafe_t <= 0.0:
		_strafe_t = STRAFE_SWITCH * randf_range(0.6, 1.4)
		_strafe_side = -_strafe_side
	var side := to_p.normalized().cross(Vector3.UP) * _strafe_side
	var origin := global_position + Vector3(0, 0.5, 0)
	if not _clear_line(origin, origin + side * WHISKER):
		_strafe_side = -_strafe_side
		side = -side
	return _avoid(side) * 0.5

func _on_impact() -> void:
	super()
	if _atk.get("blink", false):
		_blink()
		return
	var n := int(_atk.get("orbs", 0))
	if n <= 0:
		if _atk.has("radius"):
			_sparkle_burst(_attack_center(), float(_atk["radius"]))
		return
	var root := get_tree().current_scene
	if root == null:
		return
	var from := global_position + Vector3(0, 1.0, 0) + _facing * 0.6
	var spread := float(_atk.get("spread", 0.0))
	for i in n:
		var ang := (i - (n - 1) * 0.5) * spread
		var d := _facing.rotated(Vector3.UP, deg_to_rad(ang))
		var orb := MageOrb.spawn(root, from, d, float(_atk["orb_speed"]), float(_atk["damage"]) * damage_mult, COLOR, get_rid())
		orb.shooter = self

## Reaparece lejos del jugador, en suelo libre y viéndole; si no encuentra sitio, no se mueve.
func _blink() -> void:
	if not is_instance_valid(player):
		return
	var start := global_position
	var p := player.global_position
	var base_ang := atan2(start.x - p.x, start.z - p.z)
	for k in 12:
		var ang := base_ang + (k / 2) * 0.5 * (1.0 if k % 2 == 0 else -1.0)
		var d := randf_range(BLINK_DIST.x, BLINK_DIST.y)
		var to := Vector3(p.x + sin(ang) * d, start.y, p.z + cos(ang) * d)
		if map:
			var cell := map.world_to_cell(to)
			if not map._cells.has(cell) or map._walls.has(cell) or map._blocked.has(cell):
				continue
		if not _clear_line(to + Vector3(0, 1.0, 0), p + Vector3(0, 1.0, 0)):
			continue
		_sparkle_burst(start, 0.8)
		global_position = to
		reset_physics_interpolation()
		_sparkle_burst(to, 0.8)
		AudioManager.play_at("impact_magic", to, 0.0, 1.5)
		return

func _sparkle_burst(at: Vector3, radius: float) -> void:
	var root := get_tree().current_scene
	if root == null:
		return
	var s := DustVFX.sparkles(24, 0.6, radius, 0.08, 0.2, COLOR)
	s.one_shot = true
	s.explosiveness = 0.9
	root.add_child(s)
	s.global_position = at + Vector3(0, 0.4, 0)
	s.emitting = true
	get_tree().create_timer(1.0).timeout.connect(s.queue_free)
