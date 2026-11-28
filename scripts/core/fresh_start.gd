class_name FreshStart
extends RefCounted

## Borrado único de los datos de jugador al instalar una versión nueva: todos vuelven a empezar como la
## primera vez y ven la intro completa. Para repetirlo en otra versión, sube RESET_VERSION.
## Conserva ajustes (settings.json) y la config de red (net.cfg). Se llama desde GameData._init, antes de que
## ningún autoload lea sus archivos.

const RESET_VERSION := 1
const MARKER := "user://fresh_start.cfg"
const WIPE := [
	"user://soul_knight_save.json",
	"user://dungeon_hub.cfg",
	"user://armeria.cfg",
	"user://personaje.cfg",
	"user://dungeon_runs.json",
]

static func run() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(MARKER) == OK and int(cfg.get_value("reset", "version", 0)) >= RESET_VERSION:
		return
	for p in WIPE:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	var skin := DirAccess.open("user://clothing_skin")
	if skin:
		for f in skin.get_files():
			skin.remove(f)
	cfg.set_value("reset", "version", RESET_VERSION)
	cfg.save(MARKER)
