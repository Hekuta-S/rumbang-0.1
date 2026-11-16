extends Node
## Mide los clips de puños: velocidad de cada mano por fotograma (ventanas de golpe), avance de la cadera.
## Uso: Godot --headless --path . res://tools/measure_fist_clips.tscn
const CLIPS := ["fists/fist_idle", "fists/fist_punch1", "fists/fist_punch2", "fists/fist_punch3", "fists/fist_punch4",
	"fists/fist_run_attack", "fists/fist_special", "fists/fist_run_elbow"]

func _ready() -> void:
	for f in CLIPS:
		var inst := (load("res://assets/models/%s.fbx" % f) as PackedScene).instantiate() as Node3D
		add_child(inst)
		var ap := inst.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		var sk := inst.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var an: String = ap.get_animation_list()[0]
		var a := ap.get_animation(an)
		ap.play(an)
		var hips := sk.find_bone("mixamorig_Hips")
		var rh := sk.find_bone("mixamorig_RightHand")
		var lh := sk.find_bone("mixamorig_LeftHand")
		var rf := sk.find_bone("mixamorig_RightFoot")
		var lf := sk.find_bone("mixamorig_LeftFoot")
		var head := sk.find_bone("mixamorig_HeadTop_End")
		var frames := int(round(a.length * 30.0))
		var pr := Vector3.INF
		var pl := Vector3.INF
		var prf := Vector3.INF
		var plf := Vector3.INF
		var sr := []
		var sl := []
		var srf := []
		var slf := []
		var h0 := Vector3.ZERO
		var hn := Vector3.ZERO
		var height := 1.0
		for i in frames + 1:
			ap.seek(i / 30.0, true)
			sk.force_update_all_bone_transforms()
			var r := sk.get_bone_global_pose(rh).origin
			var l := sk.get_bone_global_pose(lh).origin
			var rfp := sk.get_bone_global_pose(rf).origin
			var lfp := sk.get_bone_global_pose(lf).origin
			var hp := sk.get_bone_global_pose(hips).origin
			if i == 0:
				h0 = hp
				height = maxf(sk.get_bone_global_pose(head).origin.y - lfp.y, 0.0001)
			hn = hp
			var k := 30.0 * 1.62 / height * 10.0
			if pr != Vector3.INF:
				sr.append(int(round((r - pr).length() * k)))
				sl.append(int(round((l - pl).length() * k)))
				srf.append(int(round((rfp - prf).length() * k)))
				slf.append(int(round((lfp - plf).length() * k)))
			pr = r; pl = l; prf = rfp; plf = lfp
		print("CLIP ", f, " anim=", an, " len=", snappedf(a.length, 0.001), " frames=", frames, " height=", snappedf(height, 0.001),
			" hips_move(m@1.62)=", (hn - h0) * 1.62 / height)
		print("  R_HAND ", sr)
		print("  L_HAND ", sl)
		print("  R_FOOT ", srf)
		print("  L_FOOT ", slf)
		inst.queue_free()
	get_tree().quit()
