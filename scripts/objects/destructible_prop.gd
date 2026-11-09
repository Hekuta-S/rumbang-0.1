class_name DestructibleProp
extends StaticBody3D

## Barril, caja u otro prop que se rompe a golpes (modo mazmorra).
## Bloquea el paso del jugador (capa 1) y está en el grupo "destructibles":
## MeleeHitbox y las balas del jugador le llaman take_damage().
## Al romperse se parte en sus PIEZAS REALES, que salen con física:
##  - Si existe <archivo>_pieces.glb (hechos pieza a pieza en blender_sources/dungeon_assets.blend:
##    barril y caja en el texto dungeon_props.py, choza y tótem en dungeon_structures.py), esas piezas
##    (duelas, aros, tablas; troncos, sectores del techo, cabezas talladas...).
##  - Si no, la malla del prop se parte en sus partes conectadas (troncos, techo, pieles...): las
##    MAX_SPLIT más grandes salen como piezas y el resto se pierde entre astillas y polvo.
## Las piezas pequeñas (BURST_KINDS) revientan hacia fuera desde el lado del golpe con una caja de
## colisión; las estructuras grandes se desploman y chocan con su casco convexo. Luego se quedan en el
## suelo un rato y se hunden en él.
## Además: astillas sueltas, polvo, sonido y un pequeño shake.

signal destroyed(prop: DestructibleProp)

const DEBRIS_COLORS := {
	"barrel": Color(0.4, 0.24, 0.12),
	"crate": Color(0.5, 0.36, 0.2),
	"hut": Color(0.38, 0.27, 0.16),
	"tent": Color(0.45, 0.32, 0.2),
	"palisade": Color(0.42, 0.3, 0.17),
	"skull_pole": Color(0.85, 0.82, 0.7),
	"totem": Color(0.3, 0.42, 0.28),
	"trash_bag": Color(0.08, 0.1, 0.08),
	"toxic_barrel": Color(0.55, 0.5, 0.12),
}
## Vida y astillas al romperse (las estructuras grandes aguantan más y sueltan más escombros).
const STRUCTURE := {
	"barrel": {"hp": 18.0, "chips": 10},
	"crate": {"hp": 25.0, "chips": 10},
	"skull_pole": {"hp": 16.0, "chips": 8, "chip_len": 0.2},
	"palisade": {"hp": 45.0, "chips": 16, "chip_len": 0.4},
	"tent": {"hp": 40.0, "chips": 12, "chip_len": 0.35},
	"hut": {"hp": 80.0, "chips": 24, "chip_len": 0.45},
	"totem": {"hp": 60.0, "chips": 16, "chip_len": 0.3},
	"trash_bag": {"hp": 8.0, "chips": 10},
	"toxic_barrel": {"hp": 14.0, "chips": 10},
}
## Revientan hacia fuera; el resto (estructuras) se desploma.
const BURST_KINDS := ["barrel", "crate", "trash_bag", "toxic_barrel"]
const PIECES_DIR := "res://assets/models/mapa/"
const MAX_SPLIT := 12                 ## piezas al partir una malla sin archivo de piezas
const PIECE_LAYER := 1 << 31          ## capa de los escombros (no estorban al jugador ni a los enemigos)
const WOOD_DENSITY := 550.0           ## kg/m³ (para repartir la masa entre piezas)

static func hp_for(p_kind: String) -> float:
	return float((STRUCTURE.get(p_kind, {}) as Dictionary).get("hp", 20.0))

## Tope de trozos con física vivos a la vez (piezas + astillas).
static func max_pieces() -> int:
	return 70 if Quality.is_mobile() else 180

static var _alive_pieces := 0
## kind -> [{mesh: Mesh, xf: Transform3D (en el espacio del prop), aabb: AABB (de la malla)}]
static var _pieces_cache: Dictionary = {}

var kind: String = "barrel"
var hp: float = 20.0
var max_hp: float = 20.0
var _file := ""
var _mesh: MeshInstance3D
var _mesh_xf := Transform3D.IDENTITY
var _base_basis: Basis
var _broken := false

## mesh/mesh_xf: malla del prop (la misma que usa ProceduralMap); shape_def: entrada de ProceduralMap.PROPS.
func setup(p_kind: String, mesh: Mesh, mesh_xf: Transform3D, shape_def: Dictionary, xf: Transform3D, p_hp: float = 20.0) -> void:
	kind = p_kind
	hp = p_hp
	max_hp = p_hp
	_file = String(shape_def.get("file", p_kind))
	_mesh_xf = mesh_xf
	transform = xf
	collision_layer = 1
	collision_mask = 0
	add_to_group("destructibles")
	_mesh = MeshInstance3D.new()
	_mesh.mesh = mesh
	_mesh.transform = mesh_xf
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	_base_basis = _mesh.basis
	var size: Vector3 = shape_def["size"]
	var cs := CollisionShape3D.new()
	if shape_def["shape"] == "box":
		var bx := BoxShape3D.new()
		bx.size = size
		cs.shape = bx
	else:
		var cyl := CylinderShape3D.new()
		cyl.radius = size.x
		cyl.height = size.y
		cs.shape = cyl
	cs.position.y = size.y * 0.5
	add_child(cs)

func is_broken() -> bool:
	return _broken

func take_damage(amount: float, dir: Vector3 = Vector3.ZERO) -> void:
	if _broken:
		return
	hp -= amount
	if hp <= 0.0:
		_break(dir)
		return
	# Tambaleo al recibir un golpe que no lo rompe
	AudioManager.play_at("impact_blunt", global_position, -6.0, randf_range(1.1, 1.3))
	_spawn_debris(global_position + Vector3(0, 0.6, 0), dir, 0.35 if max_hp > 30.0 else 0.2)
	_darken(1.0 - hp / max_hp)
	var push := dir
	push.y = 0.0
	var axis := Vector3.UP.cross(push.normalized()) if push.length_squared() > 0.001 else Vector3.RIGHT
	var tw := create_tween()
	tw.tween_property(_mesh, "basis", _base_basis.rotated(axis, 0.25), 0.05)
	tw.tween_property(_mesh, "basis", _base_basis.rotated(axis, -0.12), 0.08)
	tw.tween_property(_mesh, "basis", _base_basis, 0.1)

func _break(dir: Vector3) -> void:
	_broken = true
	collision_layer = 0
	remove_from_group("destructibles")
	var pos := global_position + Vector3(0, 0.5, 0)
	AudioManager.play_at("impact_slash", pos, -2.0, randf_range(0.7, 0.85))
	AudioManager.play_at("impact_blunt", pos, -4.0, randf_range(0.8, 0.95))
	if not _spawn_pieces(dir):
		_spawn_debris(pos, dir, 1.0)        # sin piezas: solo astillas (como antes)
	else:
		_spawn_debris(pos, dir, 0.6)
	_spawn_dust(pos)
	HitFeedback.shake(0.15 if kind in BURST_KINDS else 0.35)
	# Botín: cajas, barriles y bolsas pueden soltar una pieza de equipo (EquipmentPickup)
	if kind in BURST_KINDS and get_parent():
		EquipmentPickup.try_drop(get_parent(), global_position, EquipmentPickup.PROP_CHANCE)
	destroyed.emit(self)
	queue_free()

## Las estructuras dañadas se oscurecen poco a poco (grietas/quemado) hasta romperse.
func _darken(t: float) -> void:
	if _mesh == null:
		return
	var v := 1.0 - 0.5 * clampf(t, 0.0, 1.0)
	_mesh.set_instance_shader_parameter("tint", Vector3(v, v * 0.94, v * 0.88))

# ───────────────────────────── Piezas ─────────────────────────────

## Prepara (y guarda) las piezas de un tipo durante la carga del mapa: al romper el primero no hay tirón.
static func prewarm(p_kind: String, file: String, mesh: Mesh, mesh_xf: Transform3D) -> void:
	_pieces_for(p_kind, file, mesh, mesh_xf)

## Olvida las piezas guardadas (pruebas / cambio de calidad).
static func clear_cache() -> void:
	_pieces_cache.clear()

static func _pieces_for(p_kind: String, file: String, mesh: Mesh, mesh_xf: Transform3D) -> Array:
	if _pieces_cache.has(p_kind):
		return _pieces_cache[p_kind]
	var out: Array = []
	if mesh == null or mesh.get_surface_count() == 0:
		_pieces_cache[p_kind] = out
		return out
	var mat := mesh.surface_get_material(0)
	var path := PIECES_DIR + file + "_pieces.glb"
	if ResourceLoader.exists(path):
		var root := (load(path) as PackedScene).instantiate()
		for node in root.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			var xf := Transform3D.IDENTITY
			var n: Node = mi
			while n != null and n != root:
				xf = (n as Node3D).transform * xf
				n = n.get_parent()
			var m := ProceduralMap.flatten_with(mi.mesh, mat)
			# tex_offset: la malla de la pieza está centrada en su origen; el shader lo suma para que la
			# textura quede donde estaba en el prop entero
			out.append({"mesh": m, "xf": xf, "aabb": m.get_aabb(), "tex_offset": xf.origin})
		root.free()
	else:
		out = _split_components(mesh, mesh_xf, mat)
	if p_kind not in BURST_KINDS:
		for pc in out:
			pc["hull"] = _hull_points(pc["mesh"], pc["xf"])
	_pieces_cache[p_kind] = out
	return out

## Casco convexo de una pieza, centrado en su centro (espacio del prop): las piezas grandes y curvas de
## las estructuras (sectores del techo, paredes) chocan con su forma y no con una caja que flota.
static func _hull_points(m: Mesh, xf: Transform3D) -> PackedVector3Array:
	var c := xf * m.get_aabb().get_center()
	var pts := PackedVector3Array()
	for q in m.create_convex_shape(true, true).points:
		pts.append(xf * q - c)
	return pts

## Parte la malla en sus partes conectadas. Los vértices con la misma posición se unen antes (glTF
## los duplica en las aristas duras). Devuelve las MAX_SPLIT más grandes.
static func _split_components(mesh: Mesh, mesh_xf: Transform3D, mat: Material) -> Array:
	var arr := mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var nrm = arr[Mesh.ARRAY_NORMAL]
	var col = arr[Mesh.ARRAY_COLOR]
	var uv2 = arr[Mesh.ARRAY_TEX_UV2]           # clase de detalle (ProceduralMap.detail_class)
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var parent := PackedInt32Array()
	parent.resize(v.size())
	for i in v.size():
		parent[i] = i
	var first := {}
	for i in v.size():
		var key := Vector3i(roundi(v[i].x * 500.0), roundi(v[i].y * 500.0), roundi(v[i].z * 500.0))
		if first.has(key):
			_union(parent, i, first[key])
		else:
			first[key] = i
	for t in range(0, idx.size(), 3):
		_union(parent, idx[t], idx[t + 1])
		_union(parent, idx[t], idx[t + 2])
	var groups := {}                      # raíz -> Array con el primer índice de cada triángulo
	for t in range(0, idx.size(), 3):
		var r := _find(parent, idx[t])
		if not groups.has(r):
			groups[r] = []
		(groups[r] as Array).append(t)
	var roots: Array = groups.keys()
	roots.sort_custom(func(a, b): return (groups[a] as Array).size() > (groups[b] as Array).size())
	var out: Array = []
	for r in roots.slice(0, MAX_SPLIT):
		var tris: Array = groups[r]
		var remap := {}
		var nv := PackedVector3Array()
		var nn := PackedVector3Array()
		var nc := PackedColorArray()
		var nu := PackedVector2Array()
		var ni := PackedInt32Array()
		for t in tris:
			for k in 3:
				var src: int = idx[t + k]
				if not remap.has(src):
					remap[src] = nv.size()
					nv.append(v[src])
					if nrm != null:
						nn.append(nrm[src])
					if col != null:
						nc.append(col[src])
					if uv2 != null:
						nu.append(uv2[src])
				ni.append(remap[src])
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = nv
		if not nn.is_empty():
			a[Mesh.ARRAY_NORMAL] = nn
		if not nc.is_empty():
			a[Mesh.ARRAY_COLOR] = nc
		if not nu.is_empty():
			a[Mesh.ARRAY_TEX_UV2] = nu
		a[Mesh.ARRAY_INDEX] = ni
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		m.surface_set_material(0, mat)
		out.append({"mesh": m, "xf": mesh_xf, "aabb": m.get_aabb()})
	return out

static func _find(parent: PackedInt32Array, i: int) -> int:
	var r := i
	while parent[r] != r:
		r = parent[r]
	while parent[i] != r:                 # compresión del camino
		var nx := parent[i]
		parent[i] = r
		i = nx
	return r

static func _union(parent: PackedInt32Array, a: int, b: int) -> void:
	var ra := _find(parent, a)
	var rb := _find(parent, b)
	if ra != rb:
		parent[ra] = rb

## Suelta las piezas con física. false si este tipo no tiene piezas (o no queda sitio).
func _spawn_pieces(dir: Vector3) -> bool:
	var pieces := _pieces_for(kind, _file, _mesh.mesh, _mesh_xf)
	var room := maxi(0, max_pieces() - _alive_pieces)
	if pieces.is_empty() or room == 0:
		return false
	var list: Array = pieces.duplicate()
	if list.size() > room:
		list.shuffle()
		list = list.slice(0, room)
	var root := get_parent()
	var burst := kind in BURST_KINDS
	var flat := Vector3(dir.x, 0.0, dir.z)
	var push := flat.normalized() if flat.length_squared() > 0.001 else Vector3.ZERO
	var gxf := global_transform
	var sc := gxf.basis.get_scale().x
	var rot := Transform3D(gxf.basis.orthonormalized(), gxf.origin)
	# El estallido sale del lado contrario al golpe y algo por debajo del centro
	var center := gxf * _mesh.mesh.get_aabb().get_center()
	var blast := center - push * 0.35 - Vector3(0, 0.25, 0)
	# Solo chocan con el mundo: las piezas nacen solapadas (aros sobre duelas, techo dentro de las paredes)
	# y si chocaran entre sí la física las separaría de golpe y saldrían disparadas.
	var piece_mask := 1
	for p in list:
		var aabb: AABB = p["aabb"]
		var local_center: Vector3 = (p["xf"] as Transform3D) * aabb.get_center()
		var size := (aabb.size * sc).max(Vector3(0.02, 0.02, 0.02))
		var rb := RigidBody3D.new()
		rb.collision_layer = PIECE_LAYER
		rb.collision_mask = piece_mask
		rb.mass = clampf(size.x * size.y * size.z * WOOD_DENSITY, 0.2, 40.0)
		rb.continuous_cd = minf(size.x, minf(size.y, size.z)) < 0.06
		rb.linear_damp = 0.1
		rb.angular_damp = 0.6
		var pm := PhysicsMaterial.new()
		pm.bounce = 0.2
		pm.friction = 0.9
		rb.physics_material_override = pm
		# El cuerpo (sin escala: la física no la admite) gira en torno al centro de la pieza
		var mi := MeshInstance3D.new()
		mi.mesh = p["mesh"]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# vértice v -> sc * (xf * v) - sc * centro: la pieza queda centrada en el cuerpo
		var mxf := Transform3D(Basis().scaled(Vector3.ONE * sc), Vector3.ZERO) * (p["xf"] as Transform3D)
		mxf.origin -= local_center * sc
		mi.transform = mxf
		if p.has("tex_offset"):
			mi.set_instance_shader_parameter("obj_offset", p["tex_offset"])
		rb.add_child(mi)
		var cs := CollisionShape3D.new()
		if p.has("hull"):
			var pts := PackedVector3Array()
			for q in (p["hull"] as PackedVector3Array):
				pts.append(q * sc)
			var hs := ConvexPolygonShape3D.new()
			hs.points = pts
			cs.shape = hs
		else:
			var bs := BoxShape3D.new()
			bs.size = size * 0.9
			cs.shape = bs
			cs.basis = (p["xf"] as Transform3D).basis.orthonormalized()
		rb.add_child(cs)
		root.add_child(rb)
		var world_center := rot * (local_center * sc)
		rb.global_transform = Transform3D(rot.basis, world_center)
		var out := world_center - blast
		out = out.normalized() if out.length_squared() > 0.0001 else Vector3.UP
		# Cimientos (pieza plana pegada al suelo de una estructura): se quedan donde estaban
		if not burst and size.y < 0.35 and local_center.y * sc < 0.35:
			rb.freeze = true
			_track_piece(rb, randf_range(5.0, 8.0))
			continue
		if burst:
			rb.linear_velocity = out * randf_range(2.5, 5.0) + push * randf_range(1.5, 3.5) + Vector3.UP * randf_range(1.0, 3.5)
			rb.angular_velocity = Vector3(randf_range(-7.0, 7.0), randf_range(-7.0, 7.0), randf_range(-7.0, 7.0))
		else:
			# Desplome: casi sin velocidad hacia arriba, cae por su peso y se abre un poco
			rb.linear_velocity = Vector3(out.x, 0.0, out.z) * randf_range(0.6, 2.0) + push * randf_range(0.8, 2.0) + Vector3.UP * randf_range(0.0, 1.2)
			rb.angular_velocity = Vector3(randf_range(-2.5, 2.5), randf_range(-1.5, 1.5), randf_range(-2.5, 2.5))
			# Lo alto (paredes, troncos, postes) vuelca hacia donde empuja el golpe
			if size.y > 1.0:
				var fall := push if push != Vector3.ZERO else Vector3(out.x, 0.0, out.z).normalized()
				rb.angular_velocity += Vector3.UP.cross(fall) * randf_range(1.2, 2.2)
		_track_piece(rb, randf_range(5.0, 8.0) if not Quality.is_mobile() else randf_range(3.5, 5.0))
	return true

## Cuenta la pieza y la retira pasado un tiempo hundiéndola en el suelo (no encogiéndola).
static func _track_piece(rb: RigidBody3D, life: float) -> void:
	_alive_pieces += 1
	rb.tree_exited.connect(func(): _alive_pieces -= 1)
	var tw := rb.create_tween()
	tw.tween_interval(life)
	tw.tween_callback(func():
		rb.freeze = true
		rb.collision_layer = 0
		rb.collision_mask = 0)
	tw.tween_method(func(d: float): rb.global_position.y -= d, 0.0, 0.012, 1.2)   # se hunde poco a poco
	tw.tween_callback(rb.queue_free)

# ───────────────────────────── Astillas y polvo ─────────────────────────────

func _spawn_debris(pos: Vector3, dir: Vector3, frac: float = 1.0) -> void:
	var col: Color = DEBRIS_COLORS.get(kind, Color(0.45, 0.3, 0.18))
	var cfg: Dictionary = STRUCTURE.get(kind, {})
	var root := get_parent()
	# Astillas con física real: caen, rebotan en el suelo, ruedan y se quedan un rato.
	var n := maxi(2, Quality.count(int(float(cfg.get("chips", 10)) * frac)))
	n = mini(n, maxi(0, max_pieces() - _alive_pieces))
	var plank_len: float = float(cfg.get("chip_len", 0.25)) * 0.6
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 1.0
	var flat := Vector3(dir.x, 0.0, dir.z)
	var bias := flat.normalized() if flat.length_squared() > 0.001 else Vector3.ZERO
	for i in n:
		var piece := _make_chip(mat, plank_len)
		root.add_child(piece)
		piece.global_position = pos + Vector3(randf_range(-0.25, 0.25), randf_range(0.0, 0.4), randf_range(-0.25, 0.25))
		piece.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		var out := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized()
		piece.linear_velocity = (out * randf_range(1.5, 4.0) + bias * randf_range(1.5, 4.5) * frac) + Vector3.UP * randf_range(3.0, 7.0)
		piece.angular_velocity = Vector3(randf_range(-12.0, 12.0), randf_range(-12.0, 12.0), randf_range(-12.0, 12.0))

## Nube de polvo: grande y lenta en las estructuras, corta en barriles y cajas.
func _spawn_dust(pos: Vector3) -> void:
	var big := max_hp > 30.0
	var dust := CPUParticles3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.9, 0.9) if big else Vector2(0.55, 0.55)
	var dmat := StandardMaterial3D.new()
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dmat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dmat.vertex_color_use_as_albedo = true
	dmat.albedo_texture = _dust_texture()
	quad.material = dmat
	dust.mesh = quad
	dust.one_shot = true
	dust.explosiveness = 0.85
	dust.amount = maxi(3, Quality.count(22 if big else 10))
	dust.lifetime = 1.8 if big else 0.9
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	dust.emission_sphere_radius = 1.2 if big else 0.35
	dust.direction = Vector3.UP
	dust.spread = 75.0
	dust.initial_velocity_min = 0.4
	dust.initial_velocity_max = 1.8 if big else 2.4
	dust.gravity = Vector3(0, 0.35, 0)
	dust.damping_min = 1.5
	dust.damping_max = 3.0
	dust.angle_min = 0.0
	dust.angle_max = 360.0
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.5))
	curve.add_point(Vector2(1.0, 1.8))
	dust.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(0.5, 0.45, 0.38, 0.55))
	grad.set_color(1, Color(0.5, 0.45, 0.38, 0.0))
	dust.color_ramp = grad
	dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(dust)
	dust.global_position = pos
	dust.emitting = true
	get_tree().create_timer(dust.lifetime + 0.5).timeout.connect(dust.queue_free)

static var _dust_tex: Texture2D
## Mancha redonda y suave para el polvo (se genera una vez).
static func _dust_texture() -> Texture2D:
	if _dust_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(0.5, 0.0)
		gt.width = 64
		gt.height = 64
		_dust_tex = gt
	return _dust_tex

## Una astilla suelta: tabla o taco de madera. Colisiona solo con el mundo (capa 32 -> máscara 1),
## así no estorba al jugador ni a los enemigos.
func _make_chip(mat: Material, plank_len: float) -> RigidBody3D:
	var sz: Vector3
	if randf() < 0.65:
		sz = Vector3(randf_range(0.03, 0.06), randf_range(0.015, 0.03), plank_len * randf_range(0.6, 1.3))
	else:
		var c := randf_range(0.04, 0.08)
		sz = Vector3(c, c * randf_range(0.6, 1.0), c * randf_range(0.8, 1.4))
	var rb := RigidBody3D.new()
	rb.collision_layer = PIECE_LAYER
	rb.collision_mask = 1
	rb.mass = 0.2
	rb.continuous_cd = true
	rb.linear_damp = 0.15
	rb.angular_damp = 0.8
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.35
	pm.friction = 0.8
	rb.physics_material_override = pm
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = sz
	cs.shape = bs
	rb.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	bm.material = mat
	mi.mesh = bm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rb.add_child(mi)
	_track_piece(rb, randf_range(2.5, 4.0))
	return rb
