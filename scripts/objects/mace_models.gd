class_name MaceModels
extends RefCounted

## Los cinco modelos de maza (assets/models/weapons/mazas). Igual que GreatswordModels: cada .glb se
## mide una vez (tools/fit_melee_models.gd) y build() devuelve la maza normalizada:
## mango a lo largo de +Y (pomo abajo, cabeza arriba), el ancho en X y el origen en el punto donde
## cierra la mano derecha (la izquierda agarra más abajo, en el mango).
##
## pommel/up/wide/len: eje pomo -> cabeza del modelo, dirección del ancho y largo, en unidades del glb.
## world_len: largo de la maza en el juego (m). grip: dónde cierra la mano derecha, fracción del largo
## contada desde el pomo. head: centro de la cabeza, fracción desde el pomo (para la estela).
const SKINS: Array[Dictionary] = [
	{"id": "hueso", "name": "Maza de Hueso", "path": "res://assets/models/weapons/mazas/bone_mace.glb",
		"pommel": Vector3(-3.785218, 3.748814, -45.63988), "up": Vector3(0.04636, 0.012973, 0.998841),
		"wide": Vector3(-0.995071, -0.087148, 0.047317), "len": 121.2064, "world_len": 1.00, "grip": 0.15,
		"head": 0.86, "color": Color(0.9, 0.85, 0.7)},
	{"id": "mekka", "name": "Maza Mekka", "path": "res://assets/models/weapons/mazas/mekka_mace.glb",
		"pommel": Vector3(-0.000007, -0.5625, 0.000007), "up": Vector3(0.0, 1.0, 0.0),
		"wide": Vector3(-0.766044, 0.0, 0.642788), "len": 2.9375, "world_len": 0.95, "grip": 0.16,
		"head": 0.84, "color": Color(0.55, 0.85, 1.0)},
	{"id": "hierro", "name": "Maza de Hierro", "path": "res://assets/models/weapons/mazas/mace_model_textured.glb",
		"pommel": Vector3(0.130815, -0.058215, -0.000132), "up": Vector3(-0.064271, 0.997932, 0.000082),
		"wide": Vector3(-0.982772, -0.063309, 0.173643), "len": 2.475, "world_len": 1.00, "grip": 0.15,
		"head": 0.70, "color": Color(0.75, 0.78, 0.85)},
	{"id": "calavera", "name": "Maza Calavera", "path": "res://assets/models/weapons/mazas/skull_mace.glb",
		"pommel": Vector3(0.332882, -0.845157, 1.391056), "up": Vector3(-0.004233, 0.999809, -0.01908),
		"wide": Vector3(0.0, -0.01908, -0.999818), "len": 5.5562, "world_len": 0.98, "grip": 0.15,
		"head": 0.80, "color": Color(1.0, 0.9, 0.55)},
	{"id": "negro", "name": "Maza de Hierro Negro", "path": "res://assets/models/weapons/mazas/spiked_black_iron_mace.glb",
		"pommel": Vector3(2.758595, -1.218024, -0.002877), "up": Vector3(-0.914565, 0.404439, 0.000755),
		"wide": Vector3(-0.404439, -0.914565, 0.000334), "len": 5.9567, "world_len": 1.00, "grip": 0.15,
		"head": 0.80, "color": Color(0.65, 0.3, 1.0)},
]

static func count() -> int:
	return SKINS.size()

static func skin(i: int) -> Dictionary:
	return SKINS[clampi(i, 0, SKINS.size() - 1)]

static func skin_name(i: int) -> String:
	return String(skin(i)["name"])

static func skin_color(i: int) -> Color:
	return skin(i)["color"]

static func tip_y(i: int) -> float:
	var s := skin(i)
	return float(s["world_len"]) * (1.0 - float(s["grip"]))

static func pommel_y(i: int) -> float:
	var s := skin(i)
	return -float(s["world_len"]) * float(s["grip"])

## Centro de la cabeza desde el origen (la mano), en metros.
static func head_y(i: int) -> float:
	var s := skin(i)
	return float(s["world_len"]) * (float(s["head"]) - float(s["grip"]))

## Media altura de la cabeza (para la estela del golpe), en metros.
static func head_span(i: int) -> float:
	return float(skin(i)["world_len"]) * 0.14

static func fit_transform(i: int) -> Transform3D:
	var s := skin(i)
	var up: Vector3 = (s["up"] as Vector3).normalized()
	var pommel: Vector3 = s["pommel"]
	var len: float = float(s["len"])
	if bool(s.get("flip", false)):
		pommel += up * len
		up = -up
	var wide: Vector3 = s["wide"]
	wide = (wide - up * wide.dot(up)).normalized()
	var z := wide.cross(up).normalized()
	var b := Basis(wide, up, z).transposed()
	var k: float = float(s["world_len"]) / len
	b = b.scaled(Vector3.ONE * k)
	var grip_pt: Vector3 = pommel + up * (float(s["grip"]) * len)
	return Transform3D(b, -(b * grip_pt))

static func build(i: int) -> Node3D:
	var scene := load(String(skin(i)["path"])) as PackedScene
	var root := Node3D.new()
	root.name = "Maza_" + String(skin(i)["id"])
	if scene == null:
		return root
	var model := scene.instantiate() as Node3D
	model.transform = fit_transform(i)
	root.add_child(model)
	return root
