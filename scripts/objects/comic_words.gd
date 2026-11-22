class_name ComicWords
extends Node

## Onomatopeyas de cómic al golpear (¡ZAS!, SLASH!, ¡TAJO!...): sprites ya dibujados con su tinta
## (tools/make_comic_words.py → res://assets/textures/toon/words/<grupo>_<n>.png), sin shaders propios.
## HitFeedback crea uno como hijo y llama a pop() en cada impacto; aquí se decide si el arma tiene palabras,
## se limita el ritmo (en hordas saldrían decenas por segundo) y se reutilizan POOL sprites.
## Cada grupo tiene primero las palabras de golpe normal y después las de remate (baja o golpe pesado).

const DIR := "res://assets/textures/toon/words/"
const W := WeaponData.WeaponType
## grupo -> cuántas palabras de golpe y cuántas de remate hay (mismo orden que WORDS en el generador)
const GROUPS := {
	"sword": {"hit": 5, "kill": 2},
	"mace": {"hit": 5, "kill": 2},
	"fist": {"hit": 5, "kill": 2},
}
const WEAPON_GROUP := {
	W.SWORD: "sword", W.GREATSWORD: "sword", W.KATANA: "sword", W.ENERGY_SWORD: "sword",
	W.MACE: "mace", W.GIANT_MACE: "mace",
	W.FISTS: "fist",
}
const POOL := 5
const GAP_FULL_MS := 150          ## mazmorra: casi una por golpe
const GAP_LIGHT_MS := 450         ## supervivencia (perfil "light"): como mucho dos por segundo
const LIFE := 0.6                 ## s en pantalla
const PIXEL_SIZE := 0.002         ## 512 px ≈ 1 m de ancho
const HEAVY_POWER := 0.75

## false: sin onomatopeyas (ajuste o comparación)
static var enabled := true

var _sprites: Array[Sprite3D] = []
var _tweens: Array[Tween] = []
var _idx := 0
var _last_ms := -100000
var _last_word := -1
var _tex: Dictionary = {}

## Sprites y texturas se preparan al crear el nodo, no en el primer golpe (era un tirón en mitad del combo).
func _ready() -> void:
	_sprite()
	_idx = 0
	for group in GROUPS:
		for i in int(GROUPS[group]["hit"]) + int(GROUPS[group]["kill"]):
			_texture(group, i)

static func group_of(weapon: int) -> String:
	return String(WEAPON_GROUP.get(weapon, ""))

## Muestra una palabra en el punto del impacto. Devuelve si salió (false: arma sin palabras o muy seguidas).
func pop(weapon: int, pos: Vector3, dir: Vector3, power: float, killed: bool, light: bool) -> bool:
	if not enabled:
		return false
	var group := group_of(weapon)
	if group == "":
		return false
	var now := Time.get_ticks_msec()
	if now - _last_ms < (GAP_LIGHT_MS if light else GAP_FULL_MS):
		return false
	_last_ms = now
	var counts: Dictionary = GROUPS[group]
	var big := killed or power >= HEAVY_POWER
	var n: int = counts["kill"] if big else counts["hit"]
	var first: int = counts["hit"] if big else 0
	var word := first + randi() % n
	if word == _last_word and n > 1:              # no repetir la misma dos veces seguidas
		word = first + (word - first + 1) % n
	_last_word = word
	var tex := _texture(group, word)
	if tex == null:
		return false
	var s := _sprite()
	s.texture = tex
	# Al lado del golpe y algo por encima, para no tapar al enemigo
	var side := dir.cross(Vector3.UP)
	if side.length_squared() < 0.001:
		side = Vector3.RIGHT
	var start := pos + side.normalized() * randf_range(-0.55, 0.55) + Vector3(0.0, randf_range(0.55, 0.9), 0.0)
	var size := (1.15 if big else 0.8) * (0.85 + 0.3 * clampf(power, 0.0, 1.0))
	s.global_position = start
	s.scale = Vector3.ONE * size * 0.3
	s.modulate = Color(1, 1, 1, 1)
	s.visible = true
	var i := _sprites.find(s)
	if _tweens[i] != null and _tweens[i].is_valid():
		_tweens[i].kill()
	var tw := create_tween()
	_tweens[i] = tw
	# golpe de escala (entra grande y asienta), sube despacio y se apaga al final
	tw.tween_property(s, "scale", Vector3.ONE * size * 1.25, 0.07).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(s, "scale", Vector3.ONE * size, 0.07)
	tw.parallel().tween_property(s, "global_position", start + Vector3(0.0, 0.3, 0.0), LIFE - 0.07)
	tw.parallel().tween_property(s, "modulate:a", 0.0, 0.2).set_delay(LIFE - 0.27)
	tw.tween_callback(s.hide)
	return true

func _texture(group: String, word: int) -> Texture2D:
	var path := "%s%s_%d.png" % [DIR, group, word]
	if not _tex.has(path):
		_tex[path] = load(path) if ResourceLoader.exists(path) else null
	return _tex[path]

func _sprite() -> Sprite3D:
	if _sprites.is_empty():
		for i in POOL:
			var s := Sprite3D.new()
			s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			s.shaded = false
			s.no_depth_test = true                 # siempre por delante, como una viñeta
			s.double_sided = false
			s.pixel_size = PIXEL_SIZE
			s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			s.render_priority = 20
			s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			s.visible = false
			add_child(s)
			_sprites.append(s)
			_tweens.append(null)
	var out := _sprites[_idx]
	_idx = (_idx + 1) % POOL
	return out
