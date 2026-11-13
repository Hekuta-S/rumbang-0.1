extends Node

## Armaduras del pack embersstorm (pechera: peto, hombreras y antebrazos; pantalones: muslos, rodillas y espinillas):
## datos coherentes, cuelgan de sus huesos sin duplicarse, cambian de set, las lleva el jugador de la mazmorra al
## equiparlas y viajan por la red.

var _failed := false

func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failed = true
		push_error("FALLO: " + msg)
		print("FAILED: " + msg)

func _done(n: Variant, msg: String) -> bool:
	if _failed:
		print("TEST FAILED en el check %s" % str(n))
		get_tree().quit(1)
		return false
	print("CHECK %s PASSED: %s" % [str(n), msg])
	return true

func _armor_atts(skel: Skeleton3D) -> Array:
	var out := []
	for c in skel.get_children():
		if c is BoneAttachment3D and String(c.name).begins_with("Acc_armor_") and not c.is_queued_for_deletion():
			out.append(c)
	return out

func _slot_count(skel: Skeleton3D, slot: String) -> int:
	var n := 0
	for a in _armor_atts(skel):
		var piece := String(a.name).trim_prefix("Acc_armor_")
		piece = piece.substr(0, piece.rfind("_"))
		if String(CharacterLookApplier.ARMOR_PIECES[piece]["slot"]) == slot:
			n += 1
	return n

func _ready() -> void:
	print("--- TEST: ARMADURAS ---")
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveManager.save_path = "user://test_armor_save.json"   # no tocar la partida real
	SaveManager.meta = {}
	GameData.armory_path = "user://test_armor_armeria.cfg"

	# 1. Datos: ajuste de la pechera, un glb por set y una base de equipo por set
	var fit := CharacterLookApplier.armor_fit()
	_check(fit.has("pechera"), "Hay ajuste de pechera")
	for k in ["sx", "sd", "sh", "ox", "od", "oh"]:
		_check(fit["pechera"].has(k) and typeof(fit["pechera"][k]) in [TYPE_FLOAT, TYPE_INT], "La pechera tiene " + k)
	_check(float(fit["pechera"]["sx"]) > 0.5 and float(fit["pechera"]["sd"]) > 0.5 and float(fit["pechera"]["sh"]) > 0.5, "Escalas razonables")
	var used := {}
	for base_id in EquipmentDB.BASES["pechera"]:
		var s := EquipmentDB.armor_of({"slot": "pechera", "base": base_id})
		if s != "":
			used[s] = true
	for set_id in CharacterLookApplier.ARMOR_SETS:
		_check(used.has(set_id), "Hay una pechera de equipo para el set " + set_id)
		_check(ResourceLoader.exists(CharacterLookApplier.ARMOR_DIR + set_id + "_pechera.glb"), "Existe el modelo " + set_id)
	for k in ["muslo", "rodilla", "espinilla"]:
		_check(fit.has(k) and fit[k].has("sx") and fit[k].has("sh") and fit[k].has("sd"), "Hay ajuste de " + k)
	var legs_used := {}
	for base_id in EquipmentDB.BASES["pantalones"]:
		var ls := EquipmentDB.armor_of({"slot": "pantalones", "base": base_id})
		if ls != "":
			legs_used[ls] = true
	for set_id in CharacterLookApplier.ARMOR_SETS:
		_check(legs_used.has(set_id), "Hay unos pantalones de equipo para el set " + set_id)
		for piece in CharacterLookApplier.ARMOR_PIECES:
			if CharacterLookApplier.ARMOR_PIECES[piece]["slot"] == "pantalones":
				var file: String = String(CharacterLookApplier.ARMOR_PIECES[piece]["fit"]) + ("_izq" if piece.ends_with("izq") else "_der")
				_check(ResourceLoader.exists(CharacterLookApplier.ARMOR_DIR + set_id + "_" + file + ".glb"), "Existe " + set_id + "_" + file)
	_check(EquipmentDB.armor_of({"slot": "pantalones", "base": "pantalon_dril"}) == "", "Pantalones sin modelo")
	_check(EquipmentDB.armor_of({"slot": "casco", "base": "coraza_sombra"}) == "", "Un casco no es una pechera")
	_check(EquipmentDB.armor_of({"slot": "pechera", "base": "ruana_paramo"}) == "", "Pechera sin modelo")
	for set_id in CharacterLookApplier.ARMOR_SETS:
		_check(CharacterLookApplier.armor_from_net_index(CharacterLookApplier.armor_net_index(set_id)) == set_id, "Índice de red de " + set_id)
	_check(CharacterLookApplier.armor_net_index("") == 0 and CharacterLookApplier.armor_from_net_index(0) == ""
		and CharacterLookApplier.armor_from_net_index(99) == "", "Índices fuera de rango")
	if not _done(1, "datos coherentes"): return

	# 2. Colgada del hueso del torso, sin duplicados; cambia de set y se quita
	var model := (load(GameData.get_idle_model_path("riva")) as PackedScene).instantiate() as Node3D
	add_child(model)
	var ap := CharacterLookApplier.apply_to(model, CharacterLook.new())
	var regions := CharacterLookApplier.region_boxes(ap.mesh_instance, ap.skeleton)
	_check(regions.has("torso") and (regions["torso"] as AABB).size.x > 0.0, "Región del torso medida")
	ap.set_armor("pechera", "sombra")
	ap.set_armor("pechera", "sombra")
	await get_tree().process_frame
	var atts := _armor_atts(ap.skeleton)
	var piece_names := {}
	for a in atts:
		piece_names[String(a.name)] = a.bone_name
	for piece in CharacterLookApplier.ARMOR_PIECES:
		if CharacterLookApplier.ARMOR_PIECES[piece]["slot"] != "pechera":
			continue
		var nm := "Acc_armor_%s_sombra" % piece
		_check(piece_names.get(nm, "") == CharacterLookApplier.ARMOR_PIECES[piece]["bone"], "%s cuelga de su hueso" % piece)
	_check(atts.size() == 5, "Cinco piezas, sin duplicar (%d)" % atts.size())
	_check(atts.size() == 5 and _slot_count(ap.skeleton, "pechera") == 5, "Peto, hombreras y antebrazos del set (%d)" % atts.size())
	ap.set_armor("pechera", "fuego")
	await get_tree().process_frame
	atts = _armor_atts(ap.skeleton)
	var all_fuego := true
	for a in atts:
		all_fuego = all_fuego and String(a.name).ends_with("_fuego")
	_check(atts.size() == 5 and all_fuego, "Cambia de set sin dejar el anterior (%d)" % atts.size())
	# Tamaño: el ancho de la placa respecto al torso sigue el ajuste (en el espacio del mundo)
	var scale_x := ap.mesh_instance.global_transform.basis.get_scale().x
	var torso_w: float = (regions["torso"] as AABB).size.x * scale_x
	var wbox := AABB()
	var first := true
	var chest_att: Node = null
	for a in atts:
		if String(a.name) == "Acc_armor_pechera_fuego":
			chest_att = a
	for mi in CharacterLookApplier._meshes(chest_att):
		if mi.mesh:
			var b := mi.global_transform * mi.get_aabb()
			wbox = b if first else wbox.merge(b)
			first = false
	var ratio: float = wbox.size.x / torso_w
	# (las correas laterales sobresalen de la caja del torso y el pose de reposo no es exactamente el de enlace: margen amplio)
	_check(ratio > 1.0 and ratio < 1.6, "La pechera es algo más ancha que el torso (%.2f; ajuste sx %.2f)" % [ratio, float(fit["pechera"]["sx"])])
	ap.set_armor("pechera", "")
	await get_tree().process_frame
	_check(_armor_atts(ap.skeleton).is_empty(), "Se quita")
	ap.set_armor("pechera", "fantasma")
	await get_tree().process_frame
	_check(_armor_atts(ap.skeleton).is_empty(), "Un set desconocido no hace nada")
	# Pedida antes de aplicar la apariencia
	var m2 := (load(GameData.get_idle_model_path("riva")) as PackedScene).instantiate() as Node3D
	add_child(m2)
	var ap2 := CharacterLookApplier.new()
	ap2.name = "LookApplier"
	ap2._bind(m2)
	m2.add_child(ap2)
	ap2.set_armor("pechera", "frio")
	ap2.apply(CharacterLook.new())
	await get_tree().process_frame
	_check(_armor_atts(ap2.skeleton).size() == 5, "Pedida antes de aplicar la apariencia")
	# Piernas: ranura propia, 6 piezas, cada una de su hueso, independientes de la pechera
	var m3 := (load(GameData.get_idle_model_path("riva")) as PackedScene).instantiate() as Node3D
	add_child(m3)
	var ap3 := CharacterLookApplier.apply_to(m3, CharacterLook.new())
	ap3.set_armor("pantalones", "sombra")
	ap3.set_armor("pantalones", "sombra")
	await get_tree().process_frame
	_check(_armor_atts(ap3.skeleton).size() == 6, "Seis piezas de pierna, sin duplicar (%d)" % _armor_atts(ap3.skeleton).size())
	var leg_names := {}
	for a in _armor_atts(ap3.skeleton):
		leg_names[String(a.name)] = a.bone_name
	for piece in CharacterLookApplier.ARMOR_PIECES:
		if CharacterLookApplier.ARMOR_PIECES[piece]["slot"] == "pantalones":
			_check(leg_names.get("Acc_armor_%s_sombra" % piece, "") == CharacterLookApplier.ARMOR_PIECES[piece]["bone"], "%s cuelga de su hueso" % piece)
	ap3.set_armor("pechera", "fuego")
	await get_tree().process_frame
	_check(_armor_atts(ap3.skeleton).size() == 11 and _slot_count(ap3.skeleton, "pechera") == 5
		and _slot_count(ap3.skeleton, "pantalones") == 6, "Pechera y pantalones a la vez (11)")
	ap3.set_armor("pantalones", "")
	await get_tree().process_frame
	_check(_slot_count(ap3.skeleton, "pantalones") == 0 and _slot_count(ap3.skeleton, "pechera") == 5, "Quitar los pantalones deja la pechera")
	# Las piernas quedan junto a las piernas: la pieza del muslo está por debajo de la cadera, la espinilla por debajo de la rodilla
	ap3.set_armor("pantalones", "frio")
	await get_tree().process_frame
	var ys := {}
	for a in _armor_atts(ap3.skeleton):
		var pn := String(a.name)
		if pn.contains("_izq_") or pn.contains("_der_"):
			var wb := AABB()
			var f := true
			for mi in CharacterLookApplier._meshes(a):
				if mi.mesh:
					var b := mi.global_transform * mi.get_aabb()
					wb = b if f else wb.merge(b)
					f = false
			ys[pn] = wb.get_center().y
	_check(ys["Acc_armor_muslo_izq_frio"] > ys["Acc_armor_rodilla_izq_frio"] and ys["Acc_armor_rodilla_izq_frio"] > ys["Acc_armor_espinilla_izq_frio"],
		"Muslo, rodilla y espinilla en ese orden de arriba abajo")
	m3.queue_free()
	model.queue_free()
	m2.queue_free()
	if not _done(2, "colgada del torso, sin duplicados"): return

	# 3. Mazmorra: equipar una coraza con modelo la pone en el torso y quitarla la quita
	GameData.game_mode = "dungeon"
	GameData.selected_index = GameData.custom_index()
	GameData.dungeon_weapon = WeaponData.WeaponType.SPEAR_LANCE
	var scene: Node = load("res://scenes/core/main_dungeon.tscn").instantiate()
	get_tree().root.add_child.call_deferred(scene)
	await get_tree().process_frame
	get_tree().current_scene = scene
	var enc: DungeonEncounter = null
	for i in 600:
		await get_tree().process_frame
		enc = scene.get_node_or_null("DungeonEncounter")
		if enc and enc.map and is_instance_valid(enc.player):
			break
	enc._pending.clear()
	var p = enc.player
	var eq: PlayerEquipment = p.equipment
	var pap := p.animation_controller.model.get_node_or_null("LookApplier") as CharacterLookApplier
	_check(eq != null and pap != null and _armor_atts(pap.skeleton).is_empty(), "Sin pechera al empezar")
	var item := EquipmentDB.roll("pechera", 1)
	item["base"] = "coraza_sombra"
	item["name"] = "Coraza de Sombra"
	item.erase("set")
	_check(eq.receive(item) == "equipped", "La pechera se equipa sola")
	await get_tree().process_frame
	_check(_armor_atts(pap.skeleton).size() == 5, "El jugador lleva el set completo (%d)" % _armor_atts(pap.skeleton).size())
	var plain := EquipmentDB.roll("pechera", 1)
	plain["base"] = "poncho_lana"
	eq.equip(plain)   # sin modelo: sustituye a la anterior
	await get_tree().process_frame
	_check(_armor_atts(pap.skeleton).is_empty(), "Una pechera sin modelo no deja la anterior")
	eq.equip(item)
	await get_tree().process_frame
	_check(_armor_atts(pap.skeleton).size() == 5, "Vuelve al reequiparla")
	eq.unequip("pechera")
	await get_tree().process_frame
	_check(_armor_atts(pap.skeleton).is_empty(), "Quitarla la quita del torso")
	var pants := EquipmentDB.roll("pantalones", 1)
	pants["base"] = "grebas_fuego"
	pants["name"] = "Grebas de Fuego"
	pants.erase("set")
	_check(eq.receive(pants) == "equipped", "Los pantalones se equipan solos")
	await get_tree().process_frame
	_check(_armor_atts(pap.skeleton).size() == 6 and _slot_count(pap.skeleton, "pantalones") == 6,
		"El jugador lleva las piernas (%d)" % _armor_atts(pap.skeleton).size())
	eq.equip(item)
	await get_tree().process_frame
	_check(_armor_atts(pap.skeleton).size() == 11, "Pechera y grebas juntas (%d)" % _armor_atts(pap.skeleton).size())
	eq.unequip("pantalones")
	await get_tree().process_frame
	_check(_slot_count(pap.skeleton, "pantalones") == 0 and _slot_count(pap.skeleton, "pechera") == 5, "Quitar las grebas deja la pechera")
	eq.unequip("pechera")
	await get_tree().process_frame
	_check(_armor_atts(pap.skeleton).is_empty(), "Sin nada puesto")
	if not _done(3, "el jugador de la mazmorra lleva la coraza"): return

	# 4. Red: el set viaja como índice en el estado y el otro jugador lo ve
	Net.players[992] = {"name": "Remoto", "char": GameData.custom_index(), "look": CharacterLook.new().to_dict()}
	var rp := RemotePlayer.new()
	rp.peer_id = 992
	rp.char_index = GameData.custom_index()
	add_child(rp)
	await get_tree().process_frame
	var rap := rp.animation_controller.model.get_node_or_null("LookApplier") as CharacterLookApplier
	var st := func(chest: int, legs: int = 0) -> Array:
		return [Vector3.ZERO, 0.0, Vector3.ZERO, true, -1, 10.0, 10.0, false, false, 0, chest, legs]
	rp.apply_state(st.call(CharacterLookApplier.armor_net_index("natural")))
	await get_tree().process_frame
	var rn := _armor_atts(rap.skeleton)
	_check(rn.size() == 5 and String(rn[0].name).ends_with("_natural"), "El remoto lleva el set que le llega (%d)" % rn.size())
	rp.apply_state(st.call(CharacterLookApplier.armor_net_index("natural"), CharacterLookApplier.armor_net_index("frio")))
	await get_tree().process_frame
	_check(_armor_atts(rap.skeleton).size() == 11 and _slot_count(rap.skeleton, "pantalones") == 6, "El remoto lleva también las grebas")
	rp.apply_state(st.call(0))
	await get_tree().process_frame
	_check(_armor_atts(rap.skeleton).is_empty(), "Sin coraza ni grebas")
	rp.apply_state([Vector3.ZERO, 0.0, Vector3.ZERO, true, -1, 10.0, 10.0, false, false, 0])   # estado sin el campo de pechera
	rp.apply_state([Vector3.ZERO, 0.0, Vector3.ZERO, true, -1, 10.0, 10.0, false, false, 0, 0])   # sin el de pantalones
	_check(true, "Un estado sin el campo de pechera o de pantalones sigue valiendo")
	rp.queue_free()
	Net.players.erase(992)
	if not _done(4, "la coraza viaja por la red"): return
	print("ALL TESTS PASSED")
	for f in ["user://test_armor_save.json", "user://test_armor_armeria.cfg"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	get_tree().quit(0)
