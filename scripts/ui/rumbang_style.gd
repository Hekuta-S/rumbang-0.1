class_name RumbangStyle
extends RefCounted

## Estilo visual compartido de Rumbang: FUSIÓN de fantasía oscura y neón cyberpunk.
##  - Base de fantasía oscura: negro violáceo, ámbar de brasas en los marcos y títulos, fuente pixel.
##  - Acentos neón: cian (foco, hover, energía) y magenta (pulsado, peligro), con brillo (sombra de color).
##  - Botones inclinados (skew) con un filo ámbar a la izquierda; paneles con borde fino y halo violeta.
## Menú, selección, sala, ajustes, pausa, objetos, mejoras y carga usan estas constantes y este Theme.
##
## Uso: `control.theme = RumbangStyle.get_theme()` (cascada a todos los hijos)
## o `RumbangStyle.button_style(...)` para estilos puntuales. Decoración de marcos: NeonFrame.attach(panel).

const BG         := Color(0.035, 0.03, 0.065)
const ACCENT     := Color(0.98, 0.64, 0.22)
const TITLE      := Color(1.00, 0.76, 0.34)
const GLOW       := Color(0.55, 0.20, 1.00)
const TEXT       := Color(0.93, 0.90, 0.86)
const TEXT_DIM   := Color(0.60, 0.54, 0.66)
const PANEL      := Color(0.06, 0.045, 0.10, 0.95)
const BTN_BG     := Color(0.075, 0.055, 0.12)
const BTN_BORDER := Color(0.30, 0.20, 0.42)
const BTN_HOVER  := Color(0.11, 0.08, 0.19)
const BTN_PRESS  := Color(0.30, 0.08, 0.26)

## Neón
const NEON_CYAN    := Color(0.25, 0.95, 1.00)
const NEON_MAGENTA := Color(1.00, 0.27, 0.78)
const DANGER       := Color(1.00, 0.28, 0.32)

const SKEW := Vector2(0.18, 0.0)      ## inclinación de los botones (cyberpunk)

const FONT := preload("res://assets/fonts/PressStart2P-Regular.ttf")

static var _theme: Theme

## Botón: fondo oscuro, borde fino, filo izquierdo ámbar y, en hover/foco, halo neón.
static func button_style(bg: Color, border: Color, radius: int = 3, width: int = 2) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_border_width_all(width)
	s.border_width_left = width + 3
	s.border_color = border
	s.set_corner_radius_all(radius)
	s.skew = SKEW
	s.anti_aliasing = true
	s.content_margin_left = 20
	s.content_margin_right = 20
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	# Halo del color del borde cuando es neón (hover / foco / pulsado)
	if border == NEON_CYAN or border == NEON_MAGENTA or border == ACCENT:
		s.shadow_color = Color(border, 0.35)
		s.shadow_size = 8
	return s

## Panel: fondo violáceo profundo, borde ámbar tenue y halo violeta.
static func panel_style(bg: Color = PANEL, border: Color = BTN_BORDER, radius: int = 4, margin: int = 24) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_border_width_all(2)
	s.border_color = border
	s.border_width_top = 3
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	s.shadow_color = Color(GLOW, 0.22)
	s.shadow_size = 14
	s.anti_aliasing = true
	return s

## Botón estilizado (altura mínima configurable).
static func make_button(text: String, border: Color = BTN_BORDER, min_size: Vector2 = Vector2(240, 50)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	_style_button(b, border)
	return b

static func _style_button(b: Button, border: Color) -> void:
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_focus_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", TEXT_DIM)
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	b.add_theme_constant_override("outline_size", 4)
	var normal_border := ACCENT if border == ACCENT else border
	b.add_theme_stylebox_override("normal", button_style(BTN_BG, normal_border))
	b.add_theme_stylebox_override("hover", button_style(BTN_HOVER, NEON_CYAN))
	b.add_theme_stylebox_override("pressed", button_style(BTN_PRESS, NEON_MAGENTA))
	b.add_theme_stylebox_override("disabled", button_style(BTN_BG, BTN_BORDER))
	b.add_theme_stylebox_override("focus", button_style(Color(0, 0, 0, 0), NEON_CYAN))

## Título con brillo neón (contorno de color y sombra).
static func style_title(l: Label, size: int = 26, color: Color = TITLE, glow: Color = NEON_MAGENTA) -> void:
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(glow, 0.55))
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_shadow_color", Color(glow, 0.45))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 3)
	l.add_theme_constant_override("shadow_outline_size", 10)

static func _flat(bg: Color, border: Color, width: int = 2, radius: int = 3) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_border_width_all(width)
	s.border_color = border
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(8)
	s.anti_aliasing = true
	return s

## Theme completo (se construye una sola vez).
static func get_theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = FONT
	t.default_font_size = 16

	# Button (y OptionButton / CheckButton heredan los colores)
	for type in ["Button", "OptionButton", "MenuButton"]:
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_pressed_color", type, Color.WHITE)
		t.set_color("font_focus_color", type, Color.WHITE)
		t.set_color("font_disabled_color", type, TEXT_DIM)
		t.set_color("font_outline_color", type, Color(0, 0, 0, 0.8))
		t.set_constant("outline_size", type, 4)
		t.set_stylebox("normal", type, button_style(BTN_BG, BTN_BORDER))
		t.set_stylebox("hover", type, button_style(BTN_HOVER, NEON_CYAN))
		t.set_stylebox("pressed", type, button_style(BTN_PRESS, NEON_MAGENTA))
		t.set_stylebox("disabled", type, button_style(BTN_BG, BTN_BORDER))
		t.set_stylebox("focus", type, button_style(Color(0, 0, 0, 0), NEON_CYAN))

	# CheckButton / CheckBox: sin caja, solo el interruptor
	for type in ["CheckButton", "CheckBox"]:
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, NEON_CYAN)
		t.set_color("font_pressed_color", type, TEXT)
		t.set_stylebox("normal", type, StyleBoxEmpty.new())
		t.set_stylebox("hover", type, StyleBoxEmpty.new())
		t.set_stylebox("pressed", type, StyleBoxEmpty.new())
		t.set_stylebox("focus", type, StyleBoxEmpty.new())

	# Paneles
	t.set_stylebox("panel", "Panel", panel_style())
	t.set_stylebox("panel", "PanelContainer", panel_style())
	t.set_stylebox("panel", "PopupMenu", _flat(Color(0.05, 0.035, 0.09, 0.98), NEON_CYAN, 1))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_stylebox("hover", "PopupMenu", _flat(Color(NEON_CYAN, 0.18), Color(NEON_CYAN, 0.0), 0))

	# Texto
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.7))

	# Campos de texto y listas
	t.set_stylebox("normal", "LineEdit", _flat(Color(0.03, 0.02, 0.06), BTN_BORDER))
	t.set_stylebox("focus", "LineEdit", _flat(Color(0.03, 0.02, 0.06), NEON_CYAN))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", TEXT_DIM)
	t.set_color("caret_color", "LineEdit", NEON_CYAN)
	t.set_stylebox("panel", "ItemList", _flat(Color(0.03, 0.02, 0.06, 0.9), BTN_BORDER))
	t.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	t.set_stylebox("selected", "ItemList", _flat(Color(NEON_CYAN, 0.16), NEON_CYAN, 1))
	t.set_stylebox("selected_focus", "ItemList", _flat(Color(NEON_CYAN, 0.22), NEON_CYAN, 1))
	t.set_stylebox("hovered", "ItemList", _flat(Color(ACCENT, 0.10), Color(ACCENT, 0.4), 1))
	t.set_color("font_color", "ItemList", TEXT)
	t.set_color("font_selected_color", "ItemList", Color.WHITE)

	# Deslizadores: carril oscuro, relleno neón y agarrador ámbar
	var rail := StyleBoxFlat.new()
	rail.bg_color = Color(0.12, 0.09, 0.18)
	rail.set_corner_radius_all(2)
	rail.content_margin_top = 3
	rail.content_margin_bottom = 3
	var filled := StyleBoxFlat.new()
	filled.bg_color = NEON_CYAN
	filled.set_corner_radius_all(2)
	filled.shadow_color = Color(NEON_CYAN, 0.4)
	filled.shadow_size = 4
	filled.content_margin_top = 3
	filled.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", rail)
	t.set_stylebox("grabber_area", "HSlider", filled)
	t.set_stylebox("grabber_area_highlight", "HSlider", filled)

	# Barras de desplazamiento finas
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.07, 0.15)
	sb.content_margin_left = 3
	sb.content_margin_right = 3
	var grab := StyleBoxFlat.new()
	grab.bg_color = Color(NEON_CYAN, 0.55)
	grab.set_corner_radius_all(3)
	for type in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", type, sb)
		t.set_stylebox("grabber", type, grab)
		t.set_stylebox("grabber_highlight", type, grab)
		t.set_stylebox("grabber_pressed", type, grab)

	# Barra de progreso
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.07, 0.05, 0.11)
	bar_bg.set_border_width_all(2)
	bar_bg.border_color = BTN_BORDER
	bar_bg.set_corner_radius_all(3)
	bar_bg.skew = SKEW
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = ACCENT
	bar_fill.set_corner_radius_all(2)
	bar_fill.skew = SKEW
	bar_fill.shadow_color = Color(ACCENT, 0.45)
	bar_fill.shadow_size = 6
	t.set_stylebox("background", "ProgressBar", bar_bg)
	t.set_stylebox("fill", "ProgressBar", bar_fill)
	t.set_color("font_color", "ProgressBar", TEXT)

	_theme = t
	return t
