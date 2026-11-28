class_name WarTop
extends Node3D

## Trompo de Guerra (objeto activo, ItemEffects), DIBUJADO (ToonFX objetos.png): gira en círculo alrededor del jugador durante `life` s
## y daña a los enemigos que toca (cada uno, como mucho una vez cada HIT_EVERY s).

const ORBIT := 2.6
const ORBIT_SPEED := 4.5           ## rad/s
const HIT_RADIUS := 1.3
const DAMAGE := 14.0
const HIT_EVERY := 0.35
const COLOR := Color(0.85, 0.25, 0.2)
const SIZE := 1.1                  ## m del dibujo
const SPIN_FPS := 16.0

var player: Node3D
var life := 5.0
var dmg_mult := 1.0
var _t := 0.0
var _angle := 0.0
var _body: Sprite3D
var _last_fx := -1.0
var _last_hit: Dictionary = {}     ## EnemyData -> segundo del último golpe

static func spawn(parent: Node, p_player: Node3D, p_life: float, p_mult: float) -> WarTop:
	var w := WarTop.new()
	w.player = p_player
	w.life = p_life
	w.dmg_mult = p_mult
	parent.add_child(w)
	w.global_position = p_player.global_position + Vector3(ORBIT, 0.0, 0.0)
	return w

func _ready() -> void:
	# Trompo dibujado (objetos.png, 4 fotogramas de giro) en billboard
	_body = ToonFX.item_sprite(ToonFX.ITEM_FX_TROMPO, SIZE)
	_body.position.y = SIZE * 0.5
	add_child(_body)

func _process(delta: float) -> void:
	_t += delta
	if _t >= life or not is_instance_valid(player):
		var root := get_tree().current_scene
		if root:
			ToonFX.puff_burst(root, global_position + Vector3(0, 0.4, 0), Color(0.85, 0.8, 0.7), 6, 2.5, 0.5)
		queue_free()
		return
	_angle += ORBIT_SPEED * delta
	var c := player.global_position
	global_position = Vector3(c.x + cos(_angle) * ORBIT, c.y, c.z + sin(_angle) * ORBIT)
	_body.frame = ToonFX.ITEM_FX_TROMPO + int(_t * SPIN_FPS) % 4
	_body.rotation.z = 0.12 * sin(_t * 9.0)       # bamboleo
	for e in EnemyRegistry.all().duplicate():
		if not (e is EnemyData) or e.recycled:
			continue
		var off: Vector3 = e.global_position - global_position
		if absf(off.y) > 2.0 or Vector2(off.x, off.z).length() > HIT_RADIUS:
			continue
		if _t - float(_last_hit.get(e, -99.0)) < HIT_EVERY:
			continue
		_last_hit[e] = _t
		off.y = 0.0
		e.take_damage(DAMAGE * dmg_mult, off.normalized() * 7.0 if off.length() > 0.05 else Vector3.FORWARD * 7.0)
		if _t - _last_fx > 0.12:
			_last_fx = _t
			ToonFX.impact_pop(get_tree().current_scene, e.global_position + Vector3(0, 0.8, 0), Color(1.0, 0.85, 0.4), 0.7)
