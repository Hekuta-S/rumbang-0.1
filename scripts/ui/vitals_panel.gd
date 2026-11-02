class_name VitalsPanel
extends Control

## Vida del jugador, abajo a la izquierda (sustituye a las barras verticales).
## Barra gruesa con "actual / máx."; una barra blanca por detrás marca el daño reciente y se vacía
## tras una breve pausa; destello verde al curarse; con poca vida late en rojo.
## Debajo van las barras de energía, maná y balas (ResourceBars) en la mazmorra.
## HUD.update_stats() llama a set_values(); el resto son animaciones propias en _process.

const W := 300.0
const HP_H := 24.0
const PAD := 10.0
const HEIGHT := HP_H + PAD * 2.0       ## alto del panel (las barras de recursos van justo debajo)
const RESOURCES_H := 63.0             ## alto de ResourceBars en la mazmorra (debe coincidir con el suyo)
const LOW_HP := 0.3
const TRAIL_DELAY := 0.45             ## pausa antes de que el rastro de daño empiece a bajar (s)
const TRAIL_SPEED := 0.6              ## fracción de la barra por segundo

const HP_COLOR := Color(0.86, 0.16, 0.2)
const HP_COLOR_LOW := Color(1.0, 0.32, 0.25)
const FRAME := Color(0.08, 0.07, 0.09, 0.82)
const BORDER := Color(0.62, 0.56, 0.47)

var _hp := 1.0
var _max_hp := 1.0
var _hp_ratio := 1.0
var _trail := 1.0
var _trail_wait := 0.0
var _heal_flash := 0.0
var _t := 0.0
var _first := true

var _hp_label: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(W + PAD * 2.0, HEIGHT)
	# En móvil, abajo a la izquierda va el joystick virtual: el panel sube arriba a la izquierda
	if Quality.is_mobile():
		set_anchors_preset(Control.PRESET_TOP_LEFT)
		offset_left = 22.0
		offset_top = 22.0
		offset_right = offset_left + custom_minimum_size.x
		offset_bottom = offset_top + custom_minimum_size.y
	else:
		set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		offset_left = 22.0
		offset_right = offset_left + custom_minimum_size.x
		# Por encima de las barras de recursos (mazmorra), que a su vez van sobre el adorno de la barra de armas
		offset_bottom = -64.0 - (RESOURCES_H if GameData.game_mode == "dungeon" else 0.0)
		offset_top = offset_bottom - custom_minimum_size.y
	_hp_label = Label.new()
	_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_label.position = Vector2(PAD + 20.0, PAD)
	_hp_label.size = Vector2(W - 20.0, HP_H)
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hp_label.add_theme_font_size_override("font_size", 14)
	_hp_label.add_theme_color_override("font_color", Color.WHITE)
	_hp_label.add_theme_color_override("font_outline_color", Color(0.15, 0, 0))
	_hp_label.add_theme_constant_override("outline_size", 5)
	add_child(_hp_label)

func set_values(hp: float, max_hp: float) -> void:
	var new_ratio := clampf(hp / maxf(max_hp, 0.001), 0.0, 1.0)
	if _first:
		_trail = new_ratio
		_first = false
	elif new_ratio < _hp_ratio:
		_trail = maxf(_trail, _hp_ratio)
		_trail_wait = TRAIL_DELAY
	elif new_ratio > _hp_ratio + 0.001:
		_heal_flash = 1.0
		_trail = new_ratio
	_hp = hp
	_max_hp = max_hp
	_hp_ratio = new_ratio
	_hp_label.text = "%d / %d" % [int(ceil(hp)), int(ceil(max_hp))]
	queue_redraw()

func hp_ratio() -> float:
	return _hp_ratio

func trail_ratio() -> float:
	return _trail

func is_low() -> bool:
	return _hp_ratio > 0.0 and _hp_ratio <= LOW_HP

func _process(delta: float) -> void:
	_t += delta
	if _trail_wait > 0.0:
		_trail_wait -= delta
	elif _trail > _hp_ratio:
		_trail = maxf(_trail - TRAIL_SPEED * delta, _hp_ratio)
	_heal_flash = maxf(_heal_flash - delta * 2.5, 0.0)
	queue_redraw()

func _draw() -> void:
	var low := is_low()
	var pulse := 0.5 + 0.5 * sin(_t * 9.0)
	# Marco: esquinas cortadas, borde ámbar y filo neón (rojo latiendo con poca vida)
	var accent := HP_COLOR_LOW.lerp(RumbangStyle.NEON_MAGENTA, pulse) if low else RumbangStyle.NEON_CYAN
	HudDraw.panel(self, Rect2(Vector2.ZERO, size), accent)
	# Corazón (rombo) a la izquierda
	var c := Vector2(PAD + 7.0, PAD + HP_H * 0.5)
	var heart := HP_COLOR.lerp(Color.WHITE, 0.25 * pulse) if low else HP_COLOR
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -8), c + Vector2(7, 0), c + Vector2(0, 8), c + Vector2(-7, 0)]), heart)
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -4), c + Vector2(3, 0), c + Vector2(0, 4), c + Vector2(-3, 0)]), Color(1, 1, 1, 0.6))
	# Vida: barra inclinada con rastro del daño y marcas cada 10 %
	var hp_col := HP_COLOR.lerp(HP_COLOR_LOW, pulse) if low else HP_COLOR
	var bar_rect := Rect2(PAD + 20.0, PAD, W - 20.0, HP_H)
	HudDraw.bar(self, bar_rect, _hp_ratio, hp_col.lerp(Color(0.4, 1.0, 0.45), _heal_flash * 0.7), _trail, 0.1, _heal_flash)
