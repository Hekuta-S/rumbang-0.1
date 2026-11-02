extends Node

const SETTINGS_PATH := "user://settings.json"

var master_vol: float = 0.5
var sfx_vol: float = 0.5
var music_vol: float = 0.5
## Calidad gráfica guardada (Quality.Level); -1 = automática según la plataforma.
var quality_level: int = -1
## Marcas en el suelo de los ataques enemigos (mazmorra). Sin ellas siguen el destello, la pose y el sonido.
var show_attack_marks: bool = true

## Sensibilidad de la cámara (multiplicador de la base): ratón/mando y arrastre táctil por separado.
const SENS_MIN := 0.25
const SENS_MAX := 3.0
var look_sensitivity: float = 1.0
var touch_look_sensitivity: float = 1.0
## Controles táctiles: tamaño (× el automático), opacidad y botones ocultos (claves de MobileControls.BUTTONS).
const TOUCH_SCALE_MIN := 0.6
const TOUCH_SCALE_MAX := 1.6
var touch_scale: float = 1.0
var touch_opacity: float = 1.0
var touch_hidden: Array = []
## Disposición personalizada por botón (y "joystick"): {clave: {x, y (centro, fracción de la pantalla), s (tamaño ×)}}.
var touch_custom: Dictionary = {}

signal touch_layout_changed
## Ajustes pide abrir el editor de disposición de MobileControls; éste avisa al terminar.
signal touch_edit_requested
signal touch_edit_finished

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	call_deferred("_apply_all")

func load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		var data: Dictionary = parsed
		master_vol = data.get("master", 0.5)
		sfx_vol = data.get("sfx", 0.5)
		music_vol = data.get("music", 0.5)
		quality_level = int(data.get("quality", -1))
		show_attack_marks = bool(data.get("attack_marks", true))
		look_sensitivity = clampf(float(data.get("look_sens", 1.0)), SENS_MIN, SENS_MAX)
		touch_look_sensitivity = clampf(float(data.get("touch_look_sens", 1.0)), SENS_MIN, SENS_MAX)
		touch_scale = clampf(float(data.get("touch_scale", 1.0)), TOUCH_SCALE_MIN, TOUCH_SCALE_MAX)
		touch_opacity = clampf(float(data.get("touch_opacity", 1.0)), 0.2, 1.0)
		var hidden: Variant = data.get("touch_hidden", [])
		touch_hidden = hidden if hidden is Array else []
		var custom: Variant = data.get("touch_custom", {})
		touch_custom = custom if custom is Dictionary else {}

func save_settings() -> void:
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		return
	var payload := {
		"master": master_vol,
		"sfx": sfx_vol,
		"music": music_vol,
		"quality": quality_level,
		"attack_marks": show_attack_marks,
		"look_sens": look_sensitivity,
		"touch_look_sens": touch_look_sensitivity,
		"touch_scale": touch_scale,
		"touch_opacity": touch_opacity,
		"touch_hidden": touch_hidden,
		"touch_custom": touch_custom
	}
	file.store_string(JSON.stringify(payload))

func set_bus_volume(bus_name: String, vol_linear: float) -> void:
	# Convert 0.0-1.0 linear volume to Decibels (-80 to 0)
	var db: float = linear_to_db(vol_linear) if vol_linear > 0.001 else -80.0
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, db)
		AudioServer.set_bus_mute(idx, vol_linear <= 0.001)

func _apply_all() -> void:
	# Ensure SFX and Music buses exist
	_ensure_bus("SFX")
	_ensure_bus("Music")
	
	set_bus_volume("Master", master_vol)
	set_bus_volume("SFX", sfx_vol)
	set_bus_volume("Music", music_vol)

func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) == -1:
		AudioServer.add_bus()
		var new_idx := AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(new_idx, bus_name)
		AudioServer.set_bus_send(new_idx, "Master")
