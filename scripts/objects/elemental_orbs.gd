extends Node3D
class_name ElementalOrbs

## Esferas elementales que orbitan alrededor del jugador (Ciclo Elemental de Saimon).
## Cinco elementos: aire, fuego, agua, tierra y naturaleza. Cada orbe sale con un elemento al azar
## entre los cinco, así que en una misma partida pueden repetirse (tres de fuego, dos de agua...).
## Cada orbe es un dibujo 2D de cómic horneado (tools/make_orb_sprites.py -> orbs.png) en un Sprite3D
## que mira a la cámara; alterna dos fotogramas para que el dibujo "hierva".
## Las mejoras (WeaponUpgrades.ELEMENTS_CYCLE_UPGRADES) añaden orbes: ver _sync_with_upgrades.
##
## El daño lo hacen las propias esferas: mientras giran, cada una golpea por
## contacto a los enemigos que toca (ver _tick_contact_damage).  Se pueden
## aumentar (add_orb) o perder (remove_orb) según upgrades.

# ── Configuración ───────────────────────────────────────────────────────
const INITIAL_ORBS := 4            ## Orbes con los que se empieza (elementos al azar, con repetición)
const SHEET_PATH := "res://assets/textures/toon/fx/orbs.png"
const SHEET_FRAMES := 2            ## Columnas de la hoja (fotogramas por elemento)
const FRAME_TIME := 0.18           ## s por fotograma del "hervido" del dibujo
const SPRITE_PIXEL := 0.0066       ## m por píxel: la bola dibujada mide ~0.45 m
const SYNC_INTERVAL := 0.25        ## cada cuánto se comparan los orbes con las mejoras (s)
const ORBIT_RADIUS := 2.4          ## Distancia al centro del jugador
const ORBIT_HEIGHT := 1.1          ## Altura sobre el suelo del jugador
const ORBIT_SPEED := 0.6           ## Vueltas por segundo (radianes = ORBIT_SPEED * TAU)
const ORB_SIZE_FLASH := 1.3        ## Multiplicador de tamaño del destello al golpear
const ORB_BOBBING_AMP := 0.12      ## Amplitud del movimiento vertical suave
const ORB_BOBBING_SPEED := 2.5     ## Velocidad del bobbing

## Radio de contacto: si un enemigo entra en este radio respecto al centro de
## una esfera, esa esfera lo golpea.
const ORB_HIT_RADIUS := 0.9
## Tiempo mínimo antes de que las esferas puedan volver a golpear al mismo enemigo.
const ORB_HIT_INTERVAL := 0.45
## Empuje que aplica cada golpe de esfera.
const ORB_HIT_KNOCKBACK := 3.0
## Duración del destello (aclarado del dibujo) al golpear (segundos).
const FLASH_DURATION := 0.2
## Brillo pico del destello (modulate del sprite).
const FLASH_PEAK := 1.8

## Orden = filas de orbs.png.
const ELEMENT_COLORS: Array = [
	Color(0.85, 0.95, 1.0),  # Aire
	Color(1.0, 0.35, 0.1),   # Fuego
	Color(0.15, 0.55, 1.0),  # Agua
	Color(0.65, 0.44, 0.24), # Tierra
	Color(0.35, 0.8, 0.25),  # Naturaleza
]

const ELEMENT_NAMES: Array = ["aire", "fuego", "agua", "tierra", "naturaleza"]

## Señal emitida cuando una esfera golpea a un enemigo.
## element_idx: índice del elemento de la esfera que golpeó.
## enemy: referencia al nodo enemigo golpeado.
signal orb_hit(element_idx: int, enemy)

# ── Estado ──────────────────────────────────────────────────────────────
var orbs: Array[Dictionary] = []   # [{mesh (Sprite3D), particles, p_mat, color_ramp, element_idx, base_scale, flash_tween}]
var orbit_angle: float = 0.0       ## Ángulo acumulado (rad)

var _player: CharacterBody3D = null
var _extra_applied := 0
var _sync_timer := 0.0
var _orbit_speed_mult := 1.0
var _frame_t := 0.0
var _frame := 0
## Clave entera (enemigo × 64 + orbe) → instante (ms) hasta el que no se vuelve a golpear.
var _hit_until: Dictionary = {}
var _last_purge_ms: int = 0

static var _sheet: Texture2D = null

# ── Ciclo de vida ───────────────────────────────────────────────────────

func setup(player: CharacterBody3D) -> void:
	_player = player
	for i in INITIAL_ORBS:
		add_orb()
	_sync_with_upgrades()

## Elemento al azar entre los cinco (con repetición).
static func random_element() -> int:
	return randi() % ELEMENT_NAMES.size()

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
	_animate_frames(delta)
	_tick_contact_damage(delta)

## Compara las mejoras del jugador con los orbes actuales y crea los que falten
## ("Nuevo orbe" -> orbe de un elemento al azar). También actualiza la velocidad de giro.
func _sync_with_upgrades() -> void:
	if not is_instance_valid(_player) or not _player.has_method("get_weapon_modifiers"):
		return
	var mods: Dictionary = _player.get_weapon_modifiers(WeaponData.WeaponType.ELEMENTS_CYCLE)
	_orbit_speed_mult = 1.0 + float(mods.get("orbit_speed", 0.0))
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
		var m: Sprite3D = orb_data.mesh
		if not is_instance_valid(m):
			continue
		var a := orbit_angle + angle_step * float(i)
		var bob := sin(orbit_angle * ORB_BOBBING_SPEED + float(i) * 1.3) * ORB_BOBBING_AMP
		m.global_position = center + Vector3(cos(a) * ORBIT_RADIUS, bob, sin(a) * ORBIT_RADIUS)

## Alterna los dos fotogramas de cada dibujo; cada orbe va desfasado para que no "hiervan" a la vez.
func _animate_frames(delta: float) -> void:
	_frame_t += delta
	if _frame_t < FRAME_TIME:
		return
	_frame_t = 0.0
	_frame = (_frame + 1) % SHEET_FRAMES
	for i in orbs.size():
		var spr: Sprite3D = orbs[i].mesh
		if is_instance_valid(spr):
			spr.frame = int(orbs[i].element_idx) * SHEET_FRAMES + (_frame + i) % SHEET_FRAMES

# ── Crear / quitar esferas ──────────────────────────────────────────────

static func _sheet_texture() -> Texture2D:
	if _sheet == null and ResourceLoader.exists(SHEET_PATH):
		_sheet = load(SHEET_PATH)
	return _sheet

func _create_orb(element_idx: int) -> void:
	var color: Color = ELEMENT_COLORS[element_idx]

	# Dibujo de cómic horneado: billboard sin luz y recorte alfa (sin mezcla: barato y sin problemas de orden)
	var spr := Sprite3D.new()
	spr.texture = _sheet_texture()
	spr.hframes = SHEET_FRAMES
	spr.vframes = ELEMENT_NAMES.size()
	spr.frame = element_idx * SHEET_FRAMES + orbs.size() % SHEET_FRAMES
	spr.pixel_size = SPRITE_PIXEL
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.double_sided = true
	spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	spr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Chispas del color del elemento (planas, sin emisión: la mezcla aditiva lavaba el dibujo)
	var particles := CPUParticles3D.new()
	particles.amount = maxi(3, int(round(8.0 * Quality.particle_factor())))
	particles.lifetime = 0.6
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 0.18
	particles.gravity = Vector3.ZERO
	particles.spread = 180.0
	particles.initial_velocity_min = 0.2
	particles.initial_velocity_max = 0.6
	particles.scale_amount_min = 0.06
	particles.scale_amount_max = 0.12

	var p_mesh := SphereMesh.new()
	p_mesh.radius = 0.03
	p_mesh.height = 0.06
	p_mesh.radial_segments = 6
	p_mesh.rings = 3
	particles.mesh = p_mesh

	var p_mat := StandardMaterial3D.new()
	p_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	p_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	p_mat.vertex_color_use_as_albedo = true
	particles.material_override = p_mat

	var color_ramp := Gradient.new()
	color_ramp.set_color(0, Color(color.r, color.g, color.b, 0.9))
	color_ramp.set_color(1, Color(color.r, color.g, color.b, 0.0))
	particles.color_ramp = color_ramp

	spr.add_child(particles)
	particles.emitting = true

	# Añadir al árbol — como hijo del nodo orbs (self), no del jugador,
	# para que la posición sea global.
	add_child(spr)

	orbs.append({
		"mesh": spr,
		"particles": particles,
		"p_mat": p_mat,
		"color_ramp": color_ramp,
		"element_idx": element_idx,
		"base_scale": spr.scale,
		"flash_tween": null,
		"emission_tween": null,
	})

## Añade una esfera extra de un elemento al azar (pueden repetirse).
func add_orb() -> void:
	_create_orb(random_element())

## Quita la última esfera y libera todos sus recursos.
func remove_orb() -> void:
	if orbs.is_empty():
		return
	var data: Dictionary = orbs.pop_back()
	if is_instance_valid(data.mesh):
		# queue_free libera el sprite + sus hijos (partículas)
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
		var m: Sprite3D = orb_data.mesh
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

## Flash de escala breve + aclarado del dibujo (modulate).
## Siempre parte y termina en el tamaño base de la esfera, y cancela el
## flash anterior si aún estaba en curso, para que los destellos solapados
## no acumulen tamaño.
func _flash_orb(orb_data: Dictionary) -> void:
	var m: Sprite3D = orb_data.mesh
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

	# --- Aclarado del dibujo ---
	var prev_em: Tween = orb_data.get("emission_tween")
	if prev_em != null and prev_em.is_valid():
		prev_em.kill()
	m.modulate = Color(FLASH_PEAK, FLASH_PEAK, FLASH_PEAK)
	var em_tween := m.create_tween()
	orb_data["emission_tween"] = em_tween
	em_tween.tween_property(m, "modulate", Color.WHITE, FLASH_DURATION).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)

## Cambia el elemento (dibujo y color de las chispas) de una esfera.
func _rotate_orb_element(orb_data: Dictionary, new_elem: int) -> void:
	orb_data.element_idx = new_elem
	var new_color: Color = ELEMENT_COLORS[new_elem]
	var spr: Sprite3D = orb_data.mesh
	if is_instance_valid(spr):
		spr.frame = new_elem * SHEET_FRAMES + spr.frame % SHEET_FRAMES
	var ramp: Gradient = orb_data.get("color_ramp")
	if ramp:
		ramp.set_color(0, Color(new_color.r, new_color.g, new_color.b, 0.9))
		ramp.set_color(1, Color(new_color.r, new_color.g, new_color.b, 0.0))

## Cambia la visibilidad de todas las esferas.
func set_orbs_visible(visible_val: bool) -> void:
	for orb_data in orbs:
		if is_instance_valid(orb_data.mesh):
			orb_data.mesh.visible = visible_val
			# Las partículas son hijas del sprite, se ocultan automáticamente
