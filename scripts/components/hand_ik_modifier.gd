class_name HandIKModifier
extends SkeletonModifier3D

## IK de las dos manos sobre un arma sujeta (solo mazmorra): lleva cada muñeca a su objetivo
## (RHTarget / LHTarget del ancla del arma) con IK analítico de dos huesos y un polo explícito para
## el codo, conservando la orientación animada de la mano. La mezcla la da `influence`
## (PlayerAnimationController la sube al equipar el arma).

const ARMS := [["mixamorig_RightArm", "mixamorig_RightForeArm", "mixamorig_RightHand"],
	["mixamorig_LeftArm", "mixamorig_LeftForeArm", "mixamorig_LeftHand"]]

var targets: Array[Node3D] = [null, null]
var poles: Array[Node3D] = [null, null]
## Pivote del arma: se coloca en el hombro derecho animado antes de resolver (el ancla cuelga de él)
var pivot: Node3D
var _ids := []

func setup(skel: Skeleton3D, rh: Node3D, lh: Node3D, pole_r: Node3D, pole_l: Node3D) -> bool:
	_ids.clear()
	for arm in ARMS:
		var ids := []
		for b in arm:
			var i := skel.find_bone(b)
			if i < 0:
				return false
			ids.append(i)
		_ids.append(ids)
	targets = [rh, lh]
	poles = [pole_r, pole_l]
	return true

func _process_modification_with_delta(_delta: float) -> void:
	var skel := get_skeleton()
	if skel == null or _ids.size() != 2:
		return
	if is_instance_valid(pivot):
		pivot.position = skel.get_bone_global_pose(_ids[0][0]).origin
	if influence <= 0.0:
		return
	var to_skel := skel.global_transform.affine_inverse()
	for i in 2:
		if not is_instance_valid(targets[i]) or not is_instance_valid(poles[i]):
			continue
		_solve(skel, _ids[i], to_skel * targets[i].global_position, to_skel * poles[i].global_position)

## Dos huesos (brazo, antebrazo) hacia `target`, con el codo en el plano que marca `pole`.
func _solve(skel: Skeleton3D, ids: Array, target: Vector3, pole: Vector3) -> void:
	var pa := skel.get_bone_global_pose(ids[0])
	var pb := skel.get_bone_global_pose(ids[1])
	var pc := skel.get_bone_global_pose(ids[2])
	var a := pa.origin
	var b := pb.origin
	var c := pc.origin
	var len_a := a.distance_to(b)
	var len_b := b.distance_to(c)
	var to_t := target - a
	if to_t.length_squared() < 1e-14 or len_a < 1e-9 or len_b < 1e-9:
		return
	var d := clampf(to_t.length(), absf(len_a - len_b) + 1e-6, len_a + len_b - 1e-6)
	var dir := to_t.normalized()
	var bend := (pole - a) - dir * (pole - a).dot(dir)
	if bend.length_squared() < 1e-14:
		bend = (b - a) - dir * (b - a).dot(dir)
	if bend.length_squared() < 1e-14:
		return
	bend = bend.normalized()
	var cos_a := clampf((len_a * len_a + d * d - len_b * len_b) / (2.0 * len_a * d), -1.0, 1.0)
	var new_b := a + dir * (len_a * cos_a) + bend * (len_a * sqrt(1.0 - cos_a * cos_a))
	var new_c := a + dir * d
	var hand_basis := pc.basis
	# Brazo: apunta al nuevo codo
	var q1 := Quaternion((b - a).normalized(), (new_b - a).normalized())
	pa.basis = Basis(q1) * pa.basis
	skel.set_bone_global_pose(ids[0], pa)
	# Antebrazo: hereda q1 y apunta a la nueva muñeca
	var c_after := new_b + q1 * (c - b)
	var q2 := Quaternion((c_after - new_b).normalized(), (new_c - new_b).normalized())
	pb.basis = Basis(q2) * Basis(q1) * pb.basis
	pb.origin = new_b
	skel.set_bone_global_pose(ids[1], pb)
	# Mano: en el objetivo, con la orientación animada
	pc.origin = new_c
	pc.basis = hand_basis
	skel.set_bone_global_pose(ids[2], pc)
