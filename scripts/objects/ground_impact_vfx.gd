class_name GroundImpactVFX
extends Node3D

## Marca de un golpe pesado contra el suelo (mazazos): el suelo parece hundirse y saltan trozos de tierra.
##  - Hundimiento: un Decal con grietas radiales y mapa de normales (cuenco con el borde levantado) que se
##    proyecta sobre el suelo real, así la luz lo "abolla" sin tocar la malla del mapa.
##  - Borde levantado: cascotes medio enterrados alrededor, inclinados hacia fuera.
##  - Trozos volando: piedritas que salen disparadas, caen, rebotan una vez y se quedan en el suelo.
## Pasados LIFETIME segundos todo se hunde y se borra. Como mucho MAX_ALIVE a la vez (se va el más viejo).
## Uso: GroundImpactVFX.spawn(escena, punto, radio, fuerza)

## false: los golpes pesados ya no dejan grieta, cascotes ni trozos de tierra en el suelo.
const ENABLED := false
const LIFETIME := 6.0
const FADE := 1.2
const MAX_ALIVE := 8
const GRAVITY := 18.0
const TEX := 128
const DIRT := Color(0.42, 0.35, 0.27)

static var _alive: Array = []
static var _albedo: ImageTexture
static var _normal: ImageTexture
static var _rocks: Array = []        ## variantes de malla de piedra (ArrayMesh)
static var _rock_mat: StandardMaterial3D

var radius := 1.0
var strength := 1.0
var ground_y := 0.0
var _t := 0.0
var _decal: Decal
var _debris: Array = []              ## [{node, vel, spin, bounces, size, rest}]
var _rubble: Array[Node3D] = []

static func spawn(root: Node, at: Vector3, p_radius: float, p_strength: float = 1.0) -> GroundImpactVFX:
	if not ENABLED or root == null or not root.is_inside_tree():
		return null
	_alive = _alive.filter(func(n): return is_instance_valid(n))
	while _alive.size() >= MAX_ALIVE:
		var old = _alive.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	var fx := GroundImpactVFX.new()
	fx.radius = p_radius
	fx.strength = p_strength
	root.add_child(fx)
	fx.global_position = _ground_point(root, at)
	fx.ground_y = fx.global_position.y
	_alive.append(fx)
	fx._build()
	return fx

## Punto del suelo bajo `at` (rayo contra el mundo, capa 1); si no hay nada, el propio punto.
static func _ground_point(root: Node, at: Vector3) -> Vector3:
	var w := (root as Node3D).get_world_3d() if root is Node3D else root.get_viewport().world_3d
	if w == null:
		return at
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 1.5, at + Vector3.DOWN * 3.0, 1)
	var hit := w.direct_space_state.intersect_ray(q)
	return hit["position"] if not hit.is_empty() else at

func _build() -> void:
	_ensure_assets()
	var r := radius
	# 1. Hundimiento con grietas (proyectado: se adapta a la textura y al relieve del suelo)
	_decal = Decal.new()
	_decal.texture_albedo = _albedo
	_decal.texture_normal = _normal
	_decal.size = Vector3(r * 2.4, 1.6, r * 2.4)
	_decal.rotation.y = randf() * TAU
	_decal.albedo_mix = 0.7
	_decal.normal_fade = 0.4
	_decal.upper_fade = 0.3
	_decal.lower_fade = 0.3
	add_child(_decal)
	# 2. Borde levantado: cascotes medio enterrados e inclinados hacia fuera
	var n_rubble := Quality.count(int(8 * strength))
	for i in n_rubble:
		var a := TAU * (float(i) + randf_range(-0.3, 0.3)) / float(n_rubble)
		var d := r * randf_range(0.55, 0.85)
		var s := r * randf_range(0.13, 0.22) * sqrt(strength)
		var rock := _rock(s)
		add_child(rock)
		rock.position = Vector3(cos(a) * d, s * 0.08, sin(a) * d)   # asoman: la escala vertical ya los aplasta
		var out := Vector3(cos(a), 0.0, sin(a))
		rock.basis = Basis(out.cross(Vector3.UP).normalized(), deg_to_rad(randf_range(20.0, 45.0))) \
			* Basis(Vector3.UP, randf() * TAU) * Basis.from_scale(Vector3(s, s * randf_range(0.5, 0.8), s))   # (basis pisa la escala)
		_rubble.append(rock)
	# 3. Trozos que salen volando desde el centro
	var n_debris := Quality.count(int(14 * strength))
	for i in n_debris:
		var s := r * randf_range(0.06, 0.12)
		var rock := _rock(s)
		add_child(rock)
		var a := randf() * TAU
		var out := Vector3(cos(a), 0.0, sin(a))
		rock.position = out * r * 0.2 + Vector3.UP * 0.1
		var speed := randf_range(2.5, 5.5) * sqrt(strength)
		_debris.append({"node": rock, "vel": out * speed + Vector3.UP * randf_range(4.0, 7.5) * sqrt(strength),
			"spin": Vector3(randf_range(-12, 12), randf_range(-12, 12), randf_range(-12, 12)),
			"bounces": 0, "size": s, "rest": false})

func _process(delta: float) -> void:
	_t += delta
	for d in _debris:
		if d["rest"]:
			continue
		var node: Node3D = d["node"]
		var v: Vector3 = d["vel"]
		v.y -= GRAVITY * delta
		node.position += v * delta
		node.rotation += (d["spin"] as Vector3) * delta
		var floor_y: float = float(d["size"]) * 0.4
		if node.position.y <= floor_y and v.y < 0.0:
			node.position.y = floor_y
			if int(d["bounces"]) < 1:
				v = Vector3(v.x * 0.45, -v.y * 0.3, v.z * 0.45)
				d["spin"] = (d["spin"] as Vector3) * 0.4
				d["bounces"] = 1
			else:
				v = Vector3.ZERO
				d["rest"] = true
		d["vel"] = v
	# Final: todo se hunde en el suelo y la marca se desvanece
	if _t > LIFETIME:
		var k := clampf((_t - LIFETIME) / FADE, 0.0, 1.0)
		_decal.modulate.a = 1.0 - k
		for d in _debris:
			var node: Node3D = d["node"]
			node.position.y -= float(d["size"]) * 1.5 * delta / FADE
		for rock in _rubble:
			rock.position.y -= radius * 0.25 * delta / FADE
		if k >= 1.0:
			queue_free()

func _rock(size: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _rocks[randi() % _rocks.size()]
	mi.material_override = _rock_mat
	mi.scale = Vector3.ONE * size
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

# ───────────────────────────── recursos compartidos ─────────────────────────────

static func _ensure_assets() -> void:
	if _albedo:
		return
	_bake_textures()
	_rock_mat = StandardMaterial3D.new()
	_rock_mat.vertex_color_use_as_albedo = true
	_rock_mat.albedo_color = DIRT
	_rock_mat.roughness = 1.0
	for v in 3:
		_rocks.append(_rock_mesh(v))

## Piedra de pocos polígonos: esfera baja con los vértices empujados al azar (radio ~1) y un tono de tierra
## distinto por cara.
static func _rock_mesh(seed_i: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * (seed_i + 1)
	var sph := SphereMesh.new()
	sph.radius = 0.5
	sph.height = 1.0
	sph.radial_segments = 6
	sph.rings = 3
	var arr := sph.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	# El mismo desplazamiento para vértices que coinciden (la costura de la esfera no se abre)
	var bump := {}
	for i in verts.size():
		var key := Vector3i((verts[i] * 1000.0).round())
		if not bump.has(key):
			bump[key] = rng.randf_range(0.7, 1.25)
		verts[i] *= float(bump[key])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	for t in range(0, idx.size(), 3):
		var shade := rng.randf_range(0.75, 1.15)
		st.set_color(Color(shade, shade * rng.randf_range(0.95, 1.02), shade * rng.randf_range(0.9, 1.0)))
		for k in 3:
			st.add_vertex(verts[idx[t + k]])
	st.generate_normals()
	return st.commit()

## Texturas del hundimiento: altura = cuenco con el borde levantado + grietas radiales; de ahí el color
## (más oscuro en el fondo y en las grietas, transparente fuera) y el mapa de normales.
static func _bake_textures() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var cracks := []   ## [ángulo, largo, grosor, fase1, fase2]
	for i in 7:
		cracks.append([TAU * (float(i) + rng.randf_range(-0.3, 0.3)) / 7.0, rng.randf_range(0.6, 0.95),
			rng.randf_range(0.012, 0.022), rng.randf() * TAU, rng.randf() * TAU])
	var h := PackedFloat32Array()
	h.resize(TEX * TEX)
	var crack_mask := PackedFloat32Array()
	crack_mask.resize(TEX * TEX)
	for y in TEX:
		for x in TEX:
			var p := Vector2(x, y) / float(TEX) * 2.0 - Vector2.ONE
			var r := p.length()
			var ang := atan2(p.y, p.x)
			var bowl := -0.5 * pow(clampf(1.0 - r / 0.5, 0.0, 1.0), 1.3)            # fondo hundido
			var rim := 0.25 * exp(-pow((r - 0.52) / 0.1, 2.0))                      # borde levantado
			var c := 0.0
			if r > 0.2:   # las grietas nacen en el borde del hundimiento y van hacia fuera, quebradas
				for cr in cracks:
					if r > float(cr[1]):
						continue
					var wob := 0.18 * sin(r * 17.0 + float(cr[3])) + 0.08 * sin(r * 41.0 + float(cr[4]))
					var dist := absf(wrapf(ang - float(cr[0]) - wob, -PI, PI)) * r   # distancia lineal
					var w: float = float(cr[2]) * (1.0 - 0.6 * (r - 0.2) / float(cr[1]))
					c = maxf(c, clampf(1.0 - dist / w, 0.0, 1.0) * clampf((float(cr[1]) - r) * 8.0, 0.0, 1.0))
			h[y * TEX + x] = (bowl + rim) * clampf((1.0 - r) * 3.0, 0.0, 1.0) - 0.2 * c
			crack_mask[y * TEX + x] = c
	var alb := Image.create(TEX, TEX, false, Image.FORMAT_RGBA8)
	var nrm := Image.create(TEX, TEX, false, Image.FORMAT_RGBA8)
	for y in TEX:
		for x in TEX:
			var p := Vector2(x, y) / float(TEX) * 2.0 - Vector2.ONE
			var r := p.length()
			var hv := h[y * TEX + x]
			var dark := clampf(-hv * 1.1, 0.0, 0.7) + crack_mask[y * TEX + x] * 0.6
			var col := DIRT.darkened(dark)
			var a := clampf((1.0 - r) * 2.2, 0.0, 1.0) * clampf(0.35 + dark * 1.4 + absf(hv) * 1.2, 0.0, 1.0)
			alb.set_pixel(x, y, Color(col.r, col.g, col.b, a))
			var hx := h[y * TEX + mini(x + 1, TEX - 1)] - h[y * TEX + maxi(x - 1, 0)]
			var hy := h[mini(y + 1, TEX - 1) * TEX + x] - h[maxi(y - 1, 0) * TEX + x]
			var n := Vector3(-hx * 18.0, -hy * 18.0, 1.0).normalized()
			nrm.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5, 1.0))
	alb.generate_mipmaps()
	nrm.generate_mipmaps()
	_albedo = ImageTexture.create_from_image(alb)
	_normal = ImageTexture.create_from_image(nrm)
