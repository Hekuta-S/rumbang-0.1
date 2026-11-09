extends Node
## Mide los clips de espada: velocidad de la mano derecha por fotograma (para las ventanas de golpe),
## avance de la cadera y zancada (para la locomoción). Uso: Godot --headless --path . res://tools/measure_sword_clips.tscn
const CLIPS := ["sword/sw_attack1", "sword/sw_attack2", "sword/sw_combo", "sword/sw_run_attack",
	"sword/sw_walk", "sword/sw_run", "sword/sw_strafe", "greatsword/gs_walk", "greatsword/gs_run", "greatsword/gs_strafe_r"]

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
		var hand := sk.find_bone("mixamorig_RightHand")
		var lf := sk.find_bone("mixamorig_LeftFoot")
		var head := sk.find_bone("mixamorig_HeadTop_End")
		var frames := int(round(a.length * 30.0))
		var prev := Vector3.INF
		var speeds := []
		var h0 := Vector3.ZERO
		var hn := Vector3.ZERO
		var fz_min := INF
		var fz_max := -INF
		var height := 0.0
		for i in frames + 1:
			ap.seek(i / 30.0, true)
			sk.force_update_all_bone_transforms()
			var gh := sk.get_bone_global_pose(hand).origin
			var hp := sk.get_bone_global_pose(hips).origin
			if i == 0:
				h0 = hp
				height = (sk.get_bone_global_pose(head).origin).y - (sk.get_bone_global_pose(lf).origin).y
			hn = hp
			var fp := sk.get_bone_global_pose(lf).origin - hp
			fz_min = minf(fz_min, fp.z)
			fz_max = maxf(fz_max, fp.z)
			if prev != Vector3.INF:
				speeds.append(int(round((gh - prev).length() * 30.0 * 1.62 / height * 10.0)))   # dm/s, absoluta (con el avance de la cadera)
			prev = gh
		print("CLIP ", f, " len=", snappedf(a.length, 0.001), " frames=", frames, " height=", snappedf(height, 0.001),
			" hips_move(m@1.62)=", (hn - h0) * 1.62 / height, " footZrange(m@1.62)=", snappedf((fz_max - fz_min) * 1.62 / height, 0.001))
		if f.contains("attack") or f.contains("combo"):
			print("  HANDSPEED dm/s per frame: ", speeds)
		inst.queue_free()
	get_tree().quit()
