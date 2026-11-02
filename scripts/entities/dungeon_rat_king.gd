class_name DungeonRatKing
extends DungeonNecromancer

## Rey Rata: jefe de las cloacas (WorldDefs["sewers"]["boss"]). Una rata gorda y erguida con corona
## de lata, capa de bolsa de basura y un desatascador por cetro (blender_sources/sewer_enemies.blend).
## Hereda del Nigromante las fases, la barra de jefe, el rugido inmune y la armadura; cambia el
## repertorio y lo que invoca.
##
##  - claw (desatascazo): de cerca; cuña ancha → alejarse o esquivar.
##  - sweep (coletazo): gira sobre sí mismo con la cola extendida; círculo a su alrededor → salir
##    del anillo. Solo si el jugador se le pega.
##  - charge (embestida real): de lejos, agachado; franja ancha → apartarse. Contra una pared queda
##    aturdido mucho rato: la mejor ocasión para castigarle.
##  - eruption (géiseres de alcantarilla): golpea el suelo y revientan varios círculos alrededor del
##    jugador, escalonados (como el Nigromante, en amarillo tóxico) → salir de los círculos.
##  - summon (llamada): chilla y acuden ratas (DungeonRat) desde los lados; caen con él.
##  - roar: solo al cambiar de fase (inmune mientras ruge).

const KING_DIR := "res://assets/models/entities/enemigos/sewers/rey_rata/"
const KING_CLIPS := {
	"walk": KING_DIR + "king_walk.fbx",
	"claw_windup": KING_DIR + "king_claw_windup.fbx",
	"claw": KING_DIR + "king_claw.fbx",
	"sweep_windup": KING_DIR + "king_sweep_windup.fbx",
	"sweep": KING_DIR + "king_sweep.fbx",
	"charge_windup": KING_DIR + "king_charge_windup.fbx",
	"charge": KING_DIR + "king_charge.fbx",
	"erupt": KING_DIR + "king_erupt.fbx",
	"summon": KING_DIR + "king_summon.fbx",
	"roar": KING_DIR + "king_roar.fbx",
	"recover": KING_DIR + "king_recover.fbx",
	"hurt": KING_DIR + "king_hurt.fbx",
	"death": KING_DIR + "king_death.fbx",
}
## Mismo formato que DungeonNecromancer.NECRO_ATTACKS.
const KING_ATTACKS := {
	"claw": {"range": [0.0, 3.2], "weight": 3, "cooldown": 0.0, "shape": "cone", "reach": 3.6, "half_angle": 65.0,
		"windup_clip": "claw_windup", "attack_clip": "claw", "windup": 0.75, "track": 0.5,
		"attack_time": 0.55, "window": Vector2(0.08, 0.25), "lunge": 6.0, "dash": 0.0,
		"damage": 5.0, "recover": 0.8},
	"sweep": {"range": [0.0, 2.6], "weight": 2, "cooldown": 5.0, "shape": "circle", "radius": 3.8, "center": 0.0,
		"windup_clip": "sweep_windup", "attack_clip": "sweep", "windup": 0.9, "track": 0.0,
		"attack_time": 0.58, "window": Vector2(0.06, 0.32), "lunge": 0.0, "dash": 0.0,
		"damage": 4.0, "recover": 1.0, "shake": 0.3},
	"charge": {"range": [5.0, 16.0], "weight": 2, "cooldown": 7.0, "shape": "line", "reach": 13.0, "width": 2.2,
		"windup_clip": "charge_windup", "attack_clip": "charge", "windup": 1.0, "track": 0.8,
		"attack_time": 0.8, "window": Vector2(0.0, 0.75), "lunge": 0.0, "dash": 14.0,
		"damage": 6.0, "recover": 1.4, "wall_stun": 2.4},
	"eruption": {"range": [3.0, 20.0], "weight": 2, "cooldown": 6.0, "shape": "none", "ranged": true, "eruption": true,
		"windup_clip": "erupt", "attack_clip": "", "windup": 0.9, "track": 0.9,
		"attack_time": 1.2, "window": Vector2(0.05, 0.06), "lunge": 0.0, "dash": 0.0,
		"damage": 3.0, "recover": 0.6, "shake": 0.35},
	"summon": {"range": [0.0, 30.0], "weight": 1, "cooldown": 16.0, "shape": "none", "ranged": true, "summon": true,
		"windup_clip": "summon", "attack_clip": "", "windup": 1.2, "track": 0.0,
		"attack_time": 0.9, "window": Vector2(0.1, 0.11), "lunge": 0.0, "dash": 0.0,
		"damage": 0.0, "recover": 0.5},
	"roar": {"range": [-1.0, -1.0], "weight": 0, "cooldown": 0.0, "shape": "circle", "radius": 5.0, "center": 0.0,
		"windup_clip": "roar", "attack_clip": "", "windup": 0.6, "track": 0.0,
		"attack_time": 0.7, "window": Vector2(0.0, 0.12), "lunge": 0.0, "dash": 0.0,
		"damage": 2.0, "recover": 0.4, "shake": 0.7},
}
const KING_COLOR := Color(0.9, 0.78, 0.15)
const PHASE_RATS := [3, 4, 6]         ## ratas por llamada en cada fase
const MAX_RATS := 8
const FIRST_SUMMON := 8.0           ## s hasta la primera llamada: abre el combate atacando

var _rats: Array[DungeonRat] = []

func _init() -> void:
	super()                       # armadura, aturdimiento y ritmo de jefe del Nigromante
	attacks = KING_ATTACKS
	clips = KING_CLIPS
	idle_model = KING_DIR + "king_idle.fbx"
	texture = ""                  # colores de los materiales del FBX
	model_height = 3.0
	hp_mult = 18.0                # 40 × 18 = 720
	speed_mult = 0.6              # 2,7 m/s
	hit_radius = 0.75             # flaco y huesudo
	hit_height = 2.8
	telegraph_color = KING_COLOR
	boss_name = "REY RATA"
	warn_sfx = "king_screech"
	hurt_sfx = "rat_hurt"         # grave con sfx_pitch
	die_sfx = "king_die"
	sfx_pitch = 0.6

func _ready() -> void:
	super()
	_atk_ready["summon"] = FIRST_SUMMON

## Acuden ratas desde los lados, en suelo libre (no cuentan para la caverna: caen con él).
func _summon() -> void:
	_rats = _rats.filter(func(r): return is_instance_valid(r) and not r.is_dead())
	var n := mini(PHASE_RATS[phase], MAX_RATS - _rats.size())
	for i in n:
		var pos := global_position
		for t in 8:
			var ang := randf() * TAU
			var cand := global_position + Vector3(cos(ang), 0.0, sin(ang)) * randf_range(3.0, 5.5)
			if map == null:
				pos = cand
				break
			var cell := map.world_to_cell(cand)
			if map._cells.has(cell) and not map._walls.has(cell) and not map._blocked.has(cell):
				pos = cand
				break
		var r := DungeonRat.new()
		r.map = map
		r.position = Vector3(pos.x, global_position.y + 0.1, pos.z)
		get_parent().add_child(r)
		r.global_position = Vector3(pos.x, global_position.y + 0.1, pos.z)
		SpawnDissolve.play(r.get_model(), r, 0.6, telegraph_color, 1.0)
		_rats.append(r)
	AudioManager.play_at("king_screech", global_position, 2.0, 1.25)

func summon_count() -> int:
	return super() + _rats.filter(func(r): return is_instance_valid(r) and not r.is_dead()).size()

func _die() -> void:
	super()
	for r in _rats:
		if is_instance_valid(r) and not r.is_dead():
			r.take_damage(9999.0, Vector3.ZERO)
	_rats.clear()
