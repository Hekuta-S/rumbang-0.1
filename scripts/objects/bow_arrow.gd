class_name BowArrow
extends Node3D

## Flecha del arco (BowStrategy). Vuela en línea recta (con algo de caída si no va cargada), detecta enemigos sin
## física (EnemyQuery.segment_hit, cada uno una vez) y paredes/suelo con un rayo (rompe objetos destructibles).
## `pierce`: enemigos que atraviesa antes de quedarse (0 = se clava en el primero; -1 = todos). Al tocar una pared se
## queda clavada unos segundos.

const STUCK_TIME := 3.0
const GRAVITY := 4.0                  ## m/s² de caída de las flechas normales (las cargadas van rectas)
## Punto débil del arco (mazmorra): a quemarropa la flecha no llega a tensarse y hace la mitad de daño.
const POINT_BLANK_DIST := 2.5
const POINT_BLANK_MULT := 0.5

var velocity := Vector3.ZERO
var damage := 10.0
var knockback := 4.0
var stun := 0.0                       ## fracción extra de la barra de aturdimiento por impacto
var pierce := 0
var max_range := 30.0
var gravity := GRAVITY
var weapon := WeaponData.WeaponType.BOW
var source_player: Node = null
var color := Color(1.0, 0.85, 0.5)
var glow := 0.0
var _traveled := 0.0
var _hit: Array = []
var _stuck := -1.0
var _trails: Array[BladeTrail] = []
## Estela: dos cintas cruzadas (vertical y horizontal) junto a las plumas, para que se vea desde cualquier lado
## (con los dos puntos a lo largo de la flecha la cinta salía de ancho cero). Más ancha en las cargadas.
const TRAIL_HALF_WIDTH := 0.06
const TRAIL_AT_Z := 0.55               ## dónde nace, entre la punta (0) y el culatín (0,8)

## Crea y lanza una flecha desde `from` con velocidad `vel` (m/s).
static func shoot(parent: Node, from: Vector3, vel: Vector3, p_damage: float, opts: Dictionary = {}) -> BowArrow:
	var a := BowArrow.new()
	a.velocity = vel
	a.damage = p_damage
	a.knockback = float(opts.get("kb", 4.0))
	a.stun = float(opts.get("stun", 0.0))
	a.pierce = int(opts.get("pierce", 0))
	a.max_range = float(opts.get("range", 30.0))
	a.gravity = float(opts.get("gravity", GRAVITY))
	a.color = opts.get("color", a.color)
	a.glow = float(opts.get("glow", 0.0))
	a.source_player = opts.get("player")
	parent.add_child(a)
	a.global_position = from
	a._face()
	return a

func _ready() -> void:
	var model := BowModels.build_arrow(color, glow)
	# El modelo tiene la punta en -Z a 0,8 m del culatín: se adelanta para que la punta vaya en el origen
	model.position.z = 0.8
	add_child(model)
	var hw := TRAIL_HALF_WIDTH * (1.6 if glow > 0.0 else 1.0)
	for axis in [Vector3.UP, Vector3.RIGHT]:
		var base := Marker3D.new()
		base.position = Vector3(0, 0, TRAIL_AT_Z) - axis * hw
		add_child(base)
		var tip := Marker3D.new()
		tip.position = Vector3(0, 0, TRAIL_AT_Z) + axis * hw
		add_child(tip)
		var trail := BladeTrail.new()
		add_child(trail)
		trail.setup(base, tip, color)
		trail.emit(1000.0)                 # todo el vuelo; se corta al clavarse
		_trails.append(trail)
	if glow > 0.0:
		var light := Quality.new_light()
		if light:
			light.light_color = color
			light.light_energy = 1.2
			light.omni_range = 2.5
			add_child(light)

func _face() -> void:
	if velocity.length_squared() > 0.0001:
		var up := Vector3.UP if absf(velocity.normalized().dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
		look_at(global_position + velocity, up)

func _physics_process(delta: float) -> void:
	if _stuck >= 0.0:
		_stuck += delta
		if _stuck >= STUCK_TIME:
			queue_free()
		return
	velocity.y -= gravity * delta
	var from := global_position
	var step := velocity * delta
	var to := from + step
	# Pared / suelo / objeto: hasta dónde llega este paso
	var q := PhysicsRayQueryParameters3D.create(from, to + step.normalized() * 0.05, 1)
	var wall := get_world_3d().direct_space_state.intersect_ray(q)
	var limit := to
	if not wall.is_empty():
		limit = wall["position"]
	# Enemigos en el tramo (antes de la pared), cada uno una vez
	while true:
		var hit := EnemyQuery.segment_hit(from, limit, 0.08, _hit)
		if hit.is_empty():
			break
		var e: Object = hit["enemy"]
		_hit.append(e)
		_damage_enemy(e)
		if pierce >= 0 and _hit.size() > pierce:
			_finish_on_enemy(hit["pos"])
			return
	if not wall.is_empty():
		var col: Object = wall.get("collider")
		if col is Node and (col as Node).is_in_group("destructibles") and col.has_method("take_damage"):
			col.take_damage(damage, velocity.normalized())
		global_position = (wall["position"] as Vector3) - velocity.normalized() * 0.25
		_stick()
		return
	global_position = to
	_traveled += step.length()
	_face()
	if _traveled >= max_range:
		queue_free()

func _damage_enemy(e: Object) -> void:
	if not is_instance_valid(e) or not e.has_method("take_damage"):
		return
	if (e.has_method("is_dead") and e.is_dead()) or damage <= 0.0:
		return     # (la flecha del remate solo se ve: el daño lo pone el remate)
	var dir := Vector3(velocity.x, 0.0, velocity.z).normalized()
	HitFeedback.weapon_tag = weapon
	var dmg := damage * point_blank_mult(e)
	e.take_damage(dmg, dir * knockback)
	if stun > 0.0 and e.has_method("add_stun_fraction"):
		e.add_stun_fraction(stun)
	if is_instance_valid(source_player) and source_player.has_method("on_damage_dealt"):
		source_player.on_damage_dealt(dmg, weapon)

## POINT_BLANK_MULT si el tirador está a menos de POINT_BLANK_DIST del enemigo (solo mazmorra), si no 1.
func point_blank_mult(e: Object) -> float:
	if GameData.game_mode != "dungeon" or not is_instance_valid(source_player) or not (e is Node3D):
		return 1.0
	var a: Vector3 = (source_player as Node3D).global_position
	var b: Vector3 = (e as Node3D).global_position
	return POINT_BLANK_MULT if Vector2(a.x - b.x, a.z - b.z).length() < POINT_BLANK_DIST else 1.0

func _finish_on_enemy(at: Vector3) -> void:
	global_position = at
	queue_free()

func _stick() -> void:
	_stuck = 0.0
	for t in _trails:
		t._emit_left = 0.0
	_face()
	AudioManager.play_at("proj_hit_wall", global_position, -10.0, 1.5)
