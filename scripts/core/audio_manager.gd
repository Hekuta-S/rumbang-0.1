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

## Returns the cached AudioStream for a sfx name, or null if missing.
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
		# Fallback in case it's packaged differently or exact path is needed
		stream = load(SFX_DIR + sfx_name + ".wav")

	if stream:
		_stream_cache[sfx_name] = stream
	return stream

## Plays a sound in 2D (UI / global feedback).
func play(sfx_name: String, volume_db: float = 0.0, pitch_scale: float = 1.0, from_position: float = 0.0) -> void:
	var stream := get_stream(sfx_name)
	if stream == null:
		return
	var now := Time.get_ticks_msec()
	if int(_voices.get(sfx_name, 0)) >= MAX_VOICES_PER_SFX or now - int(_last_play_ms.get(sfx_name, -1000)) < MIN_GAP_MS:
		return
	_last_play_ms[sfx_name] = now
	_voices[sfx_name] = int(_voices.get(sfx_name, 0)) + 1
	var player := AudioStreamPlayer.new()
	player.bus = "SFX"
	player.stream = stream
	player.volume_db = volume_db - 8.0
	player.pitch_scale = pitch_scale
	player.finished.connect(func():
		_voices[sfx_name] = maxi(int(_voices.get(sfx_name, 1)) - 1, 0)
		player.queue_free())
	add_child(player)
	player.play(from_position)

## Plays a positional sound in 3D using a small recycled pool.
func play_at(sfx_name: String, world_pos: Vector3, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	var stream := get_stream(sfx_name)
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
	player.pitch_scale = pitch_scale
	player.global_position = world_pos
	player.play()