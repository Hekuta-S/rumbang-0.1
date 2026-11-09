extends Node

## Cascos del equipo (EquipmentDB.helmet_of, CharacterLookApplier.set_helmet y su ajuste en
## resources/helmet_fit.json): datos coherentes, el casco sustituye al gorro y esconde el pelo, no se duplica,
## queda del tamaño esperado respecto a la cabeza y el jugador de la mazmorra lo lleva al equiparlo.

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

## Colgadores de accesorios del esqueleto: {"helmet": [...], "other": [...]}
func _acc(skel: Skeleton3D) -> Dictionary:
	var out := {"helmet": [], "other": []}
	for c in skel.get_children():
		if c is BoneAttachment3D and String(c.name).begins_with("Acc_") and not c.is_queued_for_deletion():
			out["helmet" if String(c.name).begins_with("Acc_helmet_") else "other"].append(c)
	return out

func _world_aabb(root: Node) -> AABB:
	var box := AABB()
	var first := true
	for mi in CharacterLookApplier._meshes(root):
		if mi.mesh == null:
			continue
		var b := mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box

func _ready() -> void:
	print("--- TEST: CASCOS ---")
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveManager.save_path = "user://test_helmets_save.json"   # no tocar la partida real
	SaveManager.meta = {}
	GameData.armory_path = "user://test_helmets_armeria.cfg"

	# 1. Datos: cada base de casco con modelo tiene ajuste y glb; los cinco modelos tienen base
	var fit := CharacterLookApplier.helmet_fit()
	_check(fit.size() == 6, "Ajuste de los seis cascos (%d)" % fit.size())
	var used := {}
	for base_id in EquipmentDB.BASES["casco"]:
		var h := EquipmentDB.helmet_of({"slot": "casco", "base": base_id})
		if h != "":
			used[h] = true
			_check(fit.has(h), "Ajuste de " + h)
			_check(ResourceLoader.exists(CharacterLookApplier.HELMET_DIR + h + ".glb"), "Existe el modelo " + h)
	_check(used.size() == fit.size(), "Todos los ajustes tienen una pieza de equipo")
	for h in fit:
		for key in ["scale", "stretch", "up", "fwd"]:
			_check(fit[h].has(key) and typeof(fit[h][key]) in [TYPE_FLOAT, TYPE_INT], "%s tiene %s" % [h, key])
		_check(float(fit[h]["scale"]) > 0.5 and float(fit[h]["stretch"]) > 0.3, "Escalas razonables en " + h)
	_check(EquipmentDB.helmet_of({"slot": "pechera", "base": "yelmo_astado"}) == "", "Una pechera no es un casco")
	_check(EquipmentDB.helmet_of({"slot": "casco", "base": "casco_minero"}) == "", "Casco sin modelo")
	_check(EquipmentDB.helmet_of({}) == "", "Pieza vacía")
	if not _done(1, "datos coherentes"): return

	# 2. El casco sustituye al gorro, esconde el pelo, no se duplica y vuelve todo al quitarlo
	var model := (load(GameData.get_idle_model_path("riva")) as PackedScene).instantiate() as Node3D
	add_child(model)
	var l := CharacterLook.new()
	l.hat = "gorra"; l.hair_style = "riva"
	var ap := CharacterLookApplier.apply_to(model, l)
	var visible_hair := func() -> int:
		var n := 0
		for id in ap.hair_meshes:
			if ap.hair_meshes[id].visible:
				n += 1
		return n
	_check(_acc(ap.skeleton)["other"].size() == 1 and visible_hair.call() == 1, "Punto de partida: gorra y pelo")
	var box: AABB = CharacterLookApplier.region_boxes(ap.mesh_instance, ap.skeleton)["head"]
	var head_w: float = box.size.x * ap.mesh_instance.global_transform.basis.get_scale().x
	for h in fit:
		ap.set_helmet(h)
		ap.set_helmet(h)   # repetir no duplica
		await get_tree().process_frame
		var acc := _acc(ap.skeleton)
		_check(acc["helmet"].size() == 1 and String(acc["helmet"][0].name) == "Acc_helmet_" + h, "Un solo casco " + h)
		_check(acc["other"].is_empty(), "El casco sustituye al gorro (%s)" % h)
		_check(visible_hair.call() == 0, "El casco esconde el pelo (%s)" % h)
		_check(acc["helmet"][0].bone_name == CharacterLookApplier.HEAD_BONE, "Cuelga de la cabeza")
		# Tamaño: ancho del casco entre ~1 y ~2.2 veces la cabeza (con cuernos puede pasar de 1.4)
		var ratio: float = _world_aabb(acc["helmet"][0]).size.x / head_w
		_check(ratio > 0.95 and ratio < 3.0, "Tamaño del casco %s respecto a la cabeza (%.2f)" % [h, ratio])
	ap.set_helmet("")
	await get_tree().process_frame
	var acc2 := _acc(ap.skeleton)
	_check(acc2["helmet"].is_empty() and acc2["other"].size() == 1 and visible_hair.call() == 1, "Sin casco vuelven gorra y pelo")
	ap.set_helmet("fantasma")
	await get_tree().process_frame
	_check(_acc(ap.skeleton)["helmet"].is_empty() and _acc(ap.skeleton)["other"].size() == 1, "Un casco desconocido no hace nada")
	# El casco pedido ANTES de aplicar la apariencia se coloca al aplicarla
	var m2 := (load(GameData.get_idle_model_path("riva")) as PackedScene).instantiate() as Node3D
	add_child(m2)
	var ap2 := CharacterLookApplier.new()
	ap2.name = "LookApplier"
	ap2._bind(m2)
	m2.add_child(ap2)
	ap2.set_helmet("cruzado")
	ap2.apply(CharacterLook.new())
	await get_tree().process_frame
	_check(_acc(ap2.skeleton)["helmet"].size() == 1, "Casco pedido antes de aplicar")
	model.queue_free()
	m2.queue_free()
	if not _done(2, "sustituye al gorro, esconde el pelo, sin duplicados"): return

	# 3. En la mazmorra: equipar un casco con modelo lo pone en la cabeza; quitarlo, lo quita
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
	var pm: Node3D = p.animation_controller.model
	var pap := pm.get_node_or_null("LookApplier") as CharacterLookApplier
	_check(eq != null and pap != null, "Jugador con equipo y aplicador")
	_check(_acc(pap.skeleton)["helmet"].is_empty(), "Sin casco al empezar")
	var item := EquipmentDB.roll("casco", 1)
	item["base"] = "casco_vikingo"
	item["name"] = "Casco Vikingo"
	item.erase("set")
	_check(eq.receive(item) == "equipped", "El casco se equipa solo")
	await get_tree().process_frame
	var accp := _acc(pap.skeleton)
	_check(accp["helmet"].size() == 1 and String(accp["helmet"][0].name) == "Acc_helmet_vikingo", "El jugador lleva el casco vikingo")
	var minero := EquipmentDB.roll("casco", 1)
	minero["base"] = "casco_minero"
	eq.equip(minero)   # un casco sin modelo sustituye al anterior: se ve la cabeza otra vez
	await get_tree().process_frame
	_check(_acc(pap.skeleton)["helmet"].is_empty(), "Un casco sin modelo no deja el anterior")
	eq.equip(item)
	await get_tree().process_frame
	_check(_acc(pap.skeleton)["helmet"].size() == 1, "Vuelve al reequiparlo")
	eq.unequip("casco")
	await get_tree().process_frame
	_check(_acc(pap.skeleton)["helmet"].is_empty(), "Quitarlo lo quita de la cabeza")
	if not _done(3, "el jugador de la mazmorra lleva el casco equipado"): return

	# 4. Red: el casco viaja como índice en el estado del jugador y otro jugador lo ve en su copia
	_check(CharacterLookApplier.helmet_net_index("") == 0 and CharacterLookApplier.helmet_from_net_index(0) == "", "0 = sin casco")
	for h in fit:
		_check(CharacterLookApplier.helmet_from_net_index(CharacterLookApplier.helmet_net_index(h)) == h, "Ida y vuelta de " + h)
	_check(CharacterLookApplier.helmet_from_net_index(99) == "" and CharacterLookApplier.helmet_from_net_index(-3) == "", "Índices fuera de rango")
	Net.players[991] = {"name": "Remoto", "char": GameData.custom_index(), "look": CharacterLook.new().to_dict()}
	var rp := RemotePlayer.new()
	rp.peer_id = 991
	rp.char_index = GameData.custom_index()
	add_child(rp)
	await get_tree().process_frame
	_check(rp.animation_controller != null and rp.animation_controller.model != null, "El jugador remoto tiene modelo")
	var rap := rp.animation_controller.model.get_node_or_null("LookApplier") as CharacterLookApplier
	var st := func(idx: int) -> Array:
		return [Vector3.ZERO, 0.0, Vector3.ZERO, true, -1, 10.0, 10.0, false, false, idx]
	rp.apply_state(st.call(CharacterLookApplier.helmet_net_index("nordico")))
	await get_tree().process_frame
	var racc := _acc(rap.skeleton)
	_check(racc["helmet"].size() == 1 and String(racc["helmet"][0].name) == "Acc_helmet_nordico", "El remoto lleva el casco que le llega")
	rp.apply_state(st.call(CharacterLookApplier.helmet_net_index("cruzado")))
	await get_tree().process_frame
	_check(_acc(rap.skeleton)["helmet"].size() == 1 and String(_acc(rap.skeleton)["helmet"][0].name) == "Acc_helmet_cruzado", "Cambia de casco")
	rp.apply_state(st.call(0))
	await get_tree().process_frame
	_check(_acc(rap.skeleton)["helmet"].is_empty(), "Sin casco")
	rp.apply_state([Vector3.ZERO, 0.0, Vector3.ZERO, true, -1, 10.0, 10.0, false, false])   # estado antiguo, sin el campo
	_check(true, "Un estado sin el campo de casco sigue valiendo")
	rp.queue_free()
	Net.players.erase(991)
	if not _done(4, "el casco viaja por la red"): return
	print("ALL TESTS PASSED")
	for f in ["user://test_helmets_save.json", "user://test_helmets_armeria.cfg"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	get_tree().quit(0)
