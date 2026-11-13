class_name DungeonBigRat
extends DungeonRat

## Rata gorda de cloaca: el doble de grande que una rata, lenta y dura, con mordisco de perro.
## Viene sola (sin enjambre). Mismo esqueleto y clips que DungeonRat; solo cambia el modelo
## (rat_big_idle.fbx, en blender_sources/sewer_enemies.blend), el repertorio y cómo encaja.
##
##  - bite (dentellada): de cerca; anticipación más larga que la de la rata y cono más largo.
##  - pounce (embestida): de media distancia, franja ancha y lenta → apartarse de lado.
## Armadura ligera: los golpes flojos no la interrumpen; la aturde uno fuerte o varios seguidos.

const BIG_ATTACKS := {
	"bite": {"range": [0.0, 1.9], "weight": 3, "cooldown": 0.0, "shape": "cone", "reach": 2.1, "half_angle": 50.0,
		"windup_clip": "bite_windup", "attack_clip": "bite", "windup": 0.55, "track": 0.35,
		"attack_time": 0.33, "window": Vector2(0.04, 0.16), "lunge": 4.0, "dash": 0.0,
		"damage": 3.0, "recover": 0.7},
	"pounce": {"range": [3.0, 6.0], "weight": 1, "cooldown": 6.0, "shape": "line", "reach": 5.5, "width": 1.4,
		"windup_clip": "pounce_windup", "attack_clip": "pounce", "windup": 0.95, "track": 0.7,
		"attack_time": 0.5, "window": Vector2(0.05, 0.35), "lunge": 0.0, "dash": 9.0,
		"damage": 4.0, "recover": 1.0, "wall_stun": 1.6},
}

func _init() -> void:
	super()
	attacks = BIG_ATTACKS
	idle_model = RAT_DIR + "rat_big_idle.fbx"
	model_height = 0.85
	hp_mult = 1.5                 # 40 × 1,5 = 60
	speed_mult = 0.65             # 2,9 m/s (la rata normal va a 5,6)
	hit_radius = 0.55
	hit_height = 0.95
	hurt_time = 0.35
	stagger_time = 1.2
	stagger_damage = 27.0
	windup_poise = 20.0
	armor = 11.0
	armor_break = 38.0
	glance_armor = true
	knock_scale = 0.45
	sfx_pitch = 0.62
	attack_rest = 0.6
	face_player_dist = 5.0
