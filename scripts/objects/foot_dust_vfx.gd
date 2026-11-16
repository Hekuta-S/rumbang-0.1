class_name FootDustVFX
extends RefCounted

## Polvo de los pies del jugador: pisadas, despegue del salto y aterrizaje.
## Billboards suaves (textura radial) en lugar de esferas, con materiales/mallas cacheados.
## Sin iluminar (un billboard iluminado a contraluz se volvía negro); en mazmorra el color es más apagado
## para que no brille como una luz en la cueva. La onda del suelo es un plano con un anillo que se abre y se desvanece (GeometryInstance3D.transparency).

static var _soft_tex: GradientTexture2D = null
static var _ring_tex: GradientTexture2D = null
static var _toon_cloud := false     ## las nubes van con la textura dibujada (ToonFX)
static var _quad: QuadMesh = null
static var _ring_plane: PlaneMesh = null
static var _cloud_mat: StandardMaterial3D = null
static var _grit_mat: StandardMaterial3D = null
static var _ring_mat: StandardMaterial3D = null

## Color base del polvo: arena clara en superficie, más gris y apagado en mazmorra.
static func _dust_color() -> Color:
	if GameData.game_mode == "dungeon":
		return Color(0.5, 0.47, 0.42)
	return Color(0.86, 0.8, 0.68)

static func _ensure() -> void:
	if _soft_tex != null:
		return
	_soft_tex = _radial([Color(1, 1, 1, 0.85), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)], [0.0, 0.45, 1.0])
	_ring_tex = _radial([Color(1, 1, 1, 0), Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)],
		[0.0, 0.55, 0.82, 1.0])
	_quad = QuadMesh.new()
	_quad.size = Vector2(1, 1)
	_ring_plane = PlaneMesh.new()
	_ring_plane.size = Vector2(1, 1)

	_cloud_mat = _mat(_soft_tex, true)
	_toon_cloud = ToonFX.puff_material(_cloud_mat)      # nubes dibujadas (cómic) en vez de la mancha suave
	_grit_mat = _mat(_soft_tex, true)
	_ring_mat = _mat(_ring_tex, false)
	_ring_mat.albedo_color = Color(1, 1, 1, 1)

static func _radial(colors: Array, offsets: Array) -> GradientTexture2D:
	var t := GradientTexture2D.new()
	t.width = 64
	t.height = 64
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.colors = PackedColorArray(colors)
	g.offsets = PackedFloat32Array(offsets)
	t.gradient = g
	return t

static func _mat(tex: Texture2D, billboard: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = tex
	m.vertex_color_use_as_albedo = true
	m.disable_receive_shadows = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if billboard:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.billboard_keep_scale = true
	return m

## Rampa de color: aparece rápido, se mantiene y se desvanece.
## Rampa de las nubes: las dibujadas van más opacas y más claras (si no, el contorno de tinta no se lee).
static func _cloud_ramp(c: Color, alpha: float) -> Gradient:
	if not _toon_cloud:
		return _ramp(c, alpha)
	return _ramp(c.lerp(Color.WHITE, 0.35), minf(alpha * 1.8, 0.92))

static func _ramp(c: Color, alpha: float) -> Gradient:
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(c.r, c.g, c.b, 0.0), Color(c.r, c.g, c.b, alpha),
		Color(c.r, c.g, c.b, alpha * 0.55), Color(c.r, c.g, c.b, 0.0)])
	g.offsets = PackedFloat32Array([0.0, 0.12, 0.55, 1.0])
	return g

static func _grow_curve(start: float, end: float) -> Curve:
	var cv := Curve.new()
	cv.max_value = maxf(2.0, end)
	cv.add_point(Vector2(0.0, start))
	cv.add_point(Vector2(0.35, lerpf(start, end, 0.75)))
	cv.add_point(Vector2(1.0, end))
	return cv

static func _base(amount: int, lifetime: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = Quality.count(amount)
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 0.92
	p.local_coords = false
	p.randomness = 0.6
	p.lifetime_randomness = 0.3
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.angular_velocity_min = -40.0
	p.angular_velocity_max = 40.0
	p.mesh = _quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p

## Nube que se abre a ras de suelo en todas direcciones (plano XZ).
static func _ground_cloud(amount: int, lifetime: float, radius: float, speed: float, size: Vector2, alpha: float, c: Color) -> CPUParticles3D:
	var p := _base(amount, lifetime)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius
	p.direction = Vector3(1, 0, 0)
	p.spread = 180.0
	p.flatness = 1.0
	p.initial_velocity_min = speed * 0.45
	p.initial_velocity_max = speed
	p.damping_min = speed * 1.6
	p.damping_max = speed * 2.4
	p.gravity = Vector3(0, 0.35, 0)
	p.scale_amount_min = size.x
	p.scale_amount_max = size.y
	p.scale_amount_curve = _grow_curve(0.5, 1.6)
	p.color_ramp = _cloud_ramp(c, alpha)
	p.material_override = _cloud_mat
	ToonFX.vary(p)
	# Levantada media bocanada: a ras de suelo el billboard atraviesa el piso y desaparece.
	p.position = Vector3(0, size.y * 0.45, 0)
	return p

## Chorro de polvo en una dirección (hacia atrás al correr, hacia arriba al saltar).
static func _jet(amount: int, lifetime: float, dir: Vector3, spread: float, speed: float, size: Vector2, alpha: float, c: Color) -> CPUParticles3D:
	var p := _base(amount, lifetime)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.08
	p.direction = dir.normalized()
	p.spread = spread
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.damping_min = speed * 1.2
	p.damping_max = speed * 2.0
	p.gravity = Vector3(0, -0.6, 0)
	p.scale_amount_min = size.x
	p.scale_amount_max = size.y
	p.scale_amount_curve = _grow_curve(0.4, 1.5)
	p.color_ramp = _cloud_ramp(c, alpha)
	p.material_override = _cloud_mat
	ToonFX.vary(p)
	p.position = Vector3(0, size.y * 0.4, 0)
	return p

## Granitos de tierra que saltan y caen con gravedad.
static func _grit(amount: int, speed: float, c: Color) -> CPUParticles3D:
	var p := _base(amount, 0.55)
	p.explosiveness = 0.98
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.15
	p.direction = Vector3.UP
	p.spread = 55.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -14.0, 0)
	p.scale_amount_min = 0.025
	p.scale_amount_max = 0.055
	var d := c.darkened(0.35)
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(d.r, d.g, d.b, 0.95), Color(d.r, d.g, d.b, 0.0)])
	g.offsets = PackedFloat32Array([0.7, 1.0])
	p.color_ramp = g
	p.material_override = _grit_mat
	return p

## Onda plana en el suelo que se abre y se apaga.
static func _ring(holder: Node3D, size_from: float, size_to: float, duration: float, alpha: float, c: Color) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _ring_plane
	var m: StandardMaterial3D = _ring_mat.duplicate()
	m.albedo_color = Color(c.r, c.g, c.b, alpha)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0, 0.03, 0)
	mi.scale = Vector3.ONE * size_from
	holder.add_child(mi)
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * size_to, duration).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(mi, "transparency", 1.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

static func _spawn(parent: Node, pos: Vector3, systems: Array, life: float) -> Node3D:
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.global_position = pos
	for s in systems:
		holder.add_child(s)
		s.restart()
		s.emitting = true
	var tw := holder.create_tween()
	tw.tween_interval(life)
	tw.tween_callback(holder.queue_free)
	return holder

## Pisada. `move_dir`: dirección horizontal en la que avanza (el polvo sale hacia atrás al correr).
static func step(parent: Node, pos: Vector3, move_dir: Vector3, running: bool) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	_ensure()
	var c := _dust_color()
	var systems: Array = []
	if running:
		systems.append(_ground_cloud(7, 0.55, 0.1, 1.1, Vector2(0.24, 0.4), 0.42, c))
		var back := -move_dir
		back.y = 0.0
		if back.length_squared() > 0.001:
			systems.append(_jet(5, 0.5, back.normalized() + Vector3(0, 0.55, 0), 28.0, 1.8, Vector2(0.18, 0.3), 0.35, c))
		systems.append(_grit(4, 2.2, c))
	else:
		systems.append(_ground_cloud(4, 0.5, 0.06, 0.6, Vector2(0.16, 0.28), 0.32, c))
	_spawn(parent, pos, systems, 0.8)

## Despegue del salto: anillo de polvo a ras de suelo y una bocanada que sube un poco.
static func takeoff(parent: Node, pos: Vector3) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	_ensure()
	var c := _dust_color()
	var systems: Array = [
		_ground_cloud(12, 0.6, 0.18, 2.6, Vector2(0.22, 0.4), 0.45, c),
		_jet(5, 0.5, Vector3.UP, 25.0, 1.6, Vector2(0.16, 0.28), 0.3, c),
	]
	var h := _spawn(parent, pos, systems, 0.9)
	_ring(h, 0.4, 1.8, 0.35, 0.4, c)

## Salto en el aire (saltos extra): sin suelo, solo una bocanada bajo los pies.
static func air_jump(parent: Node, pos: Vector3) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	_ensure()
	var c := _dust_color().lerp(Color.WHITE, 0.4)
	var p := _ground_cloud(10, 0.45, 0.12, 2.2, Vector2(0.18, 0.32), 0.35, c)
	p.gravity = Vector3(0, -1.5, 0)
	_spawn(parent, pos, [p], 0.7)

## Aterrizaje. `k` 0..1: lo fuerte de la caída (escala la onda, la nube y los granitos).
static func land(parent: Node, pos: Vector3, k: float) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	_ensure()
	k = clampf(k, 0.0, 1.0)
	var c := _dust_color()
	var systems: Array = [
		_ground_cloud(int(12 + 14 * k), 0.65 + 0.35 * k, 0.22, 2.4 + 3.0 * k,
			Vector2(0.26 + 0.12 * k, 0.45 + 0.25 * k), 0.5, c),
		_grit(int(5 + 10 * k), 2.6 + 2.4 * k, c),
	]
	var h := _spawn(parent, pos, systems, 1.3)
	_ring(h, 0.5, 2.2 + 2.2 * k, 0.32 + 0.12 * k, 0.45 + 0.2 * k, c)

## Compila los shaders del polvo delante de la cámara (si no, la primera pisada de la partida no se ve).
static var _warmed := false

static func prewarm(parent: Node3D) -> void:
	if _warmed or parent == null or not parent.is_inside_tree():
		return
	var cam := parent.get_viewport().get_camera_3d()
	if cam == null:
		return
	_warmed = true
	_ensure()
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.global_position = cam.global_position - cam.global_transform.basis.z * 2.0
	holder.scale = Vector3.ONE * 0.001
	var c := Color(1, 1, 1)
	for ps in [_ground_cloud(2, 0.2, 0.0, 0.1, Vector2(0.1, 0.1), 0.01, c), _grit(2, 0.1, c)]:
		holder.add_child(ps)
		ps.emitting = true
	_ring(holder, 1.0, 1.0, 0.2, 0.01, c)
	parent.get_tree().create_timer(0.5).timeout.connect(holder.queue_free)
