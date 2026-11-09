class_name DaggerModels
extends RefCounted

## Los cuatro modelos de daga (assets/models/weapons/dagas). Igual que GreatswordModels: cada .glb se
## mide una vez (tools/fit_melee_models.gd) y build() devuelve la daga normalizada:
## hoja a lo largo de +Y (pomo abajo, punta arriba), el ancho de la hoja en X y el origen en el
## punto donde cierra la mano.
##
## pommel/up/wide/len: eje pomo -> punta del modelo, dirección del ancho de hoja y largo, en unidades
## del glb. world_len: largo de la daga en el juego (m). grip: dónde cierra la mano, fracción del
## largo contada desde el pomo.
## flip: el medidor confundió punta y pomo; se da la vuelta al eje antes de normalizar.
const SKINS: Array[Dictionary] = [
	{"id": "china", "name": "Daga China", "path": "res://assets/models/weapons/dagas/chinese_style_dagger.glb",
		"pommel": Vector3(-0.004887, 2.694942, 0.116574), "up": Vector3(-0.001073, -0.999023, -0.044181),
		"wide": Vector3(-0.087156, 0.044106, -0.995218), "len": 2.709, "world_len": 0.42, "grip": 0.24,
		"color": Color(1.0, 0.3, 0.35)},
	{"id": "camuflaje", "name": "Daga de Camuflaje", "path": "res://assets/models/weapons/dagas/cloaking_dagger.glb",
		"pommel": Vector3(0.187739, -0.000001, -6.860887), "up": Vector3(0.001047, 0.0, 0.999999),
		"wide": Vector3(-0.999999, 0.0, 0.001047), "len": 9.9992, "world_len": 0.44, "grip": 0.20,
		"color": Color(0.55, 1.0, 0.65)},
	{"id": "acero", "name": "Daga de Acero", "path": "res://assets/models/weapons/dagas/dague.glb",
		"pommel": Vector3(-0.000022, -3.999088, 0.000005), "up": Vector3(-0.000098, 1.0, 0.0),
		"wide": Vector3(-1.0, -0.000098, 0.0), "len": 12.0777, "world_len": 0.40, "grip": 0.22,
		"color": Color(0.8, 0.9, 1.0)},
	{"id": "runica", "name": "Daga Rúnica", "path": "res://assets/models/weapons/dagas/dague_runes.glb",
		"pommel": Vector3(-2.564771, 2.014666, 0.283836), "up": Vector3(0.711135, 0.671334, -0.208801),
		"wide": Vector3(0.527555, -0.313226, 0.789668), "len": 11.9681, "world_len": 0.44, "grip": 0.22,
		"color": Color(0.45, 0.75, 1.0)},
]

static func count() -> int:
	return SKINS.size()

static func skin(i: int) -> Dictionary:
	return SKINS[clampi(i, 0, SKINS.size() - 1)]

static func skin_name(i: int) -> String:
	return String(skin(i)["name"])

static func skin_color(i: int) -> Color:
	return skin(i)["color"]

## Largo desde el origen (la mano) hasta la punta y hasta el pomo (negativo), en metros.
static func tip_y(i: int) -> float:
	var s := skin(i)
	return float(s["world_len"]) * (1.0 - float(s["grip"]))

static func pommel_y(i: int) -> float:
	var s := skin(i)
	return -float(s["world_len"]) * float(s["grip"])

## Transformación del glb para dejarlo normalizado (ver GreatswordModels).
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
	root.name = "Daga_" + String(skin(i)["id"])
	if scene == null:
		return root
	var model := scene.instantiate() as Node3D
	model.transform = fit_transform(i)
	root.add_child(model)
	return root
