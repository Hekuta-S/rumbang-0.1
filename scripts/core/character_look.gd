class_name CharacterLook
extends RefCounted

## Apariencia del personaje personalizable (humano de MakeHuman sobre el esqueleto de Riva, ver
## tools/blender_riva_human.py): nombre, colores (piel, pelo, ojos, calzones...), peinado, accesorios
## (gorros, calzado) y proporciones. Se guarda en user://personaje.cfg y viaja por la red
## como Dictionary (to_dict / from_dict). Lo aplica CharacterLookApplier sobre el modelo.

const CHAR_ID := "riva"                         ## único personaje jugable
const SAVE_PATH := "user://personaje.cfg"
const NAME_MAX := 16

## Zonas de color: [clave, etiqueta, color por defecto]. Cada una es un material del modelo base
## (riva-base.fbx, hecho con tools/blender_riva_base.py) o de un accesorio.
const COLOR_SLOTS := [
	["skin", "Piel", Color(0.93, 0.80, 0.70)],
	["hair", "Cabello", Color(0.10, 0.11, 0.16)],
	["eyes", "Ojos", Color(0.32, 0.20, 0.10)],
	["underwear", "Calzones", Color(0.20, 0.35, 0.80)],
	["waistband", "Elástico", Color(0.95, 0.95, 0.95)],
	["shoes", "Calzado", Color(0.40, 0.25, 0.12)],
	["shoes_accent", "Calzado (detalle)", Color(0.25, 0.15, 0.08)],
	["sole", "Suela", Color(0.92, 0.90, 0.85)],
	["hat", "Gorro", Color(0.78, 0.16, 0.16)],
	["hat2", "Gorro (detalle)", Color(0.95, 0.95, 0.95)],
]

## Peinados: mallas Pelo_<id> del modelo base (se muestra solo la elegida; "rapado" = ninguna)
## Los que no son mallas del modelo base son modelos suelto (assets/models/riva/peinados/<id>.glb) que
## CharacterLookApplier cuelga de la cabeza.
const HAIR_STYLES := {
	"riva": "Despeinado", "rapado": "Al rape",
	"anime": "Anime corto", "estilo1": "Ayato", "estilo2": "Largo", "estilo3": "Kaiya",
	"estilo4": "Kaveh", "estilo5": "Medio", "estilo6": "Corto", "cuernos": "Cuernos",
}
const HATS := {"ninguno": "Sin gorro", "gorro": "Gorro de lana", "gorra": "Gorra", "gorra_atras": "Gorra al revés", "sombrero": "Sombrero"}
const FOOTWEAR := {"descalzo": "Descalzo", "botas": "Botas", "converse": "Converse"}

## Proporciones: [clave, etiqueta, mínimo, máximo].
const PROPORTIONS := [
	["height", "Altura", 0.88, 1.12],
	["build", "Complexión", 0.85, 1.2],
	["head", "Cabeza", 0.85, 1.3],
]

## Colores sugeridos (paleta rápida de la pantalla de personalización y del aleatorio).
const PALETTE := [
	Color(0.10, 0.11, 0.16), Color(0.95, 0.95, 0.95), Color(0.93, 0.56, 0.16), Color(0.78, 0.16, 0.16),
	Color(0.20, 0.45, 0.85), Color(0.15, 0.60, 0.30), Color(0.55, 0.25, 0.75), Color(0.95, 0.80, 0.20),
	Color(0.95, 0.45, 0.65), Color(0.40, 0.25, 0.12), Color(0.45, 0.47, 0.50), Color(0.10, 0.70, 0.75),
]
const SKIN_TONES := [
	Color(0.98, 0.86, 0.76), Color(0.93, 0.80, 0.70), Color(0.85, 0.66, 0.50),
	Color(0.70, 0.50, 0.35), Color(0.52, 0.36, 0.24), Color(0.36, 0.24, 0.16),
]
const EYE_TONES := [
	Color(0.32, 0.20, 0.10), Color(0.18, 0.10, 0.05), Color(0.55, 0.38, 0.18), Color(0.30, 0.45, 0.20),
	Color(0.25, 0.45, 0.75), Color(0.45, 0.55, 0.60), Color(0.10, 0.10, 0.12), Color(0.60, 0.15, 0.20),
]
const HAIR_TONES := [
	Color(0.10, 0.11, 0.16), Color(0.30, 0.18, 0.10), Color(0.62, 0.42, 0.22), Color(0.92, 0.80, 0.45),
	Color(0.75, 0.20, 0.12), Color(0.85, 0.85, 0.88), Color(0.25, 0.45, 0.90), Color(0.90, 0.40, 0.70),
]

var char_name := "Riva"
var colors: Dictionary = {}
var hair_style := "riva"
var hat := "ninguno"
var footwear := "descalzo"
var height := 1.0
var build := 1.0
var head := 1.0

static var _current: CharacterLook

func _init() -> void:
	for s in COLOR_SLOTS:
		colors[s[0]] = s[2]

## Apariencia del jugador local (se carga del disco la primera vez).
static func current() -> CharacterLook:
	if _current == null:
		_current = load_saved()
	return _current

static func set_current(look: CharacterLook) -> void:
	_current = look

func duplicate_look() -> CharacterLook:
	return CharacterLook.from_dict(to_dict())

# ───────────────────────────── serialización ─────────────────────────────

func to_dict() -> Dictionary:
	return {
		"name": char_name, "colors": colors.duplicate(), "hair_style": hair_style, "hat": hat, "footwear": footwear,
		"height": height, "build": build, "head": head,
	}

## Construye una apariencia a partir de un diccionario (del disco o de otro jugador): todo se valida.
static func from_dict(d: Dictionary) -> CharacterLook:
	var l := CharacterLook.new()
	if d.is_empty():
		return l
	l.char_name = sanitize_name(str(d.get("name", l.char_name)))
	var cols: Variant = d.get("colors", {})
	if cols is Dictionary:
		for k in l.colors:
			var c: Variant = cols.get(k)
			if c is Color:
				l.colors[k] = Color(clampf(c.r, 0, 1), clampf(c.g, 0, 1), clampf(c.b, 0, 1))
	l.hair_style = _pick(d.get("hair_style"), HAIR_STYLES, l.hair_style)
	l.hat = _pick(d.get("hat"), HATS, l.hat)
	l.footwear = _pick(d.get("footwear"), FOOTWEAR, l.footwear)
	for p in PROPORTIONS:
		l.set(p[0], clampf(float(d.get(p[0], 1.0)), p[2], p[3]))
	return l

static func _pick(v: Variant, options: Dictionary, fallback: String) -> String:
	var s := str(v) if v != null else ""
	return s if options.has(s) else fallback

static func sanitize_name(s: String) -> String:
	s = s.strip_edges().replace("\n", " ").substr(0, NAME_MAX)
	return s if s != "" else "Riva"

func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("look", "data", to_dict())
	cfg.save(SAVE_PATH)

static func load_saved() -> CharacterLook:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return CharacterLook.new()
	var d: Variant = cfg.get_value("look", "data", {})
	return from_dict(d if d is Dictionary else {})

# ───────────────────────────── utilidades ─────────────────────────────

func color(slot: String) -> Color:
	return colors.get(slot, Color.WHITE)

## Apariencia al azar (respeta el nombre).
func randomize_look(rng: RandomNumberGenerator = null) -> void:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	for s in COLOR_SLOTS:
		colors[s[0]] = PALETTE[rng.randi() % PALETTE.size()]
	colors["skin"] = SKIN_TONES[rng.randi() % SKIN_TONES.size()]
	colors["hair"] = HAIR_TONES[rng.randi() % HAIR_TONES.size()]
	colors["eyes"] = EYE_TONES[rng.randi() % EYE_TONES.size()]
	hair_style = HAIR_STYLES.keys()[rng.randi() % HAIR_STYLES.size()]
	hat = HATS.keys()[rng.randi() % HATS.size()]
	footwear = FOOTWEAR.keys()[rng.randi() % FOOTWEAR.size()]
	for p in PROPORTIONS:
		set(p[0], snappedf(rng.randf_range(lerpf(p[2], 1.0, 0.5), lerpf(1.0, p[3], 0.5)), 0.01))
