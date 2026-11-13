class_name SwordModels
extends RefCounted

## Las cuatro espadas de una mano (assets/models/weapons/espadas/finns_swords.glb). Las cuatro van en el mismo
## glb, de pie una al lado de otra (punta arriba, pomo abajo), cada una en su nodo hijo de GLTF_SceneRootNode.
## Igual que GreatswordModels: se midieron una vez (tools/fit_sword_models.gd, en el espacio de
## GLTF_SceneRootNode) y build() devuelve la espada normalizada: hoja a lo largo de +Y, ancho en X y el origen
## donde cierra la mano derecha.
##
## node: nodo de la espada en el glb. pommel/up/wide/len: eje pomo -> punta, dirección del ancho y largo (unidades
## del glb). world_len: largo en el juego (m). grip: dónde cierra la mano, fracción del largo desde el pomo.
const GLB_PATH := "res://assets/models/weapons/espadas/finns_swords.glb"
const SKINS: Array[Dictionary] = [
	{"id": "dorada", "name": "Espada Dorada", "node": "gold sword_0",
		"pommel": Vector3(-63.01278, -19.04557, -1.159015), "up": Vector3(-0.000055, 0.999939, 0.011086),
		"wide": Vector3(1, 0, 0), "len": 104.5403, "world_len": 0.95, "grip": 0.17,
		"color": Color(1.0, 0.85, 0.3)},
	{"id": "4d", "name": "Espada 4D", "node": "4D sword_2",
		"pommel": Vector3(-36.43923, -26.4942, -0.771094), "up": Vector3(0.006079, 0.999979, 0.002371),
		"wide": Vector3(1, 0, 0), "len": 116.5345, "world_len": 1.0, "grip": 0.19,
		"color": Color(0.85, 0.85, 1.0)},
	{"id": "raiz", "name": "Espada de Raíz", "node": "root sword_3",
		"pommel": Vector3(-0.416791, -28.87088, -0.493496), "up": Vector3(0.008685, 0.999953, 0.00435),
		"wide": Vector3(1, 0, 0), "len": 113.4779, "world_len": 1.0, "grip": 0.3,
		"color": Color(0.95, 0.8, 0.85)},
	{"id": "sangre_demonio", "name": "Espada de Sangre de Demonio", "node": "demon blood sword_4",
		"pommel": Vector3(35.17937, -42.14687, -0.000046), "up": Vector3(0.008889, 0.999961, 0.0),
		"wide": Vector3(1, 0, 0), "len": 147.7138, "world_len": 1.2, "grip": 0.27,
		"color": Color(1.0, 0.15, 0.1)},
]

static func count() -> int:
	return SKINS.size()

static func skin(i: int) -> Dictionary:
	return SKINS[clampi(i, 0, SKINS.size() - 1)]

static func skin_name(i: int) -> String:
	return String(skin(i)["name"])

static func skin_color(i: int) -> Color:
	return skin(i)["color"]

## Largo de la espada desde el origen (la mano) hasta la punta, y hasta el pomo (negativo), en metros.
static func tip_y(i: int) -> float:
	var s := skin(i)
	return float(s["world_len"]) * (1.0 - float(s["grip"]))

static func pommel_y(i: int) -> float:
	var s := skin(i)
	return -float(s["world_len"]) * float(s["grip"])

## Transformación (en el espacio de GLTF_SceneRootNode) que deja la espada normalizada (ver arriba).
static func fit_transform(i: int) -> Transform3D:
	var s := skin(i)
	var up: Vector3 = (s["up"] as Vector3).normalized()
	var pommel: Vector3 = s["pommel"]
	var len: float = float(s["len"])
	var wide: Vector3 = s["wide"]
	wide = (wide - up * wide.dot(up)).normalized()
	var z := wide.cross(up).normalized()
	var b := Basis(wide, up, z).transposed()
	b = b.scaled(Vector3.ONE * (float(s["world_len"]) / len))
	var grip_pt: Vector3 = pommel + up * (float(s["grip"]) * len)
	return Transform3D(b, -(b * grip_pt))

## Espada lista para colgar de la mano: solo el nodo de la espada elegida, con su transformación del glb.
static func build(i: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Espada_" + String(skin(i)["id"])
	var scene := load(GLB_PATH) as PackedScene
	if scene == null:
		return root
	var glb := scene.instantiate() as Node3D
	var src := glb.find_child(String(skin(i)["node"]), true, false) as Node3D
	if src != null:
		var holder := Node3D.new()
		holder.name = "Modelo"
		holder.transform = fit_transform(i)
		root.add_child(holder)
		var keep_xf := src.transform
		src.get_parent().remove_child(src)
		src.owner = null
		holder.add_child(src)
		src.transform = keep_xf
	glb.free()
	return root
