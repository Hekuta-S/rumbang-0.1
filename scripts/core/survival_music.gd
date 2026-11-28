class_name SurvivalMusic
extends Node

## Música adaptativa de SUPERVIVENCIA: empieza chill y se va poniendo hard con el tiempo de partida.
## Cuatro pistas de la misma canción (tools/generate_survival_soundtrack.py), cada una en su AudioStreamPlayer;
## este nodo sube cada capa según GameState.elapsed_time:
##   0 base   siempre (pads, piano, campana)
##   1 groove entra hacia el minuto 1 (bombo lo-fi, charles, arpegio)
##   2 drive  hacia los 2:40 (bajo pulsado, palmas, melodía)
##   3 hard   hacia los 4:45 (riff distorsionado, bombo a negras, platos); el jefe (430 s) ya la tiene entera
## En el modo infinito todo suena a tope. Mientras pocas capas suenan se compensa algo de volumen para que
## el arranque chill no quede demasiado bajo frente a la mezcla completa.
##
## RENDIMIENTO (móvil): una capa en silencio está PARADA, no a -60 dB, así que no se decodifica ni se mezcla
## (con AudioStreamSynchronized se decodificaban las 4 siempre). Al entrar arranca en la posición exacta de la
## base (siguiente bloque de mezcla) y cada segundo se corrige si se desvía. Base y drive se importan a 22 kHz
## (sin agudos que perder): menos memoria y menos remuestreo.

const STEMS := [
	"res://assets/audio/survival/surv_0_base.wav",
	"res://assets/audio/survival/surv_1_groove.wav",
	"res://assets/audio/survival/surv_2_drive.wav",
	"res://assets/audio/survival/surv_3_hard.wav",
]
## [inicio, fin] del fundido de entrada de cada capa, en segundos de partida.
const LAYER_FADES := [[0.0, 0.0], [50.0, 80.0], [150.0, 190.0], [270.0, 310.0]]
const SILENT_DB := -60.0
## Peso por debajo del cual la capa se para (no gasta CPU).
const SILENT_WEIGHT := 0.002
## dB extra cuando solo suena la base (va bajando a 0 cuando entran todas).
const CHILL_BOOST_DB := 5.0
## Velocidad del suavizado de volumen (por segundo).
const SMOOTH := 1.5
## Desfase máximo tolerado entre una capa y la base antes de recolocarla (s).
const MAX_DRIFT := 0.03
const DRIFT_CHECK := 1.0

## Volumen general (lo baja UIManager al subir de nivel); cada capa suma su propio volumen encima.
var master_db := -8.0
var players: Array[AudioStreamPlayer] = []
var _weights: Array[float] = [1.0, 0.0, 0.0, 0.0]
var _length := 0.0
var _running := false
var _drift_t := 0.0

## true si las 4 pistas están importadas.
static func available() -> bool:
	for p in STEMS:
		if not ResourceLoader.exists(p):
			return false
	return true

## Peso (0..1) de cada capa a los `t` segundos de partida.
static func layer_weights(t: float, endless: bool) -> Array[float]:
	var out: Array[float] = []
	for f in LAYER_FADES:
		var a: float = f[0]
		var b: float = f[1]
		if endless:
			out.append(1.0)
		elif b <= a:
			out.append(1.0 if t >= a else 0.0)
		else:
			out.append(clampf((t - a) / (b - a), 0.0, 1.0))
	return out

## Volumen (dB) de la capa `i` con esos pesos: curva de potencia igual y compensación del arranque chill.
static func layer_db(i: int, w: Array[float]) -> float:
	if w[i] <= SILENT_WEIGHT:
		return SILENT_DB
	var energy := 0.0
	for x in w:
		energy += x
	# 1 capa = +CHILL_BOOST_DB; 4 capas = 0 dB
	var boost := CHILL_BOOST_DB * clampf((float(w.size()) - energy) / float(w.size() - 1), 0.0, 1.0)
	return linear_to_db(sqrt(w[i])) + boost

func _ready() -> void:
	for i in STEMS.size():
		var p := AudioStreamPlayer.new()
		p.stream = load(STEMS[i])
		p.bus = "Music" if AudioServer.get_bus_index("Music") >= 0 else "Master"
		p.name = "Layer%d" % i
		add_child(p)
		players.append(p)
	_length = players[0].stream.get_length()

## Arranca la canción desde el principio con las capas que tocan ahora.
func play() -> void:
	_running = true
	_weights = _target()
	players[0].volume_db = master_db + layer_db(0, _weights)
	players[0].play()
	for i in range(1, players.size()):
		players[i].stop()
	# las demás entran en _process, ya alineadas con la base

func stop() -> void:
	_running = false
	for p in players:
		p.stop()

func is_playing() -> bool:
	return _running and players.size() > 0 and players[0].playing

## Capas que se están decodificando ahora (para tests y bench).
func active_layers() -> int:
	var c := 0
	for p in players:
		if p.playing:
			c += 1
	return c

func _target() -> Array[float]:
	var gs := GameState.get_instance()
	var scene := get_tree().current_scene if is_inside_tree() else null
	var facade = scene.get("facade") if scene else null
	var wm = facade.wave_manager if facade != null else null
	var endless: bool = wm != null and bool(wm.endless)
	return layer_weights(gs.elapsed_time if gs else 0.0, endless)

## Una capa nueva arranca en el próximo bloque de mezcla, y get_playback_position() de la base ya da la
## posición donde empieza ese bloque: basta copiarla (sumarle el bloque la adelantaba ~93 ms, medido).
func _start_synced(i: int) -> void:
	players[i].play(fposmod(players[0].get_playback_position(), _length))

func _process(delta: float) -> void:
	if not _running or players.is_empty() or not players[0].playing:
		return
	var target := _target()
	var k := clampf(delta * SMOOTH, 0.0, 1.0)
	for i in _weights.size():
		_weights[i] = lerpf(_weights[i], target[i], k)
		if target[i] <= SILENT_WEIGHT and _weights[i] < SILENT_WEIGHT * 5.0:
			_weights[i] = 0.0       # que termine de apagarse y se pare
	_drift_t -= delta
	var check := _drift_t <= 0.0
	if check:
		_drift_t = DRIFT_CHECK
	var base_pos := players[0].get_playback_position()
	for i in players.size():
		var p := players[i]
		var db := layer_db(i, _weights)
		if i > 0:
			if db <= SILENT_DB:
				if p.playing:
					p.stop()
				continue
			if not p.playing:
				_start_synced(i)
			elif check:
				var d := absf(p.get_playback_position() - base_pos)
				if minf(d, _length - d) > MAX_DRIFT:
					_start_synced(i)
		p.volume_db = master_db + db
