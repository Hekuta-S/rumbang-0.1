extends Area3D

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

func _on_impact(body: Node3D, hit_pos: Vector3, hit_normal: Vector3) -> void:
	if is_hit or not is_inside_tree(): return

	var BulletScript = load("res://scripts/objects/bullet.gd")
	if body.is_in_group("enemies") and body.has_method("take_damage"):
		is_hit = true
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
	# Cabeza: esfera más grande con dos ojos brillantes.
	var body_mat := StandardMaterial3D.new()
	body_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	body_mat.albedo_color = bullet_color
	body_mat.emission_enabled = true
	body_mat.emission = bullet_color
	body_mat.emission_energy_multiplier = 1.8

	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.16
	head_mesh.height = 0.32
	head.mesh = head_mesh
	head.material_override = body_mat
	add_child(head)

	for side in [-0.08, 0.08]:
		var eye := MeshInstance3D.new()
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.035
		eye_mesh.height = 0.07
		eye.mesh = eye_mesh
		var eye_mat := StandardMaterial3D.new()
		eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		eye_mat.albedo_color = Color(1.0, 0.95, 0.4)
		eye_mat.emission_enabled = true
		eye_mat.emission = Color(1.0, 0.9, 0.3)
		eye_mat.emission_energy_multiplier = 1.5
		eye.material_override = eye_mat
		eye.position = Vector3(side, 0.05, 0.12)
		add_child(eye)

	# Cuerpo: segmentos decrecientes hacia la cola, tras la cabeza (-Z local).
	var seg_color := bullet_color.darkened(0.85)
	var seg_mat := StandardMaterial3D.new()
	seg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	seg_mat.albedo_color = seg_color
	seg_mat.emission_enabled = true
	seg_mat.emission = seg_color
	seg_mat.emission_energy_multiplier = 1.2

	for i in range(BODY_SEGMENTS):
		var seg := MeshInstance3D.new()
		var seg_mesh := SphereMesh.new()
		var r := lerpf(0.14, 0.05, float(i) / float(BODY_SEGMENTS - 1))
		seg_mesh.radius = r
		seg_mesh.height = r * 2.0
		seg.mesh = seg_mesh
		seg.material_override = seg_mat
		seg.position = Vector3(0, 0, -0.3 - i * 0.22)
		add_child(seg)
		_body_segments.append(seg)

	var light := OmniLight3D.new()
	light.light_color = bullet_color
	light.light_energy = 1.8
	light.omni_range = 3.0
	add_child(light)

	# --- Emerald / Nature Essence Trail ---
	var nature_trail := CPUParticles3D.new()
	nature_trail.name = "NatureTrail"
	nature_trail.local_coords = false
	nature_trail.amount = 18
	nature_trail.lifetime = 0.35
	nature_trail.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINT
	nature_trail.gravity = Vector3(0, 0.4, 0)
	nature_trail.spread = 20.0
	nature_trail.initial_velocity_min = 0.3
	nature_trail.initial_velocity_max = 1.0
	nature_trail.scale_amount_min = 0.2
	nature_trail.scale_amount_max = 0.5

	var p_mesh := PrismMesh.new()
	p_mesh.size = Vector3(0.08, 0.08, 0.08)
	nature_trail.mesh = p_mesh

	var n_mat := StandardMaterial3D.new()
	n_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	n_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	n_mat.albedo_color = Color(0.4, 1.0, 0.5, 0.45)
	n_mat.emission_enabled = true
	n_mat.emission = Color(0.2, 0.9, 0.3)
	n_mat.emission_energy_multiplier = 1.5
	nature_trail.material_override = n_mat

	var color_ramp := Gradient.new()
	color_ramp.set_color(0, Color(0.4, 1.0, 0.5, 0.5))
	color_ramp.add_point(1.0, Color(0.1, 0.6, 0.2, 0.0))
	nature_trail.color_ramp = color_ramp

	add_child(nature_trail)
	nature_trail.emitting = true

## Onda cosmética: las esferas del cuerpo se desplazan lateralmente como una
## culebra. No altera la posición de vuelo (que sigue siendo recta).
func _animate_body() -> void:
	var n := _body_segments.size()
	for i in n:
		var seg: Node3D = _body_segments[i]
		var prog := float(i) / float(n - 1)
		seg.position.x = sin(_time * 14.0 + i * 0.6) * (0.06 + 0.22 * prog)
		seg.position.y = sin(_time * 12.0 + i * 0.45) * 0.04 * (0.3 + prog)
