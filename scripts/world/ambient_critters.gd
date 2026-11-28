class_name AmbientCritters
extends Node3D

## Fauna ambiental: bichos sin colisión ni combate que hacen que el mapa parezca habitado.
##   Supervivencia: cuervos posados en tumbas, ruinas y árboles; luciérnagas de noche.
##   Cavernas:      murciélagos colgados del techo de las salas; bichos de luz junto a los hongos.
##   Cloacas:       ratas que corren pegadas a la pared; moscas sobre el agua.
## Todos reaccionan: huyen del jugador (antes si va corriendo), de los golpes y de las esquivas, y los de luz
## se dispersan con la onda de un ataque. Cada espantada emite `scared`: los enemigos que aún no han visto al
## jugador la oyen y se ponen en guardia (ver DungeonEncounter.noise_at), así que entrar corriendo en una sala
## con murciélagos delata.
## La fauna SIGUE al jugador: son pocos (un MultiMesh, una llamada de dibujo) y los que quedan lejos se mudan,
## sin que se vea, a un sitio cercano. Así siempre hay vida alrededor sin poblar el mapa entero.
## Dibujo: quads con critter_sprite.gdshader y el atlas de tools/make_critter_sprites.py.
## Uso: AmbientCritters.new() → add_child → setup(mapa, jugador). Lo crea GameStartFacade.

signal scared(at: Vector3, kind: String)

const ATLAS_PATH := "res://assets/textures/critters/critters_atlas.png"
const SHADER: Shader = preload("res://scripts/world/critter_sprite.gdshader")

enum St { REST, FLEE, AWAY, RETURN, ROAM }

## Familias: "perch" (posado, huye volando), "run" (corretea por el suelo), "drift" (flota en torno a un punto).
##  size = alto del sprite (m) · rest / move = fotogramas del atlas · hz = alternancias por segundo
##  fear = radio al que huye del jugador (m) · speed = m/s al huir · lift = cuánto sube el sprite sobre su punto
const KINDS := {
	"crow": {"family": "perch", "size": 0.8, "rest": 0, "move": [1, 2], "hz": 5.0, "fear": 7.0, "speed": 9.5,
		"lift": 0.3, "sfx": "wing_flap", "call": "amb_crow", "glow": false},
	"bat": {"family": "perch", "size": 0.62, "rest": 3, "move": [4, 5], "hz": 10.0, "fear": 5.0, "speed": 7.5,
		"lift": -0.3, "sfx": "bat_screech", "call": "wing_flap", "glow": false},
	"rat": {"family": "run", "size": 0.46, "rest": 6, "move": [6, 7], "hz": 9.0, "fear": 5.5, "speed": 6.5,
		"lift": 0.12, "sfx": "amb_squeak", "call": "", "glow": false},
	"glow": {"family": "drift", "size": 0.2, "rest": 8, "move": [8, 8], "hz": 0.0, "fear": 0.0, "speed": 0.0,
		"lift": 0.0, "sfx": "", "call": "", "glow": true},
	"fly": {"family": "drift", "size": 0.13, "rest": 9, "move": [9, 10], "hz": 24.0, "fear": 0.0, "speed": 0.0,
		"lift": 0.0, "sfx": "", "call": "", "glow": false},
}
## Cuántos de cada tipo por perfil y calidad [baja, media, alta]. En móvil, MOBILE_FACTOR de eso.
const BUDGET := {
	"survival": {"crow": [5, 8, 12], "glow": [8, 16, 26]},
	"caves": {"bat": [5, 9, 14], "glow": [8, 14, 22]},
	"sewers": {"rat": [4, 7, 10], "fly": [8, 12, 18]},
	"survival_sewers": {"crow": [3, 5, 8], "rat": [4, 7, 10], "fly": [8, 12, 18]},
}
const MOBILE_FACTOR := 0.6
const NEAR := Vector2(9.0, 30.0)      ## m: franja alrededor del jugador donde se instala la fauna que se muda
const FAR := 46.0                     ## m: más lejos que esto, un bicho quieto se muda cerca del jugador
const RUN_SPEED := 5.0                ## m/s del jugador a partir de los cuales asusta desde más lejos
const RUN_FEAR := 1.4
const AWAY_TIME := Vector2(6.0, 14.0) ## s que un bicho espantado tarda en volver
const FLEE_TIME := 2.6                ## s que un cuervo vuela antes de perderse de vista
const BAT_FLIGHT := Vector2(4.0, 6.5) ## s que un murciélago revolotea antes de volver a colgarse
const SCARE_SFX_GAP := 0.35           ## s: varios bichos espantados a la vez no suenan todos
const SPOT_TICK := 1.0                ## s entre mudanzas y comprobaciones del mapa
const GLOW_NIGHT_MIN := 0.25          ## las luciérnagas aparecen a partir de esta fracción de noche

var profile_id := ""
var _map: Node3D
var _player: Node3D
var _mm: MultiMesh
var _critters: Array = []             # [{kind, st, pos, vel, home, t, alpha, flip, ...}]
var _spots: Dictionary = {}           # tipo -> PackedVector3Array (sitios del mapa, en coordenadas de mundo)
var _seed := -1
var _spot_t := 0.0
var _sfx_at := 0.0
var _last_pp := Vector3.INF
var _player_speed := 0.0
var _rng := RandomNumberGenerator.new()
## Espantadas desde que arrancó (para las pruebas)
var scares := 0

static func budget_for(profile: String, kind: String) -> int:
	var row: Array = (BUDGET.get(profile, {}) as Dictionary).get(kind, [0, 0, 0])
	var n: int = row[Quality.level()]
	return int(round(n * MOBILE_FACTOR)) if Quality.is_mobile() else n

func setup(map: Node3D, player: Node3D) -> void:
	_map = map
	_player = player
	_rng.randomize()
	profile_id = MapAmbience.profile_for(map)
	_seed = -1                            # fuerza a rehacer los sitios (mapa o nivel nuevo)
	_last_pp = Vector3.INF
	_build()

func count(kind: String = "") -> int:
	if kind == "":
		return _critters.size()
	var n := 0
	for c in _critters:
		if c["kind"] == kind:
			n += 1
	return n

func count_in_state(kind: String, st: int) -> int:
	var n := 0
	for c in _critters:
		if c["kind"] == kind and c["st"] == st:
			n += 1
	return n

func spot_count(kind: String) -> int:
	return (_spots.get(kind, PackedVector3Array()) as PackedVector3Array).size()

func _build() -> void:
	for c in get_children():
		c.queue_free()
	_critters.clear()
	var plan: Dictionary = BUDGET.get(profile_id, {})
	for kind in plan:
		for i in budget_for(profile_id, kind):
			_critters.append({"kind": kind, "st": St.AWAY, "pos": Vector3.ZERO, "vel": Vector3.ZERO, "home": Vector3.INF,
				"t": _rng.randf_range(0.0, 1.5), "alpha": 0.0, "flip": false, "moving": false, "seed": _rng.randf() * 100.0,
				"push": Vector3.ZERO, "room": Vector3.ZERO, "shine": 1.0})
	if _critters.is_empty():
		return
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	if ResourceLoader.exists(ATLAS_PATH):
		mat.set_shader_parameter("atlas", load(ATLAS_PATH))
	quad.material = mat
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.use_custom_data = true
	_mm.mesh = quad
	_mm.instance_count = _critters.size()
	for i in _critters.size():
		_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
		_mm.set_instance_color(i, Color(1, 1, 1, 0))
		_push_custom(i)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Sprites"
	mmi.multimesh = _mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Los bichos se mueven en _process (cada frame): sin interpolación de física, que además guardaría
	# dos transformaciones por instancia y avisa al escribirlas fuera del tick.
	mmi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	mmi.custom_aabb = AABB(Vector3(-400, -20, -400), Vector3(800, 80, 800))   # los bichos se mueven: sin recorte por caja
	add_child(mmi)

# ───────────────────────────── Sitios del mapa ─────────────────────────────

## Alturas (m, a escala 1) a las que se posa un cuervo en cada prop de supervivencia.
const PERCH_HEIGHT := {"grave_a": 1.0, "grave_b": 1.25, "pillar": 3.1, "wall": 2.2, "tree_a": 4.0, "tree_b": 3.2, "fence": 1.35}
const BAT_HEIGHT := 3.25              ## m: por debajo del techo de la cueva
const ROOSTS_PER_ROOM := 6

func _collect_spots() -> void:
	_spots.clear()
	match profile_id:
		"survival":
			var perches := PackedVector3Array()
			var inst: Dictionary = _map.get("_instances")
			for kind in PERCH_HEIGHT:
				for xf in inst.get(kind, []):
					var t := xf as Transform3D
					perches.append(_map.to_global(t.origin + Vector3(0.0, float(PERCH_HEIGHT[kind]) * t.basis.get_scale().y, 0.0)))
			_spots["crow"] = perches
		"survival_sewers":
			_collect_sewer_city_spots()
		"caves":
			var roosts := PackedVector3Array()
			var dm := _map as DungeonMap
			for i in dm.rooms.size():
				var cells: Array = dm.rooms[i]["cells"]
				for k in ROOSTS_PER_ROOM:
					var c: Vector2i = cells[_rng.randi() % cells.size()]
					if int(dm._wall_dist.get(c, 0)) >= 2:
						roosts.append(dm.to_global(dm._cell_pos(c) + Vector3(0.0, BAT_HEIGHT, 0.0)))
			_spots["bat"] = roosts
			var glows := PackedVector3Array()
			for kind in ["mush_big", "mush"]:
				for pt in (dm.ambient_points.get(kind, PackedVector3Array()) as PackedVector3Array):
					glows.append(dm.to_global(pt) + Vector3(0.0, 0.7, 0.0))
			_spots["glow"] = glows
		"sewers":
			var dm := _map as DungeonMap
			var edges := PackedVector3Array()
			for c in dm._cells:
				if int(dm._wall_dist.get(c, 0)) == 1 and not dm._blocked.has(c):
					edges.append(dm.to_global(dm._cell_pos(c)))
			_spots["rat"] = edges
			var water := PackedVector3Array()
			var wet = dm.get("_water")
			if wet is Dictionary:
				for c in wet:
					water.append(dm.to_global(dm._cell_pos(c)) + Vector3(0.0, 0.8, 0.0))
			_spots["fly"] = water

## Mapa de Cloacas de Supervivencia: cuervos en ruinas y vallas, ratas por las orillas de los canales y junto
## a la basura, moscas sobre el agua y los vertederos.
func _collect_sewer_city_spots() -> void:
	var perches := PackedVector3Array()
	var inst: Dictionary = _map.get("_instances")
	for kind in PERCH_HEIGHT:
		for xf in inst.get(kind, []):
			var t := xf as Transform3D
			perches.append(_map.to_global(t.origin + Vector3(0.0, float(PERCH_HEIGHT[kind]) * t.basis.get_scale().y, 0.0)))
	_spots["crow"] = perches
	var banks := PackedVector3Array()
	var water := PackedVector3Array()
	for d in _map.get("districts"):
		var sd := d as SewerDistrict
		for c in sd.canals:
			var mn: Vector2 = c["min"]
			var mx: Vector2 = c["max"]
			var long_x := mx.x - mn.x > mx.y - mn.y
			var n := int(maxf(mx.x - mn.x, mx.y - mn.y) / 9.0)
			for k in n:
				var t := (float(k) + 0.5) / float(n)
				var f := Vector2(t, 0.5) if long_x else Vector2(0.5, t)
				var mid := mn + (mx - mn) * f
				water.append(_map.to_global(Vector3(mid.x, sd.water_y() + 0.8, mid.y)))
				for side: float in [-1.0, 1.0]:
					var off := Vector2(0.0, (mx.y - mn.y) * 0.5 + 1.2) if long_x else Vector2((mx.x - mn.x) * 0.5 + 1.2, 0.0)
					var b := mid + off * side
					if absf(b.x) < float(_map.get("play_half")) - 3.0 and absf(b.y) < float(_map.get("play_half")) - 3.0:
						banks.append(_map.to_global(Vector3(b.x, sd.street_y, b.y)))
	for kind in ["trash_pile", "trash_bag"]:
		for xf in inst.get(kind, []):
			var o := (xf as Transform3D).origin
			banks.append(_map.to_global(o + Vector3(1.2, 0.0, 0.0)))
			if kind == "trash_pile":
				water.append(_map.to_global(o + Vector3(0.0, 1.4, 0.0)))
	_spots["rat"] = banks
	_spots["fly"] = water

## Un sitio libre del tipo dado dentro de la franja NEAR del jugador (o Vector3.INF). `avoid` = no más cerca que eso.
func _spot_near_player(kind: String, avoid: float = NEAR.x) -> Vector3:
	var pool: PackedVector3Array = _spots.get(kind, PackedVector3Array())
	if pool.is_empty():
		return Vector3.INF
	var pp := _player.global_position
	for attempt in 14:
		var s := pool[_rng.randi() % pool.size()]
		var d := Vector2(s.x - pp.x, s.z - pp.z).length()
		if d < avoid or d > NEAR.y or _taken(s):
			continue
		return s
	return Vector3.INF

func _taken(spot: Vector3) -> bool:
	for c in _critters:
		if c["st"] != St.AWAY and (c["home"] as Vector3).distance_squared_to(spot) < 0.6:
			return true
	return false

# ───────────────────────────── Bucle ─────────────────────────────

func _process(delta: float) -> void:
	if _mm == null or _player == null or not is_instance_valid(_player) or _map == null or not is_instance_valid(_map):
		return
	var pp := _player.global_position
	if _last_pp != Vector3.INF:
		_player_speed = lerpf(_player_speed, Vector2(pp.x - _last_pp.x, pp.z - _last_pp.z).length() / maxf(delta, 0.0001), 0.2)
	_last_pp = pp
	_spot_t -= delta
	if _spot_t <= 0.0:
		_spot_t = SPOT_TICK
		var s: int = int(_map.get("used_seed")) if "used_seed" in _map else 0
		if s != _seed:                    # mapa nuevo (otro nivel): sitios nuevos y todos fuera
			_seed = s
			_collect_spots()
			for c in _critters:
				c["st"] = St.AWAY
				c["t"] = _rng.randf_range(0.0, 1.5)
				c["home"] = Vector3.INF
	var fear_k := RUN_FEAR if _player_speed >= RUN_SPEED else 1.0
	var night := _night()
	for i in _critters.size():
		var c: Dictionary = _critters[i]
		var def: Dictionary = KINDS[c["kind"]]
		var was_moving: bool = c["moving"]
		var was_flip: bool = c["flip"]
		match def["family"]:
			"perch": _tick_perch(c, def, delta, pp, fear_k)
			"run": _tick_run(c, def, delta, pp, fear_k)
			"drift": _tick_drift(c, def, delta, pp, night)
		if c["moving"] != was_moving or c["flip"] != was_flip:
			_push_custom(i)
		var size: float = float(def["size"]) * (1.0 if c["alpha"] > 0.01 else 0.0)
		_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(size, size, size)),
			(c["pos"] as Vector3) + Vector3(0.0, float(def["lift"]), 0.0)))
		_mm.set_instance_color(i, Color(c["tint"] if c.has("tint") else Color.WHITE, float(c["alpha"]) * float(c["shine"])))

func _push_custom(i: int) -> void:
	var c: Dictionary = _critters[i]
	var def: Dictionary = KINDS[c["kind"]]
	var frames: Array = def["move"] if c["moving"] else [def["rest"], def["rest"]]
	var flags := (1.0 if c["flip"] else 0.0) + (2.0 if def["glow"] else 0.0)
	_mm.set_instance_custom_data(i, Color(float(frames[0]), float(frames[1]), float(def["hz"]) if c["moving"] else 0.0, flags))

## 0 = día, 1 = noche (sin ciclo: las cuevas cuentan como noche).
func _night() -> float:
	var cycle := get_parent().get_node_or_null("DayNightCycle") if get_parent() else null
	return smoothstep(0.5, 0.85, float(cycle.phase)) if cycle else (0.0 if profile_id.begins_with("survival") else 1.0)

func _fade(c: Dictionary, to: float, delta: float, rate: float = 3.0) -> void:
	c["alpha"] = move_toward(float(c["alpha"]), to, rate * delta)

func _face(c: Dictionary, dx: float) -> void:
	if absf(dx) > 0.05:
		c["flip"] = dx < 0.0

# ───────────────────────────── Posados: cuervos y murciélagos ─────────────────────────────

func _tick_perch(c: Dictionary, def: Dictionary, delta: float, pp: Vector3, fear_k: float) -> void:
	var pos: Vector3 = c["pos"]
	match c["st"]:
		St.AWAY:
			c["alpha"] = 0.0
			c["t"] = float(c["t"]) - delta
			if c["t"] <= 0.0:
				var spot := _spot_near_player(c["kind"], NEAR.x + 3.0)
				if spot == Vector3.INF:
					c["t"] = 2.0
					return
				c["home"] = spot
				# Llega volando desde fuera, por el lado contrario al jugador
				var from := spot - pp
				from.y = 0.0
				from = from.normalized() if from.length_squared() > 0.01 else Vector3.FORWARD
				c["pos"] = spot + from * 9.0 + Vector3(0.0, 4.0 if c["kind"] == "crow" else 0.0, 0.0)
				c["st"] = St.RETURN
				c["moving"] = true
		St.RETURN:
			_fade(c, 1.0, delta)
			var home: Vector3 = c["home"]
			var to := home - pos
			var step := float(def["speed"]) * 0.7 * delta
			_face(c, to.x)
			if to.length() <= step:
				c["pos"] = home
				c["st"] = St.REST
				c["moving"] = false
				c["flip"] = _rng.randf() < 0.5
			else:
				c["pos"] = pos + to.normalized() * step
		St.REST:
			_fade(c, 1.0, delta)
			var flat := Vector2(pos.x - pp.x, pos.z - pp.z).length()
			if flat < float(def["fear"]) * fear_k:
				_startle(c, def, pp)
			elif flat > FAR and _rng.randf() < delta * 0.5:
				c["st"] = St.AWAY           # demasiado lejos para verse: se muda
				c["t"] = _rng.randf_range(0.2, 2.0)
		St.FLEE:
			c["t"] = float(c["t"]) - delta
			if c["kind"] == "bat":
				_bat_flight(c, def, delta, pp)
			else:
				c["pos"] = pos + (c["vel"] as Vector3) * delta
				_face(c, (c["vel"] as Vector3).x)
				if c["t"] <= 0.8:
					_fade(c, 0.0, delta, 1.4)
				if c["t"] <= 0.0:
					c["st"] = St.AWAY
					c["t"] = _rng.randf_range(AWAY_TIME.x, AWAY_TIME.y)

## Revoloteo del murciélago: da vueltas a media altura en torno al centro de su sala y luego busca otro techo.
func _bat_flight(c: Dictionary, def: Dictionary, delta: float, pp: Vector3) -> void:
	var pos: Vector3 = c["pos"]
	var center: Vector3 = c["room"]
	var a: float = float(c["seed"]) + float(c["t"]) * 2.4
	var orbit := center + Vector3(cos(a) * 4.5, 0.0, sin(a * 1.3) * 4.5)
	orbit.y = (c["home"] as Vector3).y - 0.9 + 0.5 * sin(a * 3.1)
	var to := orbit - pos
	var vel: Vector3 = (c["vel"] as Vector3).lerp(to.normalized() * float(def["speed"]), clampf(4.0 * delta, 0.0, 1.0))
	c["vel"] = vel
	c["pos"] = pos + vel * delta
	_face(c, vel.x)
	if c["t"] <= 0.0:
		# Se cuelga en otro sitio de la zona, lejos del jugador; si no hay, sigue volando un poco más
		var spot := _spot_near_player("bat", float(def["fear"]) * 1.8)
		if spot == Vector3.INF:
			c["t"] = 1.5
		else:
			c["home"] = spot
			c["st"] = St.RETURN

func _startle(c: Dictionary, def: Dictionary, threat: Vector3) -> void:
	var pos: Vector3 = c["pos"]
	var away := pos - threat
	away.y = 0.0
	away = away.normalized() if away.length_squared() > 0.01 else Vector3.FORWARD
	away = away.rotated(Vector3.UP, _rng.randf_range(-0.6, 0.6))
	c["st"] = St.FLEE
	c["moving"] = true
	if c["kind"] == "bat":
		c["t"] = _rng.randf_range(BAT_FLIGHT.x, BAT_FLIGHT.y)
		c["vel"] = away * float(def["speed"]) + Vector3(0.0, -1.5, 0.0)
		c["room"] = pos + away * 3.0 - Vector3(0.0, pos.y, 0.0)
	else:
		c["t"] = FLEE_TIME
		c["vel"] = (away + Vector3(0.0, 0.55, 0.0)).normalized() * float(def["speed"])
	_scare(c, def)

func _scare(c: Dictionary, def: Dictionary) -> void:
	scares += 1
	scared.emit(c["pos"], c["kind"])
	var now := Time.get_ticks_msec() / 1000.0
	if now < _sfx_at:
		return
	_sfx_at = now + SCARE_SFX_GAP
	if def["sfx"] != "":
		AudioManager.play_at(def["sfx"], c["pos"], -8.0, _rng.randf_range(0.9, 1.15))
	if def["call"] != "" and _rng.randf() < 0.5:
		AudioManager.play_at(def["call"], c["pos"], -10.0, _rng.randf_range(0.95, 1.2))

# ───────────────────────────── Corredores: ratas ─────────────────────────────

const RAT_ROAM := 1.9                 ## m/s correteando tranquila
const RAT_HOP := Vector2(2.5, 7.0)    ## m de cada carrera

func _tick_run(c: Dictionary, def: Dictionary, delta: float, pp: Vector3, fear_k: float) -> void:
	var pos: Vector3 = c["pos"]
	match c["st"]:
		St.AWAY:
			c["alpha"] = 0.0
			c["t"] = float(c["t"]) - delta
			if c["t"] <= 0.0:
				var spot := _spot_near_player("rat")
				if spot == Vector3.INF:
					c["t"] = 2.0
					return
				c["pos"] = spot
				c["home"] = spot
				c["st"] = St.REST
				c["t"] = _rng.randf_range(0.4, 2.0)
				c["moving"] = false
		St.REST, St.ROAM:
			_fade(c, 1.0, delta, 2.0)
			var flat := Vector2(pos.x - pp.x, pos.z - pp.z).length()
			if flat < float(def["fear"]) * fear_k:
				# Huye en línea recta lejos del jugador y se mete por un agujero de la pared
				var away := Vector3(pos.x - pp.x, 0.0, pos.z - pp.z).normalized().rotated(Vector3.UP, _rng.randf_range(-0.5, 0.5))
				c["vel"] = away * float(def["speed"])
				c["st"] = St.FLEE
				c["t"] = 1.3
				c["moving"] = true
				_scare(c, def)
				return
			if flat > FAR:
				c["st"] = St.AWAY
				c["t"] = _rng.randf_range(0.2, 1.5)
				return
			if c["st"] == St.REST:
				c["t"] = float(c["t"]) - delta
				if c["t"] <= 0.0:
					var goal := _rat_goal(pos)
					if goal == Vector3.INF:
						c["t"] = 1.0
					else:
						c["home"] = goal
						c["st"] = St.ROAM
						c["moving"] = true
			else:
				var to := (c["home"] as Vector3) - pos
				var step := RAT_ROAM * delta
				_face(c, to.x)
				if to.length() <= step:
					c["pos"] = c["home"]
					c["st"] = St.REST
					c["t"] = _rng.randf_range(0.5, 2.6)
					c["moving"] = false
				else:
					c["pos"] = pos + to.normalized() * step
		St.FLEE:
			c["t"] = float(c["t"]) - delta
			var next := pos + (c["vel"] as Vector3) * delta
			_face(c, (c["vel"] as Vector3).x)
			if _walkable(next):
				c["pos"] = next
			else:
				c["t"] = minf(float(c["t"]), 0.25)      # ha llegado a la pared: desaparece por el agujero
			_fade(c, 0.0 if c["t"] < 0.3 else 1.0, delta, 4.0)
			if c["t"] <= 0.0:
				c["st"] = St.AWAY
				c["t"] = _rng.randf_range(AWAY_TIME.x, AWAY_TIME.y)

## Otro borde de pared a una carrera de distancia, con suelo en el punto medio (no atraviesa esquinas de roca).
func _rat_goal(from: Vector3) -> Vector3:
	var pool: PackedVector3Array = _spots.get("rat", PackedVector3Array())
	for attempt in 10:
		var s := pool[_rng.randi() % pool.size()]
		var d := s.distance_to(from)
		if d >= RAT_HOP.x and d <= RAT_HOP.y and _walkable(from.lerp(s, 0.5)):
			return s
	return Vector3.INF

func _walkable(p: Vector3) -> bool:
	var dm := _map as DungeonMap
	return dm == null or dm._cells.has(dm.world_to_cell(dm.to_local(p)))

# ───────────────────────────── Flotantes: luces y moscas ─────────────────────────────

const DRIFT_REACH := 1.3              ## m que se aleja de su punto un bicho de luz
const FLY_REACH := 0.55

func _tick_drift(c: Dictionary, def: Dictionary, delta: float, pp: Vector3, night: float) -> void:
	var home: Vector3 = c["home"]
	var free_roam: bool = c["kind"] == "glow" and profile_id == "survival"
	var shown := 1.0
	if free_roam:
		shown = smoothstep(GLOW_NIGHT_MIN, 0.7, night)
	var far := home == Vector3.INF or Vector2(home.x - pp.x, home.z - pp.z).length() > NEAR.y + 6.0
	if far:
		_fade(c, 0.0, delta, 2.0)
		if c["alpha"] <= 0.01:
			c["t"] = float(c["t"]) - delta
			if c["t"] <= 0.0:
				c["t"] = _rng.randf_range(0.3, 1.5)
				var spot := _drift_home(c["kind"], pp, free_roam)
				if spot != Vector3.INF:
					c["home"] = spot
					c["pos"] = spot
					c["push"] = Vector3.ZERO
					if def["glow"]:
						c["tint"] = _glow_tint()
		return
	_fade(c, shown, delta, 1.5)
	var t: float = Time.get_ticks_msec() / 1000.0 + float(c["seed"])
	var reach := FLY_REACH if c["kind"] == "fly" else DRIFT_REACH
	var rate := 5.5 if c["kind"] == "fly" else 0.55
	var off := Vector3(sin(t * rate * 1.0) + 0.5 * sin(t * rate * 2.3 + 1.0), 0.45 * sin(t * rate * 1.4 + 2.0),
		cos(t * rate * 0.8 + 0.5) + 0.5 * sin(t * rate * 1.9)) * reach * 0.6
	c["push"] = (c["push"] as Vector3).lerp(Vector3.ZERO, clampf(1.6 * delta, 0.0, 1.0))
	var next: Vector3 = home + off + (c["push"] as Vector3)
	_face(c, next.x - (c["pos"] as Vector3).x)
	c["pos"] = next
	c["moving"] = c["kind"] == "fly"
	if def["glow"]:
		# Parpadeo lento: cada luz respira a su ritmo
		c["shine"] = 0.5 + 0.5 * sin(t * 1.7 + float(c["seed"])) ** 2

func _drift_home(kind: String, pp: Vector3, free_roam: bool) -> Vector3:
	if free_roam:
		# Luciérnagas: en cualquier punto del suelo alrededor del jugador
		var a := _rng.randf() * TAU
		var d := _rng.randf_range(5.0, NEAR.y - 4.0)
		var x := pp.x + cos(a) * d
		var z := pp.z + sin(a) * d
		var y: float = _map.get_height_at(x, z) if _map.has_method("get_height_at") else pp.y
		return Vector3(x, y + _rng.randf_range(0.6, 1.9), z)
	var pool: PackedVector3Array = _spots.get(kind, PackedVector3Array())
	if pool.is_empty():
		return Vector3.INF
	for attempt in 10:
		var s := pool[_rng.randi() % pool.size()]
		if Vector2(s.x - pp.x, s.z - pp.z).length() <= NEAR.y:
			return s + Vector3(_rng.randf_range(-0.5, 0.5), _rng.randf_range(-0.2, 0.5), _rng.randf_range(-0.5, 0.5))
	return Vector3.INF

func _glow_tint() -> Color:
	if _map.has_method("palette"):
		return (_map.palette()["crystal"] as Color).lightened(0.25)
	return Color(0.85, 1.0, 0.45)

# ───────────────────────────── Ruido ─────────────────────────────

## Un golpe, una esquiva o una explosión en `at`: los posados y las ratas a menos de `radius` huyen, y los
## flotantes salen despedidos y vuelven poco a poco. Lo llama MapReactions.
func disturb(at: Vector3, radius: float) -> void:
	for c in _critters:
		if float(c["alpha"]) <= 0.01:
			continue
		var pos: Vector3 = c["pos"]
		var d := Vector2(pos.x - at.x, pos.z - at.z).length()
		if d > radius:
			continue
		var def: Dictionary = KINDS[c["kind"]]
		match def["family"]:
			"perch":
				if c["st"] == St.REST:
					_startle(c, def, at)
			"run":
				if c["st"] == St.REST or c["st"] == St.ROAM:
					var away := Vector3(pos.x - at.x, 0.0, pos.z - at.z)
					c["vel"] = (away.normalized() if away.length_squared() > 0.01 else Vector3.FORWARD) * float(def["speed"])
					c["st"] = St.FLEE
					c["t"] = 1.3
					c["moving"] = true
					_scare(c, def)
			"drift":
				var out := pos - at
				c["push"] = (out.normalized() if out.length_squared() > 0.01 else Vector3.UP) * (1.0 - d / radius) * 2.6
