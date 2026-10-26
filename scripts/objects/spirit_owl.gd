class_name SpiritOwl
extends SpiritAnimal

## Búho espiritual (a distancia): vuela desde arriba, se lanza en picada sobre el enemigo,
## lo golpea (daño en un radio pequeño + veneno) y se aleja ascendiendo.

const MODEL = preload("res://assets/models/spirits/owl.glb")
const HIT_RADIUS := 1.9
const POISON_DPS_FACTOR := 0.3
const POISON_TIME := 5.0
const KNOCKBACK := 7.0
const START_HEIGHT := 3.2
const EXIT_TIME := 0.7

var target = null
var hits: int = 0
var _start: Vector3
var _target_pos: Vector3
var _strike_pos: Vector3
var _exit_pos: Vector3
var _dir: Vector3 = Vector3.FORWARD
var _prev_pos: Vector3

## Invoca un búho que atacará a `enemy`.
static func summon(parent: Node, p: Node3D, enemy, dmg: float, size: float, weapon: int) -> SpiritOwl:
	var o := SpiritOwl.new()
	o.player = p
	o.target = enemy
	o.damage = dmg
	o.scale_mult = size
	o.source_weapon = weapon
	o.strike_time = 0.55
	parent.add_child(o)
	var d: Vector3 = enemy.global_position - p.global_position
	d.y = 0.0
	o._dir = d.normalized() if d.length_squared() > 0.0001 else Vector3.FORWARD
	o._start = p.global_position + Vector3(0, START_HEIGHT * size, 0) - o._dir * 1.5
	o._target_pos = enemy.global_position + Vector3(0, 0.9, 0)
	o.global_position = o._start
	o._prev_pos = o._start
	o.build(MODEL)
	o._face(o._target_pos - o._start)
	return o

func _face(v: Vector3) -> void:
	if v.length_squared() > 0.0001:
		look_at(global_position + v.normalized(), Vector3.UP)

func _motion(_delta: float) -> void:
	if not struck:
		if is_instance_valid(target):
			_target_pos = target.global_position + Vector3(0, 0.9, 0)
		var s := clampf(_elapsed / strike_time, 0.0, 1.0)
		s = s * s * (3.0 - 2.0 * s) * 0.6 + s * 0.4       # arranque suave, picada decidida
		global_position = _start.lerp(_target_pos, s)
	else:
		var s2 := clampf((_elapsed - strike_time) / EXIT_TIME, 0.0, 1.5)
		global_position = _strike_pos.lerp(_exit_pos, s2 * s2 * 0.5 + s2 * 0.5)
	var v := global_position - _prev_pos
	if v.length_squared() > 0.00001:
		_face(v)
	_prev_pos = global_position

func _on_strike() -> void:
	_strike_pos = global_position
	_exit_pos = _strike_pos + _dir * 5.0 + Vector3(0, 4.0 * scale_mult, 0)
	var center := _strike_pos
	var radius := HIT_RADIUS * scale_mult
	for e in EnemyRegistry.all():
		if not is_instance_valid(e):
			continue
		var off: Vector3 = e.global_position - center
		off.y = 0.0
		if off.length() > radius:
			continue
		var kb := (off.normalized() if off.length() > 0.05 else _dir) * KNOCKBACK
		if hit_enemy(e, damage, kb):
			hits += 1
			if is_instance_valid(e) and e.has_method("apply_status"):
				e.apply_status("poison", damage * POISON_DPS_FACTOR, POISON_TIME, player, source_weapon)
	AudioManager.play_at("hit", center, -8.0, 1.25)
