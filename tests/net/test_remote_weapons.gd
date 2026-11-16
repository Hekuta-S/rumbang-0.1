extends Node3D

## RemotePlayer: el arma que lleva su dueño se ve en su mano (y con su skin).

func _ready() -> void:
	GameData.game_mode = "dungeon"
	var rp := RemotePlayer.new()
	rp.peer_id = 2
	add_child(rp)
	await get_tree().process_frame
	var W := WeaponData.WeaponType
	for wt in [W.SPEAR_LANCE, W.SPINNING_AXE, W.DAGGERS, W.MACE, W.GREATSWORD, W.SWORD, W.KATANA, W.BOW]:
		var s := [Vector3.ZERO, 0.0, Vector3.ZERO, true, wt, 100.0, 100.0, false, false, 0, 0, 0]
		rp.apply_state(s)
		await get_tree().process_frame
		var shown := []
		for k in rp.weapon_models:
			var m = rp.weapon_models[k]
			if is_instance_valid(m) and m.is_visible_in_tree():
				shown.append(k)
		assert(shown == [wt], "Solo se ve el arma %d (%s)" % [wt, shown])
	# Skin: el espadón cambia de modelo con la skin que manda su dueño
	rp.apply_state([Vector3.ZERO, 0.0, Vector3.ZERO, true, W.GREATSWORD, 100.0, 100.0, false, false, 0, 0, 0, 1])
	assert(rp.weapon == W.GREATSWORD and rp.weapon_skin == 1, "Llega la skin del arma")
	print("CHECK PASSED: arma en la mano de cada tipo y skin sincronizada")
	get_tree().quit(0)
