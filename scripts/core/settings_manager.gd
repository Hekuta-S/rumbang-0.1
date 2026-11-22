extends Node

const SETTINGS_PATH := "user://settings.json"

var master_vol: float = 0.5
var sfx_vol: float = 0.5
var music_vol: float = 0.5
## Calidad gráfica guardada (Quality.Level); -1 = automática según la plataforma.
var quality_level: int = -1
## Marcas en el suelo de los ataques enemigos (mazmorra). Sin ellas siguen el destello, la pose y el sonido.
var show_attack_marks: bool = true
## Tope de FPS en móvil: 0 = automático (60, o 30 en calidad Baja), 30 o 60. Un móvil que se calienta rinde mejor a 30.
var mobile_fps: int = 0
## V-Sync. Apagado, el juego no espera al refresco de la pantalla (más FPS, posible "tearing"). Algunos móviles
## no dejan apagarlo: ver Quality.apply_vsync().
var vsync: bool = true
## Resolución: -1 automática (reducida en móviles de gama baja, Quality.auto_resolution), 0 nativa, 1 reducida,
## 2-5 fija a 1080p/900p/720p/540p (Quality.RES_*).
var resolution: int = -1
## Versión del campo "resolution" en settings.json (ver apply_data: migración del 0 viejo).
const RES_SAVE_VERSION := 2
const RES_NATIVE_LEGACY := 0

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
		apply_data(parsed)

## Carga los valores de un settings.json ya leído (separado para probarlo sin tocar el disco).
func apply_data(data: Dictionary) -> void:
	master_vol = data.get("master", 0.5)
	sfx_vol = data.get("sfx", 0.5)
	music_vol = data.get("music", 0.5)
	quality_level = int(data.get("quality", -1))
	show_attack_marks = bool(data.get("attack_marks", true))
	vsync = bool(data.get("vsync", true))
	var res := int(data.get("resolution", -1))
	# Antes del 2026-11-19 se guardaba siempre 0 (nativa) aunque nadie la eligiera: sin la marca res_v ese 0
	# se lee como automático, para que un móvil de gama baja reciba la resolución reducida.
	if res == RES_NATIVE_LEGACY and int(data.get("res_v", 0)) < RES_SAVE_VERSION:
		res = -1
	resolution = res if res >= 0 and res < Quality.RES_COUNT else -1
	mobile_fps = int(data.get("fps_cap", 0)) if int(data.get("fps_cap", 0)) in [30, 60] else 0
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
	file.store_string(JSON.stringify(to_payload()))

func to_payload() -> Dictionary:
	return {
		"master": master_vol,
		"sfx": sfx_vol,
		"music": music_vol,
		"quality": quality_level,
		"attack_marks": show_attack_marks,
		"fps_cap": mobile_fps,
		"vsync": vsync,
		"resolution": resolution,
		"res_v": RES_SAVE_VERSION,
		"look_sens": look_sensitivity,
		"touch_look_sens": touch_look_sensitivity,
		"touch_scale": touch_scale,
		"touch_opacity": touch_opacity,
		"touch_hidden": touch_hidden,
		"touch_custom": touch_custom
	}

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
	
	Quality.apply_vsync(vsync)
	Quality.apply_resolution(resolution if resolution >= 0 else Quality.auto_resolution())
	set_bus_volume("Master", master_vol)
	set_bus_volume("SFX", sfx_vol)
	set_bus_volume("Music", music_vol)
	set_bus_volume("UI", sfx_vol)        # la interfaz sigue al volumen de efectos (va por su propio bus, sin filtro)

func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) == -1:
		AudioServer.add_bus()
		var new_idx := AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(new_idx, bus_name)
		AudioServer.set_bus_send(new_idx, "Master")
