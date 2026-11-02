class_name HudDraw
extends RefCounted

## Dibujo compartido del HUD (estilo fusión): paneles con esquinas cortadas, borde ámbar y filo neón, y barras
## inclinadas (paralelogramos) con brillo, rastro y marcas de segmento. Lo usan VitalsPanel, ResourceBars y TeamPanel.

const FRAME := Color(0.045, 0.035, 0.08, 0.86)
const BORDER := Color(0.72, 0.52, 0.26, 0.9)
const CUT := 9.0                       ## esquina cortada (px)

## Panel de esquinas cortadas (arriba-derecha y abajo-izquierda) con filo neón inferior.
static func panel(ci: CanvasItem, r: Rect2, accent: Color = RumbangStyle.NEON_CYAN) -> void:
	var p := r.position
	var e := r.end
	var pts := PackedVector2Array([
		p, Vector2(e.x - CUT, p.y), Vector2(e.x, p.y + CUT), e, Vector2(p.x + CUT, e.y), Vector2(p.x, e.y - CUT)])
	ci.draw_colored_polygon(pts, FRAME)
	var loop := pts.duplicate()
	loop.append(pts[0])
	ci.draw_polyline(loop, BORDER, 1.5, true)
	# Filo neón abajo y marca en la esquina cortada
	ci.draw_line(Vector2(p.x + CUT + 4, e.y - 1.5), Vector2(e.x - 6, e.y - 1.5), Color(accent, 0.18), 5.0, true)
	ci.draw_line(Vector2(p.x + CUT + 4, e.y - 1.5), Vector2(e.x - 6, e.y - 1.5), Color(accent, 0.85), 1.2, true)
	ci.draw_line(Vector2(e.x - CUT + 2, p.y + 2), Vector2(e.x - 2, p.y + CUT - 2), Color(accent, 0.9), 1.5, true)

## Paralelogramo de `x0` a `x1` dentro de la fila `r` (inclinado como los botones).
static func _slant(r: Rect2, x0: float, x1: float) -> PackedVector2Array:
	var sk := r.size.y * 0.55
	return PackedVector2Array([
		Vector2(r.position.x + x0 + sk, r.position.y), Vector2(r.position.x + x1 + sk, r.position.y),
		Vector2(r.position.x + x1, r.end.y), Vector2(r.position.x + x0, r.end.y)])

## Barra inclinada: fondo, rastro (daño reciente), relleno con brillo superior y marcas cada `segment` (0..1).
static func bar(ci: CanvasItem, r: Rect2, ratio: float, color: Color, trail: float = -1.0, segment: float = 0.0, flash: float = 0.0) -> void:
	var w := r.size.x - r.size.y * 0.55
	ratio = clampf(ratio, 0.0, 1.0)
	ci.draw_colored_polygon(_slant(r, 0.0, w), Color(color.darkened(0.82), 0.95))
	if trail > ratio:
		ci.draw_colored_polygon(_slant(r, w * ratio, w * clampf(trail, 0.0, 1.0)), Color(1, 0.95, 0.9, 0.75))
	if ratio > 0.001:
		var col := color.lerp(Color.WHITE, clampf(flash, 0.0, 1.0) * 0.6)
		# Halo
		var halo := r.grow(2.0)
		ci.draw_colored_polygon(_slant(halo, 0.0, (halo.size.x - halo.size.y * 0.55) * ratio), Color(col, 0.22))
		ci.draw_colored_polygon(_slant(r, 0.0, w * ratio), col)
		# Brillo superior (volumen)
		var top := Rect2(r.position, Vector2(r.size.x, r.size.y * 0.38))
		ci.draw_colored_polygon(_slant(top, r.size.y * 0.62 * 0.55, (top.size.x - top.size.y * 0.55) * ratio * 0.985 + r.size.y * 0.2), Color(1, 1, 1, 0.18))
	if segment > 0.0:
		var k := segment
		while k < 0.999:
			var x := r.position.x + w * k
			ci.draw_line(Vector2(x + r.size.y * 0.55, r.position.y), Vector2(x, r.end.y), Color(0, 0, 0, 0.55), 1.5, true)
			k += segment
	var outline := _slant(r, 0.0, w)
	outline.append(outline[0])
	ci.draw_polyline(outline, Color(0, 0, 0, 0.7), 1.0, true)

## Texto con contorno (legible sobre cualquier fondo).
static func text(ci: CanvasItem, font: Font, pos: Vector2, s: String, size: int, color: Color = Color.WHITE) -> void:
	ci.draw_string_outline(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0, 0, 0, 0.85))
	ci.draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
