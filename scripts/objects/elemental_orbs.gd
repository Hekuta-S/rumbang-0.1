extends Node3D
class_name ElementalOrbs

## Esferas elementales que orbitan alrededor del jugador (Ciclo Elemental de Saimon).
## Empiezan siendo 4, una de cada elemento inicial (fuego, agua, planta y tierra).
## Cada esfera gira alrededor del jugador a una altura fija y conserva su elemento;
## la de planta lleva hojas y la de tierra lleva piedras girando a su alrededor.
## Las mejoras (WeaponUpgrades.ELEMENTS_CYCLE_UPGRADES) añaden elementos y orbes: ver _sync_with_upgrades.
##
## El daño lo hacen las propias esferas: mientras giran, cada una golpea por
## contacto a los enemigos que toca (ver _tick_contact_damage).  Se pueden
## aumentar (add_orb) o perder (remove_orb) según upgrades.

# ── Configuración ───────────────────────────────────────────────────────
## Elementos con los que se empieza (índices de ELEMENT_COLORS) y orden en que "Nuevo elemento" desbloquea el resto.
const INITIAL_ELEMENTS: Array[int] = [0, 3, 4, 5]
const UNLOCK_ORDER: Array[int] = [1, 2]
## Elemento → modelo decorativo que gira alrededor de su orbe (hojas / piedras).
const DECOR_SCENES := {
	4: "res://assets/models/saimon/orb_leaves.glb",
	5: "res://assets/models/saimon/orb_rocks.glb",
}
const DECOR_SPIN_SPEED := 2.4      ## rad/s de la decoración sobre su propio eje
const SYNC_INTERVAL := 0.25        ## cada cuánto se comparan los orbes con las mejoras (s)
const ORBIT_RADIUS := 2.4          ## Distancia al centro del jugador
const ORBIT_HEIGHT := 1.1          ## Altura sobre el suelo del jugador
const ORBIT_SPEED := 0.6           ## Vueltas por segundo (radianes = ORBIT_SPEED * TAU)
const ORB_RADIUS := 0.15
const ORB_SIZE_FLASH := 1.25       ## Multiplicador de tamaño del destello al golpear
const ORB_BOBBING_AMP := 0.12      ## Amplitud del movimiento vertical suave
const ORB_BOBBING_SPEED := 2.5     ## Velocidad del bobbing

## Radio de contacto: si un enemigo entra en este radio respecto al centro de
## una esfera, esa esfera lo golpea.
const ORB_HIT_RADIUS := 0.9
## Tiempo mínimo antes de que las esferas puedan volver a golpear al mismo enemigo.
const ORB_HIT_INTERVAL := 0.45
## Empuje que aplica cada golpe de esfera.
const ORB_HIT_KNOCKBACK := 3.0
## Duración del pulso de emisión al golpear (segundos).
const EMISSION_FLASH_DURATION := 0.2
## Intensidad pico del pulso de emisión.
const EMISSION_FLASH_PEAK := 5.0

# Colores del ciclo:  Fuego → Hielo → Viento → Agua → Planta
const ELEMENT_COLORS: Array = [
	Color(1.0, 0.3, 0.1),   # Fuego
	Color(0.2, 0.8, 1.0),   # Hielo
	Color(0.8, 0.8, 0.8),   # Viento
	Color(0.1, 0.4, 1.0),   # Agua
	Color(0.3, 0.9, 0.2),   # Planta
	Color(0.75, 0.5, 0.25), # Tierra
]

const ELEMENT_NAMES: Array = ["fuego", "hielo", "viento", "agua", "planta", "tierra"]

## Señal emitida cuando una esfera golpea a un enemigo.
## element_idx: índice del elemento de la esfera que golpeó.
## enemy: referencia al nodo enemigo golpeado.
signal orb_hit(element_idx: int, enemy)

# ── Estado ──────────────────────────────────────────────────────────────
var orbs: Array[Dictionary] = []   # [{mesh, mat, particles, p_mat, color_ramp, element_idx, base_scale, flash_tween}]
var orbit_angle: float = 0.0       ## Ángulo acumulado (rad)

var _player: CharacterBody3D = null
var _unlocked_elements: Array[int] = []
var _unlocks_applied := 0
var _extra_applied := 0
var _sync_timer := 0.0
var _orbit_speed_mult := 1.0
## Clave entera (enemigo × 64 + orbe) → instante (ms) hasta el que no se vuelve a golpear.
var _hit_until: Dictionary = {}
var _last_purge_ms: int = 0

# ── Ciclo de vida ───────────────────────────────────────────────────────

func setup(player: CharacterBody3D) -> void:
	_player = player
	_unlocked_elements = INITIAL_ELEMENTS.duplicate()
	for elem in INITIAL_ELEMENTS:
		_create_orb(elem)
	_sync_with_upgrades()

func _process(delta: float) -> void:
	if not is_instance_valid(_player):
		return
	_sync_timer -= delta
	if _sync_timer <= 0.0:
		_sync_timer = SYNC_INTERVAL
		_sync_with_upgrades()
	orbit_angle += ORBIT_SPEED * _orbit_speed_mult * TAU * delta
	# Normalizar para evitar pérdida de precisión flotante tras horas de juego
	orbit_angle = fmod(orbit_angle, TAU)
	_update_orb_positions(delta)
	_spin_decor(delta)
	_tick_contact_damage(delta)

## Compara las mejoras del jugador con los orbes actuales y crea los que falten:
## "Nuevo elemento" → orbe del siguiente elemento de UNLOCK_ORDER; "Nuevo orbe" → orbe
## al azar entre los elementos ya desbloqueados. También actualiza la velocidad de giro.
func _sync_with_upgrades() -> void:
	if not is_instance_valid(_player) or not _player.has_method("get_weapon_modifiers"):
		return
	var mods: Dictionary = _player.get_weapon_modifiers(WeaponData.WeaponType.ELEMENTS_CYCLE)
	_orbit_speed_mult = 1.0 + float(mods.get("orbit_speed", 0.0))
	var unlocks := mini(int(mods.get("element_unlock", 0)), UNLOCK_ORDER.size())
	while _unlocks_applied < unlocks:
		var elem: int = UNLOCK_ORDER[_unlocks_applied]
		_unlocked_elements.append(elem)
		_create_orb(elem)
		_unlocks_applied += 1
	var extra := int(mods.get("orb_extra", 0))
	while _extra_applied < extra:
		add_orb()
		_extra_applied += 1

# ── Posiciones orbitales ────────────────────────────────────────────────

func _update_orb_positions(_delta: float) -> void:
	var count := orbs.size()
	if count == 0:
		return
	var angle_step := TAU / float(count)
	var center := _player.global_position + Vector3(0, ORBIT_HEIGHT, 0)

	for i in range(count):
		var orb_data: Dictionary = orbs[i]
		var m: MeshInstance3D = orb_data.mesh
		if not is_instance_valid(m):
			continue
		var a := orbit_angle + angle_step * float(i)
		var bob := sin(orbit_angle * ORB_BOBBING_SPEED + float(i) * 1.3) * ORB_BOBBING_AMP
		m.global_position = center + Vector3(cos(a) * ORBIT_RADIUS, bob, sin(a) * ORBIT_RADIUS)

## Cada hoja/piedra es un nodo hijo con su origen en el centro del orbe: al rotarlo con un eje y una
## velocidad propios (y una leve "respiración" de tamaño) las piezas revolotean alrededor del orbe.
func _spin_decor(delta: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	for orb_data in orbs:
		var decor: Node3D = orb_data.get("decor")
		if not is_instance_valid(decor):
			continue
		decor.rotate_y(DECOR_SPIN_SPEED * delta)
		var i := 0
		for piece in decor.get_children():
			if piece is Node3D:
				var axis := Vector3(sin(i * 1.7), 1.0, cos(i * 2.3)).normalized()
				var spd := (2.2 + 0.7 * (i % 3)) * (1.0 if i % 2 == 0 else -1.0)
				var pulse := 1.0 + 0.18 * sin(t * 3.0 + i * 1.9)
				piece.transform.basis = (Basis(axis, spd * delta) * piece.transform.basis.orthonormalized()) * pulse
				i += 1

# ── Crear / quitar esferas ──────────────────────────────────────────────

func _create_orb(element_idx: int) -> void:
	var color: Color = ELEMENT_COLORS[element_idx]

	# Malla esférica con orbe_elemental.gdshader
	var mesh_inst := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = ORB_RADIUS
	sphere.height = ORB_RADIUS * 2.0
	sphere.radial_segments = 24
	sphere.rings = 16
	mesh_inst.mesh = sphere

	var mat := ShaderMaterial.new()
	mat.shader = preload("res://assets/shaders/orbe_elemental.gdshader")
	mat.set_shader_parameter("element", element_idx)
	mat.set_shader_parameter("emission_boost", 0.0)
	mesh_inst.material_override = mat

	# Partículas ambientales (chispas flotantes)
	var particles := CPUParticles3D.new()
	particles.amount = maxi(3, int(round(10.0 * Quality.particle_factor())))
	particles.lifetime = 0.7
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 0.14
	particles.gravity = Vector3.ZERO
	particles.spread = 180.0
	particles.initial_velocity_min = 0.2
	particles.initial_velocity_max = 0.6
	particles.scale_amount_min = 0.06
	particles.scale_amount_max = 0.12

	var p_mesh := SphereMesh.new()
	p_mesh.radius = 0.03
	p_mesh.height = 0.06
	particles.mesh = p_mesh

	var p_mat := StandardMaterial3D.new()
	p_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	p_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	p_mat.albedo_color = Color(color.r, color.g, color.b, 0.6)
	p_mat.emission_enabled = true
	p_mat.emission = color
	p_mat.emission_energy_multiplier = 2.0
	particles.material_override = p_mat

	var color_ramp := Gradient.new()
	color_ramp.set_color(0, Color(color.r, color.g, color.b, 0.7))
	color_ramp.add_point(1.0, Color(color.r, color.g, color.b, 0.0))
	particles.color_ramp = color_ramp

	mesh_inst.add_child(particles)
	particles.emitting = true

	# Hojas (planta) o piedras (tierra) que giran alrededor de su orbe
	var decor: Node3D = null
	if DECOR_SCENES.has(element_idx) and ResourceLoader.exists(DECOR_SCENES[element_idx]):
		var decor_scene: PackedScene = load(DECOR_SCENES[element_idx])
		decor = decor_scene.instantiate()
		mesh_inst.add_child(decor)

	# Añadir al árbol — como hijo del nodo orbs (self), no del jugador,
	# para que la posición sea global.
	add_child(mesh_inst)

	orbs.append({
		"mesh": mesh_inst,
		"mat": mat,
		"particles": particles,
		"p_mat": p_mat,
		"color_ramp": color_ramp,
		"element_idx": element_idx,
		"base_scale": mesh_inst.scale,
		"flash_tween": null,
		"emission_tween": null,
		"decor": decor,
	})

## Añade una esfera extra de un elemento desbloqueado al azar.
func add_orb() -> void:
	if _unlocked_elements.is_empty():
		_unlocked_elements = INITIAL_ELEMENTS.duplicate()
	_create_orb(_unlocked_elements[randi() % _unlocked_elements.size()])

## Quita la última esfera y libera todos sus recursos.
func remove_orb() -> void:
	if orbs.is_empty():
		return
	var data: Dictionary = orbs.pop_back()
	if is_instance_valid(data.mesh):
		# queue_free libera el mesh + sus hijos (particles, light)
		data.mesh.queue_free()
	# Limpiar referencias para el GC
	data.clear()

# ── Daño por contacto de las esferas ────────────────────────────────────

## Golpe de contacto: cada esfera que gira daña a los enemigos que toca.
## Cada esfera mantiene su propio cooldown por enemigo. Para que escale con muchos orbes y
## enemigos: primero se descartan los enemigos lejos del anillo orbital (una sola pasada) y solo
## contra los cercanos se prueba cada orbe; los cooldowns usan claves enteras y marcas de tiempo.
func _tick_contact_damage(_delta: float) -> void:
	if orbs.is_empty() or not _player.has_method("_weapon_damage"):
		return
	if EnemyRegistry.count() == 0:
		return

	var dmg: float = _player._weapon_damage(WeaponData.WeaponType.ELEMENTS_CYCLE)
	if dmg <= 0.0:
		return

	var now := Time.get_ticks_msec()
	if now - _last_purge_ms > 2000:
		_last_purge_ms = now
		for key in _hit_until.keys():
			if _hit_until[key] <= now:
				_hit_until.erase(key)

	# Enemigos que pueden tocar algún orbe: dentro del anillo orbital + radio de golpe + margen vertical
	var nearby: Array = EnemyRegistry.query_radius(_player.global_position, ORBIT_RADIUS + ORB_HIT_RADIUS + 1.5)
	if nearby.is_empty():
		return

	var hit_sq := ORB_HIT_RADIUS * ORB_HIT_RADIUS
	for orb_idx in range(orbs.size()):
		var orb_data: Dictionary = orbs[orb_idx]
		var m: MeshInstance3D = orb_data.mesh
		if not is_instance_valid(m) or not m.is_inside_tree():
			continue
		var orb_pos := m.global_position
		for enemy in nearby:
			if not is_instance_valid(enemy):
				continue
			# Cooldown por esfera + enemigo (clave entera)
			var cd_key: int = enemy.get_instance_id() * 64 + (orb_idx & 63)
			if _hit_until.get(cd_key, 0) > now:
				continue
			var to_enemy: Vector3 = (enemy.global_position + Vector3(0, 0.8, 0)) - orb_pos
			if to_enemy.length_squared() > hit_sq:
				continue
			HitFeedback.weapon_tag = WeaponData.WeaponType.ELEMENTS_CYCLE
			enemy.take_damage(dmg, to_enemy.normalized() * ORB_HIT_KNOCKBACK)
			_hit_until[cd_key] = now + int(ORB_HIT_INTERVAL * 1000.0)
			_flash_orb(orb_data)
			orb_hit.emit(int(orb_data.element_idx), enemy)

## El ataque ya no destella las esferas (causaba un parpadeo continuo); el feedback
## visual lo da solo el destello al golpear a un enemigo.
func flash_cycle() -> void:
	pass

## Flash de escala breve + pulso de emisión en el shader.
## Siempre parte y termina en el tamaño base de la esfera, y cancela el
## flash anterior si aún estaba en curso, para que los destellos solapados
## no acumulen tamaño.
func _flash_orb(orb_data: Dictionary) -> void:
	var m: MeshInstance3D = orb_data.mesh
	if not is_instance_valid(m) or not m.is_inside_tree():
		return

	# --- Flash de escala ---
	var prev: Tween = orb_data.get("flash_tween")
	if prev != null and prev.is_valid():
		prev.kill()
	var base_scale: Vector3 = orb_data.get("base_scale", Vector3.ONE)
	m.scale = base_scale
	var tween := m.create_tween()
	orb_data["flash_tween"] = tween
	tween.tween_property(m, "scale", base_scale * ORB_SIZE_FLASH, 0.06).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(m, "scale", base_scale, 0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)

	# --- Pulso de emisión en el shader ---
	var mat: ShaderMaterial = orb_data.mat
	if not is_instance_valid(mat):
		return
	var prev_em: Tween = orb_data.get("emission_tween")
	if prev_em != null and prev_em.is_valid():
		prev_em.kill()
	mat.set_shader_parameter("emission_boost", EMISSION_FLASH_PEAK)
	var em_tween := m.create_tween()
	orb_data["emission_tween"] = em_tween
	em_tween.tween_method(func(v: float):
		mat.set_shader_parameter("emission_boost", v)
	, EMISSION_FLASH_PEAK, 0.0, EMISSION_FLASH_DURATION).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)

## Cambia el elemento (shader param, color de partículas y gradient) de una esfera.
func _rotate_orb_element(orb_data: Dictionary, new_elem: int) -> void:
	orb_data.element_idx = new_elem
	var new_color: Color = ELEMENT_COLORS[new_elem]

	# Shader: cambiar elemento
	if is_instance_valid(orb_data.mat):
		var mat: ShaderMaterial = orb_data.mat
		mat.set_shader_parameter("element", new_elem)

	# Partículas: color del material
	if is_instance_valid(orb_data.get("p_mat")):
		var p_mat: StandardMaterial3D = orb_data.p_mat
		p_mat.albedo_color = Color(new_color.r, new_color.g, new_color.b, 0.6)
		p_mat.emission = new_color

	# Partículas: gradient (color_ramp)
	var ramp: Gradient = orb_data.get("color_ramp")
	if ramp:
		ramp.set_color(0, Color(new_color.r, new_color.g, new_color.b, 0.7))
		ramp.remove_point(1)
		ramp.add_point(1.0, Color(new_color.r, new_color.g, new_color.b, 0.0))

## Cambia la visibilidad de todas las esferas.
func set_orbs_visible(visible_val: bool) -> void:
	for orb_data in orbs:
		if is_instance_valid(orb_data.mesh):
			orb_data.mesh.visible = visible_val
			# Luz y partículas son hijas del mesh, se ocultan automáticamente
