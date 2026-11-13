extends Node

## Personaje personalizable (CharacterLook + CharacterLookApplier sobre riva-base.fbx): datos, red,
## materiales, accesorios, proporciones y que el jugador de la mazmorra salga con su apariencia.

func _ready() -> void:
	print("--- TEST: PERSONAJE PERSONALIZABLE ---")
	# 1. Un solo personaje jugable
	assert(GameData.UNLOCKED_CHARACTERS == ["riva"], "Solo se juega con el personaje personalizable")
	assert(GameData.CHARACTERS[GameData.selected_index]["id"] == "riva", "Seleccionado por defecto")
	print("CHECK 1 PASSED: único personaje jugable (índice %d)" % GameData.selected_index)

	# 2. Serialización y validación (lo que llega por la red no se usa tal cual)
	var l := CharacterLook.new()
	l.char_name = "Pepe"; l.footwear = "descalzo"; l.height = 1.1
	l.colors["skin"] = Color(0.5, 0.3, 0.2)
	var back := CharacterLook.from_dict(l.to_dict())
	assert(back.to_dict() == l.to_dict(), "to_dict/from_dict ida y vuelta")
	var bad := CharacterLook.from_dict({"name": "   ", "hat": "corona", "height": 9.0, "colors": {"hair": "rojo", "skin": Color(2, -1, 0.5)}})
	assert(bad.char_name == "Riva" and bad.hat == "ninguno" and is_equal_approx(bad.height, 1.12), "Valores inválidos acotados")
	assert(bad.colors["hair"] is Color and bad.colors["skin"] == Color(1, 0, 0.5), "Colores acotados")
	assert(CharacterLook.sanitize_name("x".repeat(40)).length() == CharacterLook.NAME_MAX, "Nombre recortado")
	print("CHECK 2 PASSED: serialización y saneado")

	# 3. Materiales por superficie (shaders de piel, ojos y pelo) con el color de su ranura; peinado visible
	var model := (load(GameData.get_idle_model_path("riva")) as PackedScene).instantiate() as Node3D
	add_child(model)
	l.colors["eyes"] = Color(0.2, 0.5, 0.8)
	l.hair_style = "riva"
	var ap := CharacterLookApplier.apply_to(model, l)
	var mi := ap.mesh_instance
	assert(String(mi.name).begins_with(CharacterLookApplier.BODY_NODE), "Malla del cuerpo encontrada (%s)" % mi.name)
	var mats := {}
	for i in mi.mesh.get_surface_count():
		mats[mi.mesh.surface_get_material(i).resource_name] = mi.get_surface_override_material(i) as ShaderMaterial
	# Cejas y pestañas como mallas aparte son opcionales (sin el pack de MakeHuman van pintadas en la piel)
	for k in ["rb_Piel", "rb_Ojos", "rb_Calzones", "rb_Elastico"]:
		assert(mats.has(k) and mats[k] != null, "El modelo base tiene la superficie " + k)
	assert((mats["rb_Piel"].get_shader_parameter("tint") as Color).is_equal_approx(Color(0.5, 0.3, 0.2)), "Piel con su tono")
	assert(mats["rb_Piel"].get_shader_parameter("albedo_tex") != null, "Piel con textura de detalle")
	assert((mats["rb_Ojos"].get_shader_parameter("iris_color") as Color).is_equal_approx(Color(0.2, 0.5, 0.8)), "Iris con su color")
	assert((mats["rb_Calzones"].get_shader_parameter("tint") as Color).is_equal_approx(l.color("underwear")), "Calzones con su color")
	assert(ap.hair_meshes.size() >= 1, "Peinados en el modelo (%d)" % ap.hair_meshes.size())
	for id in ap.hair_meshes:
		assert(CharacterLook.HAIR_STYLES.has(id), "Peinado conocido " + id)
		assert(ap.hair_meshes[id].visible == (id == "riva"), "Solo se ve el peinado elegido")
	l.hair_style = "rapado"
	ap.apply(l)
	for id in ap.hair_meshes:
		assert(not ap.hair_meshes[id].visible, "Al rape: sin pelo")
	# Peinados sueltos (glb en assets/models/riva/peinados): se cuelgan de la cabeza, uno solo, y se quitan al cambiar
	for id in CharacterLook.HAIR_STYLES:
		if id == "riva" or id == "rapado":
			continue
		l.hair_style = id
		ap.apply(l); ap.apply(l)
		assert(ap._hair_nodes.size() == 1 and ap._hair_shown == id, "Peinado suelto colgado: " + id)
		assert(not ap.hair_meshes["riva"].visible, "El peinado del modelo se esconde con " + id)
	l.hair_style = "rapado"
	ap.apply(l)
	assert(ap._hair_nodes.is_empty(), "Al rape quita el peinado suelto")
	l.hair_style = "riva"
	ap.apply(l)
	print("CHECK 3 PASSED: %d superficies y %d peinados" % [mats.size(), ap.hair_meshes.size()])

	# 4. Accesorios en sus huesos y se cambian sin duplicarse
	# (Ya no hay gorros ni botas rígidas: los zapatos son prendas del editor de ropa, ver test_clothing_shoes)
	var atts := _attachments(ap.skeleton)
	for a in atts:
		assert(ap.skeleton.find_bone(a.bone_name) >= 0, "Hueso válido " + a.bone_name)
	l.footwear = "descalzo"
	ap.apply(l); ap.apply(l)
	await get_tree().process_frame
	assert(_attachments(ap.skeleton).is_empty(), "Sin accesorios por defecto y reaplicar no duplica")
	print("CHECK 4 PASSED: accesorios en huesos")

	# 5. Proporciones: altura/complexión en la raíz, cabeza en el modificador
	var base := ap._base_scale
	l.height = 1.1; l.build = 0.9; l.head = 1.2
	ap.apply(l)
	assert(model.scale.is_equal_approx(base * Vector3(0.9, 1.1, 0.9)), "Escala de la raíz")
	assert(ap._head_mod.head_scale.is_equal_approx(Vector3(1.2 / 0.9, 1.2, 1.2 / 0.9)), "Escala de la cabeza")
	print("CHECK 5 PASSED: proporciones")
	model.queue_free()

	# 6. El jugador de la mazmorra sale con la apariencia guardada
	var cur := CharacterLook.new()
	cur.colors["underwear"] = Color(0.1, 0.8, 0.2); cur.hat = "ninguno"
	CharacterLook.set_current(cur)
	GameData.game_mode = "dungeon"
	var scene: Node = load("res://scenes/core/main_dungeon.tscn").instantiate()
	get_tree().root.add_child.call_deferred(scene)
	var player: Node = null
	for i in 600:
		await get_tree().process_frame
		player = scene.get_node_or_null("Player")
		if player and player.get_node_or_null("PlayerAnimationController") and player.get_node("PlayerAnimationController").model:
			break
	var pm: Node3D = player.get_node("PlayerAnimationController").model
	var pap := pm.get_node_or_null("LookApplier") as CharacterLookApplier
	assert(pap != null, "El jugador lleva el aplicador")
	var pnames: Array = []
	for a in _attachments(pap.skeleton):
		pnames.append(a.name)
	assert(pap.look.color("underwear").is_equal_approx(Color(0.1, 0.8, 0.2)) and _attachments(pap.skeleton).size() == 1, "Con su apariencia (accesorios: %s)" % str(pnames))
	print("CHECK 6 PASSED: jugador con su apariencia")
	# 7. Sin pasiva y con la espalanza de arma inicial
	assert(player.get("passive") == null, "El personaje personalizable no tiene pasiva")
	assert(GameData.get_selected()["initial_weapons"] == [WeaponData.WeaponType.SPEAR_LANCE], "Empieza con la espalanza")
	var inv = player.get("weapon_inventory")
	if inv:
		assert(inv.get_current_weapon() == WeaponData.WeaponType.SPEAR_LANCE, "Lleva la espalanza equipada (%d)" % inv.get_current_weapon())
	print("CHECK 7 PASSED: sin pasiva y con la espalanza")
	print("ALL TESTS PASSED")
	get_tree().quit(0)

func _attachments(skel: Skeleton3D) -> Array[BoneAttachment3D]:
	var out: Array[BoneAttachment3D] = []
	for c in skel.get_children():
		if c is BoneAttachment3D and String(c.name).begins_with("Acc_") and not c.is_queued_for_deletion():
			out.append(c)
	return out
