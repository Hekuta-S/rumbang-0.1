class_name BoneFollower
extends Node3D

## Sigue la posición y el giro de un hueso SIN heredar la escala del esqueleto. El personaje personalizable se dibuja
## con una escala no uniforme (proporciones, ver CharacterLookApplier), y un arma colgada de un BoneAttachment3D
## la hereda: se estira y se tuerce al rotar la mano. Con esto el arma conserva sus medidas reales (metros).
## Se actualiza cada vez que el esqueleto termina de aplicar la pose (animación + IK).

var skeleton: Skeleton3D
var bone := -1

func setup(p_skeleton: Skeleton3D, bone_name: String) -> void:
	process_priority = 1000      # después de la animación (AnimationTree) de este fotograma
	skeleton = p_skeleton
	bone = skeleton.find_bone(bone_name)
	top_level = true
	if not skeleton.skeleton_updated.is_connected(_follow):
		skeleton.skeleton_updated.connect(_follow)
	if is_inside_tree():
		_follow()

func _process(_delta: float) -> void:
	_follow()

func _enter_tree() -> void:
	if skeleton != null:
		_follow.call_deferred()

func _follow() -> void:
	if skeleton == null or bone < 0 or not is_inside_tree():
		return
	var g := skeleton.global_transform * skeleton.get_bone_global_pose(bone)
	global_transform = Transform3D(g.basis.orthonormalized(), g.origin)
