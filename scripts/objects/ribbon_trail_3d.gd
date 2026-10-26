class_name RibbonTrail3D
extends ImmediateMesh

## RibbonTrail3D: Genera una cinta/estela 3D geométrica continua en tiempo real.
## Registra las posiciones en el espacio y construye quads continuos orientados a cámara o normales.

var points: Array[Vector3] = []
var ages: Array[float] = []
var max_points: int = 36
var trail_width: float = 0.6
var lifetime: float = 0.35
var min_distance: float = 0.08

func add_trail_point(new_pos: Vector3, up_vector: Vector3 = Vector3.UP) -> void:
	if points.size() > 0 and new_pos.distance_squared_to(points[0]) < (min_distance * min_distance):
		return
	points.insert(0, new_pos)
	ages.insert(0, 0.0)

func update_trail(delta: float, camera_pos: Vector3) -> void:
	var count = points.size()
	if count < 2:
		clear_surfaces()
		return

	# Envejecer y podar puntos que excedan el lifetime
	var valid_count = 0
	for i in range(count):
		ages[i] += delta
		if ages[i] <= lifetime:
			valid_count = i + 1
		else:
			break

	if valid_count < 2:
		points.clear()
		ages.clear()
		clear_surfaces()
		return

	points = points.slice(0, valid_count)
	ages = ages.slice(0, valid_count)
	count = points.size()

	clear_surfaces()
	surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)

	for i in range(count):
		var p = points[i]
		var t = float(i) / float(max(1, count - 1))
		var life_t = clampf(ages[i] / lifetime, 0.0, 1.0)
		var current_width = trail_width * (1.0 - life_t * 0.7)

		# Orientación de la cinta
		var dir = Vector3.FORWARD
		if i < count - 1:
			dir = (points[i] - points[i + 1]).normalized()
		elif i > 0:
			dir = (points[i - 1] - points[i]).normalized()

		var to_cam = (camera_pos - p).normalized()
		var side = dir.cross(to_cam).normalized()
		if side.length_squared() < 0.001:
			side = dir.cross(Vector3.UP).normalized()
			if side.length_squared() < 0.001:
				side = Vector3.RIGHT

		var half_ext = side * (current_width * 0.5)

		# Vértice A (superior)
		surface_set_uv(Vector2(life_t, 1.0))
		surface_set_color(Color(1, 1, 1, 1.0 - life_t))
		surface_add_vertex(p + half_ext)

		# Vértice B (inferior)
		surface_set_uv(Vector2(life_t, 0.0))
		surface_set_color(Color(1, 1, 1, 1.0 - life_t))
		surface_add_vertex(p - half_ext)

	surface_end()
