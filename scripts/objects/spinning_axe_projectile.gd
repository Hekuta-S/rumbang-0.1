extends Area3D

var direction: Vector3
var damage: float = 0.0
var speed: float = 0.0
var max_range: float = 0.0
var traveled: float = 0.0
var is_spinning_in_place: bool = false
var spin_duration: float = 2.0
var spin_timer: float = 0.0
var tick_timer: float = 0.0
var has_hit_enemy: bool = false
const DAMAGE_TICK_RATE = 0.2

@onready var visual = $Visual

# Dinamismo de lanzamiento
var spin_axis: Vector3 = Vector3.UP
var spin_speed: float = 24.0
var sway_axis: Vector3 = Vector3.RIGHT
var flight_elapsed: float = 0.0

var spin_sfx: AudioStreamPlayer3D

# Estela principal de trayectoria
var ribbon_mesh_instance: MeshInstance3D
var ribbon_mesh: RibbonTrail3D

# Estela orbital / giratoria
var spin_ribbon_mesh_instance: MeshInstance3D
var spin_ribbon_mesh: RibbonTrail3D
var trail_tip: Marker3D

func setup(dir: Vector3, dmg: float, spd: float, rng: float):
	direction = dir.normalized()
	damage = dmg
	speed = spd
	max_range = rng
	flight_elapsed = 0.0

	# Variación dinámica de ángulo y giro en cada lanzamiento
	var rand_tilt_deg = randf_range(-25.0, 25.0)
	var rand_yaw_deg = randf_range(-15.0, 15.0)
	spin_speed = randf_range(20.0, 30.0)

	# Eje de rotación dinámico orientado al vuelo
	var basis_rot = Basis()
	basis_rot = basis_rot.rotated(Vector3.FORWARD, deg_to_rad(rand_tilt_deg))
	basis_rot = basis_rot.rotated(Vector3.UP, deg_to_rad(rand_yaw_deg))
	spin_axis = (basis_rot * Vector3.RIGHT).normalized()

	if visual:
		visual.rotation = Vector3(
			deg_to_rad(randf_range(-15.0, 15.0)),
			deg_to_rad(randf_range(0.0, 360.0)),
			deg_to_rad(rand_tilt_deg)
		)

func _ready():
	collision_layer = 0
	collision_mask = 4 # enemies
	body_entered.connect(_on_body_entered)
	
	spin_sfx = AudioStreamPlayer3D.new()
	var stream = AudioManager.get_stream("ataque-espalanza")
	spin_sfx.stream = stream
	spin_sfx.volume_db = -10.0
	spin_sfx.pitch_scale = 1.6
	add_child(spin_sfx)

	_setup_trails()

func _setup_trails() -> void:
	var mesh_shader = preload("res://assets/shaders/ribbon_mesh.gdshader")

	# 1. Estela principal de trayectoria (Rojo fucsia brillante)
	ribbon_mesh = RibbonTrail3D.new()
	ribbon_mesh.trail_width = 0.8
	ribbon_mesh.lifetime = 0.35
	ribbon_mesh.max_points = 40

	ribbon_mesh_instance = MeshInstance3D.new()
	ribbon_mesh_instance.top_level = true
	ribbon_mesh_instance.mesh = ribbon_mesh

	var render_mat := ShaderMaterial.new()
	render_mat.shader = mesh_shader
	# Rojo fucsia neón
	render_mat.set_shader_parameter("trail_color", Vector4(1.0, 0.05, 0.45, 0.95))
	render_mat.set_shader_parameter("rim_color", Vector4(1.0, 0.35, 0.75, 1.0))
	render_mat.set_shader_parameter("trail_fade_power", 1.2)
	ribbon_mesh_instance.material_override = render_mat
	add_child(ribbon_mesh_instance)

	# 2. Estela giratoria / dando vueltas (anclada a la punta de la pala de la guitarra)
	trail_tip = Marker3D.new()
	trail_tip.position = Vector3(0.0, 0.8, 0.4)
	if visual:
		visual.add_child(trail_tip)
	else:
		add_child(trail_tip)

	spin_ribbon_mesh = RibbonTrail3D.new()
	spin_ribbon_mesh.trail_width = 0.45
	spin_ribbon_mesh.lifetime = 0.28
	spin_ribbon_mesh.max_points = 48

	spin_ribbon_mesh_instance = MeshInstance3D.new()
	spin_ribbon_mesh_instance.top_level = true
	spin_ribbon_mesh_instance.mesh = spin_ribbon_mesh

	var spin_mat := ShaderMaterial.new()
	spin_mat.shader = mesh_shader
	# Fucsia intenso con resplandor magenta
	spin_mat.set_shader_parameter("trail_color", Vector4(0.95, 0.0, 0.5, 0.9))
	spin_mat.set_shader_parameter("rim_color", Vector4(1.0, 0.4, 0.9, 1.0))
	spin_mat.set_shader_parameter("trail_fade_power", 1.0)
	spin_ribbon_mesh_instance.material_override = spin_mat
	add_child(spin_ribbon_mesh_instance)

func _physics_process(delta: float):
	flight_elapsed += delta

	# Giro dinámico en su eje variable
	if visual:
		visual.rotate_object_local(spin_axis, spin_speed * delta)
		# Leve balanceo orgánico durante el vuelo
		visual.rotate_y(sin(flight_elapsed * 8.0) * 1.5 * delta)

	var cam = get_viewport().get_camera_3d()
	var cam_pos = cam.global_position if cam else global_position + Vector3(0, 5, 5)

	# Actualizar estela de trayectoria
	if ribbon_mesh and is_instance_valid(ribbon_mesh_instance):
		ribbon_mesh.add_trail_point(global_position)
		ribbon_mesh.update_trail(delta, cam_pos)

	# Actualizar estela dando vueltas (en el extremo giratorio)
	if spin_ribbon_mesh and is_instance_valid(spin_ribbon_mesh_instance) and is_instance_valid(trail_tip):
		spin_ribbon_mesh.add_trail_point(trail_tip.global_position)
		spin_ribbon_mesh.update_trail(delta, cam_pos)
	
	if spin_sfx and not spin_sfx.playing:
		spin_sfx.play()
	
	if not is_spinning_in_place:
		var move = direction * speed * delta
		var hit := EnemyQuery.segment_hit(global_position, global_position + move, 0.3)
		if not hit.is_empty():
			global_position = hit["pos"]
			_on_body_entered(hit["enemy"])
			return
		global_position += move
		traveled += move.length()
		if traveled >= max_range:
			_start_spinning_in_place()
	else:
		spin_timer += delta
		tick_timer += delta
		
		if tick_timer >= DAMAGE_TICK_RATE:
			tick_timer = 0.0
			_apply_area_damage()
			
		if spin_timer >= spin_duration:
			_cleanup_and_free()

func _cleanup_and_free() -> void:
	if is_instance_valid(ribbon_mesh_instance):
		ribbon_mesh_instance.queue_free()
	if is_instance_valid(spin_ribbon_mesh_instance):
		spin_ribbon_mesh_instance.queue_free()
	queue_free()

func _on_body_entered(body):
	if not is_spinning_in_place and not has_hit_enemy and body.is_in_group("enemies"):
		if body.has_method("take_damage"):
			has_hit_enemy = true
			body.take_damage(damage, direction)
		_start_spinning_in_place()

func _start_spinning_in_place():
	if is_spinning_in_place: return
	is_spinning_in_place = true
	$CollisionShape3D.shape.radius = 2.0
	spin_speed *= 1.4 # Acelera el giro al quedarse girando en el lugar

func _apply_area_damage():
	for body in EnemyQuery.overlapping(self):
		if body.is_in_group("enemies") and body.has_method("take_damage"):
			body.take_damage(damage * 0.5, Vector3.ZERO)
