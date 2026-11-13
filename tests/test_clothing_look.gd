extends Node

## Camisetas en el personaje (headless): opciones de CharacterLook, validación, red (to_dict/from_dict) y que
## CharacterLookApplier cuelga/quita la prenda PEGADA al cuerpo (malla con pesos de hueso) y que sigue a los brazos.
##   godot --headless --path . res://tests/test_clothing_look.tscn

var _fails := 0

func _check(ok: bool, what: String) -> void:
	if ok:
		print("CHECK ok: ", what)
	else:
		_fails += 1
		printerr("CHECK FAILED: ", what)

func _ready() -> void:
	_run.call_deferred()

func _shirt_nodes(skel: Skeleton3D, id: String) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for c in skel.get_children():
		if c is MeshInstance3D and String(c.name).begins_with("Acc_shirt_" + id + "_") \
				and String(c.name).trim_prefix("Acc_shirt_" + id + "_").is_valid_int():
			out.append(c)
	return out

func _box(nodes: Array[MeshInstance3D]) -> AABB:
	var box := AABB()
	var first := true
	for m in nodes:
		# La malla pegada vive en el espacio del esqueleto: se mide con los huesos reales
		var b := m.global_transform * m.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box

func _run() -> void:
	var ids := ClothingFit.fitted_ids(ClothingFit.SLOT_SHIRT)
	_check(not ids.is_empty(), "hay camisetas con ajuste guardado (%s)" % str(ids))
	var opts := CharacterLook.shirt_options()
	_check(opts.has(CharacterLook.SHIRT_NONE) and opts.size() == ids.size() + 1, "opciones = sin camiseta + las ajustadas")

	var look := CharacterLook.new()
	_check(look.shirt == CharacterLook.SHIRT_NONE, "por defecto, sin camiseta")
	look.shirt = ids[0]
	var back := CharacterLook.from_dict(look.to_dict())
	_check(back.shirt == ids[0], "la camiseta viaja en to_dict / from_dict")
	var bad := CharacterLook.from_dict({"shirt": "../../hack"})
	_check(bad.shirt == CharacterLook.SHIRT_NONE, "un id desconocido se descarta")

	var scene := load(GameData.get_idle_model_path(CharacterLook.CHAR_ID)) as PackedScene
	var model := scene.instantiate() as Node3D
	add_child(model)
	var mi := CharacterLookApplier.body_mesh(model)
	var s := 1.62 / mi.mesh.get_aabb().size.y
	model.scale = Vector3.ONE * s
	var ap := CharacterLookApplier.apply_to(model, look)
	var skel := ap.skeleton
	var nodes := _shirt_nodes(skel, ids[0])
	_check(not nodes.is_empty(), "la camiseta está en el esqueleto")
	var skinned := true
	for n in nodes:
		skinned = skinned and n.skin != null and n.mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_BONES != 0
	_check(skinned, "es una malla con pesos de hueso y Skin del cuerpo")

	# Debe quedar sobre el pecho
	var box := _box(nodes)
	_check(box.get_center().y > 1.62 * 0.55 and box.get_center().y < 1.62 * 0.85, "centrada a la altura del pecho (y=%.2f)" % box.get_center().y)
	_check(box.size.x > 0.3 and box.size.x < 1.2, "ancho razonable (%.2f m)" % box.size.x)

	# Pegada a los brazos: las mangas llevan pesos de los huesos del brazo y el torso los del torso
	var sleeves := CharacterLook.new()
	sleeves.shirt = "camiseta_basica"
	CharacterLookApplier.apply_to(model, sleeves)
	var arm_verts := 0
	var torso_verts := 0
	for n in _shirt_nodes(skel, "camiseta_basica"):
		var arr: Array = n.mesh.surface_get_arrays(0)
		var vb: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var vw: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var sk: Skin = n.skin
		for v in vb.size() / 4:
			var dom := 0
			for k in 4:
				if vw[v * 4 + k] > vw[v * 4 + dom]:
					dom = k
			var bn := String(sk.get_bind_name(vb[v * 4 + dom]))
			if bn == "":
				bn = skel.get_bone_name(sk.get_bind_bone(vb[v * 4 + dom]))
			if bn.contains("Arm") or bn.contains("Hand") or bn.contains("Shoulder"):
				arm_verts += 1
			elif bn.contains("Spine"):
				torso_verts += 1
	_check(arm_verts > 100, "las mangas siguen a los huesos del brazo (%d vértices)" % arm_verts)
	_check(torso_verts > 300, "el cuerpo de la camiseta sigue al torso (%d vértices)" % torso_verts)
	CharacterLookApplier.apply_to(model, look)

	# Cambiar a otra y quitar
	if ids.size() > 1:
		var l2 := look.duplicate_look()
		l2.shirt = ids[1]
		CharacterLookApplier.apply_to(model, l2)
		await get_tree().process_frame
		_check(not _shirt_nodes(skel, ids[1]).is_empty() and _shirt_nodes(skel, ids[0]).is_empty(), "cambiar de camiseta quita la anterior")
	var l3 := look.duplicate_look()
	l3.shirt = CharacterLook.SHIRT_NONE
	CharacterLookApplier.apply_to(model, l3)
	await get_tree().process_frame
	var left := 0
	for c in skel.get_children():
		if String(c.name).begins_with("Acc_shirt_"):
			left += 1
	_check(left == 0, "sin camiseta no queda nada colgado")

	# Rendimiento: construir la prenda más pesada la primera vez
	var heavy := ids[0]
	var best := 0
	for id in ids:
		var n := ClothingFit.normalized(id)
		var count := 0
		for m in (n["node"] as Node3D).find_children("*", "MeshInstance3D", true, false):
			for k in (m as MeshInstance3D).mesh.get_surface_count():
				count += ((m as MeshInstance3D).mesh.surface_get_arrays(k)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		(n["node"] as Node3D).free()
		if count > best:
			best = count
			heavy = id
	ClothingFit.clear_skin_cache()
	var t0 := Time.get_ticks_msec()
	var l4 := look.duplicate_look()
	l4.shirt = heavy
	CharacterLookApplier.apply_to(model, l4)
	var ms_build := Time.get_ticks_msec() - t0
	print("INFO: %s (%d vértices) se pega en %d ms" % [heavy, best, ms_build])
	_check(ms_build < 8000, "la prenda más pesada se construye en un tiempo razonable (%d ms)" % ms_build)

	if _fails == 0:
		print("CHECK test_clothing_look PASSED")
	get_tree().quit(1 if _fails > 0 else 0)
