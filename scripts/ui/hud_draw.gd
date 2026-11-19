class_name HudDraw
extends RefCounted

## Dibujo compartido del HUD (estilo fusión, colores de fantasía oscura y neón) con BORDES DE CÓMIC: contorno
## grueso de tinta y sombra dura desplazada, a juego con el mundo entintado. Paneles con esquinas cortadas,
## borde de tinta y filo neón; barras inclinadas (paralelogramos) con brillo, rastro y marcas de segmento.
## Lo usan VitalsPanel, ResourceBars, TeamPanel y Minimap.

const FRAME := Color(0.045, 0.035, 0.08, 0.86)
const BORDER := Color(0.72, 0.52, 0.26, 0.9)
const INK := Color(0.03, 0.022, 0.05)             ## la tinta de los contornos
const CUT := 9.0                       ## esquina cortada (px)
const SHADOW := Vector2(3.0, 4.0)      ## sombra dura de los paneles
const BAR_SHADOW := Vector2(2.0, 3.0)
const LINE := 3.0                      ## grosor del contorno de tinta

## Panel de esquinas cortadas (arriba-derecha y abajo-izquierda): sombra dura, fondo, filo ámbar por dentro,
## contorno de tinta y el filo neón inferior.
## `ci`: un CanvasItem (dentro de su _draw) o un HudBatch (todo en una sola llamada de dibujo).
static func panel(ci, r: Rect2, accent: Color = RumbangStyle.NEON_CYAN) -> void:
	var p := r.position
	var e := r.end
	var pts := PackedVector2Array([
		p, Vector2(e.x - CUT, p.y), Vector2(e.x, p.y + CUT), e, Vector2(p.x + CUT, e.y), Vector2(p.x, e.y - CUT)])
	var shadow := PackedVector2Array()
	for q in pts:
		shadow.append(q + SHADOW)
	ci.draw_colored_polygon(shadow, Color(INK, 0.8))
	ci.draw_colored_polygon(pts, FRAME)
	var loop := pts.duplicate()
	loop.append(pts[0])
	# Filo neón abajo y marca en la esquina cortada
	ci.draw_line(Vector2(p.x + CUT + 4, e.y - 3.5), Vector2(e.x - 6, e.y - 3.5), Color(accent, 0.18), 5.0, true)
	ci.draw_line(Vector2(p.x + CUT + 4, e.y - 3.5), Vector2(e.x - 6, e.y - 3.5), Color(accent, 0.85), 1.5, true)
	ci.draw_line(Vector2(e.x - CUT + 1, p.y + 4), Vector2(e.x - 4, p.y + CUT - 1), Color(accent, 0.9), 2.0, true)
	# filo ámbar por dentro y contorno de tinta por fuera
	var inner := PackedVector2Array()
	var c := r.get_center()
	for q in pts:
		inner.append(q + (c - q).normalized() * 3.5)
	inner.append(inner[0])
	ci.draw_polyline(inner, BORDER, 1.2, true)
	ci.draw_polyline(loop, INK, LINE, true)

## Paralelogramo de `x0` a `x1` dentro de la fila `r` (inclinado como los botones).
static func _slant(r: Rect2, x0: float, x1: float) -> PackedVector2Array:
	var sk := r.size.y * 0.55
	return PackedVector2Array([
		Vector2(r.position.x + x0 + sk, r.position.y), Vector2(r.position.x + x1 + sk, r.position.y),
		Vector2(r.position.x + x1, r.end.y), Vector2(r.position.x + x0, r.end.y)])

## Barra inclinada: sombra dura, fondo, rastro (daño reciente), relleno con brillo superior y marcas cada
## `segment` (0..1), con línea de tinta donde acaba el relleno y contorno de tinta.
static func bar(ci, r: Rect2, ratio: float, color: Color, trail: float = -1.0, segment: float = 0.0, flash: float = 0.0) -> void:
	var sk := r.size.y * 0.55
	var w := r.size.x - sk
	ratio = clampf(ratio, 0.0, 1.0)
	ci.draw_colored_polygon(_slant(Rect2(r.position + BAR_SHADOW, r.size), 0.0, w), Color(INK, 0.8))
	ci.draw_colored_polygon(_slant(r, 0.0, w), Color(color.darkened(0.82), 0.95))
	if trail > ratio:
		ci.draw_colored_polygon(_slant(r, w * ratio, w * clampf(trail, 0.0, 1.0)), Color(1, 0.95, 0.9, 0.75))
	if ratio > 0.001:
		var col := color.lerp(Color.WHITE, clampf(flash, 0.0, 1.0) * 0.6)
		ci.draw_colored_polygon(_slant(r, 0.0, w * ratio), col)
		# Brillo superior (volumen)
		var top := Rect2(r.position, Vector2(r.size.x, r.size.y * 0.38))
		ci.draw_colored_polygon(_slant(top, r.size.y * 0.62 * 0.55, (top.size.x - top.size.y * 0.55) * ratio * 0.985 + r.size.y * 0.2), Color(1, 1, 1, 0.18))
		if ratio < 0.995:
			var x := r.position.x + w * ratio
			ci.draw_line(Vector2(x + sk, r.position.y), Vector2(x, r.end.y), INK, 2.0, true)
	if segment > 0.0:
		var k := segment
		while k < 0.999:
			var x2 := r.position.x + w * k
			ci.draw_line(Vector2(x2 + sk, r.position.y), Vector2(x2, r.end.y), Color(0, 0, 0, 0.55), 1.5, true)
			k += segment
	var outline := _slant(r, 0.0, w)
	outline.append(outline[0])
	ci.draw_polyline(outline, INK, LINE, true)

## Texto con contorno grueso de tinta y sombra dura (legible sobre cualquier fondo).
static func text(ci: CanvasItem, font: Font, pos: Vector2, s: String, size: int, color: Color = Color.WHITE) -> void:
	var a := color.a
	ci.draw_string_outline(font, pos + Vector2(1.5, 2.0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 5, Color(INK, 0.85 * a))
	ci.draw_string_outline(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 5, Color(INK, a))
	ci.draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

## Figura convexa con contorno de tinta (marcas del minimapa): primero la tinta, engordada desde su centro, y
## encima el color.
static func inked_polygon(ci, pts: PackedVector2Array, color: Color, ink_px: float = 2.0) -> void:
	var c := Vector2.ZERO
	for q in pts:
		c += q
	c /= float(pts.size())
	var big := PackedVector2Array()
	for q in pts:
		var d := q - c
		big.append(q + d.normalized() * ink_px * 1.4 if d.length() > 0.001 else q)
	ci.draw_colored_polygon(big, INK)
	ci.draw_colored_polygon(pts, color)
