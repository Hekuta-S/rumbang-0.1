extends Node

## Pantalones (headless): ranuras camiseta/pantalón de ClothingFit, opciones y validación de CharacterLook, y que
## CharacterLookApplier cuelga el pantalón pegado al cuerpo a la altura de las piernas, sin tocar la camiseta.
##   godot --headless --path . res://tests/test_clothing_pants.tscn

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
	const ID := "pantalon_liso"
	# Ajuste inyectado (no toca resources/clothing_fit.json)
	ClothingFit._cache = {ID: ClothingFit.entry_to_json(ClothingFit.PANTS_BONE, Vector3(0, 0.8, 0), Basis.IDENTITY, Vector3.ONE * 0.9, {}, "pants")}
	ClothingFit._cache_loaded = true

	_check(ClothingFit.slot_of(ID) == "pants", "el nombre pantalon_* sugiere ranura de pantalón")
	_check(ClothingFit.slot_of("camiseta_lp") == "shirt", "una camiseta sigue siendo camiseta")
	_check(ClothingFit.slot_of("x", {"slot": "pants"}) == "pants", "la ranura guardada manda sobre el nombre")
	_check(ClothingFit.entry_to_json("b", Vector3.ZERO, Basis.IDENTITY, Vector3.ONE, {}, "pants").get("slot") == "pants", "el ajuste guarda la ranura")
	_check(ClothingFit.fitted_ids("pants") == [ID] and ClothingFit.fitted_ids("shirt").is_empty(), "fitted_ids filtra por ranura")
	_check(CharacterLook.pants_options().has(ID) and not CharacterLook.shirt_options().has(ID), "el pantalón no sale en el selector de camisetas")

	var look := CharacterLook.new()
	_check(look.pants == CharacterLook.PANTS_NONE, "por defecto, sin pantalón")
	look.pants = ID
	_check(CharacterLook.from_dict(look.to_dict()).pants == ID, "el pantalón viaja en to_dict / from_dict")
	_check(CharacterLook.from_dict({"pants": "../../hack"}).pants == CharacterLook.PANTS_NONE, "un id desconocido se descarta")

	var scene := load(GameData.get_idle_model_path(CharacterLook.CHAR_ID)) as PackedScene
	var model := scene.instantiate() as Node3D
	add_child(model)
	var mi := CharacterLookApplier.body_mesh(model)
	model.scale = Vector3.ONE * (1.62 / mi.mesh.get_aabb().size.y)
	var ap := CharacterLookApplier.apply_to(model, look)
	var nodes: Array[MeshInstance3D] = []
	for c in ap.skeleton.get_children():
		if c is MeshInstance3D and String(c.name).begins_with("Acc_pants_" + ID + "_"):
			nodes.append(c)
	_check(not nodes.is_empty(), "el pantalón está en el esqueleto")
	var skinned := true
	var box := AABB()
	for i in nodes.size():
		skinned = skinned and nodes[i].skin != null and nodes[i].mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_BONES != 0
		var b := nodes[i].global_transform * nodes[i].mesh.get_aabb()
		box = b if i == 0 else box.merge(b)
	_check(skinned, "es una malla con pesos de hueso")
	_check(box.get_center().y > 1.62 * 0.25 and box.get_center().y < 1.62 * 0.6, "a la altura de las piernas (y=%.2f)" % box.get_center().y)

	var none := CharacterLook.new()
	ap.apply(none)
	await get_tree().process_frame
	var left := 0
	for c in ap.skeleton.get_children():
		if String(c.name).begins_with("Acc_pants_") and not c.is_queued_for_deletion():
			left += 1
	_check(left == 0, "sin pantalón se quita la prenda")

	print("FAILS: ", _fails)
	get_tree().quit(1 if _fails > 0 else 0)
