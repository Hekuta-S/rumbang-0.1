class_name DayNightCycle
extends Node

## Ciclo día → noche del modo supervivencia.
##  - La partida empieza a pleno día y se va oscureciendo con el tiempo de partida (GameState.elapsed_time):
##    tarde dorada, atardecer, anochecer y, al llegar el jefe (WaveManager.BOSS_TIME_S), la noche de siempre.
##  - La noche final son los valores que trae la escena (main_procedural.tscn), así que el clímax se ve igual
##    que antes. A partir de ahí (modo infinito) se queda de noche.
##  - Toca el sol (color, fuerza, altura), el cielo procedural, la luz ambiente, la niebla y la fuerza de las
##    luces del mapa (los braseros casi no se notan de día). Se recalcula cada UPDATE_EVERY s: cambiar el cielo
##    obliga a rehacer su mapa de radiancia, así que no se toca en cada frame.
## Uso: DayNightCycle.new() → add_child → setup(world_environment, sol, mapa).

const UPDATE_EVERY := 0.5
const UPDATE_EVERY_MOBILE := 1.5
const MIN_STEP := 0.002               ## si la fase avanzó menos que esto, no se reaplica

## Fotogramas clave (t = fracción del camino hasta la noche). La última (t = 1) se rellena con la escena.
##  sun: color del sol · energy: fuerza · elev: altura del sol en grados · top/hor: cielo arriba/horizonte
##  ghor/gbot: suelo del cielo · amb: fuerza de la luz ambiente · fog: color de niebla · fog_k: densidad
##  relativa a la de la escena · lights: fuerza de las luces del mapa · sat: saturación final
const KEYS: Array = [
	{"t": 0.0, "sun": Color(1.0, 0.96, 0.88), "energy": 2.3, "elev": 58.0,
		"top": Color(0.24, 0.46, 0.82), "hor": Color(0.62, 0.72, 0.84), "ghor": Color(0.42, 0.45, 0.46), "gbot": Color(0.12, 0.13, 0.12),
		"amb": 0.85, "fog": Color(0.62, 0.7, 0.8), "fog_k": 0.18, "lights": 0.2, "sat": 1.0},
	{"t": 0.42, "sun": Color(1.0, 0.86, 0.66), "energy": 2.1, "elev": 34.0,
		"top": Color(0.2, 0.36, 0.68), "hor": Color(0.82, 0.7, 0.56), "ghor": Color(0.42, 0.38, 0.33), "gbot": Color(0.11, 0.1, 0.09),
		"amb": 0.85, "fog": Color(0.66, 0.62, 0.56), "fog_k": 0.25, "lights": 0.3, "sat": 1.02},
	{"t": 0.7, "sun": Color(1.0, 0.62, 0.38), "energy": 1.7, "elev": 9.0,
		"top": Color(0.12, 0.13, 0.3), "hor": Color(0.86, 0.38, 0.22), "ghor": Color(0.32, 0.17, 0.14), "gbot": Color(0.06, 0.05, 0.06),
		"amb": 1.0, "fog": Color(0.42, 0.28, 0.3), "fog_k": 0.5, "lights": 0.65, "sat": 1.0},
	{"t": 0.86, "sun": Color(0.55, 0.48, 0.8), "energy": 0.6, "elev": 3.0,
		"top": Color(0.04, 0.05, 0.13), "hor": Color(0.3, 0.16, 0.24), "ghor": Color(0.14, 0.09, 0.14), "gbot": Color(0.03, 0.03, 0.05),
		"amb": 1.4, "fog": Color(0.2, 0.14, 0.24), "fog_k": 0.85, "lights": 0.95, "sat": 0.95},
]

var duration := WaveManager.BOSS_TIME_S   ## segundos de partida hasta la noche cerrada

var _env: Environment
var _sky_mat: ProceduralSkyMaterial
var _sun: DirectionalLight3D
var _map: Node
var _keys: Array = []
var _yaw := 0.0
var _acc := 0.0
var _every := UPDATE_EVERY
var _last_t := -1.0
var _fog_density := 0.006          ## densidad de niebla de la escena (la de la noche)
var phase := 0.0                      ## 0 = mediodía, 1 = noche (lo leen tests/otros sistemas)

func setup(we: WorldEnvironment, sun: DirectionalLight3D, map: Node = null) -> void:
	_sun = sun
	_map = map
	_every = UPDATE_EVERY_MOBILE if Quality.is_mobile() else UPDATE_EVERY
	if we and we.environment:
		# Copia propia: el Environment es un subrecurso de la escena (compartido y cacheado); si se tocara
		# el original, al reiniciar la partida se leería como "noche" el cielo a medio cambiar.
		_env = we.environment.duplicate(true) as Environment
		we.environment = _env
		if _env.sky:
			_env.sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
			_sky_mat = _env.sky.sky_material as ProceduralSkyMaterial
	_keys = KEYS.duplicate(true)
	_keys.append(_night_key())
	_last_t = -1.0
	apply(_progress())

## La noche = cómo viene la escena (el sol se toma como luna: misma dirección y color frío).
func _night_key() -> Dictionary:
	var k := {"t": 1.0, "sun": Color(0.72, 0.78, 1.0), "energy": 1.9, "elev": 30.0,
		"top": Color(0.015, 0.02, 0.06), "hor": Color(0.11, 0.09, 0.18), "ghor": Color(0.08, 0.07, 0.13), "gbot": Color(0.02, 0.02, 0.04),
		"amb": 1.9, "fog": Color(0.1, 0.11, 0.2), "fog_k": 1.0, "lights": 1.0, "sat": 0.92}
	if _sun:
		k["sun"] = _sun.light_color
		k["energy"] = _sun.light_energy
		var dir := -_sun.global_transform.basis.z           # hacia donde apunta la luz
		k["elev"] = rad_to_deg(asin(clampf(-dir.y, -1.0, 1.0)))
		_yaw = atan2(-dir.x, -dir.z)
	if _env:
		k["amb"] = _env.ambient_light_energy
		k["fog"] = _env.fog_light_color
		k["sat"] = _env.adjustment_saturation if _env.adjustment_enabled else 1.0
		_fog_density = _env.fog_density
	if _sky_mat:
		k["top"] = _sky_mat.sky_top_color
		k["hor"] = _sky_mat.sky_horizon_color
		k["ghor"] = _sky_mat.ground_horizon_color
		k["gbot"] = _sky_mat.ground_bottom_color
	return k

func _progress() -> float:
	var gs := GameState.get_instance()
	var e: float = gs.elapsed_time if gs else 0.0
	return clampf(e / maxf(duration, 1.0), 0.0, 1.0)

func _process(delta: float) -> void:
	_acc += delta
	if _acc < _every:
		return
	_acc = 0.0
	var t := _progress()
	if absf(t - _last_t) >= MIN_STEP or (t >= 1.0 and _last_t < 1.0):
		apply(t)

## Aplica el estado del cielo para la fase t (0 = día, 1 = noche).
func apply(t: float) -> void:
	_last_t = t
	phase = t
	var i := 0
	while i < _keys.size() - 2 and t > float(_keys[i + 1]["t"]):
		i += 1
	var a: Dictionary = _keys[i]
	var b: Dictionary = _keys[i + 1]
	var f := smoothstep(0.0, 1.0, clampf((t - float(a["t"])) / maxf(float(b["t"]) - float(a["t"]), 0.0001), 0.0, 1.0))
	if _sun:
		_sun.light_color = (a["sun"] as Color).lerp(b["sun"], f)
		_sun.light_energy = lerpf(a["energy"], b["energy"], f)
		var elev := deg_to_rad(lerpf(a["elev"], b["elev"], f))
		var pos := _sun.global_position
		var dir := Vector3(-sin(_yaw) * cos(elev), -sin(elev), -cos(_yaw) * cos(elev))
		_sun.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.FORWARD), pos)
	if _sky_mat:
		_sky_mat.sky_top_color = (a["top"] as Color).lerp(b["top"], f)
		_sky_mat.sky_horizon_color = (a["hor"] as Color).lerp(b["hor"], f)
		_sky_mat.ground_horizon_color = (a["ghor"] as Color).lerp(b["ghor"], f)
		_sky_mat.ground_bottom_color = (a["gbot"] as Color).lerp(b["gbot"], f)
	if _env:
		_env.ambient_light_energy = lerpf(a["amb"], b["amb"], f)
		_env.fog_light_color = (a["fog"] as Color).lerp(b["fog"], f)
		_env.fog_density = _fog_density * lerpf(a["fog_k"], b["fog_k"], f)
		if _env.adjustment_enabled:
			_env.adjustment_saturation = lerpf(a["sat"], b["sat"], f)
	if _map and is_instance_valid(_map) and "light_scale" in _map:
		_map.light_scale = lerpf(a["lights"], b["lights"], f)
