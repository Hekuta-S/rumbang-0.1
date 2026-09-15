extends Node

const SETTINGS_PATH := "user://settings.json"

var master_vol: float = 0.5
var sfx_vol: float = 0.5
var music_vol: float = 0.5

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

func save_settings() -> void:
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		return
	var payload := {
		"master": master_vol,
		"sfx": sfx_vol,
		"music": music_vol
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
