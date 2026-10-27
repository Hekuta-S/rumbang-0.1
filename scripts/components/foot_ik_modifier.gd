class_name FootIKModifier
extends SkeletonModifier3D

## Animación procedural de pies: se aplica DESPUÉS de la animación (AnimationTree)
## y corrige las piernas con IK de dos huesos (muslo → pierna → pie):
##  - Los pies nunca atraviesan el suelo (sentadillas y clavados exagerados).
##  - En terreno irregular cada pie sigue la altura real del suelo bajo él y la
##    cadera baja lo necesario para que el pie más bajo llegue.
## Solo actúa con el jugador en el suelo; en el aire se desvanece (influence).

const LEGS := [
	["mixamorig_LeftUpLeg", "mixamorig_LeftLeg", "mixamorig_LeftFoot"],
	["mixamorig_RightUpLeg", "mixamorig_RightLeg", "mixamorig_RightFoot"],
]
const HIPS := "mixamorig_Hips"
const BLEND_SPEED := 10.0      ## velocidad de entrada/salida del IK (1/s)
const PELVIS_SPEED := 12.0     ## suavizado del ajuste de cadera (1/s)
const MAX_PELVIS_DROP := 0.45  ## m

var player: CharacterBody3D
var _bones: Array = []          # [[upleg, leg, foot], ...] índices
var _hips: int = -1
var _ankle_h: float = -1.0      # altura del tobillo sobre el suelo en reposo (m), medida en juego
var _pelvis: float = 0.0        # desplazamiento actual de cadera (m, mundo)
var _weight: float = 0.0
## Altura (mundo) del pie más bajo tras aplicar el IK en el último frame (depuración/pruebas).
var last_lowest_foot: float = 0.0

func setup(p_player: CharacterBody3D) -> bool:
	player = p_player
	var skel := get_skeleton()
	if skel == null:
		return false
	_hips = skel.find_bone(HIPS)
	_bones.clear()
	for leg in LEGS:
		var ids := [skel.find_bone(leg[0]), skel.find_bone(leg[1]), skel.find_bone(leg[2])]
		if ids.has(-1):
			return false
		_bones.append(ids)
	return _hips >= 0

func _floor_y(x: float, z: float) -> float:
	var map := get_tree().get_first_node_in_group("procedural_map")
	if map and map.has_method("get_height_at"):
		return map.get_height_at(x, z)
	return player.global_position.y

func _process_modification_with_delta(delta: float) -> void:
	var skel := get_skeleton()
	if skel == null or _bones.is_empty() or not is_instance_valid(player):
		return
	var grounded := player.is_on_floor()
	_weight = move_toward(_weight, 1.0 if grounded else 0.0, BLEND_SPEED * delta)
	if _weight <= 0.001:
		_pelvis = 0.0
		return

	var xf := skel.global_transform
	var inv := xf.affine_inverse()
	var to_world := xf.basis.get_scale().y        # metros por unidad de esqueleto
	var base_floor := _floor_y(player.global_position.x, player.global_position.z)

	# Altura del tobillo en reposo: se mide una vez con el jugador quieto en el suelo
	if _ankle_h < 0.0 and grounded:
		var lowest := INF
		for ids in _bones:
			lowest = minf(lowest, (xf * skel.get_bone_global_pose(ids[2]).origin).y - base_floor)
		_ankle_h = clampf(lowest, 0.02, 0.2)
	var ankle := maxf(_ankle_h, 0.02)

	# Objetivo de cada pie en mundo: misma altura relativa que en la animación,
	# trasladada al suelo real bajo el pie, y nunca por debajo del suelo.
	var targets: Array[Vector3] = []
	var needed_drop := 0.0
	for ids in _bones:
		var foot_w: Vector3 = xf * skel.get_bone_global_pose(ids[2]).origin
		var fy := _floor_y(foot_w.x, foot_w.z)
		var ty := maxf(foot_w.y + (fy - base_floor), fy + ankle)
		needed_drop = minf(needed_drop, ty - foot_w.y)
		targets.append(Vector3(foot_w.x, ty, foot_w.z))
	_pelvis = lerpf(_pelvis, clampf(needed_drop, -MAX_PELVIS_DROP, 0.0), minf(PELVIS_SPEED * delta, 1.0))

	# Bajar la cadera (en espacio de esqueleto)
	if absf(_pelvis) > 0.0005:
		var hp := skel.get_bone_global_pose(_hips)
		hp.origin += inv.basis * Vector3(0.0, _pelvis * _weight, 0.0)
		skel.set_bone_global_pose(_hips, hp)

	var lowest := INF
	for i in _bones.size():
		var t_skel: Vector3 = inv * targets[i]
		_solve_two_bone(skel, _bones[i], t_skel)
		lowest = minf(lowest, (xf * skel.get_bone_global_pose(_bones[i][2]).origin).y)
	last_lowest_foot = lowest

## IK analítico de dos huesos conservando el plano de la rodilla de la animación.
func _solve_two_bone(skel: Skeleton3D, ids: Array, target: Vector3) -> void:
	var pa := skel.get_bone_global_pose(ids[0])
	var pb := skel.get_bone_global_pose(ids[1])
	var pc := skel.get_bone_global_pose(ids[2])
	var a := pa.origin
	var b := pb.origin
	var c := pc.origin
	# Mezcla con la pose animada según el peso
	target = c.lerp(target, _weight)
	if c.distance_squared_to(target) < 1e-12:
		return
	var len_a := a.distance_to(b)
	var len_b := b.distance_to(c)
	var to_t := target - a
	var d := clampf(to_t.length(), absf(len_a - len_b) + 1e-6, len_a + len_b - 1e-6)
	var dir := to_t.normalized()
	# Polo: hacia donde ya apunta la rodilla
	var knee := (b - a) - dir * (b - a).dot(dir)
	if knee.length_squared() < 1e-12:
		knee = pa.basis.z
	knee = knee.normalized()
	var cos_a := clampf((len_a * len_a + d * d - len_b * len_b) / (2.0 * len_a * d), -1.0, 1.0)
	var new_b := a + dir * (len_a * cos_a) + knee * (len_a * sqrt(1.0 - cos_a * cos_a))
	var new_c := a + dir * d

	# Muslo: rotar para que apunte a la nueva rodilla
	var q1 := Quaternion((b - a).normalized(), (new_b - a).normalized())
	pa.basis = Basis(q1) * pa.basis
	skel.set_bone_global_pose(ids[0], pa)
	# Pierna: hereda q1 y luego apunta al nuevo tobillo
	var c_after := new_b + q1 * (c - b)
	var q2 := Quaternion((c_after - new_b).normalized(), (new_c - new_b).normalized())
	pb.basis = Basis(q2) * Basis(q1) * pb.basis
	pb.origin = new_b
	skel.set_bone_global_pose(ids[1], pb)
	# Pie: conserva la orientación animada
	pc.origin = new_c
	skel.set_bone_global_pose(ids[2], pc)
