extends Area3D
const _BULLET_SCRIPT := preload("res://scripts/objects/bullet.gd")   # antes load() en cada golpe

## SerpentProjectile.gd
## Joel el druida canaliza serpientes de esmeralda que vuelan rectas (en cono:
## una al centro y dos a los bordes, desviadas por el jugador). Cada serpiente
## daña al primer enemigo u obstáculo que golpea y desaparece.
##
## La TRAYECTORIA es siempre recta (consistente con las balas del juego); el
## cuerpo segmentado solo ondula de forma cosmética para vender la serpiente.

@export var speed: float = 24.0
@export var damage: float = 10.0
@export var max_lifetime: float = 3.0

var direction: Vector3 = Vector3.FORWARD
var lifetime: float = 0.0
var bullet_color: Color = Color(0.3, 0.9, 0.4)
var shooter_rid: RID = RID()
var is_hit: bool = false

const BODY_SEGMENTS: int = 9
var _body_segments: Array = []
var _time: float = 0.0

func _ready() -> void:
	add_to_group("bullets")
	body_entered.connect(_on_body_entered)
	_build_visual()

func setup(dir: Vector3, dmg: float, speed_val: float, shooter: RID = RID()) -> void:
	direction = dir.normalized()
	damage = dmg
	speed = speed_val
	shooter_rid = shooter

	if direction.length_squared() > 0.001 and direction.cross(Vector3.UP).length_squared() > 0.001:
		look_at(global_position + direction, Vector3.UP)

func _physics_process(delta: float) -> void:
	if is_hit: return
	_time += delta
	_animate_body()

	var current_pos = global_position
	var move_step = direction * speed * delta
	var next_pos = current_pos + move_step

	# Raycast de alta precisión paso a paso para atrapar impactos rápidos.
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(current_pos, next_pos)
	query.collision_mask = collision_mask
	if shooter_rid.is_valid():
		query.exclude = [shooter_rid]

	var hit = space_state.intersect_ray(query)
	var eh := EnemyQuery.segment_hit(current_pos, next_pos, 0.15)
	if not eh.is_empty():
		var world_dist: float = current_pos.distance_to(hit.position) if not hit.is_empty() else INF
		if current_pos.distance_to(eh["pos"]) <= world_dist:
			global_position = eh["pos"]
			_on_impact(eh["enemy"], eh["pos"], -direction)
			return
	if not hit.is_empty():
		global_position = hit.position
		_on_impact(hit.collider, hit.position, hit.normal)
		return

	global_position = next_pos
	lifetime += delta
	if lifetime >= max_lifetime:
		queue_free()

func _on_body_entered(body: Node3D) -> void:
	if is_hit: return
	# Guard: la serpiente puede haber sido quitada del árbol antes de la señal.
	if not is_inside_tree(): return
	_on_impact(body, global_position, -direction)

func _on_impact(body, hit_pos: Vector3, hit_normal: Vector3) -> void:
	if is_hit or not is_inside_tree(): return

	var BulletScript: GDScript = _BULLET_SCRIPT   # tipado como recurso: has_method() igual que con load()
	if body.is_in_group("enemies") and body.has_method("take_damage"):
		is_hit = true
		HitFeedback.weapon_tag = WeaponData.WeaponType.SERPENTS
		body.take_damage(damage, direction)
		if BulletScript and BulletScript.has_method("spawn_impact_sparks"):
			BulletScript.spawn_impact_sparks(get_parent(), hit_pos, hit_normal, bullet_color)
		queue_free()
	elif not body.is_in_group("player") and not body.is_in_group("bullets"):
		is_hit = true
		if BulletScript and BulletScript.has_method("spawn_impact_sparks"):
			BulletScript.spawn_impact_sparks(get_parent(), hit_pos, hit_normal, bullet_color)
		queue_free()

func _build_visual() -> void:
	# Dibujado (2D): la cabeza es la mota mágica verde entintada y el cuerpo, nubecitas que ondulan tras ella
	# (_animate_body). Sin mallas, luz ni partículas: antes eran 12 mallas + una luz + un emisor por serpiente.
	for n in ['MeshInstance3D', 'OmniLight3D']:
		var extra := get_node_or_null(n)   # esfera y luz que trae la escena
		if extra:
			extra.queue_free()
	var head := ToonFX.magic_sprite(ToonFX.magic_row_for(bullet_color), 0.7)
	add_child(head)
	var seg_color := bullet_color.darkened(0.35)
	for i in range(BODY_SEGMENTS):
		var r := lerpf(0.34, 0.12, float(i) / float(BODY_SEGMENTS - 1))
		var seg := ToonFX.puff_sprite(seg_color, r)
		seg.position = Vector3(0, 0, -0.3 - i * 0.22)
		add_child(seg)
		_body_segments.append(seg)

## Onda cosmética: las esferas del cuerpo se desplazan lateralmente como una
## culebra. No altera la posición de vuelo (que sigue siendo recta).
func _animate_body() -> void:
	var n := _body_segments.size()
	for i in n:
		var seg: Node3D = _body_segments[i]
		var prog := float(i) / float(n - 1)
		seg.position.x = sin(_time * 14.0 + i * 0.6) * (0.06 + 0.22 * prog)
		seg.position.y = sin(_time * 12.0 + i * 0.45) * 0.04 * (0.3 + prog)
