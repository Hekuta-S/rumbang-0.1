class_name DungeonSlug
extends DungeonGoblin

## Babosa de basura de las cloacas: lenta y blanda, con chatarra pegada al lomo. Comparte la
## máquina de estados de DungeonGoblin; cambia el repertorio, el modelo
## (blender_sources/sewer_enemies.blend) y la muerte.
##
##  - slam (panzazo): se yergue y se deja caer hacia delante; cono corto → alejarse. Deja baba.
##  - spit (escupitajo): de lejos, un glóbulo lento en línea recta (MageOrb) → apartarse de lado.
## Baba: al arrastrarse deja manchas (SlimePuddle) que frenan al jugador.
## División: la grande, al morir, suelta SPLIT_COUNT babosas pequeñas (`small`), que no se dividen
## ni escupen. Las avisa con `spawned` antes de `died` para que DungeonEncounter las cuente.

signal spawned(child: DungeonGoblin)

const SLUG_DIR := "res://assets/models/entities/enemigos/sewers/babosa/"
const SLUG_CLIPS := {
	"walk": SLUG_DIR + "slug_walk.fbx",
	"slam_windup": SLUG_DIR + "slug_slam_windup.fbx",
	"slam": SLUG_DIR + "slug_slam.fbx",
	"spit_windup": SLUG_DIR + "slug_spit_windup.fbx",
	"spit": SLUG_DIR + "slug_spit.fbx",
	"recover": SLUG_DIR + "slug_recover.fbx",
	"hurt": SLUG_DIR + "slug_hurt.fbx",
	"death": SLUG_DIR + "slug_death.fbx",
}
const SLUG_ATTACKS := {
	"slam": {"range": [0.0, 2.0], "weight": 3, "cooldown": 0.0, "shape": "cone", "reach": 2.3, "half_angle": 50.0,
		"windup_clip": "slam_windup", "attack_clip": "slam", "windup": 0.75, "track": 0.5,
		"attack_time": 0.42, "window": Vector2(0.06, 0.2), "lunge": 3.0, "dash": 0.0,
		"damage": 2.0, "recover": 0.9, "shake": 0.2, "puddle": 1.1},
	"spit": {"range": [3.5, 11.0], "weight": 2, "cooldown": 3.0, "shape": "line", "reach": 10.0, "width": 0.8,
		"needs_sight": true, "ranged": true, "orb_speed": 8.0,
		"windup_clip": "spit_windup", "attack_clip": "spit", "windup": 0.7, "track": 0.55,
		"attack_time": 0.42, "window": Vector2(0.08, 0.1), "lunge": 0.0, "dash": 0.0,
		"damage": 1.5, "recover": 0.6},
}
const SMALL_ATTACKS := {
	"slam": {"range": [0.0, 1.3], "weight": 1, "cooldown": 0.0, "shape": "cone", "reach": 1.5, "half_angle": 45.0,
		"windup_clip": "slam_windup", "attack_clip": "slam", "windup": 0.55, "track": 0.4,
		"attack_time": 0.42, "window": Vector2(0.06, 0.2), "lunge": 3.0, "dash": 0.0,
		"damage": 1.5, "recover": 0.7, "puddle": 0.6},
}
const COLOR := Color(0.6, 0.9, 0.15)
const SPLIT_COUNT := 2
const TRAIL_STEP := 1.1               ## m recorridos entre dos manchas de baba

## Babosa pequeña (nace de una grande al morir): más rápida, frágil y sin división ni escupitajo
var small := false
## Al morir suelta babosas pequeñas (DungeonBloater, la roja, revienta en su lugar)
var splits := true
var _trail_from := Vector3.INF

func _init() -> void:
	attacks = SLUG_ATTACKS
	clips = SLUG_CLIPS
	idle_model = SLUG_DIR + "slug_idle.fbx"
	texture = ""                  # colores de los materiales del FBX
	model_height = 0.95
	enemy_type = EnemyData.EnemyType.ZOMBIE_GOBLIN
	hp_mult = 2.8                 # 25 × 2,8 = 70
	speed_mult = 1.5              # 2,25 m/s
	hit_radius = 0.6
	hit_height = 0.8
	windup_poise = 16.0
	stagger_damage = 22.0
	knock_scale = 0.6
	telegraph_color = COLOR
	warn_sfx = "slug_gurgle"
	swing_sfx = "slug_splat"
	hurt_sfx = "slug_hurt"
	die_sfx = "slug_die"
	sfx_pitch = 1.0
	face_player_dist = 12.0

## Convierte esta babosa en una pequeña (antes de añadirla al árbol).
func make_small() -> DungeonSlug:
	small = true
	attacks = SMALL_ATTACKS
	model_height = 0.5
	hp_mult = 0.8                 # 20
	speed_mult = 2.0              # 3 m/s
	hit_radius = 0.35
	hit_height = 0.5
	windup_poise = 6.0
	stagger_damage = 12.0
	knock_scale = 1.1
	sfx_pitch = 1.4
	face_player_dist = 4.0
	return self

func _physics_process(delta: float) -> void:
	super(delta)
	if state == State.DEAD:
		return
	if _trail_from == Vector3.INF:
		_trail_from = global_position
	elif global_position.distance_to(_trail_from) >= TRAIL_STEP * (0.6 if small else 1.0):
		_trail_from = global_position
		SlimePuddle.spawn(get_parent(), global_position - _facing * hit_radius, 0.45 if small else 0.75)

func _on_impact() -> void:
	super()
	if _atk.has("puddle"):
		var at := global_position + _facing * float(_atk["reach"]) * 0.55
		SlimePuddle.spawn(get_parent(), at, float(_atk["puddle"]))
		_splash(at, float(_atk["puddle"]))
	if not _atk.get("ranged", false):
		return
	var root := get_tree().current_scene
	if root:
		var from := global_position + Vector3(0, 0.7, 0) + _facing * 0.8
		MageOrb.spawn(root, from, _facing, float(_atk["orb_speed"]), float(_atk["damage"]), COLOR, get_rid())
		AudioManager.play_at("slug_spit", from, 0.0, randf_range(0.9, 1.1) * sfx_pitch)

func _die() -> void:
	if splits and not small and not puppet:
		_split()
	super()

## Suelta las babosas pequeñas a los lados, en suelo libre (las registra NetWorld en su _ready).
func _split() -> void:
	var side := _facing.cross(Vector3.UP)
	for i in SPLIT_COUNT:
		var dir := side.rotated(Vector3.UP, TAU * i / SPLIT_COUNT)
		var pos := global_position + dir * 0.7
		if map:
			var cell := map.world_to_cell(pos)
			if not map._cells.has(cell) or map._walls.has(cell) or map._blocked.has(cell):
				pos = global_position
		var s := DungeonSlug.new().make_small()
		s.name = "DungeonSlugSmall"
		s.map = map
		s.position = pos
		get_parent().add_child(s)
		s.global_position = pos
		s._knock = dir * 7.0
		spawned.emit(s)
	_splash(global_position, 1.2)
	AudioManager.play_at("slug_splat", global_position, 0.0, 0.7)

func _splash(at: Vector3, r: float) -> void:
	var root := get_tree().current_scene
	if root == null:
		return
	var goo := DustVFX.haze(14, 0.6, r * 0.6, 0.12, 0.3, COLOR.darkened(0.3), 0.25)
	goo.one_shot = true
	goo.explosiveness = 0.95
	goo.initial_velocity_min = 1.5
	goo.initial_velocity_max = 3.0
	root.add_child(goo)
	goo.global_position = at + Vector3(0, 0.2, 0)
	goo.emitting = true
	get_tree().create_timer(1.0).timeout.connect(goo.queue_free)
