extends Area3D

## SporeProjectile.gd
## A canister fired by Bronch's spore bazooka.
## On impact (or at max range) it bursts into a lingering corrosive
## spore cloud that damages enemies over time.

@export var speed: float = 18.0
@export var damage: float = 20.0
@export var max_lifetime: float = 2.5

var direction: Vector3 = Vector3.FORWARD
var lifetime: float = 0.0
var is_hit: bool = false

var cloud_dps: float = 3.0
var cloud_duration: float = 3.5
var cloud_radius: float = 2.6

var cloud_scene = preload("res://scenes/objects/spore_cloud.tscn")

static var spore_shader = preload("res://assets/shaders/spore_fbm_cloud.gdshader")

func _ready() -> void:
	add_to_group("bullets")
	body_entered.connect(_on_body_entered)

	# Aplicar el shader FBM orgánico a la cabeza del proyectil
	var mesh_inst := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh_inst:
		var head_mat := ShaderMaterial.new()
		head_mat.shader = spore_shader
		head_mat.set_shader_parameter("color_deep", Vector4(0.12, 0.55, 0.2, 1.0))
		head_mat.set_shader_parameter("color_mid", Vector4(0.6, 1.0, 0.2, 1.0))
		head_mat.set_shader_parameter("color_peak", Vector4(1.0, 0.95, 0.4, 1.0))
		head_mat.set_shader_parameter("color_rim", Vector4(0.3, 1.0, 0.85, 1.0))
		head_mat.set_shader_parameter("height_scale", 0.3)
		head_mat.set_shader_parameter("wave_speed", 1.6)
		head_mat.set_shader_parameter("global_transparency", 1.0)
		head_mat.set_shader_parameter("gas_density", 0.65)      # cápsula densa
		head_mat.set_shader_parameter("spore_density", 0.8)
		head_mat.set_shader_parameter("spore_glow", 4.5)
		head_mat.set_shader_parameter("stretch_along_motion", 1.5)
		mesh_inst.material_override = head_mat
		(mesh_inst.mesh as SphereMesh).radius = 0.3
		(mesh_inst.mesh as SphereMesh).height = 0.6

func setup(dir: Vector3, dmg: float, speed_val: float, cloud_dps_val: float, cloud_dur: float, cloud_rad: float) -> void:
	direction = dir.normalized()
	damage = dmg
	speed = speed_val
	cloud_dps = cloud_dps_val
	cloud_duration = cloud_dur
	cloud_radius = cloud_rad

	if direction.length_squared() > 0.001 and direction.cross(Vector3.UP).length_squared() > 0.001:
		look_at(global_position + direction, Vector3.UP)

	_setup_spore_trail()

func _setup_spore_trail() -> void:
	# Estela: jirones de gas que se quedan atrás + esporas brillantes sueltas
	var gas := SporeVFX.gas(18, 0.55, 0.12, 0.45, 0.8, 0.28)
	gas.name = "SporeTrail"
	add_child(gas)
	gas.emitting = true
	var specks := SporeVFX.specks(34, 0.5, 0.15, 0.05, 0.11, 1.4)
	specks.name = "SporeSpecks"
	add_child(specks)
	specks.emitting = true

func _physics_process(delta: float) -> void:
	if is_hit: return

	var current_pos = global_position
	var next_pos = current_pos + direction * speed * delta

	# Step collision so fast projectiles don't tunnel through geometry/enemies.
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(current_pos, next_pos)
	query.collision_mask = 1 # solo el mundo; los enemigos se detectan por geometría
	var hit = space_state.intersect_ray(query)
	var eh := EnemyQuery.segment_hit(current_pos, next_pos, 0.2)
	if not eh.is_empty():
		var world_dist: float = current_pos.distance_to(hit.position) if not hit.is_empty() else INF
		if current_pos.distance_to(eh["pos"]) <= world_dist:
			global_position = eh["pos"]
			_burst(eh["enemy"], eh["pos"])
			return
	if not hit.is_empty():
		global_position = hit.position
		_burst(hit.collider, hit.position)
		return

	global_position = next_pos
	lifetime += delta
	if lifetime >= max_lifetime:
		_burst(null, global_position)

func _on_body_entered(body: Node3D) -> void:
	if is_hit: return
	if not is_inside_tree(): return
	_burst(body, global_position)

func _burst(hit_body, hit_pos: Vector3) -> void:
	if is_hit: return
	is_hit = true

	# Explosión: daño enorme en área (pleno en el centro, 60 % en el borde) a TODOS los enemigos
	_explode(hit_body, hit_pos)

	# Leave a lingering corrosive cloud.
	var cloud = cloud_scene.instantiate()
	cloud.damage_per_tick = cloud_dps
	cloud.lifetime = cloud_duration
	cloud.radius = cloud_radius
	get_parent().add_child(cloud)
	cloud.global_position = hit_pos

	_spawn_burst_visual(hit_pos)
	AudioManager.play_at("explosion_bits", hit_pos)
	queue_free()

## Radio de la explosión respecto al de la nube de esporas.
const EXPLOSION_RADIUS_FACTOR := 1.4
const EXPLOSION_EDGE_DAMAGE := 0.6
const EXPLOSION_KNOCKBACK := 5.0

## Origen del daño (robo de vida y similares). -1 = sin origen.
var source_weapon: int = -1
var source_player: Node = null

func explosion_radius() -> float:
	return cloud_radius * EXPLOSION_RADIUS_FACTOR

func _explode(hit_body, center: Vector3) -> void:
	var radius := explosion_radius()
	var victims: Array = []
	for e in EnemyRegistry.all():
		if not is_instance_valid(e) or not e.has_method("take_damage"):
			continue
		var d: float = Vector2(e.global_position.x - center.x, e.global_position.z - center.z).length()
		# La vertical cuenta poco: el enemigo es alto
		var dy := absf((e.global_position.y + 0.8) - center.y)
		if e == hit_body or (d <= radius and dy <= radius):
			victims.append([e, d])
	for v in victims:
		var e = v[0]
		var t: float = clampf(float(v[1]) / maxf(radius, 0.01), 0.0, 1.0)
		var amount: float = damage * lerpf(1.0, EXPLOSION_EDGE_DAMAGE, t)
		if e == hit_body:
			amount = damage            # impacto directo: daño completo
		var away: Vector3 = (e.global_position - center)
		away.y = 0.0
		away = away.normalized() if away.length_squared() > 0.0001 else direction
		e.take_damage(amount, away * EXPLOSION_KNOCKBACK)
		if source_weapon >= 0 and is_instance_valid(source_player) and source_player.has_method("on_damage_dealt"):
			source_player.on_damage_dealt(amount, source_weapon)

func _spawn_burst_visual(pos: Vector3) -> void:
	if not is_inside_tree(): return
	var container = Node3D.new()
	get_parent().add_child(container)
	container.global_position = pos

	var light = Quality.new_light()
	light.light_color = Color(0.7, 1.0, 0.35)
	light.light_energy = 3.5
	light.omni_range = 4.5
	container.add_child(light)

	# Estallido: esporas lanzadas en todas direcciones + bocanada de gas que se expande
	var spores := SporeVFX.specks(48, 0.9, 0.25, 0.06, 0.14, 5.5)
	spores.one_shot = true
	spores.explosiveness = 0.95
	spores.gravity = Vector3(0, 0.6, 0)
	container.add_child(spores)
	spores.emitting = true

	var puff := SporeVFX.gas(10, 0.9, 0.3, 0.9, 1.6, 0.34)
	puff.one_shot = true
	puff.explosiveness = 0.9
	puff.initial_velocity_min = 0.8
	puff.initial_velocity_max = 2.2
	container.add_child(puff)
	puff.emitting = true

	var tween = container.create_tween()
	tween.tween_property(light, "light_energy", 0.0, 0.4)
	tween.tween_interval(0.7)
	tween.tween_callback(container.queue_free)
