class_name KatanaModels
extends RefCounted

## Katanas míticas (cada una en su glb). Como SwordModels: medidas una vez (tools/measure_katana_glb.tscn, espacio de
## la raíz del glb) y build() devuelve la katana normalizada: hoja a lo largo de +Y, filo en X y el origen donde
## cierra la mano derecha.
##
## glb/node: archivo y nodo de la katana ("" = el glb entero). pommel/up/wide/len: punto del pomo, eje del mango
## pomo -> guarda, dirección del filo y largo total (unidades del glb). world_len: largo en el juego (m). grip: dónde
## cierra la mano derecha, fracción del largo desde el pomo (la guarda está al ~25 %).
const SKINS: Array[Dictionary] = [
	{"id": "rengoku", "name": "Katana de Sangre", "glb": "res://assets/models/katana/rengoku_katana.glb", "node": "",
		"pommel": Vector3(7.272, 17.44, -17.302), "up": Vector3(0.0, -0.032, 0.9995),
		"wide": Vector3(0, 1, 0), "len": 34.493, "world_len": 1.05, "grip": 0.2,
		"color": Color(1.0, 0.12, 0.08)},
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

## Katana lista para colgar de la mano.
static func build(i: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Katana_" + String(skin(i)["id"])
	var scene := load(String(skin(i)["glb"])) as PackedScene
	if scene == null:
		return root
	var glb := scene.instantiate() as Node3D
	var holder := Node3D.new()
	holder.name = "Modelo"
	holder.transform = fit_transform(i)
	root.add_child(holder)
	var node := String(skin(i)["node"])
	var src: Node3D = glb if node == "" else glb.find_child(node, true, false) as Node3D
	if src == null:
		glb.free()
		return root
	if src == glb:
		holder.add_child(glb)
	else:
		var keep_xf := src.transform
		src.get_parent().remove_child(src)
		src.owner = null
		holder.add_child(src)
		src.transform = keep_xf
		glb.free()
	return root
