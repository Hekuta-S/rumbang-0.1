class_name GreatswordModels
extends RefCounted

## Los cuatro modelos de espadón (assets/models/weapons/espadones). Cada .glb viene con su propia orientación y
## escala, así que aquí se miden una vez (tools/fit_swords.gd) y build() devuelve el espadón normalizado:
## hoja a lo largo de +Y (pomo abajo, punta arriba), el ancho de la hoja en X y el origen en el punto donde
## cierra la mano derecha. La izquierda agarra la empuñadura más abajo (el mango mide ~0,4 m).
##
## pommel/up/wide/len: eje pomo -> punta del modelo, dirección del ancho de hoja y largo, en unidades del glb.
## world_len: largo del espadón en el juego (m). grip: dónde cierra la mano derecha, fracción del largo contada
## desde el pomo (justo debajo de la guarda).
## flip: el medidor confundió punta y pomo (la katana curva): se da la vuelta al eje pomo -> punta antes de
## normalizar. La posición del agarre (grip) sigue contándose desde el pomo real.
const SKINS: Array[Dictionary] = [
	{"id": "gotico", "name": "Espadón Gótico", "path": "res://assets/models/weapons/espadones/great_sword.glb",
		"pommel": Vector3(-448.7552, -119.2906, 179.2006), "up": Vector3(0.903795, 0.23472, -0.357857),
		"wide": Vector3(0.426739, -0.557552, 0.71206), "len": 852.4566, "world_len": 1.4, "grip": 0.22,
		"color": Color(1.0, 0.35, 0.3)},
	{"id": "matadragones", "name": "Matadragones", "path": "res://assets/models/weapons/espadones/dragonslayer.glb",
		"pommel": Vector3(-5.763079, -350.3365, 1.363186), "up": Vector3(0.00985, 0.999915, -0.008579),
		"wide": Vector3(0.0, -0.008579, -0.999963), "len": 721.7282, "world_len": 1.65, "grip": 0.17,
		"color": Color(0.85, 0.9, 1.0)},
	{"id": "gran_ola", "name": "Katana de la Gran Ola", "path": "res://assets/models/weapons/espadones/great_wave_katana.glb",
		"pommel": Vector3(1.56298, -1.934219, 0.857326), "up": Vector3(-0.646112, 0.670003, -0.365563),
		"wide": Vector3(-0.583136, -0.742359, -0.329932), "len": 5.0288, "world_len": 1.45, "grip": 0.18,
		"flip": true, "color": Color(0.4, 0.8, 1.0)},
	{"id": "obsidiana", "name": "Espadón de Obsidiana", "path": "res://assets/models/weapons/espadones/obsidian.glb",
		"pommel": Vector3(3.777206, 0.028713, 0.200554), "up": Vector3(-0.99977, -0.000571, -0.021451),
		"wide": Vector3(0.02142, -0.087156, -0.995964), "len": 9.5404, "world_len": 1.55, "grip": 0.15,
		"color": Color(0.7, 0.3, 1.0)},
]

static func count() -> int:
	return SKINS.size()

static func skin(i: int) -> Dictionary:
	return SKINS[clampi(i, 0, SKINS.size() - 1)]

static func skin_name(i: int) -> String:
	return String(skin(i)["name"])

static func skin_color(i: int) -> Color:
	return skin(i)["color"]

## Largo del espadón desde el origen (la mano) hasta la punta, y hasta el pomo (negativo), en metros.
static func tip_y(i: int) -> float:
	var s := skin(i)
	return float(s["world_len"]) * (1.0 - float(s["grip"]))

static func pommel_y(i: int) -> float:
	var s := skin(i)
	return -float(s["world_len"]) * float(s["grip"])

## Transformación del glb para dejarlo normalizado (ver arriba).
static func fit_transform(i: int) -> Transform3D:
	var s := skin(i)
	var up: Vector3 = (s["up"] as Vector3).normalized()
	var pommel: Vector3 = s["pommel"]
	var len: float = float(s["len"])
	if bool(s.get("flip", false)):
		# Punta y pomo invertidos: se toma como pomo el otro extremo y se da la vuelta al eje.
		pommel += up * len
		up = -up
	var wide: Vector3 = s["wide"]
	wide = (wide - up * wide.dot(up)).normalized()
	var z := wide.cross(up).normalized()
	# Filas = ejes del modelo que pasan a X, Y y Z del espadón normalizado
	var b := Basis(wide, up, z).transposed()
	var k: float = float(s["world_len"]) / len
	b = b.scaled(Vector3.ONE * k)
	var grip_pt: Vector3 = pommel + up * (float(s["grip"]) * len)
	return Transform3D(b, -(b * grip_pt))

## Espadón listo para colgar de la mano (sin sombras propias: va dentro del personaje).
static func build(i: int) -> Node3D:
	var scene := load(String(skin(i)["path"])) as PackedScene
	var root := Node3D.new()
	root.name = "Espadon_" + String(skin(i)["id"])
	if scene == null:
		return root
	var model := scene.instantiate() as Node3D
	model.transform = fit_transform(i)
	root.add_child(model)
	return root
