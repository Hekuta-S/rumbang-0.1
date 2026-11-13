class_name DungeonHub
extends Node3D

## Salón de la Invocación: el MENÚ PRINCIPAL del juego es este salón del trono, que se recorre andando.
## La primera vez se ve la cinemática (el rey y su mago invocan al héroe); al acabar (o al saltarla) la
## cámara pasa sin cortes a seguir al héroe. Cada opción del menú es un objeto del salón (STATIONS):
##   mago           -> abre un portal por mundo de mazmorra; al cruzarlo: personalización y partida
##   yunque         -> arma inicial de la mazmorra (espalanza, dagas o maza: GameData.dungeon_weapon)
##   puerta arena   -> supervivencia con los personajes de siempre
##   cofre          -> mejoras de armas      libro -> logros y evoluciones      mesa -> ajustes
##   bola de cristal-> multijugador LAN      portón -> salir del juego
## Modelos: tools/blender_salon_invocacion.py (assets/models/salon/salon_trono.glb, rey.glb, mago.glb).
## Coordenadas: el salón de Blender pasa a Godot como (x, z, -y): el círculo está en (0, 0, -1.5), el
## trono al fondo (z = -11) y el portón de entrada en z = +8.

const Style := preload("res://scripts/ui/rumbang_style.gd")
const HubPanelsScript := preload("res://scripts/ui/hub_panels.gd")

const SALON_PATH := "res://assets/models/salon/salon_trono.glb"
const KING_PATH := "res://assets/models/salon/rey.glb"
const MAGE_PATH := "res://assets/models/salon/mago.glb"
const TEX_DIR := "res://assets/textures/dungeon/"
const CHARACTER_SELECT := "res://scenes/ui/character_select.tscn"
const SURVIVAL_SCENE := "res://scenes/core/main_procedural.tscn"
const LOBBY := "res://scenes/ui/lobby_menu.tscn"
const TUTORIAL := "res://scenes/core/tutorial_patio.tscn"
const TITLE := "res://scenes/ui/title_screen.tscn"   ## pantalla de título (panorama del mapa)

const FLOOR_Y := 0.08
const CIRCLE := Vector3(0.0, FLOOR_Y, -1.5)
const KING_POS := Vector3(0.35, 0.75, -9.55)
const MAGE_POS := Vector3(-3.05, FLOOR_Y, -0.35)
const PLAYER_HEIGHT := 1.62
## Cámara de seguimiento: detrás del héroe (hacia la entrada) y en alto, mirando hacia el trono.
const FOLLOW_OFFSET := Vector3(0.0, 3.3, 4.6)
const FOLLOW_LOOK := Vector3(0.0, 1.0, -0.6)

## Estaciones: id -> punto de uso, radio, rótulo, texto del aviso y plano de cámara al usarla
## [posición, objetivo] relativos al punto (null = la cámara sigue al héroe).
const STATIONS := {
	"mago": {"pos": Vector3(-3.05, FLOOR_Y, -0.35), "r": 1.7, "label": "EL MAGO", "h": 2.35, "prompt": "Hablar con el mago",
		"cam": null},
	"yunque": {"pos": Vector3(4.5, FLOOR_Y, -1.0), "r": 1.5, "label": "YUNQUE", "h": 1.5, "prompt": "Yunque: armas de la mazmorra",
		"cam": [Vector3(-2.3, 1.5, 0.6), Vector3(0.4, 0.9, -0.9)]},
	"arena": {"pos": Vector3(0.0, FLOOR_Y, -12.6), "r": 2.0, "label": "ARENA", "h": 5.6, "prompt": "Arena de supervivencia",
		"cam": [Vector3(-2.4, 1.7, 3.0), Vector3(0.0, 1.7, -1.4)]},
	"cofre": {"pos": Vector3(5.0, FLOOR_Y, 4.4), "r": 1.5, "label": "COFRE", "h": 1.3, "prompt": "Cofre: mejoras de armas",
		"cam": [Vector3(-2.0, 1.4, 1.2), Vector3(0.0, 0.4, 0.0)]},
	"libro": {"pos": Vector3(-4.8, FLOOR_Y, 5.2), "r": 1.4, "label": "LOGROS", "h": 1.7, "prompt": "Libro de logros",
		"cam": [Vector3(1.6, 1.6, 1.0), Vector3(0.0, 1.0, 0.0)]},
	"mesa": {"pos": Vector3(4.4, FLOOR_Y, -6.4), "r": 1.6, "label": "AJUSTES", "h": 1.6, "prompt": "Mesa del escriba: ajustes",
		"cam": [Vector3(-1.8, 1.6, 1.4), Vector3(0.0, 0.8, 0.0)]},
	"bola": {"pos": Vector3(-4.4, FLOOR_Y, -6.6), "r": 1.5, "label": "MULTIJUGADOR", "h": 1.9, "prompt": "Bola de cristal: multijugador LAN",
		"cam": [Vector3(1.6, 1.6, 1.4), Vector3(0.0, 1.2, 0.0)]},
	"patio": {"pos": Vector3(2.6, FLOOR_Y, 4.2), "r": 1.5, "label": "TUTORIAL", "h": 2.5, "prompt": "Repetir el tutorial del patio",
		"cam": null},
	"salir": {"pos": Vector3(0.0, FLOOR_Y, 6.9), "r": 1.9, "label": "SALIR", "h": 3.4, "prompt": "Salir del juego",
		"cam": [Vector3(0.0, 2.0, -4.0), Vector3(0.0, 2.2, 1.0)]},
}
## Estaciones de los muros: al acercarse, la cámara se gira para enseñar la puerta
## [posición relativa al héroe, punto mirado (absoluto)].
const NEAR_CAMS := {
	"salir": [Vector3(1.8, 2.0, -3.6), Vector3(0.0, 2.3, 7.9)],
	"arena": [Vector3(2.4, 2.2, 3.4), Vector3(0.0, 2.0, -13.9)],
}
## Portales del mago (uno por mundo, en las marcas de runas de la izquierda) y su color
const PORTAL_SPOTS := [Vector3(-4.7, FLOOR_Y, -4.4), Vector3(-4.7, FLOOR_Y, 2.6)]
const PORTAL_COLORS := {"caves": Color(1.0, 0.55, 0.2), "sewers": Color(0.45, 1.0, 0.3)}
const PORTAL_ENTER_R := 0.75

## Guion de la intro: [segundo, quién, texto]. Tono épico con humor (el héroe aparece en calzones).
const LINES := [
	[1.2, "rey", "¡Por la corona de Rumbang! Mago, ¡que se cumpla la profecía!"],
	[5.2, "mago", "Círculo antiguo, escucha mi voz... ¡Tráenos al héroe de las mazmorras!"],
	[12.4, "rey", "¿...Este es el héroe? ¿En calzones?"],
	[15.4, "mago", "Ejem. La profecía no decía nada de la ropa, majestad."],
	[18.6, "rey", "¡Bah! Bienvenido, héroe. Mis mazmorras te esperan."],
]
const MAGE_OPEN_LINE := "¿Listo para las mazmorras? ¡Abro los portales! Elige tu destino."
const MAGE_AGAIN_LINE := "Los portales siguen abiertos, héroe. Cruza el que quieras."
const SPEAKERS := {"rey": ["El Rey", Color(1.0, 0.78, 0.3)], "mago": ["El Mago", Color(0.45, 0.8, 1.0)]}
const INTRO_LENGTH := 22.2
const FLASH_AT := 9.6

## Ruta del ajuste "intro vista" (los tests la cambian para no tocar la partida guardada).
static var config_path := "user://dungeon_hub.cfg"
## Fuerza la cinemática aunque ya se haya visto (tests y capturas).
static var force_intro := false
## Los portales del mago siguen abiertos durante la sesión (al volver de una partida).
static var portals_open := false

signal intro_finished
signal explore_started
signal station_used(id: String)
signal portals_opened

var state := "loading"            ## loading | intro | explore | panel | leaving
var intro_time := 0.0
var camera: Camera3D
var king: Node3D
var mage: Node3D
var player: HubPlayer
var player_model: Node3D
var ui: CanvasLayer
var panels: HubPanels
var near_station := ""            ## estación al alcance del héroe ("" = ninguna)
var portals: Array[Dictionary] = []   ## {world, node, light, label, open}
var rack_weapons: Dictionary = {}     ## WeaponType -> Node3D (en el armero)

var _cam_pos := Vector3.ZERO
var _cam_target := Vector3.ZERO
var _cam_fov := 45.0
var _cam_override: Variant = null     ## [pos, target] mientras hay un panel abierto
var _shake := 0.0
var _cam_tween: Tween
var _timeline: Array[Dictionary] = []   ## eventos de la intro {t, fn, done}
var _rune_mat: StandardMaterial3D
var _flame_mat: StandardMaterial3D
var _circle_light: OmniLight3D
var _torches: Array[OmniLight3D] = []
var _torch_base: Array[float] = []
var _beam: MeshInstance3D
var _beam_mat: ShaderMaterial
var _sparks: CPUParticles3D
var _voice: AudioStreamPlayer
var _time := 0.0
var _skip_armed := false
var _station_labels: Dictionary = {}  ## id -> Label3D
var _movers: Dictionary = {}          ## puertas y tapa del cofre (nombre -> Node3D)
var _rack_light: OmniLight3D
var _sub_hide_at := -1.0

# UI
var _fade: ColorRect
var _flash: ColorRect
var _sub_panel: PanelContainer
var _sub_name: Label
var _sub_text: Label
var _skip_label: Label
var _hud: Control
var _prompt: Button
var _touch_controls: Node   ## MobileControls en modo "hub" (null fuera de móvil)
var _hint: Label
var _letterbox: Array[ColorRect] = []

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_world()
	_build_ui()
	if force_intro or OS.get_cmdline_user_args().has("--intro"):
		start_intro()
	else:
		begin_explore(true)

# ───────────────────────────── intro vista ─────────────────────────────

static func intro_seen() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(config_path) != OK:
		return false
	return bool(cfg.get_value("intro", "seen", false))

## Tutorial del patio (TutorialPatio): la primera vez, el título lleva allí antes que al salón.
static func tutorial_done() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(config_path) != OK:
		return false
	return bool(cfg.get_value("tutorial", "done", false))

static func set_tutorial_done(done: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.load(config_path)
	cfg.set_value("tutorial", "done", done)
	cfg.save(config_path)

## Creación de personaje de la primera partida (CharacterSelect.creation): va antes del tutorial.
static func character_created() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(config_path) != OK:
		return false
	return bool(cfg.get_value("personaje", "creado", false))

static func set_character_created(done: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.load(config_path)
	cfg.set_value("personaje", "creado", done)
	cfg.save(config_path)

static func set_intro_seen(seen: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.load(config_path)
	cfg.set_value("intro", "seen", seen)
	cfg.save(config_path)

# ───────────────────────────── mundo ─────────────────────────────

func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.01, 0.02)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.3, 0.42)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 5.0
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.1
	env.fog_enabled = true
	env.fog_light_color = Color(0.12, 0.1, 0.16)
	env.fog_density = 0.012
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.06
	Quality.tune_environment(env, get_viewport())
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	Quality.add_governor(self, get_viewport())

	camera = Camera3D.new()
	camera.near = 0.05
	camera.far = 80.0
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # se mueve en _process
	add_child(camera)
	camera.current = true

	var salon := _instance(SALON_PATH)
	if salon:
		salon.name = "Salon"
		add_child(salon)
		_dress_salon(salon)
		for n in ["porton_izq", "porton_der", "puerta_arena_izq", "puerta_arena_der", "cofre_tapa"]:
			var found := salon.find_child(n, true, false)
			if found:
				_movers[n] = found
	_build_collision()

	# Luna por las vidrieras (fría, la única con sombras de largo alcance)
	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.55, 0.62, 1.0)
	moon.light_energy = 0.35
	moon.rotation_degrees = Vector3(-38.0, -70.0, 0.0)
	Quality.tune_light(moon)
	moon.directional_shadow_max_distance = 30.0
	add_child(moon)

	# Luces omni (el renderizador móvil admite 8 por malla y el salón es una sola): antorchas, braseros,
	# círculo y fragua. Lo demás (relleno, portales, bola, arena) son focos, que tienen su propio cupo.
	for p in [Vector3(-5.6, 3.2, 1.0), Vector3(5.6, 3.2, 1.0), Vector3(-3.2, 1.9, -11.4), Vector3(3.2, 1.9, -11.4)]:
		if Quality.is_mobile() and p.y < 2.5:
			continue   # móvil: menos luces omni (cada una se recalcula por píxel); el foco de la arena cubre el fondo
		_torch(p, Color(1.0, 0.58, 0.26), 2.2 if p.y > 2.5 else 1.8, 9.0, p.y < 2.5)
	if not Quality.is_mobile():
		_torch(Vector3(5.6, 1.4, -1.0), Color(1.0, 0.45, 0.15), 2.0, 5.0, false)      # fragua
	_circle_light = OmniLight3D.new()
	_circle_light.position = CIRCLE + Vector3(0, 0.6, 0)
	_circle_light.light_color = Color(0.4, 0.75, 1.0)
	_circle_light.light_energy = 0.6
	_circle_light.omni_range = 7.0
	Quality.tune_light(_circle_light)
	add_child(_circle_light)
	_spot(Vector3(-4.4, 2.6, -6.6), Vector3(-4.4, FLOOR_Y, -6.6), Color(0.75, 0.4, 1.0), 2.5, 35.0)   # bola
	_spot(Vector3(0.0, 3.4, -10.6), Vector3(0.0, 1.6, -13.9), Color(1.0, 0.3, 0.1), 2.6, 50.0)        # arena
	_spot(Vector3(4.6, 3.0, -1.4), Vector3(4.8, 0.8, -2.55), Color(1.0, 0.8, 0.6), 1.6, 40.0)        # armero

	_build_beam()

	mage = _spawn_npc(MAGE_PATH, MAGE_POS, _yaw_to(MAGE_POS, CIRCLE) - 0.35, _mage_look())
	_play(mage, "mago_idle")
	player = HubPlayer.new()
	player.name = "Heroe"
	add_child(player)
	player.position = CIRCLE
	player.setup(FLOOR_Y, CharacterLook.current())
	player.pivot.rotation.y = 0.3
	player_model = player.model
	# luz de relleno que acompaña al héroe (la cara no queda a contraluz)
	var fill := SpotLight3D.new()
	fill.position = Vector3(-0.8, 2.6, 2.4)
	fill.light_color = Color(1.0, 0.86, 0.72)
	fill.light_energy = 1.4
	fill.spot_range = 6.0
	fill.spot_angle = 30.0
	player.add_child(fill)
	fill.look_at_from_position(fill.position, Vector3(0, 1.0, 0))
	# Móvil: joystick + correr + interactuar (solo visibles al explorar)
	if Quality.is_mobile():
		_touch_controls = load("res://scripts/ui/mobile_controls.gd").new()
		_touch_controls.mode = "hub"
		_touch_controls.visible = false
		add_child(_touch_controls)

	_build_station_labels()
	_build_training_dummy()
	_build_rack()
	_build_portals()

	MusicDirector.play("hub")   # tema tranquilo del salón (tools/generate_chill_soundtrack.gd)
	_voice = AudioStreamPlayer.new()
	_voice.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	add_child(_voice)

func _torch(p: Vector3, c: Color, energy: float, rng: float, shadow: bool) -> void:
	var l := OmniLight3D.new()
	l.position = p
	l.light_color = c
	l.light_energy = energy
	l.omni_range = rng
	l.omni_attenuation = 1.3
	Quality.tune_light(l, shadow)
	add_child(l)
	_torches.append(l)
	_torch_base.append(energy)

func _spot(p: Vector3, target: Vector3, c: Color, energy: float, angle: float) -> SpotLight3D:
	var s := SpotLight3D.new()
	s.light_color = c
	s.light_energy = energy
	s.spot_range = 7.0
	s.spot_angle = angle
	add_child(s)
	s.look_at_from_position(p, target, Vector3.UP if absf((target - p).normalized().y) < 0.99 else Vector3.FORWARD)
	return s

func _instance(path: String) -> Node3D:
	if not ResourceLoader.exists(path):
		push_warning("[DungeonHub] Falta " + path + " (tools/blender_salon_invocacion.py)")
		return null
	var ps := load(path) as PackedScene
	return ps.instantiate() as Node3D if ps else null

func _yaw_to(from: Vector3, to: Vector3) -> float:
	var d := to - from
	return atan2(d.x, d.z)

# ───────────────────────────── colisiones ─────────────────────────────

## Colisiones a mano (el .glb no trae): muros, columnas, estrado y muebles. Capa 1.
func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "Colisiones"
	add_child(body)
	var boxes := [   # [centro (x, z), tamaño (x, z)]
		[Vector2(8.3, -3.0), Vector2(0.6, 23.0)], [Vector2(-8.3, -3.0), Vector2(0.6, 23.0)],
		[Vector2(0.0, 8.0), Vector2(17.0, 1.2)], [Vector2(0.0, -14.3), Vector2(17.0, 0.6)],
		[Vector2(6.0, -1.0), Vector2(1.4, 1.7)], [Vector2(4.9, -2.55), Vector2(0.25, 1.7)],   # fragua, armero
		[Vector2(5.0, 4.4), Vector2(0.75, 1.2)], [Vector2(4.4, -6.4), Vector2(1.0, 1.6)],     # cofre, mesa
	]
	for b in boxes:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(b[1].x, 3.0, b[1].y)
		cs.shape = sh
		cs.position = Vector3(b[0].x, 1.5, b[0].y)
		body.add_child(cs)
	var cyls := [   # [centro (x, z), radio]
		[Vector2(-3.2, -11.4), 0.4], [Vector2(3.2, -11.4), 0.4], [Vector2(-3.6, -0.6), 0.32],
		[Vector2(4.5, -1.0), 0.38], [Vector2(5.8, -2.15), 0.3], [Vector2(4.7, 5.25), 0.28],
		[Vector2(-4.8, 5.2), 0.42], [Vector2(-4.4, -6.6), 0.42], [Vector2(5.0, -6.4), 0.25],
		[Vector2(-5.4, 6.9), 0.34], [Vector2(-5.0, 7.3), 0.28], [Vector2(MAGE_POS.x, MAGE_POS.z), 0.42],
	]
	for z in [5.0, 1.0, -3.0, -7.0, -11.0]:
		for sx in [-1.0, 1.0]:
			cyls.append([Vector2(sx * 6.2, z), 0.6])
	for i in 8:   # candelabros alrededor del círculo
		var a := TAU * i / 8.0 + TAU / 16.0
		cyls.append([Vector2(CIRCLE.x + 3.25 * cos(a), CIRCLE.z - 3.25 * sin(a)), 0.16])
	for c in cyls:
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = c[1]
		sh.height = 3.0
		cs.shape = sh
		cs.position = Vector3(c[0].x, 1.5, c[0].y)
		body.add_child(cs)

# ───────────────────────────── materiales del salón ─────────────────────────────

static var _tex_cache: Dictionary = {}

static func _tex(file: String) -> Texture2D:
	if not _tex_cache.has(file):
		var p := TEX_DIR + file
		_tex_cache[file] = load(p) if ResourceLoader.exists(p) else null
	return _tex_cache[file]

## Material del juego para un material del .glb, según su nombre (ver tools/blender_salon_invocacion.py).
static func salon_material(mat_name: String, src: Material) -> Material:
	var base := Color(0.5, 0.5, 0.5)
	if src is BaseMaterial3D:
		base = (src as BaseMaterial3D).albedo_color
	var n := mat_name.to_lower()
	var m := StandardMaterial3D.new()
	m.resource_name = mat_name
	m.vertex_color_use_as_albedo = true      # oclusión horneada en Blender
	m.roughness = 0.88
	if "glow" in n:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = false
		m.albedo_color = base
		m.emission_enabled = true
		m.emission = base
		m.emission_energy_multiplier = 2.5
		if "window" in n or "night" in n:
			m.albedo_color = base.darkened(0.2)
			m.emission_energy_multiplier = 1.2
		elif "flame" in n:
			# llama: aditiva y algo transparente
			m.albedo_color = Color(1.0, 0.42, 0.08, 0.85)
			m.emission = Color(1.0, 0.45, 0.1)
			m.emission_energy_multiplier = 4.0
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		return m
	var tex := ""
	var gain := 1.0
	if "brick" in n:
		tex = "brick"; gain = 1.5
	elif "floor" in n or "stone" in n:
		tex = "flagstone" if "floor" in n else "stone"; gain = 1.55
	elif "wood" in n:
		tex = "wood"; gain = 1.6
	elif "carpet" in n or "velvet" in n or "banner" in n or "robe" in n or "cape" in n or "leather" in n:
		m.normal_enabled = true
		m.normal_texture = _tex("hide_normal.png")
		m.normal_scale = 0.35
		m.uv1_scale = Vector3(2.5, 2.5, 1)
		m.roughness = 0.95
	elif "gold" in n or "trim" in n:
		m.metallic = 0.9
		m.roughness = 0.32
		m.metallic_specular = 0.7
		m.normal_enabled = true
		m.normal_texture = _tex("stone_normal.png")
		m.normal_scale = 0.15
	elif "iron" in n or "steel" in n:
		m.metallic = 0.85 if "steel" in n else 0.8
		m.roughness = 0.3 if "steel" in n else 0.5
	elif "fur" in n or "beard" in n:
		m.roughness = 1.0
		m.normal_enabled = true
		m.normal_texture = _tex("straw_normal.png")
		m.normal_scale = 0.5
		m.uv1_scale = Vector3(4, 4, 1)
	if tex != "":
		m.albedo_texture = _tex(tex + "_albedo.png")
		m.normal_enabled = true
		m.normal_texture = _tex(tex + "_normal.png")
		m.normal_scale = 0.9
		base = Color(minf(base.r * gain, 1.0), minf(base.g * gain, 1.0), minf(base.b * gain, 1.0))
	m.albedo_color = base
	return m

func _dress_salon(root: Node) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var src := mesh.surface_get_material(i)
			var nm := src.resource_name if src else ""
			var m := salon_material(nm, src)
			(mi as MeshInstance3D).set_surface_override_material(i, m)
			if nm == "salon_glow_rune":
				_rune_mat = m as StandardMaterial3D
			elif nm == "salon_glow_flame":
				_flame_mat = m as StandardMaterial3D
	if _rune_mat:
		_rune_mat.emission_energy_multiplier = 0.6

# ───────────────────────────── columna de luz y chispas (intro) ─────────────────────────────

const BEAM_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec4 color : source_color = vec4(0.45, 0.8, 1.0, 1.0);
uniform float intensity = 0.0;
void fragment() {
	float h = UV.y;
	float stripes = 0.55 + 0.45 * sin(UV.x * 37.7 + TIME * 3.0) * sin(UV.x * 12.6 - TIME * 1.7 + h * 6.0);
	float fade = smoothstep(0.0, 0.08, h) * (1.0 - smoothstep(0.35, 1.0, h));
	ALBEDO = color.rgb * 3.0;
	ALPHA = clamp(intensity * fade * stripes, 0.0, 1.0);
}
"""

func _build_beam() -> void:
	_beam = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.25
	cyl.bottom_radius = 1.25
	cyl.height = 7.0
	cyl.cap_top = false
	cyl.cap_bottom = false
	cyl.radial_segments = 48
	_beam.mesh = cyl
	var sh := Shader.new()
	sh.code = BEAM_SHADER
	_beam_mat = ShaderMaterial.new()
	_beam_mat.shader = sh
	_beam.material_override = _beam_mat
	_beam.position = CIRCLE + Vector3(0, 3.5, 0)
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.visible = false
	add_child(_beam)
	_sparks = _make_sparks(Color(0.5, 0.85, 1.0), 90, 2.4)
	_sparks.position = CIRCLE + Vector3(0, 0.05, 0)
	add_child(_sparks)

func _make_sparks(c: Color, amount: int, ring: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = 2.2
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_radius = ring
	p.emission_ring_inner_radius = ring * 0.15
	p.emission_ring_height = 0.02
	p.emission_ring_axis = Vector3.UP
	p.direction = Vector3.UP
	p.spread = 12.0
	p.gravity = Vector3(0, 0.6, 0)
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 1.1
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	var q := QuadMesh.new()
	q.size = Vector2(0.035, 0.035)
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	pm.albedo_color = c
	pm.vertex_color_use_as_albedo = true
	var dot := Gradient.new()
	dot.set_color(0, Color(1, 1, 1, 1))
	dot.set_color(1, Color(1, 1, 1, 0))
	var dt := GradientTexture2D.new()
	dt.gradient = dot
	dt.fill = GradientTexture2D.FILL_RADIAL
	dt.fill_from = Vector2(0.5, 0.5)
	dt.fill_to = Vector2(1.0, 0.5)
	dt.width = 32
	dt.height = 32
	pm.albedo_texture = dt
	q.material = pm
	p.mesh = q
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0))
	ramp.add_point(0.2, Color(1, 1, 1, 1))
	ramp.set_color(ramp.get_point_count() - 1, Color(1, 1, 1, 0))
	p.color_ramp = ramp
	p.emitting = false
	return p

# ───────────────────────────── estaciones ─────────────────────────────

func _build_station_labels() -> void:
	for id in STATIONS:
		var st: Dictionary = STATIONS[id]
		var l := Label3D.new()
		l.text = String(st["label"])
		l.font = Style.FONT
		l.font_size = 40
		l.pixel_size = 0.004
		l.outline_size = 10
		l.outline_modulate = Color(0.03, 0.01, 0.06)
		l.modulate = Color(1.0, 0.85, 0.5, 0.45)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = false
		l.position = (st["pos"] as Vector3) + Vector3(0, float(st["h"]), 0)
		if id == "mago":
			l.position = MAGE_POS + Vector3(0, float(st["h"]), 0)
		add_child(l)
		_station_labels[id] = l

## Muñeco de práctica junto a la entrada: la estación para repetir el tutorial.
func _build_training_dummy() -> void:
	var p: Vector3 = STATIONS["patio"]["pos"]
	var wood := salon_material("salon_wood", null) as StandardMaterial3D
	wood.vertex_color_use_as_albedo = false
	var root := Node3D.new()
	root.position = p
	add_child(root)
	var post := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.13
	cm.bottom_radius = 0.17
	cm.height = 1.5
	post.mesh = cm
	post.position.y = 0.75
	post.material_override = wood
	root.add_child(post)
	var arm := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.9, 0.12, 0.12)
	arm.mesh = bm
	arm.position.y = 1.1
	arm.material_override = wood
	root.add_child(arm)
	var head := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.17
	sm.height = 0.34
	head.mesh = sm
	head.position.y = 1.62
	var straw := StandardMaterial3D.new()
	straw.albedo_color = Color(0.78, 0.64, 0.28)
	straw.roughness = 1.0
	head.material_override = straw
	root.add_child(head)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 0.3
	sh.height = 1.8
	cs.shape = sh
	cs.position.y = 0.9
	body.add_child(cs)
	root.add_child(body)

## Las tres armas del yunque colgadas en el armero (modelos del juego); la equipada se ilumina.
func _build_rack() -> void:
	var files := {WeaponData.WeaponType.SPEAR_LANCE: ["res://assets/models/weapons/espalanza.glb", 1.9],
		WeaponData.WeaponType.DAGGERS: ["", 0.5],
		WeaponData.WeaponType.MACE: ["", 1.5],
		WeaponData.WeaponType.GREATSWORD: ["", 1.7],
		WeaponData.WeaponType.SWORD: ["", 1.1],
		WeaponData.WeaponType.BOW: ["", 1.3],
		WeaponData.WeaponType.KATANA: ["", 1.05]}
	var zs := {WeaponData.WeaponType.SPEAR_LANCE: -3.0, WeaponData.WeaponType.DAGGERS: -2.55, WeaponData.WeaponType.MACE: -2.1,
		WeaponData.WeaponType.GREATSWORD: -1.65, WeaponData.WeaponType.SWORD: -1.2, WeaponData.WeaponType.BOW: -0.75,
		WeaponData.WeaponType.KATANA: -0.3}
	for w in files:
		var f: Array = files[w]
		var holder := Node3D.new()
		holder.name = "Armero_%d" % w
		add_child(holder)
		holder.position = Vector3(4.76, FLOOR_Y + 1.05, float(zs[w]))
		var copies := 2 if w == WeaponData.WeaponType.DAGGERS else 1
		for k in copies:
			var m: Node3D
			match w:
				WeaponData.WeaponType.DAGGERS:
					m = DaggerModels.build(GameData.dagger_skin)
				WeaponData.WeaponType.MACE:
					m = MaceModels.build(GameData.mace_skin)
				WeaponData.WeaponType.GREATSWORD:
					m = GreatswordModels.build(GameData.greatsword_skin)
				WeaponData.WeaponType.SWORD:
					m = SwordModels.build(GameData.sword_skin)
				WeaponData.WeaponType.BOW:
					m = BowModels.build(GameData.bow_skin)
				WeaponData.WeaponType.KATANA:
					m = KatanaModels.build(0)
				_:
					m = _instance(String(f[0]))
			if m == null:
				continue
			holder.add_child(m)
			_fit_vertical(m, float(f[1]))
			if copies > 1:
				m.position.z += (k - 0.5) * 0.16
				m.rotation.x = (k - 0.5) * 0.25
		rack_weapons[w] = holder
	_rack_light = OmniLight3D.new()
	_rack_light.light_color = Color(1.0, 0.75, 0.35)
	_rack_light.light_energy = 0.0
	_rack_light.omni_range = 1.2
	add_child(_rack_light)
	refresh_rack()

## Escala un modelo para que su lado más largo mida `length`, de pie y centrado en el soporte.
func _fit_vertical(m: Node3D, length: float) -> void:
	var aabb := AABB()
	var first := true
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var b := (mi as MeshInstance3D).get_aabb()
		var xf := m.global_transform.affine_inverse() * (mi as MeshInstance3D).global_transform
		b = xf * b
		aabb = b if first else aabb.merge(b)
		first = false
	if first:
		return
	var axis := 1
	if aabb.size.x > aabb.size[axis]:
		axis = 0
	if aabb.size.z > aabb.size[axis]:
		axis = 2
	var s := length / maxf(aabb.size[axis], 0.001)
	m.scale = Vector3.ONE * s
	if axis == 0:
		m.rotation.z = PI / 2
	elif axis == 2:
		m.rotation.x = PI / 2
	m.position = -(m.basis * aabb.get_center())   # centrado en el soporte

func refresh_rack() -> void:
	for w in rack_weapons:
		var h: Node3D = rack_weapons[w]
		var on := int(w) == GameData.dungeon_weapon
		h.scale = Vector3.ONE * (1.08 if on else 1.0)
	if rack_weapons.has(GameData.dungeon_weapon):
		_rack_light.position = (rack_weapons[GameData.dungeon_weapon] as Node3D).position + Vector3(-0.35, 0.2, 0)
		_rack_light.light_energy = 1.6

# ───────────────────────────── portales del mago ─────────────────────────────

const PORTAL_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec4 color : source_color = vec4(1.0, 0.6, 0.2, 1.0);
uniform float intensity = 1.0;
void fragment() {
	vec2 p = (UV - vec2(0.5)) * vec2(2.0, 2.0);
	float r = length(p);
	float a = atan(p.y, p.x);
	float swirl = 0.5 + 0.5 * sin(a * 5.0 + r * 14.0 - TIME * 4.0);
	float ring = smoothstep(0.75, 0.95, r) * (1.0 - smoothstep(0.95, 1.0, r));
	float core = (1.0 - smoothstep(0.0, 0.95, r)) * (0.35 + 0.65 * swirl);
	ALBEDO = mix(color.rgb, vec3(1.0), ring * 0.6) * 2.5;
	ALPHA = clamp((core * 0.8 + ring * 1.5) * intensity, 0.0, 1.0);
}
"""

func _build_portals() -> void:
	var sh := Shader.new()
	sh.code = PORTAL_SHADER
	for i in mini(WorldDefs.ORDER.size(), PORTAL_SPOTS.size()):
		var world: String = WorldDefs.ORDER[i]
		var c: Color = PORTAL_COLORS.get(world, Color(0.6, 0.8, 1.0))
		var root := Node3D.new()
		root.name = "Portal_" + world
		root.position = PORTAL_SPOTS[i]
		add_child(root)
		var disc := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(1.7, 2.6)
		disc.mesh = q
		var mat := ShaderMaterial.new()
		mat.shader = sh
		mat.set_shader_parameter("color", c)
		disc.material_override = mat
		disc.position = Vector3(0, 1.35, 0)
		disc.rotation.y = PI / 2          # mira hacia el centro del salón (+X)
		disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(disc)
		var light := SpotLight3D.new()
		light.light_color = c
		light.light_energy = 0.0
		light.spot_range = 6.0
		light.spot_angle = 55.0
		root.add_child(light)
		light.look_at_from_position(root.position + Vector3(0.2, 2.8, 0), root.position + Vector3(2.5, 0, 0))
		var sp := _make_sparks(c, 40, 0.8)
		root.add_child(sp)
		var lab := Label3D.new()
		lab.text = String(WorldDefs.get_def(world)["name"]).to_upper()
		lab.font = Style.FONT
		lab.font_size = 40
		lab.pixel_size = 0.004
		lab.outline_size = 10
		lab.outline_modulate = Color(0.03, 0.01, 0.06)
		lab.modulate = c.lightened(0.3)
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab.position = Vector3(0, 3.0, 0)
		root.add_child(lab)
		root.scale = Vector3(0.01, 0.01, 0.01)
		root.visible = false
		portals.append({"world": world, "node": root, "light": light, "sparks": sp, "open": false})
	if portals_open:
		open_portals(true)

## El mago abre los portales (instant: sin animación, al volver al salón).
func open_portals(instant: bool = false) -> void:
	portals_open = true
	for i in portals.size():
		var p: Dictionary = portals[i]
		if p["open"]:
			continue
		p["open"] = true
		var root: Node3D = p["node"]
		root.visible = true
		(p["sparks"] as CPUParticles3D).emitting = true
		if instant:
			root.scale = Vector3.ONE
			(p["light"] as SpotLight3D).light_energy = 2.2
			continue
		var tw := create_tween().set_parallel(true)
		tw.tween_property(root, "scale", Vector3.ONE, 0.9).set_delay(0.6 + i * 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(p["light"], "light_energy", 2.2, 0.9).set_delay(0.6 + i * 0.5)
		get_tree().create_timer(0.6 + i * 0.5).timeout.connect(func(): AudioManager.play("orb_cast", -2.0, 0.8 + i * 0.15))
	if _rune_mat and not instant:
		_ramp_runes(2.6, 0.8)
	portals_opened.emit()

func _enter_portal(world: String) -> void:
	if state != "explore":
		return
	state = "leaving"
	player.locked = true
	player.stop()
	AudioManager.play("impact_magic", 0.0, 1.1)
	GameData.game_mode = "dungeon"
	GameData.world = world
	_flash.color = Color(PORTAL_COLORS.get(world, Color.WHITE), 0.0)
	var tw := create_tween()
	tw.tween_property(_flash, "color:a", 1.0, 0.45)
	tw.tween_callback(func(): SceneLoader.load_scene(CHARACTER_SELECT))

# ───────────────────────────── personajes ─────────────────────────────

func _king_look() -> CharacterLook:
	var l := CharacterLook.new()
	l.char_name = "Rey"
	l.hair_style = "rapado"
	l.colors["skin"] = Color(0.86, 0.64, 0.52)
	l.colors["hair"] = Color(0.34, 0.22, 0.13)
	l.colors["eyes"] = Color(0.32, 0.22, 0.12)
	return l

func _mage_look() -> CharacterLook:
	var l := CharacterLook.new()
	l.char_name = "Mago"
	l.hair_style = "rapado"
	l.colors["skin"] = Color(0.93, 0.8, 0.72)
	l.colors["hair"] = Color(0.82, 0.8, 0.76)
	l.colors["eyes"] = Color(0.3, 0.55, 0.85)
	return l

func _spawn_npc(path: String, pos: Vector3, yaw: float, look: CharacterLook) -> Node3D:
	var n := _instance(path)
	if n == null:
		n = Node3D.new()
	add_child(n)
	n.position = pos
	n.rotation.y = yaw
	CharacterLookApplier.apply_to(n, look)
	# ropa y accesorios: materiales del juego según su nombre en el .glb
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		if String(mi.name).begins_with(CharacterLookApplier.BODY_NODE):
			continue
		var mesh := (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var src := mesh.surface_get_material(i)
			var m := salon_material(src.resource_name if src else "", src) as StandardMaterial3D
			m.vertex_color_use_as_albedo = false
			(mi as MeshInstance3D).set_surface_override_material(i, m)
	var ap := _anim(n)
	if ap:
		for a in ap.get_animation_list():
			var an := ap.get_animation(a)
			if an and not ("sorpresa" in a or "reverencia" in a):
				an.loop_mode = Animation.LOOP_LINEAR
	return n

func _anim(n: Node) -> AnimationPlayer:
	var found := n.find_children("*", "AnimationPlayer", true, false)
	return found[0] as AnimationPlayer if not found.is_empty() else null

## Reproduce un clip del rey o del mago (con mezcla); si es de una vez, vuelve luego a `then`.
func _play(who: Node3D, clip: String, then: String = "", blend: float = 0.35) -> void:
	var ap := _anim(who) if who else null
	if ap == null or not ap.has_animation(clip):
		return
	ap.play(clip, blend)
	if then != "":
		var clip_len := ap.get_animation(clip).length
		get_tree().create_timer(maxf(0.1, clip_len - blend)).timeout.connect(func():
			if is_instance_valid(ap) and ap.current_animation == clip:
				ap.play(then, blend))

# ───────────────────────────── cinemática ─────────────────────────────

func start_intro() -> void:
	state = "intro"
	intro_time = 0.0
	var vl := []
	for l in LINES:
		vl.append([l[1], l[2]])
	vl.append(["mago", MAGE_OPEN_LINE])
	vl.append(["mago", MAGE_AGAIN_LINE])
	Murmur.prepare(vl)
	_skip_armed = false
	_hud.visible = false
	for b in _letterbox:
		b.visible = true
		b.modulate.a = 1.0
	player.visible = false
	player.locked = true
	_play(king, "rey_invocar", "", 0.0)
	_play(mage, "mago_conjurar", "", 0.0)
	_sparks.emitting = true
	_set_cam(Vector3(0.0, 5.2, 7.3), Vector3(0.0, 1.6, -5.0), 52.0)   # junto al portón (muro en z = 8)
	_fade.color.a = 1.0
	var t := create_tween()
	t.tween_property(_fade, "color:a", 0.0, 1.6)

	_timeline.clear()
	# cámara: una sola toma que viaja por el salón (sin cortes) y acaba detrás del héroe
	_cam_tween = create_tween()
	_cam_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_cam_move(_cam_tween, Vector3(0.0, 4.2, 5.4), Vector3(0.0, 1.8, -7.0), 48.0, 4.6)       # avanza hacia el trono y el rey
	_cam_move(_cam_tween, Vector3(-1.0, 1.75, 1.7), Vector3(-3.0, 1.45, -0.4), 40.0, 4.2)    # gira hacia el mago
	_cam_move(_cam_tween, Vector3(2.3, 1.0, 1.6), Vector3(0.0, 0.9, -1.5), 46.0, 2.4)       # baja al círculo
	_cam_move(_cam_tween, Vector3(1.6, 1.5, 2.0), Vector3(0.0, 1.15, -1.5), 44.0, 1.6)      # recibe al héroe
	_cam_move(_cam_tween, Vector3(0.9, 1.75, 0.6), Vector3(0.2, 1.6, -8.5), 38.0, 2.6)      # tras el héroe, hacia el rey
	_cam_move(_cam_tween, Vector3(-0.4, 1.7, 1.2), Vector3(-2.2, 1.45, -1.0), 40.0, 3.2)    # el mago se excusa
	_cam_move(_cam_tween, Vector3(0.4, 1.9, 0.9), Vector3(0.3, 1.9, -8.8), 34.0, 3.2)       # el rey da la bienvenida
	_cam_move(_cam_tween, CIRCLE + FOLLOW_OFFSET, CIRCLE + FOLLOW_LOOK, 50.0, 2.4)            # detrás del héroe
	_cam_tween.finished.connect(_end_intro)

	_at(0.3, func(): _ramp_runes(1.4, 4.0))
	for line in LINES:
		var ln: Array = line
		_at(float(ln[0]), func(): _say(String(ln[1]), String(ln[2])))
	_at(1.0, func(): _play(king, "rey_invocar"))
	_at(5.0, func():
		_ramp_runes(3.2, 4.0)
		_play(mage, "mago_conjurar"))
	_at(8.6, func():
		_beam.visible = true
		var tw := create_tween()
		tw.tween_method(func(v: float): _beam_mat.set_shader_parameter("intensity", v), 0.0, 0.7, 1.0))
	_at(FLASH_AT, _flash_and_summon)
	_at(12.0, func(): _play(king, "rey_sorpresa", "rey_idle", 0.15))
	_at(12.5, func(): _play(mage, "mago_sorpresa", "mago_idle", 0.15))
	_at(15.2, func(): _play(mage, "mago_reverencia", "mago_idle"))
	_at(18.4, func(): _play(king, "rey_hablar", "", 0.4))
	_at(INTRO_LENGTH - 1.2, func(): _play(king, "rey_idle", "", 0.6))

func _cam_move(t: Tween, pos: Vector3, target: Vector3, fov: float, dur: float) -> void:
	t.tween_property(self, "_cam_pos", pos, dur)
	t.parallel().tween_property(self, "_cam_target", target, dur)
	t.parallel().tween_property(self, "_cam_fov", fov, dur)

func _set_cam(pos: Vector3, target: Vector3, fov: float) -> void:
	_cam_pos = pos
	_cam_target = target
	_cam_fov = fov

func _at(t: float, fn: Callable) -> void:
	_timeline.append({"t": t, "fn": fn, "done": false})

func _ramp_runes(energy: float, dur: float) -> void:
	var tw := create_tween().set_parallel(true)
	if _rune_mat:
		tw.tween_property(_rune_mat, "emission_energy_multiplier", energy, dur)
	tw.tween_property(_circle_light, "light_energy", energy * 1.1, dur)

func _flash_and_summon() -> void:
	AudioManager.play("impact_magic", 2.0, 0.8)
	AudioManager.play("slam_boom", -2.0, 0.9)
	_shake = 0.5
	_flash.color = Color(0.85, 0.95, 1.0, 1.0)
	var tw := create_tween()
	tw.tween_property(_flash, "color:a", 0.0, 1.1).set_ease(Tween.EASE_OUT)
	var tl := create_tween()
	_circle_light.light_energy = 12.0
	tl.tween_property(_circle_light, "light_energy", 1.6, 1.6)
	if _rune_mat:
		_rune_mat.emission_energy_multiplier = 8.0
		tl.parallel().tween_property(_rune_mat, "emission_energy_multiplier", 1.6, 2.5)
	var tp := create_tween()
	tp.tween_method(func(v: float): _beam_mat.set_shader_parameter("intensity", v), 1.4, 0.0, 1.8)
	tp.tween_callback(func(): _beam.visible = false)
	_appear_player(1.3)

func _appear_player(duration: float) -> void:
	player.visible = true
	SpawnDissolve.play(player, self, duration, Color(0.45, 0.85, 1.0), PLAYER_HEIGHT)

func _end_intro() -> void:
	if state != "intro":
		return
	set_intro_seen(true)
	_hide_subtitle()
	intro_finished.emit()
	begin_explore(false)

## Salta la cinemática: deja todo como al final y la cámara se va detrás del héroe.
func skip_intro() -> void:
	if state != "intro":
		return
	for e in _timeline:
		e["done"] = true
	if _cam_tween:
		_cam_tween.kill()
	_voice.stop()
	_hide_subtitle()
	_beam.visible = false
	_fade.color.a = 0.0
	_flash.color.a = 0.0
	if not player.visible:
		_appear_player(0.8)
	_ramp_runes(1.6, 0.6)
	_play(king, "rey_idle")
	_play(mage, "mago_idle")
	_cam_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_cam_move(_cam_tween, CIRCLE + FOLLOW_OFFSET, CIRCLE + FOLLOW_LOOK, 50.0, 1.2)
	_cam_tween.finished.connect(_end_intro)

# ───────────────────────────── explorar el salón ─────────────────────────────

func begin_explore(instant: bool) -> void:
	state = "explore"
	_skip_label.visible = false
	player.visible = true
	player.locked = false
	_sparks.emitting = true
	_sparks.amount = 40
	if _rune_mat:
		_rune_mat.emission_energy_multiplier = 1.6
	_circle_light.light_energy = 1.6
	_cam_fov = 50.0
	if instant:
		_set_cam(player.global_position + FOLLOW_OFFSET, player.global_position + FOLLOW_LOOK, 50.0)
		_fade.color.a = 1.0
		create_tween().tween_property(_fade, "color:a", 0.0, 0.8)
	for b in _letterbox:
		var tb := create_tween()
		tb.tween_property(b, "modulate:a", 0.0, 0.6)
		tb.tween_callback(func(): b.visible = false)
	_hud.visible = true
	_hud.modulate.a = 0.0
	create_tween().tween_property(_hud, "modulate:a", 1.0, 0.6)
	if not instant:
		_show_hint("Explora el salón: habla con el mago para abrir los portales de las mazmorras.", 6.0)
	explore_started.emit()

## Estación más cercana al alcance del héroe ("" si ninguna).
func station_at(p: Vector3) -> String:
	var best := ""
	var best_d := INF
	for id in STATIONS:
		var st: Dictionary = STATIONS[id]
		var d := Vector2(p.x - (st["pos"] as Vector3).x, p.z - (st["pos"] as Vector3).z).length()
		if d < float(st["r"]) and d < best_d:
			best = id
			best_d = d
	return best

## Usa una estación (desde el aviso, la tecla E o al llegar con clic/toque).
func use_station(id: String) -> void:
	if state != "explore" or not STATIONS.has(id):
		return
	player.stop()
	var st: Dictionary = STATIONS[id]
	player.face(st["pos"] if id != "mago" else MAGE_POS)
	station_used.emit(id)
	match id:
		"mago":
			_talk_to_mage()
		"patio":
			start_tutorial()
		"bola":
			AudioManager.play("orb_cast", -4.0, 1.2)
			state = "leaving"
			get_tree().change_scene_to_file(LOBBY)
		_:
			_open_station_panel(id)

## Repetir el tutorial: funde a negro y vuelve al patio (se puede saltar desde allí).
func start_tutorial(change: bool = true) -> void:
	if state != "explore":
		return
	state = "leaving"
	player.locked = true
	player.stop()
	AudioManager.play("impact_magic", 0.0, 1.1)
	_flash.color = Color(0.45, 0.8, 1.0, 0.0)
	var tw := create_tween()
	tw.tween_property(_flash, "color:a", 1.0, 0.45)
	if change:
		tw.tween_callback(func(): SceneLoader.load_scene(TUTORIAL))

func _talk_to_mage() -> void:
	_play(mage, "mago_reverencia" if portals_open else "mago_conjurar", "mago_idle" if portals_open else "", 0.3)
	if portals_open:
		_say("mago", MAGE_AGAIN_LINE, 2.5)
		return
	_say("mago", MAGE_OPEN_LINE, 2.5)
	open_portals(false)
	get_tree().create_timer(2.8).timeout.connect(func(): _play(mage, "mago_idle", "", 0.5))

func _open_station_panel(id: String) -> void:
	state = "panel"
	player.locked = true
	var st: Dictionary = STATIONS[id]
	if st["cam"] != null:
		var base: Vector3 = st["pos"]
		_cam_override = [base + (st["cam"][0] as Vector3), base + (st["cam"][1] as Vector3)]
	_prompt.visible = false
	if id == "cofre":
		_swing("cofre_tapa", Vector3(0, 0, -1.1), 0.5)
	panels.open(id)

## Lo llama HubPanels al cerrar un panel.
func on_panel_closed(id: String) -> void:
	if state != "panel":
		return
	state = "explore"
	player.locked = false
	_cam_override = null
	if id == "cofre":
		_swing("cofre_tapa", Vector3.ZERO, 0.4)
	refresh_rack()

## Supervivencia: se abre la puerta de la arena y se entra con el personaje elegido.
func start_survival(char_index: int) -> void:
	state = "leaving"
	GameData.game_mode = "survival"
	GameData.selected_index = char_index
	_swing("puerta_arena_izq", Vector3(0, 1.5, 0), 0.9)
	_swing("puerta_arena_der", Vector3(0, -1.5, 0), 0.9)
	AudioManager.play("slam_boom", -8.0, 0.6)
	var tw := create_tween()
	tw.tween_interval(0.7)
	tw.tween_property(_fade, "color:a", 1.0, 0.5)
	tw.tween_callback(func(): SceneLoader.load_scene(SURVIVAL_SCENE))

## Esc mientras se explora: funde a negro y vuelve a la pantalla de título (change = false en tests).
func back_to_title(change: bool = true) -> void:
	if state != "explore":
		return
	state = "leaving"
	player.locked = true
	player.stop()
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.5)
	if change:
		tw.tween_callback(func(): get_tree().change_scene_to_file(TITLE))

## Salir del juego: se abre el portón y se funde a negro.
func quit_game() -> void:
	state = "leaving"
	_swing("porton_izq", Vector3(0, -1.4, 0), 1.2)
	_swing("porton_der", Vector3(0, 1.4, 0), 1.2)
	var tw := create_tween()
	tw.tween_interval(0.8)
	tw.tween_property(_fade, "color:a", 1.0, 0.6)
	tw.tween_callback(func(): get_tree().quit())

func _swing(node_name: String, rot: Vector3, dur: float) -> void:
	var n: Node3D = _movers.get(node_name)
	if n == null:
		return
	create_tween().tween_property(n, "rotation", rot, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

# ───────────────────────────── bucle ─────────────────────────────

func _process(delta: float) -> void:
	_time += delta
	if _touch_controls:
		_touch_controls.visible = state == "explore"
	if state == "intro":
		intro_time += delta
		for e in _timeline:
			if not e["done"] and intro_time >= float(e["t"]):
				e["done"] = true
				(e["fn"] as Callable).call()
	elif state == "explore":
		_update_explore()
	# antorchas y velas parpadean
	for i in _torches.size():
		var f := sin(_time * 9.0 + i * 1.7) * 0.07 + sin(_time * 23.0 + i * 3.1) * 0.05
		_torches[i].light_energy = _torch_base[i] * (1.0 + f)
	if _flame_mat:
		_flame_mat.emission_energy_multiplier = 4.0 + sin(_time * 11.0) * 0.5
	if state != "intro" and _rune_mat:
		_rune_mat.emission_energy_multiplier = (2.2 if portals_open else 1.6) + sin(_time * 1.3) * 0.35
	if _sub_hide_at > 0.0 and _time > _sub_hide_at:
		_sub_hide_at = -1.0
		_hide_subtitle()
	_update_camera(delta)

func _update_explore() -> void:
	if VirtualInput.just_pressed_interact:
		VirtualInput.just_pressed_interact = false
		if near_station != "":
			use_station(near_station)
			return
	var here := station_at(player.global_position)
	if here != near_station:
		near_station = here
		_prompt.visible = here != ""
		if here != "":
			_prompt.text = "  E   %s  " % String(STATIONS[here]["prompt"])
	for id in _station_labels:
		var l: Label3D = _station_labels[id]
		l.modulate.a = lerpf(l.modulate.a, 1.0 if id == near_station else 0.45, 0.15)
	# cruzar un portal abierto
	for p in portals:
		if p["open"]:
			var n: Node3D = p["node"]
			var d := Vector2(player.global_position.x - n.position.x, player.global_position.z - n.position.z)
			if d.length() < PORTAL_ENTER_R:
				_enter_portal(String(p["world"]))
				return

func _update_camera(delta: float) -> void:
	if state != "intro" and player:
		var want_pos: Vector3
		var want_look: Vector3
		if _cam_override != null:
			want_pos = _cam_override[0]
			want_look = _cam_override[1]
		elif NEAR_CAMS.has(near_station) and state == "explore":
			var nc: Array = NEAR_CAMS[near_station]
			want_pos = player.global_position + (nc[0] as Vector3)
			want_look = nc[1]
		else:
			var pp := player.global_position
			want_pos = pp + FOLLOW_OFFSET
			want_look = pp + FOLLOW_LOOK
			# que no se salga por el portón ni por los muros
			if want_pos.z > 7.4:
				want_pos.y += (want_pos.z - 7.4) * 0.8
				want_pos.z = 7.4
			want_pos.x = clampf(want_pos.x, -7.2, 7.2)
		var k := minf(1.0, delta * 3.0)
		_cam_pos = _cam_pos.lerp(want_pos, k)
		_cam_target = _cam_target.lerp(want_look, k)
		_cam_fov = lerpf(_cam_fov, 50.0, k)
	_shake = maxf(0.0, _shake - delta * 0.9)
	var shake := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * _shake * 0.06
	camera.position = _cam_pos + shake
	camera.fov = _cam_fov
	if not camera.position.is_equal_approx(_cam_target):
		camera.look_at(_cam_target, Vector3.UP)

func _unhandled_input(event: InputEvent) -> void:
	if state == "intro":
		var pressed: bool = (event is InputEventKey and event.pressed and not event.echo) \
			or (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed) \
			or (event is InputEventJoypadButton and event.pressed)
		if pressed and intro_time > 0.4:
			if _skip_armed:
				skip_intro()
			else:
				_skip_armed = true
				_skip_label.text = "Pulsa otra vez para saltar"
				_skip_label.modulate.a = 1.0
			get_viewport().set_input_as_handled()
	elif state == "explore":
		var use: bool = (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E) \
			or event.is_action_pressed("ui_accept") or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_A)
		if use and near_station != "":
			use_station(near_station)
			get_viewport().set_input_as_handled()
			return
		# clic / toque en el suelo: ir andando allí (y usar la estación si se tocó una)
		var click_pos := Vector2(-1, -1)
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			click_pos = event.position
		elif event is InputEventScreenTouch and event.pressed:
			click_pos = event.position
		if click_pos.x >= 0 and not VirtualInput.touch_ui_active:   # con controles táctiles, el joystick sustituye al toque-para-ir
			var hit: Variant = _floor_point(click_pos)
			if hit != null:
				var target: Vector3 = hit
				var st := station_at(target)
				var portal_world := _portal_at(target)
				if portal_world != "":
					player.move_to(target)
				elif st != "":
					player.move_to(target, func(): if station_at(player.global_position) == st: use_station(st))
				else:
					player.move_to(target)
			get_viewport().set_input_as_handled()
	elif state == "explore" and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		back_to_title()
	elif state == "panel" and event.is_action_pressed("ui_cancel"):
		panels.close()
		get_viewport().set_input_as_handled()

func _floor_point(screen: Vector2) -> Variant:
	var from := camera.project_ray_origin(screen)
	var dir := camera.project_ray_normal(screen)
	if absf(dir.y) < 0.001:
		return null
	var t := (FLOOR_Y - from.y) / dir.y
	if t <= 0.0:
		return null
	return from + dir * t

func _portal_at(p: Vector3) -> String:
	for q in portals:
		if q["open"] and Vector2(p.x - (q["node"] as Node3D).position.x, p.z - (q["node"] as Node3D).position.z).length() < 1.0:
			return String(q["world"])
	return ""

# ───────────────────────────── subtítulos y voces ─────────────────────────────

## Muestra una línea con su voz; con `linger` >= 0 se oculta sola tras escribirse (fuera de la intro).
func _say(who: String, text: String, linger: float = -1.0) -> void:
	var sp: Array = SPEAKERS[who]
	_sub_name.text = String(sp[0])
	_sub_name.add_theme_color_override("font_color", sp[1])
	_sub_text.text = text
	_sub_text.visible_ratio = 0.0
	_sub_panel.visible = true
	_sub_panel.modulate.a = 1.0
	var dur := text.length() * 0.04
	var t := create_tween()
	t.tween_property(_sub_text, "visible_ratio", 1.0, dur)
	_sub_hide_at = _time + dur + linger if linger >= 0.0 else -1.0
	var wav := Murmur.cached(text, who)
	if wav == null and state != "intro":
		wav = Murmur.make(text, who)
	if wav:
		_voice.stream = wav
		_voice.volume_db = -4.0
		_voice.play()

func _hide_subtitle() -> void:
	if _sub_panel and _sub_panel.visible:
		var t := create_tween()
		t.tween_property(_sub_panel, "modulate:a", 0.0, 0.3)
		t.tween_callback(func(): _sub_panel.visible = false)

func _show_hint(text: String, secs: float) -> void:
	_hint.text = text
	_hint.modulate.a = 1.0
	var t := create_tween()
	t.tween_interval(secs)
	t.tween_property(_hint, "modulate:a", 0.0, 1.0)

# ───────────────────────────── interfaz ─────────────────────────────

func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = Style.get_theme()
	ui.add_child(root)

	# bandas de cine durante la intro
	for top in [true, false]:
		var b := ColorRect.new()
		b.color = Color.BLACK
		b.set_anchors_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
		b.custom_minimum_size = Vector2(0, 64)
		if not top:
			b.offset_top = -64
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.visible = false
		root.add_child(b)
		_letterbox.append(b)

	_build_hud(root)

	panels = HubPanelsScript.new()
	panels.hub = self
	panels.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(panels)

	# subtítulos
	_sub_panel = PanelContainer.new()
	_sub_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_sub_panel.offset_top = -150
	_sub_panel.offset_bottom = -78
	_sub_panel.offset_left = -430
	_sub_panel.offset_right = 430
	_sub_panel.add_theme_stylebox_override("panel", Style.panel_style(Color(0.02, 0.01, 0.04, 0.78), Color(0.3, 0.2, 0.42, 0.6), 4, 14))
	_sub_panel.visible = false
	_sub_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_sub_panel)
	var sb := VBoxContainer.new()
	sb.add_theme_constant_override("separation", 6)
	_sub_panel.add_child(sb)
	_sub_name = Label.new()
	_sub_name.add_theme_font_size_override("font_size", 13)
	sb.add_child(_sub_name)
	_sub_text = Label.new()
	_sub_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub_text.add_theme_font_size_override("font_size", 17)
	_sub_text.add_theme_color_override("font_color", Style.TEXT)
	sb.add_child(_sub_text)

	_skip_label = Label.new()
	_skip_label.text = "Pulsa cualquier tecla para saltar"
	_skip_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_skip_label.offset_left = -380
	_skip_label.offset_top = -50
	_skip_label.offset_right = -20
	_skip_label.offset_bottom = -26
	_skip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_skip_label.add_theme_font_size_override("font_size", 11)
	_skip_label.add_theme_color_override("font_color", Style.TEXT_DIM)
	_skip_label.modulate.a = 0.7
	root.add_child(_skip_label)

	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(0.85, 0.95, 1.0, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_flash)
	_fade = ColorRect.new()
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_fade)

func _build_hud(root: Control) -> void:
	_hud = Control.new()
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.visible = false
	root.add_child(_hud)
	var title := Label.new()
	title.text = "RUMBANG"
	Style.style_title(title, 26)
	title.position = Vector2(28, 20)
	_hud.add_child(title)
	var sub := Label.new()
	sub.text = "Salón de la Invocación"
	sub.position = Vector2(30, 60)
	sub.add_theme_font_size_override("font_size", 11)
	sub.add_theme_color_override("font_color", Style.TEXT_DIM)
	_hud.add_child(sub)
	var keys := Label.new()
	keys.text = "WASD / stick: andar   Shift: correr   E: usar   Clic o toque: ir allí   Esc: título"
	keys.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	keys.offset_left = 28
	keys.offset_top = -40
	keys.offset_right = 900
	keys.offset_bottom = -18
	keys.add_theme_font_size_override("font_size", 10)
	keys.add_theme_color_override("font_color", Style.TEXT_DIM)
	keys.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(keys)
	# aviso de la estación cercana: también es un botón (ratón y táctil)
	_prompt = Style.make_button("  E  Usar  ", Style.ACCENT, Vector2(0, 46))
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.offset_left = -260
	_prompt.offset_right = 260
	_prompt.offset_top = -120
	_prompt.offset_bottom = -74
	_prompt.focus_mode = Control.FOCUS_NONE
	_prompt.visible = false
	_prompt.pressed.connect(func(): if near_station != "": use_station(near_station))
	_hud.add_child(_prompt)
	_hint = Label.new()
	_hint.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_hint.offset_left = -420
	_hint.offset_right = 420
	_hint.offset_top = 24
	_hint.offset_bottom = 60
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_font_size_override("font_size", 13)
	_hint.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	_hint.modulate.a = 0.0
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_hint)
