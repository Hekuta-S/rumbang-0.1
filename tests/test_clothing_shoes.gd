extends Node

## Zapatos (headless): cada .glb trae un solo pie y el editor lo clona (gemelo "__der" espejado); opciones de calzado,
## colocación por defecto en cada pie, "Espejar pareja" y que CharacterLookApplier ponga los dos pies pegados al cuerpo.
##   godot --headless --path . res://tests/test_clothing_shoes.tscn

var _fails := 0

func _check(ok: bool, what: String) -> void:
	if ok:
		print("CHECK ok: ", what)
	else:
		_fails += 1
		printerr("CHECK FAILED: ", what)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	const ID := "zapato_converse_sketchfab"
	const TW := ID + "__der"
	var ids := ClothingFit.garment_ids()
	_check(ids.has(ID) and ids.has(TW), "el editor lista el zapato y su gemelo")
	_check(ClothingFit.slot_of(ID) == "shoes" and ClothingFit.slot_of(TW) == "shoes", "los zapatos tienen su ranura")
	_check(ClothingFit.twin_id(ID) == TW and ClothingFit.twin_id(TW) == ID, "twin_id va y vuelve")
	var n := ClothingFit.normalized(TW)
	var base := ClothingFit.normalized(ID)
	_check(not n.is_empty() and (n["extent"] as Vector3).is_equal_approx(base["extent"]), "el gemelo carga el mismo modelo")
	n["node"].free()
	base["node"].free()

	# Editor: colocación por defecto y espejo
	var ed := (load("res://tools/clothing_editor.tscn") as PackedScene).instantiate()
	add_child(ed)
	await get_tree().create_timer(1.0).timeout
	ed.select_garment(ID)
	var a = ed._selected()
	ed.select_garment(TW)
	var b = ed._selected()
	_check(a.bone == "mixamorig_LeftFoot" and b.bone == "mixamorig_RightFoot", "cada uno en su pie (%s / %s)" % [a.bone, b.bone])
	_check(a.pos.x > 0.0 and b.pos.x < 0.0, "izquierdo a +X y derecho a -X (%.2f / %.2f)" % [a.pos.x, b.pos.x])
	_check(a.pos.y < 0.4 and a.pos.y > -0.1, "a la altura de los pies (y=%.2f)" % a.pos.y)
	a.pos = Vector3(0.1, 0.07, 0.08)
	a.rot = Basis.from_euler(Vector3(0.2, 0.5, 0.0))
	a.touched = true
	ed.select_garment(TW)
	ed._on_mirror_pair()
	_check(b.bone == "mixamorig_RightFoot" and is_equal_approx(b.pos.x, -0.1) and is_equal_approx(b.pos.z, 0.08), "Espejar pareja copia reflejado")
	_check(absf(b.rot.get_euler().y + 0.5) < 0.01, "el giro en Y se invierte")

	# Juego: los dos pies
	ClothingFit._cache = {
		ID: ClothingFit.entry_to_json("mixamorig_LeftFoot", Vector3(0.09, 0.07, 0.06), Basis.from_euler(Vector3(0, PI / 2, 0)), Vector3.ONE * 0.29, {}, "shoes"),
		TW: ClothingFit.entry_to_json("mixamorig_RightFoot", Vector3(-0.09, 0.07, 0.06), Basis.from_euler(Vector3(0, -PI / 2, 0)), Vector3.ONE * 0.29, {}, "shoes"),
	}
	ClothingFit._cache_loaded = true
	_check(CharacterLook.footwear_options().has(ID) and not CharacterLook.footwear_options().has(TW), "el zapato sale en el selector de calzado (solo el original)")
	var look := CharacterLook.new()
	look.footwear = ID
	_check(CharacterLook.from_dict(look.to_dict()).footwear == ID, "el calzado viaja en to_dict / from_dict")
	var scene := load(GameData.get_idle_model_path(CharacterLook.CHAR_ID)) as PackedScene
	var model := scene.instantiate() as Node3D
	add_child(model)
	var mi := CharacterLookApplier.body_mesh(model)
	model.scale = Vector3.ONE * (1.62 / mi.mesh.get_aabb().size.y)
	var ap := CharacterLookApplier.apply_to(model, look)
	var groups := {"L": 0.0, "R": 0.0}
	var ok_mesh := true
	for c in ap.skeleton.get_children():
		if c is MeshInstance3D and String(c.name).begins_with("Acc_shoes_"):
			ok_mesh = ok_mesh and c.mesh.get_surface_count() > 0
			var bb: AABB = c.global_transform * c.mesh.get_aabb()
			groups["R" if String(c.name).contains(TW) else "L"] = bb.get_center().x
	_check(ok_mesh, "las mallas de los zapatos se construyen")
	_check(groups["L"] > 0.02 and groups["R"] < -0.02, "un zapato a cada lado (%.2f / %.2f)" % [groups["L"], groups["R"]])
	look.footwear = "descalzo"
	ap.apply(look)
	await get_tree().process_frame
	var left := 0
	for c in ap.skeleton.get_children():
		if String(c.name).begins_with("Acc_shoes_") and not c.is_queued_for_deletion():
			left += 1
	_check(left == 0, "descalzo quita los zapatos")
	print("FAILS: ", _fails)
	get_tree().quit(1 if _fails > 0 else 0)
