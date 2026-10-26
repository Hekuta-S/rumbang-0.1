class_name SpiritHippo
extends SpiritAnimal

## Cabeza de hipopótamo espiritual (melee): emerge del suelo sobre el grupo de enemigos más
## denso y los devora. Su "estómago" tiene capacidad según el tamaño de cada enemigo
## (pequeño = 1, mediano = 2, grande = 3). Lo que no cabe recibe un mordisco normal.

const MODEL = preload("res://assets/models/spirits/hippo.glb")
const BASE_CAPACITY := 3
const MOUTH_RADIUS := 2.3
const MOUTH_FORWARD := 0.9        ## m (a escala 1) del origen de la cabeza al centro de la boca
const RISE_TIME := 0.3
const RISE_DEPTH := 1.6
const NO_FIT := 99                ## coste de lo que no se puede devorar (jefes)

var capacity: int = BASE_CAPACITY
var center: Vector3 = Vector3.ZERO
var facing: Vector3 = Vector3.FORWARD
var eaten: int = 0
var eaten_cost: int = 0
var bitten: int = 0               ## enemigos que no cupieron y solo recibieron daño
var _ground: Vector3

## Cuánto "estómago" ocupa un enemigo.
static func devour_cost(e) -> int:
	if "type" in e and "max_hp" in e and e.max_hp <= 400.0:
		match int(e.type):
			2: return 3     # HEAVY_BRUTE
			4: return 2     # ZOMBIE_GOBLIN
			_: return 1
	return NO_FIT

## El enemigo con más vecinos dentro del radio de la boca (empate: el más cercano al jugador).
static func pick_target(tree: SceneTree, from: Vector3, search_range: float):
	var cands: Array = []
	for e in EnemyRegistry.all():
		if is_instance_valid(e) and e.global_position.distance_to(from) <= search_range:
			cands.append(e)
	var best = null
	var best_n := -1
	var best_d := INF
	for e in cands:
		var n := 0
		for o in cands:
			var off: Vector3 = o.global_position - e.global_position
			off.y = 0.0
			if off.length() <= MOUTH_RADIUS:
				n += 1
		var d: float = e.global_position.distance_to(from)
		if n > best_n or (n == best_n and d < best_d):
			best = e
			best_n = n
			best_d = d
	return best

static func summon(parent: Node, p: Node3D, enemy, dmg: float, size: float, weapon: int, cap: int = BASE_CAPACITY) -> SpiritHippo:
	var h := SpiritHippo.new()
	h.player = p
	h.damage = dmg
	h.scale_mult = size * 1.3
	h.source_weapon = weapon
	h.capacity = cap
	h.strike_time = 0.47
	parent.add_child(h)
	h.center = enemy.global_position
	var d: Vector3 = p.global_position - enemy.global_position
	d.y = 0.0
	h.facing = d.normalized() if d.length_squared() > 0.0001 else Vector3.BACK    # mira hacia el jugador
	h._ground = h.center - h.facing * MOUTH_FORWARD * h.scale_mult
	h.global_position = h._ground - Vector3(0, RISE_DEPTH, 0)
	h.look_at(h.global_position - h.facing, Vector3.UP)      # el modelo mira a -Z
	h.build(MODEL)
	return h

func _motion(_delta: float) -> void:
	var t := clampf(_elapsed / RISE_TIME, 0.0, 1.0)
	t = 1.0 - pow(1.0 - t, 3.0)
	global_position = _ground - Vector3(0, RISE_DEPTH * (1.0 - t), 0)

func _on_strike() -> void:
	var budget := capacity
	var mouth := center
	var r := MOUTH_RADIUS * scale_mult / 1.3
	var inside: Array = []
	for e in EnemyRegistry.all():
		if not is_instance_valid(e):
			continue
		var off: Vector3 = e.global_position - mouth
		off.y = 0.0
		if off.length() <= r:
			inside.append([off.length(), e])
	inside.sort_custom(func(a, b): return a[0] < b[0])
	for item in inside:
		var e = item[1]
		if not is_instance_valid(e):
			continue
		var cost := devour_cost(e)
		if cost <= budget:
			budget -= cost
			var pos: Vector3 = e.global_position
			var lethal: float = maxf(float(e.hp), 1.0) + 1.0
			if hit_enemy(e, lethal, Vector3.ZERO):
				eaten += 1
				eaten_cost += cost
				spawn_vanish_burst(get_parent(), pos + Vector3(0, 0.8, 0), 0.5)
		else:
			if hit_enemy(e, damage, -facing * 6.0):
				bitten += 1
	AudioManager.play_at("hit", mouth, -4.0, 0.6)
