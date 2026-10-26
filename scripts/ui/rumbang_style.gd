class_name RumbangStyle
extends RefCounted

## Estilo visual compartido de Rumbang (dark fantasy: negro violáceo, ámbar de
## brasas y violeta arcano). Menú, selección, pausa, objetos, mejoras y carga
## usan estas constantes y este Theme para verse como un solo juego.
##
## Uso: `control.theme = RumbangStyle.get_theme()` (cascada a todos los hijos)
## o `RumbangStyle.button_style(...)` para estilos puntuales.

const BG         := Color(0.04, 0.035, 0.07)
const ACCENT     := Color(0.95, 0.62, 0.20)
const TITLE      := Color(1.00, 0.74, 0.32)
const GLOW       := Color(0.55, 0.20, 1.00)
const TEXT       := Color(0.92, 0.89, 0.84)
const TEXT_DIM   := Color(0.58, 0.52, 0.62)
const PANEL      := Color(0.07, 0.055, 0.11, 0.94)
const BTN_BG     := Color(0.09, 0.07, 0.13)
const BTN_BORDER := Color(0.27, 0.19, 0.36)
const BTN_HOVER  := Color(0.17, 0.11, 0.25)
const BTN_PRESS  := Color(0.50, 0.28, 0.10)

const FONT := preload("res://assets/fonts/PressStart2P-Regular.ttf")

static var _theme: Theme

static func button_style(bg: Color, border: Color, radius: int = 5, width: int = 2) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_border_width_all(width)
	s.border_color = border
	s.set_corner_radius_all(radius)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s

static func panel_style(bg: Color = PANEL, border: Color = BTN_BORDER, radius: int = 6, margin: int = 16) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_border_width_all(2)
	s.border_color = border
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
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
	b.add_theme_color_override("font_disabled_color", TEXT_DIM)
	b.add_theme_stylebox_override("normal", button_style(BTN_BG, border))
	b.add_theme_stylebox_override("hover", button_style(BTN_HOVER, ACCENT))
	b.add_theme_stylebox_override("pressed", button_style(BTN_PRESS, ACCENT))
	b.add_theme_stylebox_override("disabled", button_style(BTN_BG, BTN_BORDER))
	b.add_theme_stylebox_override("focus", button_style(BTN_BG, ACCENT))

## Theme completo (se construye una sola vez).
static func get_theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = FONT
	t.default_font_size = 16

	# Button
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", TEXT_DIM)
	t.set_stylebox("normal", "Button", button_style(BTN_BG, BTN_BORDER))
	t.set_stylebox("hover", "Button", button_style(BTN_HOVER, ACCENT))
	t.set_stylebox("pressed", "Button", button_style(BTN_PRESS, ACCENT))
	t.set_stylebox("disabled", "Button", button_style(BTN_BG, BTN_BORDER))
	t.set_stylebox("focus", "Button", button_style(BTN_BG, ACCENT))

	# Paneles
	t.set_stylebox("panel", "Panel", panel_style())
	t.set_stylebox("panel", "PanelContainer", panel_style())

	# Texto
	t.set_color("font_color", "Label", TEXT)

	# Barra de progreso
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.09, 0.07, 0.13)
	bar_bg.set_border_width_all(2)
	bar_bg.border_color = BTN_BORDER
	bar_bg.set_corner_radius_all(4)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = ACCENT
	bar_fill.set_corner_radius_all(3)
	t.set_stylebox("background", "ProgressBar", bar_bg)
	t.set_stylebox("fill", "ProgressBar", bar_fill)
	t.set_color("font_color", "ProgressBar", TEXT)

	_theme = t
	return t
