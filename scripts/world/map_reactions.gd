class_name MapReactions
extends Node

## El mapa responde al jugador local: cruzar una sala deja rastro durante un par de segundos.
##  - Hierba y hongos: los shaders leen dos uniformes globales, world_actor_pos (dónde está el jugador: la hierba
##    se aparta, los hongos brillan más) y world_pulse (la onda de un golpe o una esquiva: un anillo que crece).
##  - Agua de las Cloacas: cada zancada deja un anillo en sewer_water.gdshader (uniforme ripples), salpica y suena.
##  - Fuego: un tajo o una esquiva cerca hace temblar las luces (ProceduralMap.gust) y suelta brasas.
##  - Hongos: golpear junto a un grupo suelta una nube de esporas del color del nivel.
##  - Hierba: cruzarla deprisa suena.
## Partículas: CPUParticles3D de un solo disparo, reutilizadas. Son ráfagas de 8 a 16 partículas: ahí un sistema
## de GPU cuesta más que lo que ahorra (cada uno tiene coste fijo y compila su shader la primera vez).
## Uso: MapReactions.new() → add_child → setup(mapa, jugador). Lo crea GameStartFacade.

const PULSE_TIME := 0.55              ## s que tarda la onda en cruzar PULSE_RADIUS
const PULSE_RADIUS := 5.0
const HIT_REACH := 1.6                ## m por delante del jugador donde cae la onda de un ataque
const RIPPLES := 6                    ## = RIPPLES de sewer_water.gdshader
const RIPPLE_LIFE := 1.6              ## = RIPPLE_LIFE del shader
const STRIDE := 1.1                   ## m andados en el agua entre dos anillos
const RUSTLE_GAP := 0.32              ## s entre dos roces de hierba
const RUSTLE_SPEED := 1.5             ## m/s mínimos para que suene
const GRASS_CELL := 1.0
const SPORE_REACH := 2.8              ## m del golpe a los que un grupo de hongos reacciona
const SPORE_COOLDOWN := 1.4           ## s hasta que el mismo grupo vuelve a soltar esporas
const FIRE_REACH := 3.6
const BURST_POOL := 6

## Ráfagas de partículas: cantidad, vida, dirección, apertura, velocidad (mín, máx), gravedad, tamaño (mín, máx)
const BURSTS := {
	"splash": {"amount": 10, "life": 0.5, "dir": Vector3.UP, "spread": 38.0, "vel": Vector2(1.8, 3.6),
		"gravity": Vector3(0, -9.0, 0), "size": Vector2(0.05, 0.11), "glow": 0.0},
	"spore": {"amount": 16, "life": 1.7, "dir": Vector3.UP, "spread": 75.0, "vel": Vector2(0.4, 1.5),
		"gravity": Vector3(0, 0.25, 0), "size": Vector2(0.04, 0.09), "glow": 2.5},
	"ember": {"amount": 12, "life": 0.9, "dir": Vector3.UP, "spread": 55.0, "vel": Vector2(1.4, 3.4),
		"gravity": Vector3(0, -1.5, 0), "size": Vector2(0.03, 0.06), "glow": 4.0},
}
const WATER_TINT := Color(0.42, 0.5, 0.3)
const EMBER_TINT := Color(1.0, 0.55, 0.15)

var _map: Node3D
var _player: Node3D
var _last_pos := Vector3.INF
var _was_dodging := false
var _was_in_water := false
var _stride := 0.0
var _rustle_cd := 0.0
var _pulse_t := -1.0
var _pulse_pos := Vector3.ZERO
var _pulse_strength := 0.0
var _ripples: Array[Vector4] = []
var _ripple_i := 0
var _ripples_live := false
var _grass_cells: Dictionary = {}     # Vector2i -> true
var _grass_count := -1
var _spore_cd: Dictionary = {}        # Vector3 (grupo de hongos) -> s en que vuelve a reaccionar
var _bursts: Array[CPUParticles3D] = []
var _burst_i := 0
## Lo último que pasó, para las pruebas: "pulse", "ripple", "spore", "ember", "rustle" -> veces
var counts: Dictionary = {}
## Lo que se ha mandado a los uniformes globales (el servidor de render sin ventana no deja leerlos de vuelta)
var pulse_now := Vector4.ZERO
var actor_now := Vector3(0.0, -1000.0, 0.0)

func setup(map: Node3D, player: Node3D) -> void:
	_map = map
	if _player != player:
		if _player and is_instance_valid(_player) and _player.has_signal("weapon_attacked") \
				and _player.is_connected("weapon_attacked", _on_attack):
			_player.disconnect("weapon_attacked", _on_attack)
		_player = player
		if player and player.has_signal("weapon_attacked"):
			player.connect("weapon_attacked", _on_attack)
	_ripples.resize(RIPPLES)
	_ripples.fill(Vector4.ZERO)
	_grass_count = -1
	_spore_cd.clear()
	_last_pos = Vector3.INF
	_clear_pulse()

func _exit_tree() -> void:
	# Los uniformes globales sobreviven a la escena: que la siguiente no herede una onda ni un jugador fantasma
	_clear_pulse()
	RenderingServer.global_shader_parameter_set("world_actor_pos", Vector3(0.0, -1000.0, 0.0))

func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player) or _map == null or not is_instance_valid(_map):
		return
	var pos := _player.global_position
	RenderingServer.global_shader_parameter_set("world_actor_pos", pos)
	actor_now = pos
	var moved := 0.0 if _last_pos == Vector3.INF else Vector2(pos.x - _last_pos.x, pos.z - _last_pos.z).length()
	_last_pos = pos
	var speed := moved / maxf(delta, 0.0001)
	_rustle_cd -= delta
	_tick_pulse(delta)
	_tick_dodge(pos)
	_tick_water(pos, moved, delta)
	if speed >= RUSTLE_SPEED and _rustle_cd <= 0.0 and in_grass(pos):
		_rustle_cd = RUSTLE_GAP
		_count("rustle")
		AudioManager.play_at("grass_rustle", pos, -13.0, randf_range(0.9, 1.15))

func _count(what: String) -> void:
	counts[what] = int(counts.get(what, 0)) + 1

# ───────────────────────────── Onda de golpe ─────────────────────────────

## Lanza la onda (hierba tumbada, hongos sacudidos) desde `at`. Una a la vez: manda la última.
func pulse(at: Vector3, strength: float = 1.0) -> void:
	_pulse_t = 0.0
	_pulse_pos = at
	_pulse_strength = strength
	_count("pulse")

func _tick_pulse(delta: float) -> void:
	if _pulse_t < 0.0:
		return
	_pulse_t += delta
	var k := _pulse_t / PULSE_TIME
	if k >= 1.0:
		_clear_pulse()
		return
	pulse_now = Vector4(_pulse_pos.x, _pulse_pos.z, k * PULSE_RADIUS, _pulse_strength * (1.0 - k))
	RenderingServer.global_shader_parameter_set("world_pulse", pulse_now)

func _clear_pulse() -> void:
	_pulse_t = -1.0
	pulse_now = Vector4.ZERO
	RenderingServer.global_shader_parameter_set("world_pulse", Vector4.ZERO)

func _on_attack(_weapon_type = null) -> void:
	if _player == null or not is_instance_valid(_player) or _map == null or not is_instance_valid(_map):
		return
	var mesh = _player.get("mesh")
	var fwd: Vector3 = -(mesh as Node3D).global_transform.basis.z if mesh is Node3D else -_player.global_transform.basis.z
	fwd.y = 0.0
	var hit := _player.global_position + fwd.normalized() * HIT_REACH
	pulse(hit, 1.0)
	disturb(hit, 1.0)

func _tick_dodge(pos: Vector3) -> void:
	var mc = _player.get("movement_controller")
	var dodging: bool = mc != null and mc.has_method("is_dodging") and mc.is_dodging()
	if dodging and not _was_dodging:
		pulse(pos, 0.6)
		disturb(pos, 0.6)
		if _map.has_method("is_water") and _map.is_water(pos):
			ripple(pos, 1.0)
			burst("splash", pos + Vector3(0.0, 0.1, 0.0), WATER_TINT)
	_was_dodging = dodging

## Algo se ha movido con fuerza en `at` (0..1): tiemblan las llamas cercanas y los hongos sueltan esporas.
func disturb(at: Vector3, strength: float) -> void:
	if _map.has_method("gust"):
		_map.gust(at, 5.5 * strength + 1.5, 0.6 * strength)
	if not ("ambient_points" in _map):
		return
	var points: Dictionary = _map.ambient_points
	var now := Time.get_ticks_msec() / 1000.0
	var puffs := 0
	for kind in ["mush_big", "mush"]:
		if not points.has(kind):
			continue
		for pt in (points[kind] as PackedVector3Array):
			var world: Vector3 = _map.to_global(pt)
			if puffs >= 2 or world.distance_squared_to(at) > SPORE_REACH * SPORE_REACH or now < float(_spore_cd.get(pt, 0.0)):
				continue
			_spore_cd[pt] = now + SPORE_COOLDOWN
			puffs += 1
			_count("spore")
			var glow: Color = _map.palette()["crystal"] if _map.has_method("palette") else Color(0.45, 1.0, 0.75)
			burst("spore", world + Vector3(0.0, 0.5 if kind == "mush" else 1.1, 0.0), glow)
			AudioManager.play_at("spore_puff", world, -9.0, randf_range(0.9, 1.15))
	if points.has("fire"):
		var nearest := Vector3.INF
		var best := FIRE_REACH * FIRE_REACH
		for pt in (points["fire"] as PackedVector3Array):
			var world: Vector3 = _map.to_global(pt)
			var d2 := world.distance_squared_to(at)
			if d2 < best:
				best = d2
				nearest = world
		if nearest != Vector3.INF:
			_count("ember")
			burst("ember", nearest, EMBER_TINT)
			AudioManager.play_at("fire_whoosh", nearest, -10.0 + 4.0 * strength, randf_range(0.9, 1.2))

# ───────────────────────────── Agua ─────────────────────────────

func _tick_water(pos: Vector3, moved: float, delta: float) -> void:
	var in_water: bool = _map.has_method("is_water") and _map.is_water(pos)
	if in_water:
		_stride += moved
		if not _was_in_water or _stride >= STRIDE:
			_stride = 0.0
			ripple(pos, 0.7 if _was_in_water else 1.0)
			burst("splash", pos + Vector3(0.0, 0.1, 0.0), WATER_TINT)
			AudioManager.play_at("water_step", pos, -11.0, randf_range(0.9, 1.12))
	_was_in_water = in_water
	if not _ripples_live:
		return
	var live := false
	for i in RIPPLES:
		var r := _ripples[i]
		if r.w <= 0.0:
			continue
		r.z += delta
		if r.z >= RIPPLE_LIFE:
			r = Vector4.ZERO
		else:
			live = true
		_ripples[i] = r
	_ripples_live = live
	_push_ripples()

## Anillo en el agua con centro en `at` (fuerza 0..1). Se reciclan RIPPLES anillos: el más viejo cede el sitio.
func ripple(at: Vector3, strength: float) -> void:
	_ripples[_ripple_i] = Vector4(at.x, at.z, 0.0, strength)
	_ripple_i = (_ripple_i + 1) % RIPPLES
	_ripples_live = true
	_count("ripple")

func active_ripples() -> int:
	var n := 0
	for r in _ripples:
		if r.w > 0.0:
			n += 1
	return n

func _push_ripples() -> void:
	var mat := water_material()
	if mat:
		mat.set_shader_parameter("ripples", _ripples)

## Material del agua del mapa (SewerMap crea el nodo "Water" en cada nivel), o null.
func water_material() -> ShaderMaterial:
	var water := _map.get_node_or_null("Water") as MultiMeshInstance3D
	if water == null or water.multimesh == null or water.multimesh.mesh == null:
		return null
	return water.multimesh.mesh.surface_get_material(0) as ShaderMaterial

# ───────────────────────────── Hierba ─────────────────────────────

## ¿Hay hierba donde pisa `pos`? La rejilla se rehace sola cuando el mapa cambia de nivel.
func in_grass(pos: Vector3) -> bool:
	if not _map.has_method("grass_transforms"):
		return false
	var grass: Array = _map.grass_transforms()
	if grass.size() != _grass_count:
		_grass_count = grass.size()
		_grass_cells.clear()
		for xf in grass:
			var world: Vector3 = _map.to_global((xf as Transform3D).origin)
			_grass_cells[Vector2i(floori(world.x / GRASS_CELL), floori(world.z / GRASS_CELL))] = true
	return _grass_cells.has(Vector2i(floori(pos.x / GRASS_CELL), floori(pos.z / GRASS_CELL)))

# ───────────────────────────── Partículas ─────────────────────────────

## Ráfaga de partículas de un tipo de BURSTS en `at`, teñida de `tint`.
func burst(kind: String, at: Vector3, tint: Color) -> void:
	var def: Dictionary = BURSTS[kind]
	if _bursts.is_empty():
		for i in BURST_POOL:
			var np := CPUParticles3D.new()
			np.emitting = false
			np.one_shot = true
			np.explosiveness = 0.9
			np.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var quad := QuadMesh.new()
			quad.size = Vector2.ONE
			np.mesh = quad
			var sm := StandardMaterial3D.new()
			sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
			sm.billboard_keep_scale = true
			np.material_override = sm
			var fade := Curve.new()
			fade.add_point(Vector2(0.0, 1.0))
			fade.add_point(Vector2(1.0, 0.0))
			np.scale_amount_curve = fade
			add_child(np)
			_bursts.append(np)
	var p := _bursts[_burst_i]
	_burst_i = (_burst_i + 1) % BURST_POOL
	p.amount = Quality.count(def["amount"])
	p.lifetime = def["life"]
	p.direction = def["dir"]
	p.spread = def["spread"]
	p.initial_velocity_min = (def["vel"] as Vector2).x
	p.initial_velocity_max = (def["vel"] as Vector2).y
	p.gravity = def["gravity"]
	p.scale_amount_min = (def["size"] as Vector2).x
	p.scale_amount_max = (def["size"] as Vector2).y
	var sm := p.material_override as StandardMaterial3D
	sm.albedo_color = tint
	sm.emission_enabled = float(def["glow"]) > 0.0
	sm.emission = tint
	sm.emission_energy_multiplier = float(def["glow"])
	p.global_position = at
	p.restart()
	p.emitting = true
