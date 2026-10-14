extends Node3D
class_name ElementalOrbs

## Esferas elementales que orbitan alrededor del jugador (Ciclo Elemental de Saimon).
## Empiezan siendo 3.  Cada esfera gira alrededor del jugador a una altura fija
## y tiene su propio elemento/color que rota por el ciclo.
##
## El daño lo hacen las propias esferas: mientras giran, cada una golpea por
## contacto a los enemigos que toca (ver _tick_contact_damage).  Se pueden
## aumentar (add_orb) o perder (remove_orb) según upgrades.

# ── Configuración ───────────────────────────────────────────────────────
const BASE_ORB_COUNT := 3
const ORBIT_RADIUS := 1.6          ## Distancia al centro del jugador
const ORBIT_HEIGHT := 1.1          ## Altura sobre el suelo del jugador
const ORBIT_SPEED := 1.8           ## Vueltas por segundo (radianes = ORBIT_SPEED * TAU)
const ORB_RADIUS := 0.15
const ORB_SIZE_FLASH := 1.6        ## Multiplicador de tamaño del destello al golpear
const ORB_EMISSION_ENERGY := 2.8
const ORB_BOBBING_AMP := 0.12      ## Amplitud del movimiento vertical suave
const ORB_BOBBING_SPEED := 2.5     ## Velocidad del bobbing

## Radio de contacto: si un enemigo entra en este radio respecto al centro de
## una esfera, esa esfera lo golpea.
const ORB_HIT_RADIUS := 0.9
## Tiempo mínimo antes de que las esferas puedan volver a golpear al mismo enemigo.
const ORB_HIT_INTERVAL := 0.45
## Empuje que aplica cada golpe de esfera.
const ORB_HIT_KNOCKBACK := 3.0

# Colores del ciclo:  Fuego → Hielo → Viento → Agua → Planta
const ELEMENT_COLORS: Array = [
	Color(1.0, 0.3, 0.1),   # Fuego
	Color(0.2, 0.8, 1.0),   # Hielo
	Color(0.8, 0.8, 0.8),   # Viento
	Color(0.1, 0.4, 1.0),   # Agua
	Color(0.3, 0.9, 0.2),   # Planta
]

const ELEMENT_NAMES: Array = ["fuego", "hielo", "viento", "agua", "planta"]

# ── Estado ──────────────────────────────────────────────────────────────
var orbs: Array[Dictionary] = []   # [{mesh: MeshInstance3D, light: OmniLight3D, element_idx: int}]
var orbit_angle: float = 0.0       ## Ángulo acumulado (rad)

var _player: CharacterBody3D = null
## id de instancia de enemigo -> tiempo restante antes de volver a golpearlo
var _hit_cooldowns: Dictionary = {}

# ── Ciclo de vida ───────────────────────────────────────────────────────

func setup(player: CharacterBody3D) -> void:
	_player = player
	for i in range(BASE_ORB_COUNT):
		_create_orb(i % ELEMENT_COLORS.size())

func _process(delta: float) -> void:
	if not is_instance_valid(_player):
		return
	orbit_angle += ORBIT_SPEED * TAU * delta
	_update_orb_positions(delta)
	_tick_contact_damage(delta)

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

		var light: OmniLight3D = orb_data.light
		if is_instance_valid(light):
			light.global_position = m.global_position

# ── Crear / quitar esferas ──────────────────────────────────────────────

func _create_orb(element_idx: int) -> void:
	var color: Color = ELEMENT_COLORS[element_idx]

	# Malla esférica
	var mesh_inst := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = ORB_RADIUS
	sphere.height = ORB_RADIUS * 2.0
	sphere.radial_segments = 16
	sphere.rings = 8
	mesh_inst.mesh = sphere

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color.r, color.g, color.b, 0.85)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = ORB_EMISSION_ENERGY
	mesh_inst.material_override = mat

	# Partículas ambientales (chispas flotantes)
	var particles := CPUParticles3D.new()
	particles.amount = 8
	particles.lifetime = 0.6
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 0.12
	particles.gravity = Vector3.ZERO
	particles.spread = 180.0
	particles.initial_velocity_min = 0.3
	particles.initial_velocity_max = 0.8
	particles.scale_amount_min = 0.08
	particles.scale_amount_max = 0.15

	var p_mesh := SphereMesh.new()
	p_mesh.radius = 0.04
	p_mesh.height = 0.08
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

	# Luz puntual suave
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 1.2
	light.omni_range = 2.0
	light.shadow_enabled = false

	# Añadir al árbol — como hijo del nodo orbs (self), no del jugador,
	# para que la posición sea global.
	add_child(mesh_inst)
	add_child(light)

	orbs.append({
		"mesh": mesh_inst,
		"light": light,
		"mat": mat,
		"element_idx": element_idx,
		"base_scale": mesh_inst.scale,
		"flash_tween": null,
	})

## Añade una esfera extra con el siguiente elemento del ciclo.
func add_orb() -> void:
	var next_elem := orbs.size() % ELEMENT_COLORS.size()
	_create_orb(next_elem)

## Quita la última esfera.
func remove_orb() -> void:
	if orbs.is_empty():
		return
	var data: Dictionary = orbs.pop_back()
	if is_instance_valid(data.mesh):
		data.mesh.queue_free()
	if is_instance_valid(data.light):
		data.light.queue_free()

# ── Daño por contacto de las esferas ────────────────────────────────────

## Golpe de contacto: cada esfera que gira daña a los enemigos que toca.
func _tick_contact_damage(delta: float) -> void:
	# Enfriar los enemigos golpeados recientemente.
	for id in _hit_cooldowns.keys():
		_hit_cooldowns[id] -= delta
		if _hit_cooldowns[id] <= 0.0:
			_hit_cooldowns.erase(id)

	if orbs.is_empty() or not _player.has_method("_weapon_damage"):
		return

	var enemies := get_tree().get_nodes_in_group("enemies")
	if enemies.is_empty():
		return

	var dmg: float = _player._weapon_damage(WeaponData.WeaponType.ELEMENTS_CYCLE)
	if dmg <= 0.0:
		return

	for orb_data in orbs:
		var m: MeshInstance3D = orb_data.mesh
		if not is_instance_valid(m) or not m.is_inside_tree():
			continue
		for enemy in enemies:
			if not is_instance_valid(enemy) or not enemy.has_method("take_damage"):
				continue
			if _hit_cooldowns.has(enemy.get_instance_id()):
				continue
			var to_enemy: Vector3 = (enemy.global_position + Vector3(0, 0.8, 0)) - m.global_position
			if to_enemy.length() > ORB_HIT_RADIUS:
				continue
			enemy.take_damage(dmg, to_enemy.normalized() * ORB_HIT_KNOCKBACK)
			_hit_cooldowns[enemy.get_instance_id()] = ORB_HIT_INTERVAL
			_flash_orb(orb_data)

## Destella todas las esferas y avanza su elemento (feedback visual del ataque).
func flash_cycle() -> void:
	for orb_data in orbs:
		_flash_orb(orb_data)
		_rotate_orb_element(orb_data, (int(orb_data.element_idx) + 1) % ELEMENT_COLORS.size())

## Flash de escala breve sobre una esfera. Siempre parte y termina en el tamaño
## base de la esfera, y cancela el flash anterior si aún estaba en curso, para
## que los destellos solapados no acumulen tamaño.
func _flash_orb(orb_data: Dictionary) -> void:
	var m: MeshInstance3D = orb_data.mesh
	if not is_instance_valid(m) or not m.is_inside_tree():
		return
	var prev: Tween = orb_data.get("flash_tween")
	if prev != null and prev.is_valid():
		prev.kill()
	var base_scale: Vector3 = orb_data.get("base_scale", Vector3.ONE)
	m.scale = base_scale
	var tween := m.create_tween()
	orb_data["flash_tween"] = tween
	tween.tween_property(m, "scale", base_scale * ORB_SIZE_FLASH, 0.06).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(m, "scale", base_scale, 0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)

## Cambia el elemento (color del material y de la luz) de una esfera.
func _rotate_orb_element(orb_data: Dictionary, new_elem: int) -> void:
	var old_elem: int = orb_data.element_idx
	orb_data.element_idx = new_elem
	var new_color: Color = ELEMENT_COLORS[new_elem]
	var m: MeshInstance3D = orb_data.mesh

	if is_instance_valid(orb_data.mat) and is_instance_valid(m) and m.is_inside_tree():
		var mat: StandardMaterial3D = orb_data.mat
		var color_tween := m.create_tween()
		color_tween.tween_method(func(col: Color):
			mat.albedo_color = Color(col.r, col.g, col.b, 0.85)
			mat.emission = col
		, ELEMENT_COLORS[old_elem], new_color, 0.25)
	if is_instance_valid(orb_data.light):
		var lt: OmniLight3D = orb_data.light
		var lt_tween := lt.create_tween()
		lt_tween.tween_property(lt, "light_color", new_color, 0.25)

## Cambia la visibilidad de todas las esferas.
func set_orbs_visible(visible_val: bool) -> void:
	for orb_data in orbs:
		if is_instance_valid(orb_data.mesh):
			orb_data.mesh.visible = visible_val
		if is_instance_valid(orb_data.light):
			orb_data.light.visible = visible_val
