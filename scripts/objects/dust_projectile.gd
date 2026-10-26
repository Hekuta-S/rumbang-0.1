extends Area3D

## DustProjectile.gd
## Ataque de Polvos Alquímicos:
## - En el aire: Nube de polvos comprimida con deformación orgánica de ruido (no círculo liso).
##   Desprende partículas de polvo fino que se quedan en el aire.
## - Al explotar: Nube de polvo suave, tamaño proporcionado, con elevación lenta natural (levita hacia arriba)
##   y disolución de humo algodonado estilizado.

@export var max_lifetime: float = 3.0

var velocity: Vector3 = Vector3.ZERO
var gravity_vec: Vector3 = Vector3(0, -18.0, 0)
var flight_time: float = 1.0
var elapsed: float = 0.0
var mode: int = 0
var player: Node3D = null
var bursted: bool = false

@export var max_throw_speed: float = 20.0 * WeaponData.PROJECTILE_SPEED_MULT
@export var max_range: float = 24.0

## Polvos mágicos: predominan el blanco; el tinte solo distingue el tipo de polvo.
const MODE_COLORS: Dictionary = {
	0: Color(0.86, 0.78, 1.0),   # blanco lila (arcano, daño en área)
	1: Color(1.0, 0.93, 0.74),   # blanco cálido (vigorizante, velocidad)
	2: Color(0.80, 1.0, 0.90),   # blanco menta (sanador)
}

const MODE_RIMS: Dictionary = {
	0: Color(1.0, 0.97, 1.0),
	1: Color(1.0, 0.99, 0.92),
	2: Color(0.96, 1.0, 0.98),
}

const DUST_VFX = preload("res://scripts/objects/dust_vfx.gd")

static var cloud_shader: Shader = preload("res://assets/shaders/alchemical_clouds.gdshader")

var cloud_mesh: MeshInstance3D = null
var cloud_mat: ShaderMaterial = null
var trail_particles: CPUParticles3D = null

func _ready() -> void:
	add_to_group("bullets")
	body_entered.connect(_on_body_entered)

## Mejoras por nivel (ver WeaponUpgrades.DUSTS_UPGRADES)
const BASE_RADIUS := 5.0
const SLOW_DURATION := 3.0
var base_damage: float = 38.0
var blast_radius: float = BASE_RADIUS
var slow_amount: float = 0.0   ## fracción de velocidad que se quita (0.3 = -30%)

func setup(start: Vector3, target: Vector3, dust_mode: int, shooter: Node3D,
		damage: float = 38.0, radius: float = BASE_RADIUS, slow: float = 0.0) -> void:
	mode = dust_mode
	player = shooter
	base_damage = damage
	blast_radius = radius
	slow_amount = clampf(slow, 0.0, 0.8)
	global_position = start

	var to_target: Vector3 = target - start
	var horiz: Vector3 = Vector3(to_target.x, 0.0, to_target.z)
	if horiz.length() > max_range:
		to_target = horiz.normalized() * max_range
		to_target.y = target.y - start.y
	target = start + to_target

	var horiz_dist: float = Vector3(to_target.x, 0.0, to_target.z).length()
	flight_time = clampf(horiz_dist / maxf(max_throw_speed, 1.0), 0.35, 1.5)
	velocity = (to_target - 0.5 * gravity_vec * flight_time * flight_time) / flight_time

	_create_visuals()

func _physics_process(delta: float) -> void:
	if bursted:
		return
	elapsed += delta
	velocity += gravity_vec * delta
	global_position += velocity * delta

	# Apuntar la deformación comprimida a la trayectoria
	if velocity.length_squared() > 0.05:
		look_at(global_position + velocity, Vector3.UP)

	if elapsed >= flight_time or elapsed >= max_lifetime:
		_burst(global_position)
	elif elapsed >= 0.1 and EnemyQuery.any_overlapping(self):
		_burst(global_position)

func _on_body_entered(body: Node3D) -> void:
	if bursted or elapsed < 0.1 or body == player:
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
			# Polvo curativo: cura al jugador si queda dentro de la nube
			if is_instance_valid(player) and player.global_position.distance_to(pos) <= blast_radius:
				player.heal(25.0)

	_spawn_cloud_explosion(pos)
	queue_free()

func _aoe_damage(pos: Vector3) -> void:
	var dmg: float = base_damage
	if is_instance_valid(player) and "is_berserk" in player and player.is_berserk:
		dmg *= 1.5
	for enemy in EnemyRegistry.all():
		if not is_instance_valid(enemy):
			continue
		if enemy.global_position.distance_to(pos) <= blast_radius and enemy.has_method("take_damage"):
			enemy.take_damage(dmg, (enemy.global_position - pos).normalized() * 3.5)
			if slow_amount > 0.0 and enemy.has_method("apply_slow"):
				enemy.apply_slow(SLOW_DURATION, 1.0 - slow_amount)

## Visual del proyectil en vuelo: una nube compacta de polvo con brillo, y una estela de granos
func _create_visuals() -> void:
	var main_color: Color = MODE_COLORS.get(mode, Color(0.86, 0.78, 1.0))
	var rim_col: Color = MODE_RIMS.get(mode, Color(1.0, 0.97, 1.0))

	# 1. Cabeza: bolsita de polvo (shader de polvo, comprimida en el sentido del vuelo)
	cloud_mat = ShaderMaterial.new()
	cloud_mat.shader = cloud_shader
	cloud_mat.set_shader_parameter("clouds_color", Vector3(main_color.r, main_color.g, main_color.b))
	cloud_mat.set_shader_parameter("rim_color", Vector3(rim_col.r, rim_col.g, rim_col.b))
	cloud_mat.set_shader_parameter("clouds_speed", 4.0)
	cloud_mat.set_shader_parameter("clouds_scale", 2.2)
	cloud_mat.set_shader_parameter("compression_squish", 0.5)
	cloud_mat.set_shader_parameter("explosion_progress", 0.0)
	cloud_mat.set_shader_parameter("noise_vertex_displacement", 0.2)
	cloud_mat.set_shader_parameter("haze_strength", 0.55)       # cabeza más densa que la neblina de la explosión
	cloud_mat.set_shader_parameter("grain_glow", 3.6)

	cloud_mesh = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.34
	sphere.height = 0.68
	sphere.radial_segments = 20
	sphere.rings = 12
	cloud_mesh.mesh = sphere
	cloud_mesh.material_override = cloud_mat
	cloud_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cloud_mesh)

	# 2. Estela: neblina + granos que quedan flotando + algún destello
	var haze: CPUParticles3D = DUST_VFX.haze(14, 0.5, 0.15, 0.35, 0.6, main_color, 0.2)
	add_child(haze)
	haze.emitting = true
	trail_particles = DUST_VFX.grains(46, 0.6, 0.2, 0.04, 0.09, main_color, 1.1)
	add_child(trail_particles)
	trail_particles.emitting = true
	var stars: CPUParticles3D = DUST_VFX.sparkles(6, 0.5, 0.2, 0.14, 0.24, main_color)
	add_child(stars)
	stars.emitting = true

	# 3. Luz suave blanca
	var light := Quality.new_light()
	light.light_color = rim_col
	light.light_energy = 1.4
	light.omni_range = 2.6
	add_child(light)

## Efecto de explosión de polvo alquímico
## - Tiempo templado (1.25 segundos para apreciarse con calma)
## - Se eleva suavemente hacia arriba (leve flotación de humo)
## - Tamaño contenido y silueta de nube con volumenes algodonados
func _spawn_cloud_explosion(pos: Vector3) -> void:
	if not is_inside_tree():
		return

	var main_color: Color = MODE_COLORS.get(mode, Color(0.86, 0.78, 1.0))
	var rim_col: Color = MODE_RIMS.get(mode, Color(1.0, 0.97, 1.0))

	var container := Node3D.new()
	get_parent().add_child(container)
	container.global_position = pos
	container.scale = Vector3.ONE * (blast_radius / BASE_RADIUS)   # la nube refleja el rango real

	# Cúmulo de polvo (3 esferas con el shader de polvo) que se eleva y se disuelve
	var cloud_cluster := Node3D.new()
	container.add_child(cloud_cluster)

	var exp_mat := ShaderMaterial.new()
	exp_mat.shader = cloud_shader
	exp_mat.set_shader_parameter("clouds_color", Vector3(main_color.r, main_color.g, main_color.b))
	exp_mat.set_shader_parameter("rim_color", Vector3(rim_col.r, rim_col.g, rim_col.b))
	exp_mat.set_shader_parameter("clouds_speed", 3.0)
	exp_mat.set_shader_parameter("clouds_scale", 2.4)
	exp_mat.set_shader_parameter("compression_squish", 1.0)
	exp_mat.set_shader_parameter("explosion_progress", 0.0)
	exp_mat.set_shader_parameter("noise_vertex_displacement", 0.4)

	var cloud_offsets: Array[Vector3] = [Vector3(0.0, 0.1, 0.0), Vector3(0.4, 0.2, 0.2), Vector3(-0.35, 0.25, -0.2)]
	var cloud_scales: Array[float] = [0.75, 0.6, 0.65]
	for i in range(cloud_offsets.size()):
		var sub_cloud := MeshInstance3D.new()
		var s_mesh := SphereMesh.new()
		s_mesh.radius = cloud_scales[i]
		s_mesh.height = cloud_scales[i] * 2.0
		s_mesh.radial_segments = 16
		s_mesh.rings = 10
		sub_cloud.mesh = s_mesh
		sub_cloud.position = cloud_offsets[i]
		sub_cloud.material_override = exp_mat
		sub_cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cloud_cluster.add_child(sub_cloud)

	var light := Quality.new_light()
	light.light_color = rim_col
	light.light_energy = 3.0
	light.omni_range = 4.0
	container.add_child(light)

	# Estallido de polvo: neblina que se expande, granos lanzados que titilan y destellos
	var haze: CPUParticles3D = DUST_VFX.haze(12, 1.2, 0.3, 0.9, 1.6, main_color, 0.24)
	haze.one_shot = true
	haze.explosiveness = 0.85
	haze.initial_velocity_min = 0.6
	haze.initial_velocity_max = 2.0
	container.add_child(haze)
	haze.emitting = true

	var grains: CPUParticles3D = DUST_VFX.grains(90, 1.4, 0.35, 0.05, 0.11, main_color, 3.4)
	grains.one_shot = true
	grains.explosiveness = 0.9
	grains.gravity = Vector3(0, -0.25, 0)
	container.add_child(grains)
	grains.emitting = true

	var stars: CPUParticles3D = DUST_VFX.sparkles(16, 1.1, 0.4, 0.16, 0.3, main_color)
	stars.one_shot = true
	stars.explosiveness = 0.8
	container.add_child(stars)
	stars.emitting = true

	AudioManager.play_at("explosion_bits", pos, -4.0, 1.2)

	var anim_duration: float = 1.25
	var tween := container.create_tween().set_parallel(true)
	tween.tween_property(cloud_cluster, "position:y", 0.9, anim_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(cloud_cluster, "scale", Vector3(1.65, 1.65, 1.65), anim_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(exp_mat, "shader_parameter/explosion_progress", 1.0, anim_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(light, "light_energy", 0.0, anim_duration * 0.7)
	tween.chain().tween_callback(container.queue_free)
