extends Node

## Piernas y barra lateral del editor de ropa (headless): sliders, asas arrastrables, guardado en el JSON de la prenda
## (solo si no están en reposo), recuperación al elegir prenda y que el pegado al cuerpo las siga.
##   godot --headless --path . res://tests/test_clothing_legs.tscn

var _fails := 0

func _check(ok: bool, what: String) -> void:
	if ok:
		print("CHECK ok: ", what)
	else:
		_fails += 1
		printerr("CHECK FAILED: ", what)

func _ready() -> void:
	_run.call_deferred()

func _foot(ed, side: String) -> Vector3:
	return ed._arm_points(side, 1)[0]

func _run() -> void:
	var ed := (load("res://tools/clothing_editor.tscn") as PackedScene).instantiate()
	add_child(ed)
	await get_tree().create_timer(1.0).timeout
	ed.set_view(0.0, 8.0, 3.0, Vector3(0, 0.9, 0))
	await get_tree().process_frame
	await get_tree().process_frame

	# — Barra lateral —
	_check(ed._sidebar.visible, "la barra empieza abierta")
	ed.set_sidebar_open(false)
	_check(not ed._sidebar.visible and ed._sidebar_btn.visible, "minimizada: solo queda el botón")
	ed.set_sidebar_open(true)
	_check(ed._sidebar.visible, "se vuelve a abrir")

	# — Piernas —
	ed.select_garment("pantalon_liso")
	var it = ed._selected()
	var l0: Vector3 = _foot(ed, "LeftLeg")
	var r0: Vector3 = _foot(ed, "RightLeg")
	ed.set_legs(0.0, 0.0)
	_check(it.arms.has("Left") and not it.arms.has("LeftLeg"), "piernas en reposo: no se guardan en la prenda")
	ed.set_legs(40.0, 40.0)
	await get_tree().process_frame
	var l1: Vector3 = _foot(ed, "LeftLeg")
	var r1: Vector3 = _foot(ed, "RightLeg")
	_check(l1.x > l0.x + 0.1 and r1.x < r0.x - 0.1, "abrir las piernas separa los pies (%.2f -> %.2f)" % [l0.x, l1.x])
	_check(it.arms.has("LeftLeg") and it.arms.has("RightLeg"), "la pose de piernas se anota en la prenda")

	# — Asa de la rodilla izquierda: arrastrar hacia delante dobla la pierna —
	var knee: Vector3 = ed._arm_points("LeftLeg", 0)[0]
	var sp: Vector2 = ed._screen(knee)
	_check(ed._pick_arm_handle(sp) in ["LeftLeg_0", "RightLeg_0"], "el ratón sobre la rodilla elige su asa (%s)" % ed._pick_arm_handle(sp))
	ed.set_legs(0.0, 0.0)
	await get_tree().process_frame
	knee = ed._arm_points("LeftLeg", 0)[0]
	sp = ed._screen(knee)
	ed._leg_sync.button_pressed = false
	var r_before: Vector3 = _foot(ed, "RightLeg")
	ed._begin_arm_drag("LeftLeg_0")
	ed._update_arm_drag(sp + Vector2(70, 0))
	ed._arm_drag = ""
	var knee2: Vector3 = ed._arm_points("LeftLeg", 0)[0]
	_check(knee2.x > knee.x + 0.05, "arrastrar la rodilla la abre hacia fuera (%.2f -> %.2f)" % [knee.x, knee2.x])
	_check(absf(_foot(ed, "RightLeg").x - r_before.x) < 0.01, "sin simetría, la otra pierna no se mueve")

	# — Cambiar de prenda recupera SU pose de piernas —
	ed.set_legs(25.0, 25.0)
	ed.select_garment("camiseta")
	ed.select_garment("pantalon_liso")
	_check(absf(float(ed._arm["LeftLeg"]) - 25.0) < 0.1, "al volver a la prenda vuelve su pose de piernas")

	# — JSON y pegado —
	var d: Dictionary = ed._arms_dict()
	var json := ClothingFit.entry_to_json("mixamorig_Hips", Vector3(0, 0.8, 0), Basis.IDENTITY, Vector3.ONE * 0.9, d, "pants")
	var back: Dictionary = ClothingFit.parse_entry(JSON.parse_string(JSON.stringify(json)))["arms"]
	_check(back.has("LeftLeg") and (back["LeftLeg"]["dirs"] as Array).size() == 2, "las piernas viajan en el JSON")
	var body := CharacterLookApplier.body_mesh(ed._model)
	var pose := ClothingFit._arm_pose(body, back)
	_check(not pose.is_empty() and (pose["mats"] as Array).size() > 0, "el pegado calcula la pose con piernas")

	print("FAILS: ", _fails)
	get_tree().quit(1 if _fails > 0 else 0)
