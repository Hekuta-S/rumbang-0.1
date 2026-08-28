extends Area3D

## DustProjectile.gd
## Alchemy dust pouch lobbed in a parabola. It flies from the player toward a
## target point, arcing under gravity, then bursts on arrival.
##   mode 0 = Purple dust  -> AoE damage explosion on landing.
##   mode 2 = Green dust   -> Healing cloud on landing.
## (mode 1 Brown dust is a self-buff and is NOT thrown.)

@export var max_lifetime: float = 3.0

var velocity: Vector3 = Vector3.ZERO
var gravity_vec: Vector3 = Vector3(0, -18.0, 0)
var flight_time: float = 1.0
var elapsed: float = 0.0
var mode: int = 0
var player: Node3D = null
var bursted: bool = false

@export var max_throw_speed: float = 18.0
@export var max_range: float = 22.0

const MODE_COLORS: Dictionary = {
	0: Color(0.7, 0.2, 0.9),   # Purple
	2: Color(0.2, 0.95, 0.4),  # Green
}

func _ready() -> void:
	add_to_group("bullets")
	body_entered.connect(_on_body_entered)

## Launch the pouch from `start` toward `target` (a point the player aims at).
func setup(start: Vector3, target: Vector3, dust_mode: int, shooter: Node3D) -> void:
	mode = dust_mode
	player = shooter
	global_position = start

	# Cap the horizontal reach so it stays a thrown lob (never an aimbot).
	var to_target: Vector3 = target - start
	var horiz: Vector3 = Vector3(to_target.x, 0.0, to_target.z)
	if horiz.length() > max_range:
		to_target = horiz.normalized() * max_range
		to_target.y = target.y - start.y
	target = start + to_target

	# Horizontal speed dictates flight time; vertical component follows gravity.
	var horiz_dist: float = Vector3(to_target.x, 0.0, to_target.z).length()
	flight_time = clampf(horiz_dist / maxf(max_throw_speed, 1.0), 0.35, 1.6)
	velocity = (to_target - 0.5 * gravity_vec * flight_time * flight_time) / flight_time

	_build_visual()

func _physics_process(delta: float) -> void:
	if bursted:
		return
	elapsed += delta
	velocity += gravity_vec * delta
	global_position += velocity * delta
	if elapsed >= flight_time:
		_burst(global_position)
	elif elapsed >= max_lifetime:
		_burst(global_position)

func _on_body_entered(body: Node3D) -> void:
	if bursted:
		return
	# Ignore the brief overlap right at spawn and the player's own body.
	if elapsed < 0.12:
		return
	if body == player:
		return
	_burst(global_position)

func _burst(pos: Vector3) -> void:
	if bursted:
		return
	bursted = true
	match mode:
		0:
			_aoe_damage(pos)
		2:
			if is_instance_valid(player) and player.has_method("spawn_alchemy_healing_cloud"):
				player.spawn_alchemy_healing_cloud(pos)
	_spawn_burst_visual(pos)
	queue_free()

func _aoe_damage(pos: Vector3) -> void:
	var dmg: float = 35.0
	if is_instance_valid(player) and "is_berserk" in player:
		dmg = 35.0 * (1.5 if player.is_berserk else 1.0)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		if enemy.global_position.distance_to(pos) <= 5.5 and enemy.has_method("take_damage"):
			enemy.take_damage(dmg, (enemy.global_position - pos).normalized() * 4.0)

func _build_visual() -> void:
	var color: Color = MODE_COLORS.get(mode, Color.WHITE)
	
	var trail := CPUParticles3D.new()
	trail.amount = 40
	trail.lifetime = 0.4
	trail.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	trail.emission_sphere_radius = 0.3
	trail.gravity = Vector3(0, 1.0, 0)
	var t_mesh := SphereMesh.new()
	t_mesh.radius = 0.04
	t_mesh.height = 0.08
	trail.mesh = t_mesh
	
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(color.r, color.g, color.b, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = color
	trail.material_override = mat
	add_child(trail)

	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 1.6
	light.omni_range = 2.5
	add_child(light)

func _spawn_burst_visual(pos: Vector3) -> void:
	if not is_inside_tree():
		return
	var color: Color = MODE_COLORS.get(mode, Color.WHITE)
	var container := Node3D.new()
	get_parent().add_child(container)
	container.global_position = pos

	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 4.5
	light.omni_range = 4.5
	container.add_child(light)

	var particles := CPUParticles3D.new()
	particles.amount = 60
	particles.lifetime = 0.6
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.spread = 180.0
	particles.initial_velocity_min = 6.0
	particles.initial_velocity_max = 18.0
	particles.gravity = Vector3(0, 3.0, 0)
	particles.scale_amount_min = 0.5
	particles.scale_amount_max = 1.2
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	var p_mesh := SphereMesh.new()
	p_mesh.radius = 0.1
	p_mesh.height = 0.2
	particles.mesh = p_mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(color.r, color.g, color.b, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 3.0
	particles.material_override = mat
	container.add_child(particles)
	particles.emitting = true

	var tween := container.create_tween().set_parallel(true)
	tween.tween_property(light, "light_energy", 0.0, 0.35)
	tween.chain().tween_callback(container.queue_free)
