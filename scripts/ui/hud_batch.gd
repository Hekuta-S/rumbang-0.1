class_name HudBatch
extends RefCounted

## Junta los polígonos y líneas de un _draw() en UNA malla con colores por vértice, para dibujarla con un
## solo draw_mesh. En Godot cada draw_colored_polygon / draw_line / draw_polyline es una llamada de dibujo
## (solo los rectángulos se agrupan): el panel de vida del móvil hacía ~21 y en un Mali-G57 el HUD costaba
## ~3.5 ms por frame. Imita esa parte de la API de CanvasItem, así HudDraw puede dibujar aquí o directo.
## Las líneas son tiras sin antialias (a la densidad de un móvil no se nota). Las figuras deben ser
## convexas o simples (se triangulan con Geometry2D).
##     var b := HudBatch.new()
##     HudDraw.panel(b, rect)
##     b.commit(self)          # dentro de _draw()

var _v := PackedVector2Array()
var _c := PackedColorArray()
var _mesh := ArrayMesh.new()

func clear() -> void:
	_v.resize(0)
	_c.resize(0)

func draw_colored_polygon(pts: PackedVector2Array, color: Color, _uvs = null, _texture = null) -> void:
	if pts.size() < 3:
		return
	var tri := Geometry2D.triangulate_polygon(pts)
	if tri.is_empty():
		# Figura degenerada o con autointersección: abanico (son convexas casi siempre)
		for i in range(1, pts.size() - 1):
			_tri(pts[0], pts[i], pts[i + 1], color)
		return
	for i in range(0, tri.size(), 3):
		_tri(pts[tri[i]], pts[tri[i + 1]], pts[tri[i + 2]], color)

func draw_line(a: Vector2, b: Vector2, color: Color, width: float = -1.0, _antialiased: bool = false) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.0001:
		return
	var n := Vector2(-d.y, d.x) / l * (maxf(width, 1.0) * 0.5)
	_tri(a + n, b + n, b - n, color)
	_tri(a + n, b - n, a - n, color)

func draw_polyline(pts: PackedVector2Array, color: Color, width: float = -1.0, antialiased: bool = false) -> void:
	for i in range(pts.size() - 1):
		draw_line(pts[i], pts[i + 1], color, width, antialiased)

func _tri(a: Vector2, b: Vector2, c: Vector2, color: Color) -> void:
	_v.append(a)
	_v.append(b)
	_v.append(c)
	_c.append(color)
	_c.append(color)
	_c.append(color)

## Dibuja todo lo acumulado en `ci` (llamar desde su _draw) y vacía el lote.
func commit(ci: CanvasItem) -> void:
	_mesh.clear_surfaces()
	if not _v.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _v
		arrays[Mesh.ARRAY_COLOR] = _c
		_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		ci.draw_mesh(_mesh, null)
	clear()
