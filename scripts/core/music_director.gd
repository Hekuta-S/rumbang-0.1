## MusicDirector.gd — Autoload. Música de ambiente por contexto con fundido cruzado.
## - play("hub" | "patio")  → tema tranquilo (tools/generate_chill_soundtrack.gd); no reinicia si ya suena.
## - stop(fade)             → lo apaga (la partida arranca su propia música: UIManager.start_music lo llama).
## Mazmorra y supervivencia siguen con su reproductor propio (UIManager), con el tema darksynth de siempre.
extends Node

const TRACKS := {
	"hub": {"path": "res://assets/audio/hub_theme.wav", "db": -12.0},
	"patio": {"path": "res://assets/audio/patio_theme.wav", "db": -12.0},
}
const FADE := 1.5

var current := ""
var _player: AudioStreamPlayer
var _tween: Tween

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = AudioStreamPlayer.new()
	_player.bus = "Music" if AudioServer.get_bus_index("Music") >= 0 else "Master"
	_player.finished.connect(func(): if current != "": _player.play())   # bucle de respaldo
	add_child(_player)

func play(track: String) -> void:
	if track == current or not TRACKS.has(track):
		return
	var def: Dictionary = TRACKS[track]
	if not ResourceLoader.exists(def["path"]):
		return
	current = track
	_kill_tween()
	var swap := func():
		_player.stream = load(def["path"])
		_player.volume_db = -60.0
		_player.play()
	_tween = create_tween()
	if _player.playing:
		_tween.tween_property(_player, "volume_db", -60.0, FADE * 0.5)
	_tween.tween_callback(swap)
	_tween.tween_property(_player, "volume_db", float(def["db"]), FADE)

func stop(fade: float = 0.6) -> void:
	if current == "":
		return
	current = ""
	_kill_tween()
	_tween = create_tween()
	_tween.tween_property(_player, "volume_db", -60.0, fade)
	_tween.tween_callback(_player.stop)

func _kill_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
