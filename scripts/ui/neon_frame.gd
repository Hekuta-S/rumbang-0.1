class_name NeonFrame
extends Control

## Decoración de marco para paneles (estilo fusión fantasía oscura + neón): esquinas en escuadra ámbar,
## una línea neón arriba con un destello que la recorre, otra fina abajo y un rombo en el centro superior.
## Se dibuja encima del control al que se engancha y no recibe clics.
## Uso: NeonFrame.attach(panel)  o  NeonFrame.attach(panel, RumbangStyle.NEON_MAGENTA)

const CORNER := 18.0
const INSET := 5.0

var accent: Color = RumbangStyle.NEON_CYAN
var corner_color: Color = RumbangStyle.ACCENT
var _t := 0.0

static func attach(target: Control, p_accent: Color = RumbangStyle.NEON_CYAN) -> NeonFrame:
	var f := NeonFrame.new()
	f.accent = p_accent
	target.add_child(f)
	return f

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0
	offset_top = 0
	offset_right = 0
	offset_bottom = 0
	# Encima de los hijos del panel aunque estos se añadan después
	z_index = 1
	top_level = false

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _glow_line(a: Vector2, b: Vector2, col: Color, width: float) -> void:
	draw_line(a, b, Color(col, 0.10), width * 5.0, true)
	draw_line(a, b, Color(col, 0.25), width * 2.5, true)
	draw_line(a, b, col, width, true)

func _draw() -> void:
	var s := size
	if s.x < 40.0 or s.y < 30.0:
		return
	var c := corner_color
	var i := INSET
	# Esquinas en escuadra
	for p in [[Vector2(i, i), Vector2(1, 1)], [Vector2(s.x - i, i), Vector2(-1, 1)],
			[Vector2(i, s.y - i), Vector2(1, -1)], [Vector2(s.x - i, s.y - i), Vector2(-1, -1)]]:
		var o: Vector2 = p[0]
		var d: Vector2 = p[1]
		draw_line(o, o + Vector2(CORNER * d.x, 0), c, 2.0, true)
		draw_line(o, o + Vector2(0, CORNER * d.y), c, 2.0, true)
		draw_rect(Rect2(o - Vector2(2, 2) + Vector2(d.x * 1.0, d.y * 1.0), Vector2(3, 3)), Color(c, 0.9))
	# Línea neón superior con destello que la recorre
	var x0 := s.x * 0.18
	var x1 := s.x * 0.82
	_glow_line(Vector2(x0, 1.5), Vector2(x1, 1.5), Color(accent, 0.8), 1.5)
	var k := fmod(_t * 0.35, 1.0)
	var sx := lerpf(x0, x1, k)
	_glow_line(Vector2(maxf(sx - 26.0, x0), 1.5), Vector2(minf(sx + 26.0, x1), 1.5), Color(1, 1, 1, 0.9 * sin(k * PI)), 2.0)
	# Línea inferior corta
	_glow_line(Vector2(s.x * 0.38, s.y - 1.5), Vector2(s.x * 0.62, s.y - 1.5), Color(RumbangStyle.NEON_MAGENTA, 0.6), 1.2)
	# Rombo central superior
	var m := Vector2(s.x * 0.5, 1.5)
	draw_colored_polygon(PackedVector2Array([m + Vector2(0, -5), m + Vector2(6, 0), m + Vector2(0, 5), m + Vector2(-6, 0)]), c)
	draw_colored_polygon(PackedVector2Array([m + Vector2(0, -2.5), m + Vector2(3, 0), m + Vector2(0, 2.5), m + Vector2(-3, 0)]), Color(accent, 0.95))
