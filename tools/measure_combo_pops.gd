extends Node

## Mide la continuidad de la pose al encadenar el combo (mazmorra, con ventana):
##   Godot --path . res://tools/measure_combo_pops.tscn -- [espada|espadon|...]
## Pulsa atacar sin parar y registra cuánto salta cada fotograma la mano derecha y la cadera respecto al cuerpo.
## Imprime el salto en los fotogramas en que cambia el golpe frente al salto típico del resto: un corte entre
## golpes sale como un pico varias veces mayor que la mediana.

var _main: Node
var _was_active := false

func _ready() -> void:
	GameData.game_mode = "dungeon"
	_main = (load(Net.game_scene()) as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(_main)
	_run.call_deferred()

func _run() -> void:
	await get_tree().process_frame
	get_tree().current_scene = _main
	await get_tree().create_timer(2.0).timeout
	var enc = _main.get_node_or_null("DungeonEncounter")
	if enc:
		enc.process_mode = Node.PROCESS_MODE_DISABLED
	for e in get_tree().get_nodes_in_group("enemies"):
		(e as Node).queue_free()
	var player: CharacterBody3D = _main.get_node("Player")
	player.health_comp.max_hp = 9999.0
	player.health_comp.hp = 9999.0
	var W := WeaponData.WeaponType
	var by_name := {"maza": W.MACE, "dagas": W.DAGGERS, "espalanza": W.SPEAR_LANCE, "espadon": W.GREATSWORD, "espada": W.SWORD}
	var args := OS.get_cmdline_user_args()
	var names: Array = ["espada", "espadon"] if args.is_empty() else String(args[0]).split(",")
	var ac = player.animation_controller
	var skel := ac._find_first_node_of_type(ac.model, "Skeleton3D") as Skeleton3D
	var bones := [skel.find_bone("mixamorig_RightHand"), skel.find_bone("mixamorig_LeftHand"), skel.find_bone("mixamorig_Head")]
	for nm in names:
		var w: int = by_name[nm]
		if not player.weapon_slots.has(w):
			player.add_weapon(w)
		player.select_slot(player.weapon_slots.find(w))
		await get_tree().create_timer(1.0).timeout
		var prev := []
		var last_action := ""
		var jumps := []
		var chain_jumps := []
		var t := 0.0
		while t < 6.0:
			player.resources.energy = PlayerResources.ENERGY_MAX
			player.combat_controller.buffer_attack()
			await get_tree().process_frame
			t += get_process_delta_time()
			var pos := []
			for b in bones:
				pos.append(skel.get_bone_global_pose(b).origin)
			var cur := String(ac._current_action_name)
			if prev.size() == pos.size():
				var j := 0.0
				for k in pos.size():
					j = maxf(j, (pos[k] - prev[k]).length())
				jumps.append(j)
				if cur != last_action and last_action != "":
					# el cambio y los 3 fotogramas siguientes
					chain_jumps.append([last_action + "->" + cur, jumps.size() - 1])
			if OS.get_environment("POPS_LOG") != "" and (cur != last_action or bool(ac.anim_tree.get("parameters/shot/active")) != _was_active):
				print("  t=%.2f %s active=%s elapsed=%.2f" % [t, cur, ac.anim_tree.get("parameters/shot/active"), ac._action_elapsed])
			_was_active = bool(ac.anim_tree.get("parameters/shot/active"))
			if cur != last_action and last_action != "":
				_check_active.call_deferred(ac, last_action + "->" + cur)
			prev = pos
			last_action = cur
		var sorted := jumps.duplicate()
		sorted.sort()
		var med: float = sorted[sorted.size() / 2]
		var p90: float = sorted[int(sorted.size() * 0.9)]
		var out := []
		for c in chain_jumps:
			var i0: int = c[1]
			var mx := 0.0
			for i in range(i0, mini(i0 + 4, jumps.size())):
				mx = maxf(mx, jumps[i])
			out.append("%s %.3f (x%.1f)" % [c[0], mx, mx / maxf(med, 0.0001)])
		print("POPS %s mediana=%.3f p90=%.3f max=%.3f | %s" % [nm, med, p90, sorted[-1], ", ".join(out)])
		await get_tree().create_timer(1.5).timeout
	get_tree().quit(0)

func _check_active(ac, label: String) -> void:
	await get_tree().create_timer(0.3).timeout
	if not bool(ac.anim_tree.get("parameters/shot/active")):
		print("CUT ", label, ": el golpe nuevo ya no está activo a los 0,3 s")
