## AudioManager.gd — Autoload Singleton
## Plays the procedurally generated SFX in assets/sfx/.
## - play(name)           → 2D sound (UI, global events)
## - play_at(name, pos)   → 3D positional sound (world events)
extends Node

const SFX_DIR := "res://assets/sfx/"
const POOL_3D_SIZE: int = 16

var _stream_cache: Dictionary = {}
var _pool_3d: Array[AudioStreamPlayer3D] = []
var _pool_3d_index: int = 0

## Límite de voces: máx. MAX_VOICES_PER_SFX sonidos 2D iguales a la vez y MIN_GAP_MS entre repeticiones
## del mismo sonido (evita saturar el mezclador con muchos golpes/disparos iguales, sobre todo en móvil).
const MAX_VOICES_PER_SFX: int = 4
const MIN_GAP_MS: int = 40
var _voices: Dictionary = {}
var _last_play_ms: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ensure_buses()

## Variantes: si existen nombre_2, nombre_3... junto a "nombre", cada reproducción elige una al azar
## (una ráfaga de golpes no suena a la misma muestra repetida).
var _variant_count: Dictionary = {}

func _pick_variant(sfx_name: String) -> String:
	if not _variant_count.has(sfx_name):
		var count := 1
		while _exists(sfx_name + "_" + str(count + 1)):
			count += 1
		_variant_count[sfx_name] = count
	var n: int = _variant_count[sfx_name]
	if n <= 1:
		return sfx_name
	var k := randi_range(1, n)
	return sfx_name if k == 1 else sfx_name + "_" + str(k)

func _exists(sfx_name: String) -> bool:
	for ext in [".wav", ".mp3", ".ogg"]:
		if ResourceLoader.exists(SFX_DIR + sfx_name + ext):
			return true
	return false

## Returns the cached AudioStream for a sfx name, or null if missing.
## Un sonido que falta avisa una sola vez y se guarda como null (no se vuelve a buscar ni a cargar).
func get_stream(sfx_name: String) -> AudioStream:
	if _stream_cache.has(sfx_name):
		return _stream_cache[sfx_name]

	var stream: AudioStream = null
	if ResourceLoader.exists(SFX_DIR + sfx_name + ".wav"):
		stream = load(SFX_DIR + sfx_name + ".wav")
	elif ResourceLoader.exists(SFX_DIR + sfx_name + ".mp3"):
		stream = load(SFX_DIR + sfx_name + ".mp3")
	elif ResourceLoader.exists(SFX_DIR + sfx_name + ".ogg"):
		stream = load(SFX_DIR + sfx_name + ".ogg")
	else:
		push_warning("[AudioManager] Falta el sonido %s%s (.wav/.mp3/.ogg)" % [SFX_DIR, sfx_name])

	_stream_cache[sfx_name] = stream
	return stream

## Plays a sound in 2D (UI / global feedback). `bus` "" = según el sonido (UI_SFX van al bus UI; el resto, SFX).
func play(sfx_name: String, volume_db: float = 0.0, pitch_scale: float = 1.0, from_position: float = 0.0, bus: String = "") -> void:
	var stream := get_stream(_pick_variant(sfx_name))
	if stream == null:
		return
	var now := Time.get_ticks_msec()
	if int(_voices.get(sfx_name, 0)) >= MAX_VOICES_PER_SFX or now - int(_last_play_ms.get(sfx_name, -1000)) < MIN_GAP_MS:
		return
	_last_play_ms[sfx_name] = now
	_voices[sfx_name] = int(_voices.get(sfx_name, 0)) + 1
	var player := AudioStreamPlayer.new()
	player.bus = bus if bus != "" else ("UI" if UI_SFX.has(sfx_name) else "SFX")
	player.stream = stream
	player.volume_db = volume_db - 8.0
	player.pitch_scale = pitch_scale * _jitter()
	player.finished.connect(func():
		_voices[sfx_name] = maxi(int(_voices.get(sfx_name, 1)) - 1, 0)
		player.queue_free())
	add_child(player)
	player.play(from_position)
	if DUCK_ON.has(sfx_name):
		duck(float(DUCK_ON[sfx_name][0]), float(DUCK_ON[sfx_name][1]))

## Plays a positional sound in 3D using a small recycled pool.
func play_at(sfx_name: String, world_pos: Vector3, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	var stream := get_stream(_pick_variant(sfx_name))
	if stream == null:
		return
	if _pool_3d.is_empty():
		for i in range(POOL_3D_SIZE):
			var p := AudioStreamPlayer3D.new()
			p.bus = "SFX"
			p.max_distance = 80.0
			p.unit_size = 12.0
			add_child(p)
			_pool_3d.append(p)
	var player := _pool_3d[_pool_3d_index]
	_pool_3d_index = (_pool_3d_index + 1) % POOL_3D_SIZE
	player.stream = stream
	player.volume_db = volume_db - 8.0
	player.pitch_scale = pitch_scale * _jitter()
	player.global_position = world_pos
	player.play()
	if DUCK_ON.has(sfx_name):
		duck(float(DUCK_ON[sfx_name][0]), float(DUCK_ON[sfx_name][1]))

# ───────────────────────────── Mezcla (fase 6 del plan de juice) ─────────────────────────────
## Buses: Master ← Music (con atenuador de ducking + paso bajo), SFX (paso bajo), UI (directo: los menús y el
## latido no se filtran) y Ambient (→ SFX). Los volúmenes de los ajustes van a Music / SFX (y UI = SFX).

## Sonidos de interfaz: al bus UI (sin filtro de vida baja).
const UI_SFX := ["ui_click", "heartbeat"]
## Sonidos que bajan la música al sonar: nombre -> [dB, s que se mantiene].
const DUCK_ON := {"boss_sting": [7.0, 0.9], "king_screech": [4.0, 0.4], "victory": [6.0, 1.5]}
const PITCH_JITTER := 0.015        ## variación aleatoria de tono en cada reproducción (±1,5 %)
const DUCK_ATTACK := 0.04
const DUCK_RELEASE := 0.35
const LOWPASS_OPEN := 20500.0
const LOWPASS_CLOSED := 750.0      ## corte con la vida al mínimo
const DANGER_SMOOTH := 3.0         ## 1/s: lo rápido que entra/sale el filtro
const BEAT_SLOW := 0.95            ## s entre latidos al empezar el peligro
const BEAT_FAST := 0.48            ## y al borde de la muerte

var _duck_fx: AudioEffectAmplify
var _lp_music: AudioEffectLowPassFilter
var _lp_sfx: AudioEffectLowPassFilter
var _duck_tw: Tween
var _duck_depth := 0.0
var _danger_target := 0.0
var _danger := 0.0
var _beat_t := 0.0

static func _jitter() -> float:
	return randf_range(1.0 - PITCH_JITTER, 1.0 + PITCH_JITTER)

## Crea los buses que falten (con sus envíos) y los efectos de mezcla. Se puede llamar varias veces.
func ensure_buses() -> void:
	_bus("SFX", "Master")
	_bus("Music", "Master")
	_bus("UI", "Master")
	_bus("Ambient", "SFX")
	_duck_fx = _effect("Music", AudioEffectAmplify) as AudioEffectAmplify
	_lp_music = _effect("Music", AudioEffectLowPassFilter) as AudioEffectLowPassFilter
	_lp_sfx = _effect("SFX", AudioEffectLowPassFilter) as AudioEffectLowPassFilter
	_apply_danger()

func _bus(bus_name: String, send: String) -> int:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		AudioServer.add_bus()
		idx = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, send)
	return idx

## Devuelve el efecto de clase `cls` del bus (lo añade si no está).
func _effect(bus_name: String, cls) -> AudioEffect:
	var idx := AudioServer.get_bus_index(bus_name)
	for i in AudioServer.get_bus_effect_count(idx):
		var fx := AudioServer.get_bus_effect(idx, i)
		if is_instance_of(fx, cls):
			return fx
	var nfx: AudioEffect = cls.new()
	if nfx is AudioEffectLowPassFilter:
		(nfx as AudioEffectLowPassFilter).cutoff_hz = LOWPASS_OPEN
	AudioServer.add_bus_effect(idx, nfx)
	AudioServer.set_bus_effect_enabled(idx, AudioServer.get_bus_effect_count(idx) - 1, not (nfx is AudioEffectLowPassFilter))
	return nfx

## Baja la música `db` dB casi al instante, la mantiene `hold` s y la recupera en DUCK_RELEASE s.
## Varios a la vez: manda el más profundo. En tiempo real (también durante el hitstop).
func duck(db: float, hold: float = 0.1) -> void:
	if _duck_fx == null:
		return
	if db < _duck_depth and _duck_tw and _duck_tw.is_valid():
		return
	_duck_depth = db
	if _duck_tw and _duck_tw.is_valid():
		_duck_tw.kill()
	_duck_tw = create_tween().set_ignore_time_scale(true)
	_duck_tw.tween_method(_set_duck, _duck_fx.volume_db, -db, DUCK_ATTACK)
	_duck_tw.tween_interval(hold)
	_duck_tw.tween_method(_set_duck, -db, 0.0, DUCK_RELEASE).set_ease(Tween.EASE_OUT)
	_duck_tw.tween_callback(func(): _duck_depth = 0.0)

func _set_duck(v: float) -> void:
	if _duck_fx:
		_duck_fx.volume_db = v

func duck_level_db() -> float:
	return _duck_fx.volume_db if _duck_fx else 0.0

## Peligro por vida baja (0 = nada, 1 = al borde): filtro paso bajo en música y efectos + latido.
func set_danger(k: float) -> void:
	_danger_target = clampf(k, 0.0, 1.0)

## Pura: corte del paso bajo para un nivel de peligro.
static func lowpass_for(k: float) -> float:
	return lerpf(LOWPASS_OPEN, LOWPASS_CLOSED, pow(clampf(k, 0.0, 1.0), 0.6))

## Pura: segundos entre latidos para un nivel de peligro (0 = sin latido).
static func beat_interval(k: float) -> float:
	return 0.0 if k <= 0.01 else lerpf(BEAT_SLOW, BEAT_FAST, clampf(k, 0.0, 1.0))

func _process(delta: float) -> void:
	if is_equal_approx(_danger, _danger_target) and _danger <= 0.0:
		return
	var dt := minf(delta / maxf(Engine.time_scale, 0.05), 0.1)   # tiempo real
	_danger = move_toward(_danger, _danger_target, DANGER_SMOOTH * dt)
	_apply_danger()
	if _danger_target > 0.01 and not get_tree().paused:
		_beat_t -= dt
		if _beat_t <= 0.0:
			_beat_t = beat_interval(_danger_target)
			play("heartbeat", lerpf(-12.0, -2.0, _danger_target), 1.0, 0.0, "UI")
	else:
		_beat_t = 0.0

func _apply_danger() -> void:
	var on := _danger > 0.001
	var cut := lowpass_for(_danger)
	for pair in [["Music", _lp_music], ["SFX", _lp_sfx]]:
		var fx: AudioEffectLowPassFilter = pair[1]
		if fx == null:
			continue
		fx.cutoff_hz = cut
		var idx := AudioServer.get_bus_index(pair[0])
		for i in AudioServer.get_bus_effect_count(idx):
			if AudioServer.get_bus_effect(idx, i) == fx:
				AudioServer.set_bus_effect_enabled(idx, i, on)
