extends Node

## Armaduras de los goblins normales: perfil goblin de ClothingFit (pechera = set peto + hombreras, taparrabo, casco),
## editor (tools/goblin_armor_editor.tscn) y DungeonGoblin.put_on_armor. No escribe resources/goblin_armor_fit.json
## (los ajustes se inyectan en la caché).
##   godot --headless --path . res://tests/test_goblin_armor.tscn
## Con `-- shot <prefijo>` (sin headless) guarda capturas del goblin con cada pieza en su ajuste por defecto.

const PROF := ClothingFit.PROFILE_GOBLIN
var _fails := 0
var _n := 0

func _check(ok: bool, what: String) -> void:
	_n += 1
	if ok:
		print("CHECK %d PASSED: %s" % [_n, what])
	else:
		_fails += 1
		printerr("CHECK %d FAILED: %s" % [_n, what])

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var shot := args.size() >= 2 and args[0] == "shot"
	var ids := ClothingFit.garment_ids(PROF)
	_check(ids.size() == 7, "7 piezas: peto, 2 hombreras, taparrabo, 3 cascos (%s)" % str(ids))
	var slots_ok: bool = ClothingFit.slot_of("casco_uruk", {}, PROF) == ClothingFit.SLOT_HELMET
	slots_ok = slots_ok and ClothingFit.slot_of("peto_uruk", {}, PROF) == ClothingFit.SLOT_SHIRT
	slots_ok = slots_ok and ClothingFit.slot_of("hombrera_uruk_izq", {}, PROF) == ClothingFit.SLOT_SHIRT
	slots_ok = slots_ok and ClothingFit.slot_of("taparrabo_uruk", {}, PROF) == ClothingFit.SLOT_PANTS
	_check(slots_ok, "ranuras por nombre: pechera / taparrabo / casco")
	_check(ClothingFit.armor_set("hombrera_uruk_der") == "uruk" and ClothingFit.armor_set("peto_uruk") == "uruk"
			and ClothingFit.side_twin("hombrera_uruk_izq") == "hombrera_uruk_der", "set y pareja de lado")
	_check(ClothingFit.garment_ids().size() > 0 and not ClothingFit.garment_ids().has("peto_uruk"), "la ropa de Riva sigue aparte")

	var ed := (load("res://tools/goblin_armor_editor.tscn") as PackedScene).instantiate()
	add_child(ed)
	await get_tree().create_timer(0.5).timeout
	_check(ed._goblin() and ed._ms > 1.0, "editor con el goblin (ms %.1f)" % ed._ms)
	var entries := {}
	for id in ids:
		ed.select_garment(id)
		var it = ed._selected()
		entries[id] = ClothingFit.entry_to_json(it.bone, it.pos, it.rot, it.scl, it.arms, it.slot)
		ed.show_garment(id, false)
	_check(entries.size() == ids.size(), "todas las piezas cargan en el editor")
	_check(String(entries["casco_uruk"]["bone"]) == ClothingFit.HELMET_BONE, "el casco se cuelga de la cabeza")
	_check(String(entries["hombrera_uruk_izq"]["bone"]) == "mixamorig_LeftArm" and String(entries["hombrera_uruk_der"]["bone"]) == "mixamorig_RightArm"
			and String(entries["peto_uruk"]["bone"]) == "mixamorig_Spine2", "cada pieza del set con su hueso propio")

	# Espejar: la hombrera derecha queda como reflejo de la izquierda
	ed.select_garment("hombrera_uruk_izq")
	var hl = ed._selected()
	ed.select_garment("hombrera_uruk_der")
	ed._on_mirror_pair()
	var hr = ed._selected()
	_check(absf(hr.pos.x + hl.pos.x) < 0.0001 and is_equal_approx(hr.pos.y, hl.pos.y), "espejar hombrera (%s / %s)" % [hl.pos, hr.pos])
	ed.show_garment("hombrera_uruk_izq", false)
	ed.show_garment("hombrera_uruk_der", false)

	# Vista pegada en el editor
	ed.select_garment("peto_uruk")
	ed._skin_check.button_pressed = true
	await get_tree().create_timer(0.2).timeout
	var it2 = ed._selected()
	ed._sync_skin(it2)
	_check(not it2.skin.is_empty() and it2.skin[0].skin != null, "peto pegado al esqueleto en el editor")
	if shot:
		await _shots(ed, ids, args[1])
	ed.queue_free()
	await get_tree().process_frame

	# En el juego
	ClothingFit._profile_caches[PROF] = entries
	var g := DungeonGoblin.new()
	DungeonGoblin.armor_enabled = false
	add_child(g)
	var n0: int = g._meshes.size()
	g.put_on_armor("hombrera_uruk_izq")   # una pieza de la pechera pone el set entero
	g.put_on_armor("taparrabo_uruk")
	g.put_on_armor("casco_berserker")
	var shirt: Array[String] = []
	for m in g._meshes:
		if String(m.name).begins_with("Armor_shirt_"):
			shirt.append(String(m.name))
	var has_peto := shirt.any(func(n): return n.contains("peto_uruk"))
	var has_der := shirt.any(func(n): return n.contains("hombrera_uruk_der"))
	_check(shirt.size() >= 3 and has_peto and has_der, "la pechera pone peto + 2 hombreras (%s)" % str(shirt))
	_check(g.worn_armor == "uruk" and g.worn_loincloth == "taparrabo_uruk" and g.worn_helmet == "casco_berserker", "pechera, taparrabo y casco puestos")
	g.put_on_armor("taparrabo_uruk")
	var pants := 0
	for m in g._meshes:
		if String(m.name).begins_with("Armor_pants_"):
			pants += 1
			_check(m.skin != null and m.get_parent() is Skeleton3D and m.material_overlay != null, "pieza con piel, en el esqueleto y con destello")
	_check(pants == 1 and g.worn_loincloth == "taparrabo_uruk" and g._meshes.size() > n0 + 3, "volver a ponerse el taparrabo no lo duplica y deja la pechera")

	# Sorteo determinista por net_id (anfitrión y clientes iguales)
	DungeonGoblin.armor_enabled = true
	var picks := []
	for k in 2:
		var h := DungeonGoblin.new()
		h.net_id = 77
		add_child(h)
		picks.append([h.worn_armor, h.worn_loincloth, h.worn_helmet])
		h.queue_free()
	DungeonGoblin.armor_enabled = false
	_check(picks[0] == picks[1], "mismo net_id = misma armadura (%s)" % str(picks[0]))
	for i in 20:
		await get_tree().physics_frame
	_check(is_instance_valid(g), "anima con la armadura sin errores")
	await _riva_loot()
	_fists()
	ClothingFit.reload_fits()
	print("RESULT: %s (%d fallos)" % ["PASSED" if _fails == 0 else "FAILED", _fails])
	get_tree().quit(1 if _fails > 0 else 0)

## Botín del jugador: las mismas piezas como equipo de Riva (perfil riva_armor; ajustes inyectados, no se guardan).
func _riva_loot() -> void:
	var rp := ClothingFit.PROFILE_RIVA_ARMOR
	_check(ClothingFit.garment_ids(rp) == ClothingFit.garment_ids(PROF) and ClothingFit.body_of(rp) == "riva", "perfil riva_armor: mismas piezas, cuerpo de Riva")
	var ed := (load("res://tools/riva_armor_editor.tscn") as PackedScene).instantiate()
	add_child(ed)
	await get_tree().create_timer(0.5).timeout
	var entries := {}
	for id in ClothingFit.garment_ids(rp):
		ed.select_garment(id)
		var it = ed._selected()
		entries[id] = ClothingFit.entry_to_json(it.bone, it.pos, it.rot, it.scl, it.arms, it.slot)
	_check(not ed._goblin() and ed._armor_mode() and entries.size() == 7, "editor de armaduras Uruk sobre Riva")
	ed.queue_free()
	await get_tree().process_frame
	ClothingFit._profile_caches[rp] = entries

	var bases := {"casco": "casco_uruk", "pechera": "coraza_uruk", "pantalones": "taparrabo_uruk"}
	var ok := true
	for kind in bases:
		ok = ok and EquipmentDB.lootable_bases(kind).has(bases[kind])
	_check(ok, "las bases Uruk caen como botín")
	var chest := EquipmentDB.armor_of({"slot": "pechera", "base": "coraza_uruk"})
	var legs := EquipmentDB.armor_of({"slot": "pantalones", "base": "taparrabo_uruk"})
	var helm := EquipmentDB.helmet_of({"slot": "casco", "base": "casco_uruk"})
	_check(chest == "uruk:uruk" and legs == "uruk:taparrabo_uruk" and helm == "uruk:casco_uruk"
			and EquipmentDB.element_of({"slot": "pechera", "base": "coraza_uruk"}) == "", "valores Uruk sin elemento")
	var net_ok := CharacterLookApplier.armor_from_net_index(CharacterLookApplier.armor_net_index(chest)) == chest \
		and CharacterLookApplier.helmet_from_net_index(CharacterLookApplier.helmet_net_index(helm)) == helm \
		and CharacterLookApplier.armor_net_index("sombra") == CharacterLookApplier.ARMOR_SETS.find("sombra") + 1
	_check(net_ok, "índices de red Uruk ida y vuelta")

	var model := (load("res://assets/models/riva/riva-base.fbx") as PackedScene).instantiate() as Node3D
	add_child(model)
	var look := CharacterLook.new()
	CharacterLookApplier.apply_to(model, look)
	CharacterLookApplier.set_armor_on(model, "pechera", chest)
	CharacterLookApplier.set_armor_on(model, "pantalones", legs)
	CharacterLookApplier.set_helmet_on(model, helm)
	var skel := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var counts := {"casco": 0, "pechera": 0, "pantalones": 0}
	for c in skel.get_children():
		var n := String(c.name)
		for kind in counts:
			if n.begins_with("Acc_uruk_%s_" % kind) and not c.is_queued_for_deletion():
				counts[kind] += 1
	_check(counts["pechera"] == 3 and counts["pantalones"] == 1 and counts["casco"] == 1, "Riva lleva coraza (3 piezas), taparrabo y casco Uruk (%s)" % str(counts))
	CharacterLookApplier.set_armor_on(model, "pechera", "")
	CharacterLookApplier.set_helmet_on(model, "")
	var left := 0
	for c in skel.get_children():
		if String(c.name).begins_with("Acc_uruk_") and not c.is_queued_for_deletion():
			left += 1
	_check(left == 1, "quitar coraza y casco deja solo el taparrabo (%d)" % left)
	model.queue_free()

## Puños: arma del botín y categoría del editor de daño por fotograma.
func _fists() -> void:
	var F := WeaponData.WeaponType.FISTS
	_check(EquipmentDB.WEAPONS.has(F) and EquipmentDB.WEAPON_MODS.has(F), "los puños salen como arma de botín (con mejoras propias)")
	var ged := load("res://tools/melee_grip_editor.gd") as GDScript
	var consts := ged.get_script_constant_map()
	var cat: int = consts["CAT_FISTS"]
	_check(consts["CAT_NAMES"][cat] == "Puños" and consts["CAT_ANIM_PREFIX"][cat] == "fs" and consts["CAT_COUNT"] == cat + 1, "categoría Puños en el editor de daño")
	var anims := PlayerAnimationController.MELEE_ACTIONS.filter(func(a): return String(a).begins_with("fs"))
	_check(anims.size() >= 8 and PlayerAnimationController.attack_windows("fs1").size() > 0, "sus golpes (%d) tienen ventanas de daño" % anims.size())

func _shots(ed: Node, ids: Array, prefix: String) -> void:
	ed._skin_check.button_pressed = false
	ed._leave_skin()
	ed.set_sidebar_open(false)
	for id in ["peto_uruk", "hombrera_uruk_izq", "hombrera_uruk_der", "taparrabo_uruk", "casco_uruk"]:
		ed.show_garment(id, true)
	for v in [[0.0, 8.0], [90.0, 8.0], [180.0, 8.0]]:
		ed.set_view(v[0], v[1], 2.4, Vector3(0, 0.75, 0))
		await get_tree().create_timer(0.3).timeout
		get_viewport().get_texture().get_image().save_png("%s_todo_%d.png" % [prefix, int(v[0])])
	for id in ids:
		ed.show_garment(id, false)
