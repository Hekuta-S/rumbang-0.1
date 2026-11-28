class_name DungeonCrow
extends DungeonBat

## Cuervo carroñero de supervivencia: el volador del modo supervivencia (WaveManager lo suelta cada cierto tiempo,
## cada vez más). Es el DungeonBat con otro dibujo del atlas (cuervo de perfil) y la vida/daño que le pone el
## director de la partida. Pica en línea recta desde el aire: se le tira con armas a distancia o se le espera al
## encaramarse. Suelta XP como un goblin normal (más, porque no es tan fácil de alcanzar).

const XP_MULT := 1.5                  ## XP respecto a un goblin normal

func _init() -> void:
	super()
	frames = Vector2i(1, 2)
	sprite_w = 1.0
	faces_right = true
	hover_h = 0.85
	model_height = 0.8
	hp_mult = 0.7
	speed_mult = 1.35
	warn_sfx = "amb_crow"
	hurt_sfx = "wing_flap"
	die_sfx = "amb_crow"
	telegraph_color = Color(1.0, 0.25, 0.1)
