class_name LookHeadModifier
extends SkeletonModifier3D

## Escala la cabeza del personaje personalizable DESPUÉS de la animación (CharacterLook.head).
## Los modificadores no acumulan entre frames: el esqueleto restaura la pose al terminar.

const HEAD_BONE := "mixamorig_Head"

var head_scale := Vector3.ONE
var _head := -1

func _process_modification_with_delta(_delta: float) -> void:
	if head_scale.is_equal_approx(Vector3.ONE):
		return
	var skel := get_skeleton()
	if skel == null:
		return
	if _head < 0:
		_head = skel.find_bone(HEAD_BONE)
		if _head < 0:
			return
	skel.set_bone_pose_scale(_head, skel.get_bone_pose_scale(_head) * head_scale)
