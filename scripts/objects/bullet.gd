extends Area3D

@export var speed: float = 30.0
@export var damage: float = 12.0
@export var is_enemy_bullet: bool = false
@export var max_lifetime: float = 3.0

var direction: Vector3 = Vector3.FORWARD
var lifetime: float = 0.0
var bullet_color: Color = Color(0.0, 0.85, 1.0)
var shooter_rid: RID = RID()
var is_hit: bool = false

func _ready() -> void:
	add_to_group("bullets")
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

var custom_vfx_node: Node3D = null

func setup(dir: Vector3, dmg: float, speed_val: float, enemy_flag: bool = false, col: Color = Color(0.0, 0.85, 1.0), shooter: RID = RID(), vfx_scene: PackedScene = null) -> void:
	direction = dir.normalized()
	damage = dmg
	speed = speed_val
	is_enemy_bullet = enemy_flag
	bullet_color = col
	shooter_rid = shooter

	if direction.length_squared() > 0.001 and direction.cross(Vector3.UP).length_squared() > 0.001:
		look_at(global_position + direction, Vector3.UP)

	# Clean up any previously attached custom VFX if bullet is reused from pool
	if custom_vfx_node and is_instance_valid(custom_vfx_node):
		custom_vfx_node.queue_free()
		custom_vfx_node = null

	if vfx_scene != null:
		# Hide default placeholder mesh and default trail
		if has_node("MeshInstance3D"):
			$MeshInstance3D.visible = false
		if has_node("TrailParticles"):
			$TrailParticles.emitting = false
			$TrailParticles.visible = false
		if has_node("OmniLight3D"):
			$OmniLight3D.visible = false
		
		custom_vfx_node = vfx_scene.instantiate()
		add_child(custom_vfx_node)
		# Face forward along bullet velocity direction (bullet looks along -Z)
		custom_vfx_node.rotation_degrees = Vector3(0, 90, 0)
		return

	# Default bullet appearance
	if has_node("MeshInstance3D"):
		$MeshInstance3D.visible = true
	if has_node("OmniLight3D"):
		$OmniLight3D.visible = Quality.bullet_lights()

	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	if is_enemy_bullet:
		bullet_color = Color(1.0, 0.1, 0.3)
		mat.albedo_color = bullet_color
		if has_node("OmniLight3D"):
			$OmniLight3D.light_color = bullet_color
	else:
		mat.albedo_color = bullet_color
		if has_node("OmniLight3D"):
			$OmniLight3D.light_color = bullet_color

	if has_node("MeshInstance3D"):
		$MeshInstance3D.material_override = mat

	# --- Dynamic Bullet Trail ---
	_setup_trail(mat, bullet_color)

func _setup_trail(mat: StandardMaterial3D, col: Color) -> void:
	var trail: CPUParticles3D
	if has_node("TrailParticles"):
		trail = get_node("TrailParticles")
	else:
		trail = CPUParticles3D.new()
		trail.name = "TrailParticles"
		add_child(trail)

	trail.local_coords = false
	trail.amount = Quality.count(25)
	trail.lifetime = 0.18
	trail.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINT
	trail.gravity = Vector3.ZERO
	trail.spread = 15.0
	trail.initial_velocity_min = 0.5
	trail.initial_velocity_max = 1.5
	trail.scale_amount_min = 0.3
	trail.scale_amount_max = 0.8
	
	var p_mesh = SphereMesh.new()
	p_mesh.radius = 0.12
	p_mesh.height = 0.24
	trail.mesh = p_mesh
	
	var trail_mat = mat.duplicate() as StandardMaterial3D
	trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail_mat.albedo_color = Color(col.r, col.g, col.b, 0.4)
	trail_mat.emission_enabled = true
	trail_mat.emission = col
	trail_mat.emission_energy_multiplier = 1.5
	trail.material_override = trail_mat
	
	var color_ramp = Gradient.new()
	color_ramp.set_color(0, Color(col.r, col.g, col.b, 0.5))
	color_ramp.add_point(1.0, Color(col.r, col.g, col.b, 0.0))
	trail.color_ramp = color_ramp
	
	trail.emitting = true

func _physics_process(delta: float) -> void:
	if is_hit: return

	var current_pos = global_position
	var move_step = direction * speed * delta
	var next_pos = current_pos + move_step

	# High accuracy physics raycast step calculation
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(current_pos, next_pos)
	query.collision_mask = collision_mask
	if shooter_rid.is_valid():
		query.exclude = [shooter_rid]

	var hit = space_state.intersect_ray(query)
	# Las balas del jugador también golpean enemigos (por geometría, no por física)
	if not is_enemy_bullet:
		var eh := EnemyQuery.segment_hit(current_pos, next_pos, 0.12)
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
		PoolManager.return_bullet(self)

func _on_body_entered(body: Node3D) -> void:
	if is_hit: return
	# Guard: the bullet may have been removed from the tree by the time this signal fires
	if not is_inside_tree(): return
	_on_impact(body, global_position, -direction)

func _on_area_entered(_area: Area3D) -> void:
	pass

func _on_impact(body, hit_pos: Vector3, hit_normal: Vector3) -> void:
	if is_hit: return

	if is_enemy_bullet:
		if body.is_in_group("player") and body.has_method("take_damage"):
			is_hit = true
			body.take_damage(damage)
			spawn_impact_sparks(get_parent(), hit_pos, hit_normal, bullet_color)
			PoolManager.return_bullet(self)
		elif not body.is_in_group("enemies") and not body.is_in_group("bullets"):
			is_hit = true
			spawn_impact_sparks(get_parent(), hit_pos, hit_normal, bullet_color)
			PoolManager.return_bullet(self)
	else:
		if body.is_in_group("enemies") and body.has_method("take_damage"):
			is_hit = true
			HitFeedback.weapon_tag = -1
			body.take_damage(damage, direction)
			spawn_impact_sparks(get_parent(), hit_pos, hit_normal, bullet_color)
			PoolManager.return_bullet(self)
		elif not body.is_in_group("player") and not body.is_in_group("bullets"):
			is_hit = true
			if body.is_in_group("destructibles"):
				body.take_damage(damage, direction)
			spawn_impact_sparks(get_parent(), hit_pos, hit_normal, bullet_color)
			PoolManager.return_bullet(self)

static var CACHED_RING_MATS: Dictionary = {}
static var CACHED_SPARK_MATS: Dictionary = {}

## Pool de efectos de impacto: se crean una vez (luz, anillo, chispas) y se reutilizan. Antes cada impacto
## construía ~12 nodos y recursos nuevos (≈ 0,3 ms en PC, bastante más en móvil).
static var _spark_pool: Array = []     # entradas {root, light, ring, r_mat, particles, ramp, busy}
const SPARK_POOL_MAX := 24

static func _build_spark_entry(parent_node: Node) -> Dictionary:
	var root := Node3D.new()
	parent_node.add_child(root)
	var light = Quality.new_light()
	light.light_energy = 0.0
	light.omni_range = 3.5
	root.add_child(light)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.08
	torus.outer_radius = 0.25
	torus.rings = 16
	torus.ring_segments = 12
	ring.mesh = torus
	var r_mat := StandardMaterial3D.new()
	r_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	r_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	r_mat.emission_enabled = true
	r_mat.emission_energy_multiplier = 2.5
	ring.material_override = r_mat
	root.add_child(ring)
	var particles := CPUParticles3D.new()
	particles.amount = Quality.count(18)
	particles.lifetime = 0.3
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.spread = 70.0
	particles.initial_velocity_min = 6.0
	particles.initial_velocity_max = 14.0
	particles.gravity = Vector3(0, -12.0, 0)
	particles.scale_amount_min = 0.5
	particles.scale_amount_max = 1.1
	var p_mesh := BoxMesh.new()
	p_mesh.size = Vector3(0.06, 0.06, 0.18)
	particles.mesh = p_mesh
	var ramp := Gradient.new()
	particles.color_ramp = ramp
	root.add_child(particles)
	particles.emitting = false
	root.visible = false
	return {"root": root, "light": light, "ring": ring, "r_mat": r_mat, "particles": particles, "ramp": ramp, "busy": false}

static func spawn_impact_sparks(parent_node: Node, pos: Vector3, normal: Vector3, spark_color: Color) -> void:
	# Guard: parent must exist, be valid, and be inside the scene tree
	if not parent_node or not is_instance_valid(parent_node) or not parent_node.is_inside_tree(): return

	# Entradas del pool cuyo nodo ya no existe (cambio de escena) se descartan
	_spark_pool = _spark_pool.filter(func(en): return is_instance_valid(en["root"]) and en["root"].is_inside_tree())
	var entry: Dictionary = {}
	for en in _spark_pool:
		if not en["busy"]:
			entry = en
			break
	if entry.is_empty():
		if _spark_pool.size() >= SPARK_POOL_MAX:
			return   # demasiados impactos a la vez: se omite el efecto
		entry = _build_spark_entry(parent_node)
		_spark_pool.append(entry)
	entry["busy"] = true

	var root: Node3D = entry["root"]
	var light: OmniLight3D = entry["light"]
	var ring: MeshInstance3D = entry["ring"]
	var r_mat: StandardMaterial3D = entry["r_mat"]
	var particles: CPUParticles3D = entry["particles"]
	var ramp: Gradient = entry["ramp"]

	root.global_position = pos
	root.visible = true
	light.light_color = spark_color
	light.light_energy = 4.0
	ring.transform = Transform3D.IDENTITY
	ring.scale = Vector3.ONE
	r_mat.albedo_color = Color(spark_color.r, spark_color.g, spark_color.b, 0.45)
	r_mat.emission = spark_color
	if normal != Vector3.ZERO and normal.cross(Vector3.UP).length_squared() > 0.001:
		ring.look_at(ring.global_position + normal, Vector3.UP)
	elif normal != Vector3.ZERO:
		ring.look_at(ring.global_position + normal, Vector3.FORWARD)

	particles.direction = normal if normal != Vector3.ZERO else Vector3.UP
	var mat_key = spark_color.to_html()
	if not CACHED_SPARK_MATS.has(mat_key):
		var new_mat = StandardMaterial3D.new()
		new_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		new_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		new_mat.albedo_color = Color(spark_color.r, spark_color.g, spark_color.b, 0.6)
		new_mat.emission_enabled = true
		new_mat.emission = Color(spark_color.r, spark_color.g, spark_color.b).lerp(Color.WHITE, 0.3)
		new_mat.emission_energy_multiplier = 2.5
		CACHED_SPARK_MATS[mat_key] = new_mat
	particles.material_override = CACHED_SPARK_MATS[mat_key]
	ramp.offsets = PackedFloat32Array([0.0, 1.0])
	ramp.colors = PackedColorArray([Color(spark_color.r, spark_color.g, spark_color.b, 0.65), Color(spark_color.r, spark_color.g, spark_color.b, 0.0)])
	particles.restart()
	particles.emitting = true

	var tween = root.create_tween().set_parallel(true)
	tween.tween_property(light, "light_energy", 0.0, 0.25)
	tween.tween_property(ring, "scale", Vector3(2.5, 2.5, 2.5), 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(r_mat, "albedo_color:a", 0.0, 0.22)
	tween.chain().tween_callback(func():
		root.visible = false
		particles.emitting = false
		entry["busy"] = false)
