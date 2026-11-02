class_name DungeonRat
extends DungeonGoblin

## Rata de cloaca: pequeña, rápida y frágil; nunca viene sola (WorldDefs "swarm" la multiplica al
## formar el grupo). Comparte la máquina de estados de DungeonGoblin; cambia el repertorio, el
## modelo (blender_sources/sewer_enemies.blend) y cómo encaja los golpes.
##
##  - bite (mordisco): pegada al jugador; anticipación muy corta y cono estrecho → alejarse.
##  - pounce (salto): de media distancia se agazapa, tiembla y se lanza en línea → apartarse de lado.
## Cualquier golpe la interrumpe (`windup_poise` bajo) y sale despedida lejos: el peligro es el
## número, no cada rata.

const RAT_DIR := "res://assets/models/entities/enemigos/sewers/rata/"
const RAT_CLIPS := {
	"walk": RAT_DIR + "rat_walk.fbx",
	"bite_windup": RAT_DIR + "rat_bite_windup.fbx",
	"bite": RAT_DIR + "rat_bite.fbx",
	"pounce_windup": RAT_DIR + "rat_pounce_windup.fbx",
	"pounce": RAT_DIR + "rat_pounce.fbx",
	"recover": RAT_DIR + "rat_recover.fbx",
	"hurt": RAT_DIR + "rat_hurt.fbx",
	"death": RAT_DIR + "rat_death.fbx",
}
const RAT_ATTACKS := {
	"bite": {"range": [0.0, 1.3], "weight": 3, "cooldown": 0.0, "shape": "cone", "reach": 1.4, "half_angle": 45.0,
		"windup_clip": "bite_windup", "attack_clip": "bite", "windup": 0.32, "track": 0.22,
		"attack_time": 0.33, "window": Vector2(0.04, 0.16), "lunge": 5.0, "dash": 0.0,
		"damage": 1.5, "recover": 0.45},
	"pounce": {"range": [2.5, 5.5], "weight": 2, "cooldown": 3.5, "shape": "line", "reach": 5.0, "width": 0.9,
		"windup_clip": "pounce_windup", "attack_clip": "pounce", "windup": 0.6, "track": 0.45,
		"attack_time": 0.5, "window": Vector2(0.05, 0.35), "lunge": 0.0, "dash": 12.0,
		"damage": 2.0, "recover": 0.6, "wall_stun": 0.9},
}

func _init() -> void:
	attacks = RAT_ATTACKS
	clips = RAT_CLIPS
	idle_model = RAT_DIR + "rat_idle.fbx"
	texture = ""                  # colores de los materiales del FBX
	model_height = 0.5
	enemy_type = EnemyData.EnemyType.NORMAL_GOBLIN
	hp_mult = 0.4                 # 40 × 0,4 = 16
	speed_mult = 1.25             # 5,6 m/s
	hit_radius = 0.35
	hit_height = 0.6
	hurt_time = 0.25
	stagger_time = 0.9
	stagger_damage = 10.0
	windup_poise = 3.0
	knock_scale = 1.5
	warn_sfx = "rat_squeak"
	swing_sfx = "rat_bite"
	hurt_sfx = "rat_hurt"
	die_sfx = "rat_die"
	sfx_pitch = 1.0
	attack_rest = 0.25
	face_player_dist = 6.0
