class_name DungeonZombie
extends DungeonGoblin

## Goblin zombi de la mazmorra: lento y torpe, pero se levanta una vez si no se le remata.
## Comparte la máquina de estados de DungeonGoblin; cambia el repertorio, el modelo y la muerte.
##
##  - claw (zarpazo doble): de cerca; cuña corta → alejarse.
##  - lunge (abalanzarse): a media distancia, con línea de visión; franja corta → apartarse de lado.
## Reanimación: la primera vez que muere cae boca abajo y sigue en EnemyRegistry (se le puede
## golpear). Si nadie le golpea en REVIVE_TIME, se levanta con REVIVE_HP de su vida; un golpe
## mientras está en el suelo lo remata. Un brillo verde que late cada vez más deprisa avisa.
## Es lo que invoca el jefe necromántico (DungeonNecromancer).

const ZOMBIE_DIR := MODEL_DIR + "dungeon/zombi/"
const ZOMBIE_CLIPS := {
	"walk": MODEL_DIR + "goblin_caminar_zombie.fbx",
	"claw_windup": ZOMBIE_DIR + "zombie_claw_windup.fbx",
	"claw": ZOMBIE_DIR + "zombie_claw.fbx",
	"lunge_windup": ZOMBIE_DIR + "zombie_lunge_windup.fbx",
	"lunge": ZOMBIE_DIR + "zombie_lunge.fbx",
	"recover": ZOMBIE_DIR + "zombie_recover.fbx",
	"hurt": ZOMBIE_DIR + "zombie_hurt.fbx",
	"death": ZOMBIE_DIR + "zombie_death.fbx",
	"rise": ZOMBIE_DIR + "zombie_rise.fbx",
}
const ZOMBIE_ATTACKS := {
	"claw": {"range": [0.0, 1.8], "weight": 3, "cooldown": 0.0, "shape": "cone", "reach": 2.0, "half_angle": 60.0,
		"windup_clip": "claw_windup", "attack_clip": "claw", "windup": 0.55, "track": 0.4,
		"attack_time": 0.4, "window": Vector2(0.08, 0.2), "lunge": 3.0, "dash": 0.0,
		"damage": 2.0, "recover": 0.7},
	"lunge": {"range": [2.5, 5.0], "weight": 2, "cooldown": 4.0, "shape": "line", "reach": 4.5, "width": 1.2,
		"windup_clip": "lunge_windup", "attack_clip": "lunge", "windup": 0.8, "track": 0.6,
		"attack_time": 0.5, "window": Vector2(0.1, 0.35), "lunge": 0.0, "dash": 10.0,
		"damage": 3.0, "recover": 1.0, "wall_stun": 1.0},
}
const COLOR := Color(0.45, 1.0, 0.2)
const REVIVE_TIME := 3.0              ## segundos en el suelo antes de levantarse
const REVIVE_HP := 0.5                ## fracción de la vida con la que se levanta
const RISE_TIME := 1.45               ## lo que dura el clip "rise" (s)

## Puede levantarse (los invocados por el jefe no: si no, el combate se alarga demasiado)
var can_revive := true
var _downed := false
var _revived := false
var _down_t := 0.0

func _init() -> void:
	attacks = ZOMBIE_ATTACKS
	clips = ZOMBIE_CLIPS
	idle_model = MODEL_DIR + "goblin_idle_zombie.fbx"
	texture = "res://assets/textures/enemigos/textura_zombie_goblin.png"
	model_height = 1.3
	enemy_type = EnemyData.EnemyType.ZOMBIE_GOBLIN
	hp_mult = 2.0                 # 25 × 2 = 50
	speed_mult = 1.8              # 2,7 m/s
	windup_poise = 20.0
	stagger_damage = 21.0
	armor = 10.0
	armor_break = 30.0
	knock_scale = 0.6
	telegraph_color = COLOR
	warn_sfx = "zombie_warn"
	swing_sfx = "zombie_swing"
	hurt_sfx = "zombie_hurt"
	die_sfx = "zombie_die"
	sfx_pitch = 1.0

func is_downed() -> bool:
	return _downed

func take_damage(amount: float, knockback_dir: Vector3 = Vector3.ZERO) -> void:
	if puppet:
		super(amount, knockback_dir)
		return
	if _downed:
		# En el suelo: cualquier golpe lo remata
		_downed = false
		_revived = true
		_flash_color = Color(1, 1, 1)
		_flash = 1.0
		HitFeedback.on_enemy_hit(self, amount, knockback_dir, true)
		super._die()
		_anim.seek(_anim.current_animation_length, true)   # ya está tumbado: no repetir la caída
		return
	super(amount, knockback_dir)

## Un remate lo deja muerto del todo (no se levanta).
func receive_finisher(dir: Vector3) -> void:
	if not puppet:
		_revived = true
	super(dir)

func _die() -> void:
	if not can_revive or _revived:
		super()
		return
	# Primera muerte: cae, pero sigue siendo un blanco (y la caverna sigue cerrada)
	_downed = true
	_down_t = 0.0
	_set_state(State.DEAD)
	AudioManager.play_at("zombie_die", global_position, -3.0, 1.1)

func _physics_process(delta: float) -> void:
	super(delta)
	if not _downed:
		return
	_down_t += delta
	# Brillo verde que late cada vez más rápido: ¡se va a levantar!
	var k := clampf(_down_t / REVIVE_TIME, 0.0, 1.0)
	_flash_color = COLOR
	_flash = maxf(_flash, (0.1 + 0.5 * k) * (0.5 + 0.5 * sin(_down_t * (4.0 + 16.0 * k))))
	if _down_t >= REVIVE_TIME:
		_rise()

func _rise() -> void:
	_downed = false
	_revived = true
	hp = max_hp * REVIVE_HP
	_set_state(State.HURT)
	_state_t = hurt_time - RISE_TIME   # la reacción dura lo que tarda en levantarse
	_play("rise", 0.05)
	AudioManager.play_at("zombie_rise", global_position, 0.0)
