extends Area3D

## RadiationZone.gd
## Aura radiactiva de Vangry: daña a los enemigos dentro en ticks fijos.
## Está pegada al jugador, así que lo sigue sola.
##
## Visual: un Decal que proyecta el símbolo de radiación sobre el suelo (se adapta
## al relieve y a los enemigos) y gira despacio, más unas pocas motas verdes.

@export var radius: float = 4.5
@export var damage_per_tick: float = 2.5
@export var tick_interval: float = 0.5

## Capa física de los enemigos (enemy.tscn: collision_layer = 4).
const ENEMY_MASK := 4
const TEX_SIZE := 512
const AURA_COLOR := Color(0.38, 1.0, 0.28)

static var _aura_texture: ImageTexture = null
static var _aura_emission: ImageTexture = null

var _tick_accum: float = 0.0
var _decal: Decal
var _t: float = 0.0

func _ready() -> void:
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = ENEMY_MASK
	add_to_group("radiation_zones")

	var shape := SphereShape3D.new()
	shape.radius = radius
	var col := CollisionShape3D.new()
	col.shape = shape
	add_child(col)

	_build_visual()

func _physics_process(delta: float) -> void:
	_tick_accum += delta
	if _tick_accum < tick_interval:
		return
	_tick_accum = 0.0
	for body in EnemyQuery.overlapping(self):
		if body.is_in_group("enemies") and body.has_method("take_damage"):
			body.take_damage(damage_per_tick, Vector3.ZERO)

func _process(delta: float) -> void:
	if _decal == null:
		return
	_t += delta
	_decal.rotation.y += delta * 0.35                      # giro lento del símbolo
	var pulse := 0.75 + 0.25 * sin(_t * 2.2)
	_decal.emission_energy = 1.1 * pulse
	_decal.modulate = Color(1, 1, 1, 0.65 + 0.2 * pulse)

# ───────────────────────────── Visual ─────────────────────────────

func _build_visual() -> void:
	if _aura_texture == null:
		_bake_textures()

	_decal = Decal.new()
	_decal.size = Vector3(radius * 2.0, 3.0, radius * 2.0)   # proyecta ±1.5 m en vertical
	_decal.position = Vector3(0.0, 0.8, 0.0)
	_decal.texture_albedo = _aura_texture
	_decal.texture_emission = _aura_emission
	_decal.emission_energy = 1.1
	_decal.upper_fade = 0.4
	_decal.lower_fade = 0.4
	_decal.distance_fade_enabled = false
	# En el mapa procedural el símbolo se proyecta SOLO sobre el suelo (no tiñe de verde
	# a los personajes); en otros mapas se proyecta sobre todo.
	if get_tree().get_first_node_in_group("procedural_map") != null:
		_decal.cull_mask = ProceduralMap.GROUND_VISUAL_LAYER
	add_child(_decal)

	# Pocas motas verdes que suben (barato: 10 partículas)
	var particles := CPUParticles3D.new()
	particles.amount = Quality.count(10)
	particles.lifetime = 1.8
	particles.direction = Vector3.UP
	particles.spread = 25.0
	particles.initial_velocity_min = 0.3
	particles.initial_velocity_max = 0.9
	particles.gravity = Vector3(0, 0.15, 0)
	particles.scale_amount_min = 0.5
	particles.scale_amount_max = 1.0
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = radius * 0.85
	particles.position = Vector3(0.0, 0.1, 0.0)
	var p_mesh := SphereMesh.new()
	p_mesh.radius = 0.05
	p_mesh.height = 0.1
	p_mesh.radial_segments = 6
	p_mesh.rings = 3
	particles.mesh = p_mesh
	var p_mat := StandardMaterial3D.new()
	p_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	p_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	p_mat.vertex_color_use_as_albedo = true
	p_mat.albedo_color = Color(0.55, 1.0, 0.4, 0.85)
	p_mat.emission_enabled = true
	p_mat.emission = AURA_COLOR
	p_mat.emission_energy_multiplier = 2.0
	particles.material_override = p_mat
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.9))
	ramp.add_point(1.0, Color(1, 1, 1, 0.0))
	particles.color_ramp = ramp
	add_child(particles)
	particles.emitting = true

## Dibuja el símbolo de radiación (trébol) con anillos y marcas, una sola vez para todos.
static func _step(edge: float, x: float) -> float:
	return 1.0 if x >= edge else 0.0

static func _bake_textures() -> void:
	var albedo := Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	var emis := Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	var c := Vector2(TEX_SIZE * 0.5, TEX_SIZE * 0.5)
	var aa := 2.0 / float(TEX_SIZE)       # ancho de suavizado ≈ 1 px
	for y in range(TEX_SIZE):
		for x in range(TEX_SIZE):
			var d := (Vector2(x + 0.5, y + 0.5) - c) / (TEX_SIZE * 0.5)   # -1..1
			var r := d.length()
			var a := 0.0       # opacidad
			var e := 0.0       # brillo emisivo
			if r <= 1.0:
				var ang := atan2(d.y, d.x)
				# Niebla tenue que sube hacia el borde
				a = 0.06 * smoothstep(0.1, 1.0, r)
				# Anillo exterior fino
				var outer := 1.0 - smoothstep(0.012, 0.012 + aa * 2.0, absf(r - 0.94))
				# Anillo interior discontinuo (marcas de peligro), bordes suaves
				var dash := smoothstep(-0.12, 0.12, sin(ang * 24.0))
				var inner := (1.0 - smoothstep(0.010, 0.010 + aa * 2.0, absf(r - 0.72))) * dash
				# Trébol: 3 aspas de 60° entre r=0.22 y r=0.54. Borde luminoso + relleno tenue
				var sector := fposmod(ang + PI * 0.5, TAU / 3.0)            # 0..120°
				var ang_edge := minf(sector, PI / 3.0 - sector)              # distancia angular al borde del aspa (≥0 dentro)
				var in_sector := smoothstep(-aa * 2.0 / maxf(r, 0.05), aa * 2.0 / maxf(r, 0.05), PI / 3.0 - sector) * smoothstep(-aa * 2.0 / maxf(r, 0.05), aa * 2.0 / maxf(r, 0.05), sector)
				var in_ring := smoothstep(0.22 - aa, 0.22 + aa, r) * (1.0 - smoothstep(0.54 - aa, 0.54 + aa, r))
				var blade := in_sector * in_ring
				var blade_edge := blade * (1.0 - smoothstep(0.0, 0.06, minf(ang_edge * r, minf(r - 0.22, 0.54 - r))))
				var hub := 1.0 - smoothstep(0.085 - aa, 0.085 + aa, r)
				var hub_ring := 1.0 - smoothstep(0.012, 0.012 + aa * 2.0, absf(r - 0.15))
				var symbol_fill := blade * 0.22 + hub * 0.55
				var symbol_line := maxf(blade_edge, hub_ring)
				a = maxf(a, maxf(outer * 0.75, maxf(inner * 0.55, maxf(symbol_fill, symbol_line * 0.7))))
				e = maxf(outer * 0.9, maxf(inner * 0.7, maxf(symbol_fill * 0.7, symbol_line)))
				# Atenuar en el borde del cuadrado
				var edge := 1.0 - smoothstep(0.96, 1.0, r)
				a *= edge
				e *= edge
			albedo.set_pixel(x, y, Color(AURA_COLOR.r * 0.8, AURA_COLOR.g, AURA_COLOR.b * 0.7, a))
			emis.set_pixel(x, y, Color(AURA_COLOR.r, AURA_COLOR.g, AURA_COLOR.b, 1.0) * e)
	albedo.generate_mipmaps()
	emis.generate_mipmaps()
	_aura_texture = ImageTexture.create_from_image(albedo)
	_aura_emission = ImageTexture.create_from_image(emis)
