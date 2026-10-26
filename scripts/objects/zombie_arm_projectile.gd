extends Area3D

## ZombieArmProjectile.gd
## Brazo boomerang arrojadizo.
## Vuela y gira de forma auténtica como un bumerán en ángulo aerodinámico inclinado,
## con trayectoria curvada dinámica y estela ribbon viva.

var damage: float = 25.0
var speed: float = 26.0 * WeaponData.PROJECTILE_SPEED_MULT
var max_range: float = 22.0
var player: Node3D = null

var direction: Vector3 = Vector3.ZERO
var start_pos: Vector3 = Vector3.ZERO
var returning: bool = false
var flight_time: float = 0.0

var visual: Node3D
var ribbon_mesh_instance: MeshInstance3D
var ribbon_mesh: RibbonTrail3D

# Dinamismo de lanzamiento
var roll_tilt: float = 0.0
var spin_speed: float = 28.0
var curve_lateral_dir: Vector3 = Vector3.RIGHT

static var ribbon_shader: Shader = preload("res://assets/shaders/ribbon_mesh.gdshader")

## Capa física de los enemigos (enemy.tscn: collision_layer = 4). La máscara anterior (3)
## solo veía las capas 1-2, así que el brazo nunca detectaba enemigos.
const ENEMY_MASK := 4

## Enemigos ya golpeados en la pasada actual (ida o regreso). Los brazos de un mismo
## lanzamiento comparten estas listas (un enemigo recibe un golpe por pasada aunque lo
## crucen varios brazos); al girar se pasa a la lista de regreso.
var hits_this_pass: Array = []
var hits_back: Array = []

## Origen del daño (robo de vida y similares). -1 = sin origen.
var source_weapon: int = -1
var source_player: Node = null

## Multiplicadores de las mejoras del arma
var range_mult: float = 1.0
var size_mult: float = 1.0
var max_flight_time: float = 1.2 / WeaponData.PROJECTILE_SPEED_MULT

func _ready():
	collision_layer = 0
	collision_mask = ENEMY_MASK
	body_entered.connect(_on_body_entered)

func setup(dir: Vector3, dmg: float, p: Node3D):
	direction = dir.normalized()
	damage = dmg
	player = p
	start_pos = global_position
	flight_time = 0.0

	# Dinamismo aleatorio por lanzamiento (velocidad de rotación y banqueo de vuelo)
	spin_speed = randf_range(26.0, 34.0)
	roll_tilt = randf_range(0.25, 0.45) * (1.0 if randf() > 0.5 else -1.0)
	
	var up_vec = Vector3.UP
	curve_lateral_dir = direction.cross(up_vec).normalized()
	if curve_lateral_dir.length_squared() < 0.01:
		curve_lateral_dir = Vector3.RIGHT

	# Contenedor visual que rota horizontalmente como un disco / bumerán plano
	visual = Node3D.new()
	var arm_scene = load("res://assets/models/weapons/human_arm_bones.glb")
	if arm_scene:
		# Nodo pivote para acostar el brazo plano horizontalmente (plano XZ)
		var arm_pivot = Node3D.new()
		var arm_model = arm_scene.instantiate()
		arm_model.scale = Vector3(0.12, 0.12, 0.12)
		# Centrar el eje Z (largo del brazo que va de -9.5 a +2.4, centro aprox -3.55 -> * 0.12 = -0.42)
		arm_model.position = Vector3(0.0, 0.0, 0.42)
		# Acostar el brazo en horizontal plano
		arm_model.rotation.x = deg_to_rad(90.0)
		arm_pivot.add_child(arm_model)
		visual.add_child(arm_pivot)
	else:
		var b_mesh = BoxMesh.new()
		b_mesh.size = Vector3(1.2, 0.08, 0.25)
		var m_inst = MeshInstance3D.new()
		m_inst.mesh = b_mesh
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.4, 0.7, 0.3)
		m_inst.material_override = mat
		visual.add_child(m_inst)

	add_child(visual)

	_setup_ribbon_trail()

## Tamaño (nodo + estela) y alcance según las mejoras. Llamar tras setup().
func apply_upgrades(p_size_mult: float, p_range_mult: float) -> void:
	size_mult = p_size_mult
	range_mult = p_range_mult
	max_range *= p_range_mult
	max_flight_time = (1.2 / WeaponData.PROJECTILE_SPEED_MULT) * p_range_mult
	scale = Vector3.ONE * p_size_mult
	if ribbon_mesh:
		ribbon_mesh.trail_width = 0.55 * p_size_mult

## Altura de vuelo sobre el suelo (m). El brazo sigue el relieve para no pasar por
## encima/debajo de enemigos en colinas o en la cripta.
const HOVER_HEIGHT := 1.1

func _follow_terrain(delta: float) -> void:
	var ground := _ground_height(global_position.x, global_position.z)
	if is_nan(ground):
		return
	global_position.y = lerpf(global_position.y, ground + HOVER_HEIGHT, clampf(delta * 40.0, 0.0, 1.0))

## Altura del suelo: la escena de juego (Main.get_floor_y) o, si no, el mapa procedural.
func _ground_height(x: float, z: float) -> float:
	var main := get_tree().current_scene
	if main != null and main.has_method("get_floor_y"):
		return main.get_floor_y(x, z)
	var pm := get_tree().get_first_node_in_group("procedural_map")
	if pm != null and pm.has_method("get_height_at"):
		return pm.get_height_at(x, z)
	return NAN

## Comparte las listas de golpeados con los demás brazos del mismo lanzamiento.
func share_hits(out_hits: Array, back_hits: Array) -> void:
	hits_this_pass = out_hits
	hits_back = back_hits

func _setup_ribbon_trail() -> void:
	ribbon_mesh = RibbonTrail3D.new()
	ribbon_mesh.trail_width = 0.55
	ribbon_mesh.lifetime = 0.38
	ribbon_mesh.max_points = 32

	ribbon_mesh_instance = MeshInstance3D.new()
	ribbon_mesh_instance.top_level = true
	ribbon_mesh_instance.mesh = ribbon_mesh

	var r_mat := ShaderMaterial.new()
	r_mat.shader = ribbon_shader
	r_mat.set_shader_parameter("trail_color", Vector4(0.35, 0.9, 0.25, 0.85)) # Verde zombie
	r_mat.set_shader_parameter("rim_color", Vector4(0.85, 1.0, 0.45, 1.0))
	r_mat.set_shader_parameter("trail_fade_power", 1.2)
	ribbon_mesh_instance.material_override = r_mat

	add_child(ribbon_mesh_instance)

func _physics_process(delta: float):
	flight_time += delta
	_poll_overlaps()

	# Giro completamente horizontal (plano al suelo) alrededor del eje Y del mundo
	if visual:
		visual.rotate_y(spin_speed * delta)

	# Actualizar la estela Ribbon en espacio global
	if ribbon_mesh and is_instance_valid(ribbon_mesh_instance):
		ribbon_mesh.add_trail_point(global_position)
		var cam = get_viewport().get_camera_3d()
		var cam_pos = cam.global_position if cam else global_position + Vector3(0, 5, 5)
		ribbon_mesh.update_trail(delta, cam_pos)

	if not returning:
		# Trayectoria arqueada/curva dinámica de bumerán hacia afuera
		var curve_force = sin((global_position.distance_to(start_pos) / max_range) * PI) * 5.0
		var current_vel = direction * speed + curve_lateral_dir * (curve_force * sign(roll_tilt))
		global_position += current_vel * delta
		_follow_terrain(delta)

		if global_position.distance_to(start_pos) >= max_range or flight_time > max_flight_time:
			returning = true
			hits_this_pass = hits_back   # en el regreso puede volver a golpear a cada enemigo una vez
	else:
		# Retorno guiado hacia el jugador con curva
		if is_instance_valid(player):
			var target_pos = player.global_position + Vector3(0, 1.0, 0)
			var to_player = (target_pos - global_position).normalized()
			global_position += to_player * (speed * 1.35) * delta
			
			if global_position.distance_to(target_pos) < 2.0:
				_cleanup_and_free()
		else:
			_cleanup_and_free()

## Los enemigos que ya tocaban el área o que atraviesa de un tirón no siempre emiten
## body_entered; se revisan también los solapamientos cada frame física.
func _poll_overlaps() -> void:
	for body in EnemyQuery.overlapping(self):
		_on_body_entered(body)

func _cleanup_and_free() -> void:
	if is_instance_valid(ribbon_mesh_instance):
		ribbon_mesh_instance.queue_free()
	queue_free()

func _on_body_entered(body):
	if body.is_in_group("enemies") and body.has_method("take_damage"):
		if hits_this_pass.has(body):
			return
		hits_this_pass.append(body)
		body.take_damage(damage, direction)
		if source_weapon >= 0 and is_instance_valid(source_player) and source_player.has_method("on_damage_dealt"):
			source_player.on_damage_dealt(damage, source_weapon)
