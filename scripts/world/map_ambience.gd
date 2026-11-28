class_name MapAmbience
extends Node

## Sonido ambiente de un mapa de partida (supervivencia, Cavernas, Cloacas). Tres capas, todas en el bus Ambient:
##  - Camas: bucles 2D que identifican el lugar (viento, aire de cueva, agua). En supervivencia el viento de día
##    se funde con el de noche según DayNightCycle.phase; en las Cloacas el agua sube al acercarse a un canal.
##  - Emisores: unos pocos AudioStreamPlayer3D que se mudan a las fuentes más cercanas (fuego, hongos grandes).
##    Las fuentes salen de ProceduralMap.ambient_points; hay cientos de antorchas pero solo suenan las de al lado.
##  - Sueltos: cada pocos segundos, un sonido al azar en algún punto alrededor del jugador (cuervo, gota, cadena).
## Los sonidos los genera tools/generate_ambient_sfx.py (assets/sfx/amb_*.wav).
## Uso: MapAmbience.new() → add_child → setup(mapa, jugador). Lo crea GameStartFacade.

## Modos: "always", "day" / "night" (supervivencia, según la fase del ciclo), "water" (más fuerte cerca de un
## canal) y "canal" (solo cerca de un canal: el Barrio del Desagüe de Supervivencia).
const PROFILES := {
	"survival": {
		"beds": [["amb_wind_day", -17.0, "day"], ["amb_wind_night", -15.0, "night"], ["amb_sewer", -15.0, "canal"]],
		# [sonido, dB, peso, modo]
		"shots": [["amb_crow", -9.0, 3.0, "day"], ["amb_gust", -10.0, 2.0, "always"], ["amb_creak", -12.0, 1.5, "always"],
			["amb_owl", -9.0, 3.0, "night"]],
	},
	# Supervivencia en Cloacas (ProceduralMap theme "sewers"): agua corriendo en todo el mapa y viento de noche
	"survival_sewers": {
		"beds": [["amb_sewer", -14.0, "water"], ["amb_wind_night", -18.0, "night"]],
		"shots": [["amb_drip", -10.0, 3.0, "always"], ["amb_pipe_groan", -11.0, 2.0, "always"], ["amb_squeak", -13.0, 2.0, "always"],
			["amb_chain", -15.0, 1.0, "always"], ["amb_crow", -11.0, 1.0, "day"]],
	},
	"caves": {
		"beds": [["amb_cave", -13.0, "always"]],
		"shots": [["amb_drip", -8.0, 5.0, "always"], ["amb_rockfall", -10.0, 1.5, "always"], ["amb_chain", -14.0, 1.0, "always"]],
	},
	"sewers": {
		"beds": [["amb_sewer", -15.0, "water"]],
		"shots": [["amb_drip", -9.0, 4.0, "always"], ["amb_pipe_groan", -10.0, 2.0, "always"], ["amb_chain", -14.0, 1.5, "always"],
			["amb_squeak", -13.0, 2.0, "always"]],
	},
}
## Fuentes con sonido propio: tipo de ambient_points -> [bucle, dB, distancia a la que deja de oírse (m)]
const EMITTERS := {
	"fire": ["amb_fire", -9.0, 13.0],
	"mush_big": ["amb_mush_hum", -15.0, 8.0],
}
const TICK := 0.5                     ## s entre recálculos (fuentes cercanas, día/noche, agua)
const FADE := 1.6                     ## 1/s: lo rápido que una cama llega a su volumen
const SHOT_GAP := Vector2(7.0, 18.0)  ## s entre sonidos sueltos
const SHOT_DIST := Vector2(11.0, 24.0)
const WATER_FLOOR := 0.4              ## volumen de la cama de agua lejos de los canales (0..1)
const WATER_REACH := 6.0              ## m alrededor del jugador donde se busca agua
const SILENT_DB := -60.0

var profile_id := ""
var _map: Node3D
var _player: Node3D
var _beds: Array = []                 # [{player, db, mode, gain}]
var _emitters: Array = []             # [{player, kind, point}]
var _shot_player: AudioStreamPlayer3D
var _acc := TICK
var _shot_t := 5.0
var _rng := RandomNumberGenerator.new()

## Perfil que le toca a un mapa: el id de su mundo si es una mazmorra, "survival" si no.
static func profile_for(map: Node) -> String:
	if map is DungeonMap:
		var w: String = (map as DungeonMap).world_id
		if w == "":
			w = GameData.world if "world" in GameData else WorldDefs.DEFAULT
		return w if PROFILES.has(w) else "caves"
	if map.has_method("get_theme") and map.get_theme() == "sewers":
		return "survival_sewers"
	return "survival"

## Emisores 3D a la vez: cada uno mezcla en cada frame, así que en móvil y en calidad baja van menos.
static func emitter_budget() -> int:
	if Quality.is_mobile():
		return [2, 3, 3][Quality.level()]
	return [3, 4, 6][Quality.level()]

func setup(map: Node3D, player: Node3D) -> void:
	_map = map
	_player = player
	_rng.randomize()
	var id := profile_for(map)
	if id == profile_id:
		return
	profile_id = id
	_build()

func bed_count() -> int:
	return _beds.size()

func emitter_count() -> int:
	return _emitters.size()

## Emisores que tienen ahora una fuente asignada.
func active_emitters() -> int:
	var n := 0
	for e in _emitters:
		if e["kind"] != "":
			n += 1
	return n

func _build() -> void:
	for c in get_children():
		c.queue_free()
	_beds.clear()
	_emitters.clear()
	AudioManager.ensure_buses()
	var prof: Dictionary = PROFILES[profile_id]
	for b in prof["beds"]:
		var stream := _loop_stream(b[0])
		if stream == null:
			continue
		var p := AudioStreamPlayer.new()
		p.bus = "Ambient"
		p.stream = stream
		p.volume_db = SILENT_DB
		add_child(p)
		p.play(_rng.randf() * stream.get_length())
		_beds.append({"player": p, "db": float(b[1]), "mode": String(b[2]), "gain": 0.0})
	for i in emitter_budget():
		var e := AudioStreamPlayer3D.new()
		e.bus = "Ambient"
		e.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		e.unit_size = 3.0
		add_child(e)
		_emitters.append({"player": e, "kind": "", "point": Vector3.INF})
	_shot_player = AudioStreamPlayer3D.new()
	_shot_player.bus = "Ambient"
	_shot_player.unit_size = 14.0
	_shot_player.max_distance = 70.0
	add_child(_shot_player)

## Stream en bucle sin costura (los .wav de ambiente empalman: no hace falta tocar su importación).
static func _loop_stream(sfx_name: String) -> AudioStream:
	var s := AudioManager.get_stream(sfx_name)
	var wav := s as AudioStreamWAV
	if wav and wav.loop_mode == AudioStreamWAV.LOOP_DISABLED:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(round(wav.get_length() * wav.mix_rate))
	return s

func _process(delta: float) -> void:
	if profile_id == "" or _player == null or not is_instance_valid(_player):
		return
	for b in _beds:
		var p: AudioStreamPlayer = b["player"]
		var cur := db_to_linear(p.volume_db) if p.volume_db > SILENT_DB + 1.0 else 0.0
		var goal: float = db_to_linear(b["db"]) * float(b["gain"])
		cur = move_toward(cur, goal, FADE * db_to_linear(b["db"]) * delta)
		p.volume_db = linear_to_db(cur) if cur > 0.001 else SILENT_DB
	_acc += delta
	if _acc >= TICK:
		_acc = 0.0
		_update_beds()
		_update_emitters()
	_shot_t -= delta
	if _shot_t <= 0.0:
		_shot_t = _rng.randf_range(SHOT_GAP.x, SHOT_GAP.y)
		_play_shot()

# ───────────────────────────── Camas ─────────────────────────────

## 0 = pleno día, 1 = noche cerrada (sin ciclo: de día).
func night() -> float:
	var cycle := get_parent().get_node_or_null("DayNightCycle") if get_parent() else null
	return smoothstep(0.55, 0.9, float(cycle.phase)) if cycle else 0.0

## Fracción de puntos con agua alrededor del jugador (0 = lejos de los canales).
func water_near() -> float:
	if _map == null or not is_instance_valid(_map) or not _map.has_method("is_water"):
		return 0.0
	var pp := _player.global_position
	var hits := 1.0 if _map.is_water(pp) else 0.0
	for i in 8:
		var a := TAU * float(i) / 8.0
		for r in [WATER_REACH * 0.5, WATER_REACH]:
			if _map.is_water(pp + Vector3(cos(a) * r, 0.0, sin(a) * r)):
				hits += 1.0
	return clampf(hits / 6.0, 0.0, 1.0)

func gain_for(mode: String) -> float:
	match mode:
		"day":
			return 1.0 - night()
		"night":
			return night()
		"water":
			return lerpf(WATER_FLOOR, 1.0, water_near())
		"canal":
			return water_near()
	return 1.0

func _update_beds() -> void:
	for b in _beds:
		b["gain"] = gain_for(b["mode"])

# ───────────────────────────── Emisores ─────────────────────────────

## Reparte los emisores entre las fuentes más cercanas. El que ya suena en una fuente elegida no se mueve
## (cambiarlo de sitio cortaría el bucle); solo se mudan los que se han quedado sin fuente.
func _update_emitters() -> void:
	if _emitters.is_empty() or _map == null or not is_instance_valid(_map) or not ("ambient_points" in _map):
		return
	var pp := _player.global_position
	var near: Array = []                  # [d2, tipo, punto]
	var points: Dictionary = _map.ambient_points
	for kind in EMITTERS:
		if not points.has(kind):
			continue
		var reach: float = EMITTERS[kind][2]
		var r2 := reach * reach
		for pt in (points[kind] as PackedVector3Array):
			var world: Vector3 = _map.to_global(pt)
			var d2 := world.distance_squared_to(pp)
			if d2 <= r2:
				near.append([d2, kind, world])
	near.sort_custom(func(a, b): return a[0] < b[0])
	if near.size() > _emitters.size():
		near.resize(_emitters.size())
	var wanted := {}
	for n in near:
		wanted[n[2]] = n[1]
	var free_slots: Array = []
	for e in _emitters:
		if e["kind"] != "" and wanted.has(e["point"]):
			wanted.erase(e["point"])
		else:
			free_slots.append(e)
	for pt in wanted:
		var e: Dictionary = free_slots.pop_back()
		_assign(e, wanted[pt], pt)
	for e in free_slots:
		if e["kind"] != "":
			e["kind"] = ""
			(e["player"] as AudioStreamPlayer3D).stop()

func _assign(e: Dictionary, kind: String, point: Vector3) -> void:
	var def: Array = EMITTERS[kind]
	var stream := _loop_stream(def[0])
	if stream == null:
		return
	var p: AudioStreamPlayer3D = e["player"]
	p.stream = stream
	p.volume_db = float(def[1])
	p.max_distance = float(def[2])
	p.pitch_scale = _rng.randf_range(0.94, 1.06)      # dos antorchas juntas no suenan en fase
	p.global_position = point
	p.play(_rng.randf() * stream.get_length())
	e["kind"] = kind
	e["point"] = point

# ───────────────────────────── Sueltos ─────────────────────────────

## Elige un sonido suelto del perfil según el momento (pesos; los de otro modo no entran).
func pick_shot() -> Array:
	var pool: Array = []
	var total := 0.0
	for s in PROFILES[profile_id]["shots"]:
		var w: float = float(s[2]) * gain_for(s[3])
		if w > 0.05:
			pool.append([s, w])
			total += w
	var roll := _rng.randf() * total
	for e in pool:
		roll -= e[1]
		if roll <= 0.0:
			return e[0]
	return pool.back()[0] if not pool.is_empty() else []

func _play_shot() -> void:
	var shot := pick_shot()
	if shot.is_empty() or get_tree().paused:
		return
	var stream := AudioManager.get_stream(AudioManager._pick_variant(shot[0]))
	if stream == null:
		return
	var a := _rng.randf() * TAU
	var d := _rng.randf_range(SHOT_DIST.x, SHOT_DIST.y)
	_shot_player.stream = stream
	_shot_player.volume_db = float(shot[1])
	_shot_player.pitch_scale = _rng.randf_range(0.92, 1.08)
	_shot_player.global_position = _player.global_position + Vector3(cos(a) * d, _rng.randf_range(1.5, 5.0), sin(a) * d)
	_shot_player.play()
