class_name BowModels
extends RefCounted

## Los tres arcos (assets/models/weapons/arcos/*.glb, uno por archivo). Como SwordModels: se midieron una vez
## (tools/fit_bow_models.gd, en el espacio de la raíz del glb) y build() devuelve el arco normalizado:
##  - palas a lo largo de +Y (de la empuñadura a la punta de arriba),
##  - la flecha sale hacia -Z (la cuerda queda en +Z),
##  - el origen es donde cierra la mano izquierda (la empuñadura).
##
## up/fwd: ejes del glb a lo largo de las palas y hacia donde sale la flecha. grip: centro de la empuñadura (unidades
## del glb). len: largo de punta a punta (unidades del glb). world_len: largo en el juego (m). string: [a, b] puntas de
## la cuerda (unidades del glb) para los arcos que no la traen modelada; brace: distancia empuñadura-cuerda (m).
const SKINS: Array[Dictionary] = [
	{"id": "rustico", "name": "Arco Rústico", "path": "res://assets/models/weapons/arcos/cool_bow.glb",
		"up": Vector3(1, 0, 0), "fwd": Vector3(0, 0, 1), "grip": Vector3(0.0, 0.0, 0.38),
		"len": 4.2846, "world_len": 1.35, "brace": 0.22, "color": Color(1.0, 0.8, 0.45)},
	{"id": "fantasia", "name": "Arco de Fantasía", "path": "res://assets/models/weapons/arcos/fantasy_bow.glb",
		"up": Vector3(0, 1, 0), "fwd": Vector3(-1, 0, 0), "grip": Vector3(-20.0, 0.0, 0.0),
		"len": 1240.39, "world_len": 1.35, "brace": 0.13, "color": Color(0.55, 0.85, 1.0)},
	{"id": "espinas", "name": "Arco de Espinas", "path": "res://assets/models/weapons/arcos/bow.glb",
		"up": Vector3(1, 0, 0), "fwd": Vector3(0, -1, 0), "grip": Vector3(0.0, 0.5, -0.06),
		"len": 192.58, "world_len": 1.25, "brace": 0.14, "color": Color(0.6, 1.0, 0.4),
		"string": [Vector3(-93.0, 21.5, 0.0), Vector3(93.0, 21.5, 0.0)]},
]

static func count() -> int:
	return SKINS.size()

static func skin(i: int) -> Dictionary:
	return SKINS[clampi(i, 0, SKINS.size() - 1)]

static func skin_name(i: int) -> String:
	return String(skin(i)["name"])

static func skin_color(i: int) -> Color:
	return skin(i)["color"]

## Media longitud del arco (m): de la empuñadura a cada punta.
static func half_len(i: int) -> float:
	return float(skin(i)["world_len"]) * 0.5

## Distancia (m) de la empuñadura a la cuerda en reposo: ahí se encaja la flecha.
static func brace(i: int) -> float:
	return float(skin(i)["brace"])

## Transformación (en el espacio de la raíz del glb) que deja el arco normalizado (ver arriba).
static func fit_transform(i: int) -> Transform3D:
	var s := skin(i)
	var up: Vector3 = (s["up"] as Vector3).normalized()
	var fwd: Vector3 = s["fwd"]
	fwd = (fwd - up * fwd.dot(up)).normalized()
	var z := -fwd
	var x := up.cross(z).normalized()
	var b := Basis(x, up, z).transposed()
	b = b.scaled(Vector3.ONE * (float(s["world_len"]) / float(s["len"])))
	return Transform3D(b, -(b * (s["grip"] as Vector3)))

## Arco listo para colgar de la mano: todas sus mallas (sin esqueleto: el de "espinas" viene con huesos) bajo un
## nodo con la transformación normalizada.
static func build(i: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Arco_" + String(skin(i)["id"])
	var scene := load(String(skin(i)["path"])) as PackedScene
	if scene == null:
		return root
	var holder := Node3D.new()
	holder.name = "Modelo"
	holder.transform = fit_transform(i)
	root.add_child(holder)
	var glb := scene.instantiate() as Node3D
	for mi in glb.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var xf := Transform3D.IDENTITY
		var n: Node = m
		while n != null and n != glb:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		m.get_parent().remove_child(m)
		m.owner = null
		m.skin = null
		m.skeleton = NodePath()
		m.transform = xf
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		holder.add_child(m)
	glb.free()
	var s := skin(i)
	if s.has("string"):
		var pts: Array = s["string"]
		var f := fit_transform(i)
		root.add_child(_string_mesh(f * (pts[0] as Vector3), f * (pts[1] as Vector3)))
	return root

## Cuerda fina entre dos puntos (ejes ya normalizados).
static func _string_mesh(a: Vector3, b: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Cuerda"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.0025
	cyl.bottom_radius = 0.0025
	cyl.height = a.distance_to(b)
	cyl.radial_segments = 4
	cyl.rings = 1
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.82, 0.7)
	mat.roughness = 0.8
	cyl.material = mat
	mi.mesh = cyl
	var y := (b - a).normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	mi.transform = Transform3D(Basis(x, y, x.cross(y)), (a + b) * 0.5)
	return mi

## Flecha (m): asta a lo largo de -Z con la punta en -largo, el culatín (donde va la cuerda) en el origen.
static func build_arrow(color: Color = Color(1.0, 0.85, 0.5), glow: float = 0.0) -> Node3D:
	var root := Node3D.new()
	root.name = "Flecha"
	const LEN := 0.78
	var shaft := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.0055
	cyl.bottom_radius = 0.0055
	cyl.height = LEN
	cyl.radial_segments = 5
	cyl.rings = 1
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.55, 0.38, 0.22)
	wood.roughness = 0.85
	cyl.material = wood
	shaft.mesh = cyl
	shaft.rotation.x = PI * 0.5
	shaft.position.z = -LEN * 0.5
	root.add_child(shaft)
	var head := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.018
	cone.height = 0.07
	cone.radial_segments = 4
	cone.rings = 1
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.75, 0.75, 0.8)
	steel.metallic = 0.8
	steel.roughness = 0.35
	if glow > 0.0:
		steel.emission_enabled = true
		steel.emission = color
		steel.emission_energy_multiplier = glow
	cone.material = steel
	head.mesh = cone
	head.rotation.x = -PI * 0.5
	head.position.z = -LEN - 0.03
	root.add_child(head)
	# Plumas: dos planos cruzados cerca del culatín
	var feather := StandardMaterial3D.new()
	feather.albedo_color = color
	feather.cull_mode = BaseMaterial3D.CULL_DISABLED
	if glow > 0.0:
		feather.emission_enabled = true
		feather.emission = color
		feather.emission_energy_multiplier = glow * 0.6
	for k in 2:
		var f := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.035, 0.12)
		q.material = feather
		f.mesh = q
		# Plano a lo largo del asta (Z); la segunda, girada 90° sobre el asta
		f.transform = Transform3D(Basis(Vector3.BACK, PI * 0.5 * k) * Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, -0.09))
		root.add_child(f)
	return root
