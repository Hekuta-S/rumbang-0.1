class_name EnemyQuery
extends RefCounted

## Detección de golpes contra enemigos SIN física: sustituye a get_overlapping_bodies(), body_entered y
## a los rayos físicos con máscara de enemigos. Trabaja con las posiciones del EnemyRegistry (y su
## rejilla espacial) y trata a cada enemigo como una cápsula vertical (hit_radius × hit_height).
##
## Cualquier cosa del registro debe exponer global_position y, opcionalmente, hit_radius / hit_height.

const DEFAULT_RADIUS := 0.45
const DEFAULT_HEIGHT := 1.6

static func radius_of(e: Object) -> float:
	var r = e.get("hit_radius")
	return float(r) if r != null else DEFAULT_RADIUS

static func height_of(e: Object) -> float:
	var h = e.get("hit_height")
	return float(h) if h != null else DEFAULT_HEIGHT

# ───────────────────────────── Áreas (sustituye get_overlapping_bodies) ─────────────────────────────

## Enemigos que solapan con alguna CollisionShape3D del área (caja, esfera, cápsula o cilindro).
static func overlapping(area: Area3D) -> Array:
	var out: Array = []
	if not is_instance_valid(area) or not area.is_inside_tree():
		return out
	for child in area.get_children():
		if not (child is CollisionShape3D):
			continue
		var cs := child as CollisionShape3D
		if cs.disabled or cs.shape == null:
			continue
		var xf := cs.global_transform
		var reach := _shape_reach(cs.shape, xf) + 2.5   # + alto/radio de un enemigo
		for e in EnemyRegistry.query_radius(xf.origin, reach):
			if not out.has(e) and _enemy_touches_shape(e, cs.shape, xf):
				out.append(e)
	return out

## true si algún enemigo solapa con el área (para proyectiles que estallan al tocar).
static func any_overlapping(area: Area3D) -> bool:
	return not overlapping(area).is_empty()

static func _shape_reach(shape: Shape3D, xf: Transform3D) -> float:
	var s := xf.basis.get_scale()
	var smax := maxf(s.x, maxf(s.y, s.z))
	if shape is SphereShape3D:
		return (shape as SphereShape3D).radius * smax
	if shape is BoxShape3D:
		return (shape as BoxShape3D).size.length() * 0.5 * smax
	if shape is CapsuleShape3D:
		var c := shape as CapsuleShape3D
		return maxf(c.height * 0.5, c.radius) * smax + c.radius * smax
	if shape is CylinderShape3D:
		var cy := shape as CylinderShape3D
		return Vector2(cy.radius, cy.height * 0.5).length() * smax
	return 6.0

static func _enemy_touches_shape(e: Object, shape: Shape3D, xf: Transform3D) -> bool:
	var er := radius_of(e)
	var eh := height_of(e)
	var base: Vector3 = e.global_position
	# La cápsula del enemigo se muestrea con 3 esferas: pies, cintura y cabeza
	for k in range(3):
		var p := base + Vector3(0.0, er + (eh - 2.0 * er) * (float(k) / 2.0), 0.0)
		if _sphere_touches_shape(p, er, shape, xf):
			return true
	return false

static func _sphere_touches_shape(p: Vector3, r: float, shape: Shape3D, xf: Transform3D) -> bool:
	var s := xf.basis.get_scale()
	var inv := xf.basis.orthonormalized().transposed()
	var local := inv * (p - xf.origin)       # en el marco de la forma, con escala aplicada
	if shape is SphereShape3D:
		return local.length() <= (shape as SphereShape3D).radius * maxf(s.x, maxf(s.y, s.z)) + r
	if shape is BoxShape3D:
		var half := (shape as BoxShape3D).size * 0.5 * s
		var closest := Vector3(clampf(local.x, -half.x, half.x), clampf(local.y, -half.y, half.y), clampf(local.z, -half.z, half.z))
		return local.distance_to(closest) <= r
	if shape is CapsuleShape3D:
		var c := shape as CapsuleShape3D
		var rad := c.radius * maxf(s.x, s.z)
		var half_seg := maxf(c.height * 0.5 * s.y - rad, 0.0)
		var cy := clampf(local.y, -half_seg, half_seg)
		return Vector3(local.x, local.y - cy, local.z).length() <= rad + r
	if shape is CylinderShape3D:
		var cyl := shape as CylinderShape3D
		var rad2 := cyl.radius * maxf(s.x, s.z)
		var hh := cyl.height * 0.5 * s.y
		return Vector2(local.x, local.z).length() <= rad2 + r and absf(local.y) <= hh + r
	# Forma desconocida: se usa una esfera del tamaño de su caja envolvente
	var aabb := shape.get_debug_mesh().get_aabb() if shape.has_method("get_debug_mesh") else AABB(Vector3.ZERO, Vector3.ONE)
	return local.length() <= aabb.size.length() * 0.5 * maxf(s.x, maxf(s.y, s.z)) + r

# ───────────────────────────── Segmentos (sustituye rayos con máscara de enemigos) ─────────────────────────────

## Primer enemigo que corta el segmento from→to (con `extra` de grosor del proyectil).
## Devuelve {"enemy": e, "pos": Vector3, "t": 0..1} o {} si no toca a nadie. `skip` = enemigos a ignorar.
static func segment_hit(from: Vector3, to: Vector3, extra: float = 0.0, skip: Array = []) -> Dictionary:
	var seg := to - from
	var seg_len := seg.length()
	var best := {}
	var best_t := 2.0
	var mid := from + seg * 0.5
	for e in EnemyRegistry.query_radius(mid, seg_len * 0.5 + 3.5 + extra):
		if skip.has(e):
			continue
		var r := radius_of(e) + extra
		var base: Vector3 = e.global_position
		var h := height_of(e) + extra
		var t := _segment_vs_cylinder(from, seg, base, r, h)
		if t >= 0.0 and t < best_t:
			best_t = t
			best = {"enemy": e, "pos": from + seg * t, "t": t}
	return best

## Parámetro t (0..1) donde el segmento entra en el cilindro vertical (base, radio r, altura h); -1 si no.
static func _segment_vs_cylinder(from: Vector3, seg: Vector3, base: Vector3, r: float, h: float) -> float:
	var ox := from.x - base.x
	var oz := from.z - base.z
	var a := seg.x * seg.x + seg.z * seg.z
	var t_enter := 0.0
	var t_exit := 1.0
	if a < 0.000001:
		# Segmento vertical: solo cuenta si está dentro del círculo
		if ox * ox + oz * oz > r * r:
			return -1.0
	else:
		var b := 2.0 * (ox * seg.x + oz * seg.z)
		var c := ox * ox + oz * oz - r * r
		var disc := b * b - 4.0 * a * c
		if disc < 0.0:
			return -1.0
		var sq := sqrt(disc)
		t_enter = (-b - sq) / (2.0 * a)
		t_exit = (-b + sq) / (2.0 * a)
		if t_exit < 0.0 or t_enter > 1.0:
			return -1.0
		t_enter = maxf(t_enter, 0.0)
		t_exit = minf(t_exit, 1.0)
	# Intervalo vertical: y entre base.y y base.y + h
	var y0 := from.y - base.y
	if absf(seg.y) < 0.000001:
		if y0 < 0.0 or y0 > h:
			return -1.0
	else:
		var ta := (0.0 - y0) / seg.y
		var tb := (h - y0) / seg.y
		var lo := minf(ta, tb)
		var hi := maxf(ta, tb)
		t_enter = maxf(t_enter, lo)
		t_exit = minf(t_exit, hi)
		if t_enter > t_exit:
			return -1.0
	return clampf(t_enter, 0.0, 1.0)

# ───────────────────────────── Auxiliares ─────────────────────────────

## Enemigo más cercano a `pos` dentro de `radius` (o null).
static func nearest(pos: Vector3, radius: float) -> Object:
	var best: Object = null
	var best_d := INF
	for e in EnemyRegistry.query_radius(pos, radius):
		var d := pos.distance_squared_to(e.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best
