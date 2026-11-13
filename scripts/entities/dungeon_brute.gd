class_name DungeonBrute
extends DungeonGoblin

## Goblin bruto de la mazmorra: lento, grande y con armadura. Comparte la máquina de estados de
## DungeonGoblin y cambia el repertorio, el modelo y cómo encaja los golpes.
##
## Cuatro ataques, todos más lentos de anunciar que los del goblin normal pero más castigadores:
##  - sweep (barrido): revés amplio de cerca; cuña de 160° → salir hacia atrás o esquivar a través.
##  - smash (mazazo): martillo a dos manos por encima de la cabeza; círculo delante → apartarse.
##    Recuperación larga: la mejor ocasión para castigarle.
##  - stomp (pisotón): si el jugador se le pega; onda en círculo a su alrededor → salir del anillo.
##  - charge (carga con el hombro): de lejos, franja ancha → apartarse; contra una pared queda
##    aturdido mucho rato.
## Armadura: fuera de la anticipación, los golpes flojos no le interrumpen (solo destellan); se
## aturde con un golpe fuerte o al acumular `armor_break` de daño seguido. En la anticipación
## aguanta hasta `windup_poise`.
## Mientras no existan sus clips propios (BRUTE_DIR), usa los del goblin normal: mismo esqueleto.

const BRUTE_DIR := MODEL_DIR + "dungeon/bruto/"
const BRUTE_CLIPS := {
	"walk": MODEL_DIR + "caminar_goblin_bruto.fbx",
	"sweep_windup": BRUTE_DIR + "brute_sweep_windup.fbx",
	"sweep": BRUTE_DIR + "brute_sweep.fbx",
	"smash_windup": BRUTE_DIR + "brute_smash_windup.fbx",
	"smash": BRUTE_DIR + "brute_smash.fbx",
	"stomp_windup": BRUTE_DIR + "brute_stomp_windup.fbx",
	"stomp": BRUTE_DIR + "brute_stomp.fbx",
	"charge_windup": BRUTE_DIR + "brute_charge_windup.fbx",
	"charge": BRUTE_DIR + "brute_charge.fbx",
	"recover": BRUTE_DIR + "brute_recover.fbx",
	"hurt": BRUTE_DIR + "brute_hurt.fbx",
	"death": BRUTE_DIR + "brute_death.fbx",
}
const GOBLIN_DIR := MODEL_DIR + "dungeon/"
const FALLBACKS := {
	"sweep_windup": GOBLIN_DIR + "goblin_swipe_windup.fbx",
	"sweep": GOBLIN_DIR + "goblin_swipe.fbx",
	"smash_windup": GOBLIN_DIR + "goblin_windup.fbx",
	"smash": GOBLIN_DIR + "goblin_attack.fbx",
	"stomp_windup": GOBLIN_DIR + "goblin_windup.fbx",
	"stomp": GOBLIN_DIR + "goblin_attack.fbx",
	"charge_windup": GOBLIN_DIR + "goblin_leap_windup.fbx",
	"charge": GOBLIN_DIR + "goblin_leap.fbx",
	"recover": GOBLIN_DIR + "goblin_recover.fbx",
	"hurt": GOBLIN_DIR + "goblin_hurt.fbx",
	"death": GOBLIN_DIR + "goblin_death.fbx",
}
## Mismo formato que DungeonGoblin.ATTACKS. "circle": radius + center (m por delante del bruto).
const BRUTE_ATTACKS := {
	"sweep": {"range": [0.0, 2.4], "weight": 3, "cooldown": 0.0, "shape": "cone", "reach": 2.7, "half_angle": 80.0,
		"windup_clip": "sweep_windup", "attack_clip": "sweep", "windup": 0.65, "track": 0.45,
		"attack_time": 0.5, "window": Vector2(0.1, 0.26), "lunge": 3.0, "dash": 0.0,
		"damage": 3.0, "recover": 0.8},
	"smash": {"range": [1.2, 3.4], "weight": 2, "cooldown": 0.0, "shape": "circle", "radius": 1.5, "center": 2.3,
		"windup_clip": "smash_windup", "attack_clip": "smash", "windup": 1.0, "track": 0.7,
		"attack_time": 0.6, "window": Vector2(0.12, 0.24), "lunge": 4.0, "dash": 0.0,
		"damage": 5.0, "recover": 1.4, "shake": 0.55},
	"stomp": {"range": [0.0, 1.5], "weight": 2, "cooldown": 4.0, "shape": "circle", "radius": 3.0, "center": 0.0,
		"windup_clip": "stomp_windup", "attack_clip": "stomp", "windup": 0.85, "track": 0.0,
		"attack_time": 0.55, "window": Vector2(0.1, 0.22), "lunge": 0.0, "dash": 0.0,
		"damage": 3.0, "recover": 1.0, "shake": 0.45},
	"charge": {"range": [4.5, 10.0], "weight": 1, "cooldown": 7.0, "shape": "line", "reach": 9.0, "width": 2.0,
		"windup_clip": "charge_windup", "attack_clip": "charge", "windup": 1.1, "track": 0.8,
		"attack_time": 0.75, "window": Vector2(0.0, 0.7), "lunge": 0.0, "dash": 13.0,
		"damage": 5.0, "recover": 1.6, "wall_stun": 2.6},
}

func _init() -> void:
	attacks = BRUTE_ATTACKS
	clips = BRUTE_CLIPS
	clip_fallbacks = FALLBACKS
	idle_model = MODEL_DIR + "idle_goblin_bruto.fbx"
	texture = "res://assets/textures/enemigos/textura_goblin_bruto.png"
	model_height = 1.95
	enemy_type = EnemyData.EnemyType.HEAVY_BRUTE
	hp_mult = 1.5                 # 90 × 1,5 = 135 (el goblin normal tiene 80)
	speed_mult = 1.6              # 2,0 de las hordas es demasiado lento en una caverna: 3,2 m/s
	hit_radius = 0.75
	hit_height = 2.0
	hurt_time = 0.3
	stagger_time = 1.6
	stagger_damage = 36.0
	stagger_knock = 16.0
	windup_poise = 36.0
	armor = 20.0
	armor_break = 44.0
	glance_armor = true
	knock_scale = 0.25
	warn_sfx = "brute_warn"
	swing_sfx = "brute_swing"
	hurt_sfx = "brute_hurt"
	die_sfx = "brute_die"
	sfx_pitch = 1.0
