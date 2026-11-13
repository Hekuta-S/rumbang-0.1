class_name DungeonBloater
extends DungeonSlug

## Babosa roja hinchada de las cloacas: más rápida que la de basura, va a por el jugador, se infla
## y revienta. Comparte la máquina de estados (y el rastro de baba) de DungeonSlug; no se divide.
##
##  - burst (reventón): pegada al jugador se infla (círculo rojo a su alrededor) y estalla; muere
##    en el estallido → salir del círculo antes de que acabe de hincharse.
## Si la matan antes, revienta igual tras DEATH_FUSE s (más pequeño y flojo): matarla de lejos es
## lo seguro. Su estallido daña también a los enemigos cercanos: revienta en cadena a otras rojas.
## El estallido es un GroundBlast (aviso en el suelo, daño al jugador y copia en red).

const BLOAT_DIR := "res://assets/models/entities/enemigos/sewers/babosa_roja/"
const BLOAT_CLIPS := {
	"walk": SLUG_DIR + "slug_walk.fbx",
	"inflate": BLOAT_DIR + "bloater_inflate.fbx",
	"burst": BLOAT_DIR + "bloater_burst.fbx",
	"recover": SLUG_DIR + "slug_recover.fbx",
	"hurt": SLUG_DIR + "slug_hurt.fbx",
	"death": BLOAT_DIR + "bloater_inflate.fbx",   # al morir se hincha hasta reventar
}
const BURST_RADIUS := 2.6
const BLOAT_ATTACKS := {
	"burst": {"range": [0.0, 1.8], "weight": 1, "cooldown": 0.0, "shape": "circle", "radius": BURST_RADIUS, "center": 0.0,
		"ranged": true, "burst": true,
		"windup_clip": "inflate", "attack_clip": "burst", "windup": 0.9, "track": 0.5,
		"attack_time": 0.3, "window": Vector2(0.0, 0.05), "lunge": 0.0, "dash": 0.0,
		"damage": 5.0, "recover": 0.5},
}
const RED := Color(1.0, 0.25, 0.1)
const DEATH_RADIUS := 2.2
const DEATH_FUSE := 0.6               ## s entre que la matan y que revienta: da tiempo a apartarse
const DEATH_DAMAGE := 3.0
const ENEMY_DAMAGE := 30.0            ## a los enemigos dentro del estallido (revienta a otras rojas)

var _popped := false                  ## reventó ella sola (ataque), no la mataron

func _init() -> void:
	super()
	splits = false
	attacks = BLOAT_ATTACKS
	clips = BLOAT_CLIPS
	idle_model = BLOAT_DIR + "bloater_idle.fbx"
	model_height = 0.85
	hp_mult = 1.2                 # 25 × 1,2 = 30
	speed_mult = 2.0              # 3 m/s
	hit_radius = 0.55
	hit_height = 0.8
	windup_poise = 27.0           # inflándose solo la para un golpe fuerte
	stagger_damage = 23.0
	armor = 12.0
	armor_break = 34.0
	knock_scale = 0.7
	telegraph_color = RED
	sfx_pitch = 0.8
	face_player_dist = 12.0

func _on_impact() -> void:
	# Sin charco ni escupitajo (DungeonSlug): el ataque es reventar
	if _atk.get("burst", false):
		_popped = true
		_die()

func _die() -> void:
	if state == State.DEAD:
		return
	var pos := global_position
	var popped := _popped
	super()
	var delay := 0.05 if popped else DEATH_FUSE
	var radius := BURST_RADIUS if popped else DEATH_RADIUS
	GroundBlast.spawn(get_parent(), pos, radius, delay, float(_atk["damage"]) if popped else DEATH_DAMAGE, RED)
	# Se hincha hasta reventar y desaparece
	_anim.play("inflate", 0.05)
	_anim.speed_scale = 1.0 / maxf(delay, 0.05) * 0.4
	var tw := create_tween()
	tw.tween_property(_model, "scale", _model.scale * 1.35, delay)
	tw.tween_callback(_model.hide)
	var tree := get_tree()
	var me := self
	tree.create_timer(delay).timeout.connect(func():
		AudioManager.play_at("explosion", pos, -2.0, randf_range(0.9, 1.1))
		_splash(pos, radius)
		for e in EnemyRegistry.all():
			if not is_instance_valid(e) or e == me or not e.has_method("is_dead") or e.is_dead():
				continue
			var off: Vector3 = e.global_position - pos
			if Vector2(off.x, off.z).length() <= radius + float(e.get("hit_radius") if e.get("hit_radius") != null else 0.5):
				e.take_damage(ENEMY_DAMAGE, Vector3(off.x, 0.0, off.z).normalized() * 8.0))
