extends Node

## Tutorial del patio: pasos del director, escena real (jugador, goblin de práctica, rey y mago),
## saltar y marcar como hecho.

const FLASH_WAIT := TutorialCinematic.FLASH_AT + 0.8

func _ready() -> void:
	print("--- TEST: TUTORIAL ---")
	DungeonHub.config_path = "user://test_tutorial.cfg"
	DirAccess.remove_absolute("user://test_tutorial.cfg")
	assert(not DungeonHub.tutorial_done(), "Sin ajuste el tutorial no está hecho")

	# 0. Creación de personaje de la primera partida: sin atrás, con espada, y lleva al tutorial
	GameData.armory_path = "user://test_armeria_tut.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameData.armory_path))
	CharacterSelect.creation = true
	var cs: CharacterSelect = load("res://scenes/ui/character_select.tscn").instantiate()
	add_child(cs)
	await get_tree().process_frame
	assert(GameData.dungeon_weapon == WeaponData.WeaponType.SWORD, "La primera arma es una espada")
	assert(GameData.initial_weapons() == [WeaponData.WeaponType.SWORD], "Se empieza con la espada")
	assert(cs._btn_start.text == "CONFIRMAR E INVOCAR" and not cs._btn_back.visible, "Creación sin atrás")
	cs._on_back()
	assert(CharacterSelect.creation, "No se puede salir sin crear")
	cs.queue_free()
	CharacterSelect.creation = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameData.armory_path))
	print("CHECK 0 PASSED: creación de personaje con espada antes del tutorial")

	# 1. Director: cada evento solo cuenta en su paso
	var d := TutorialDirector.new()
	var steps := []
	d.step_changed.connect(func(i): steps.append(i))
	d.start()
	assert(d.current()["id"] == "mover")
	assert(not d.report("hit"), "Un golpe no cuenta al moverse")
	d.report("move", 3.0)
	assert(d.index == 0, "Faltan metros")
	d.report("move", 3.5)
	assert(d.index == 1, "Moverse completado")
	for e in ["hit", "dodge", "parry", "kill"]:
		for k in int(d.goal()):
			d.report(e)
	assert(d.done and steps == [0, 1, 2, 3, 4], "Pasos recorridos: %s" % [steps])
	print("CHECK 1 PASSED: director recorre los 5 pasos")

	# 2. Saltar
	var d2 := TutorialDirector.new()
	var fin := [false]
	d2.finished.connect(func(): fin[0] = true)
	d2.start()
	d2.skip_all()
	assert(fin[0] and d2.done, "Saltar termina el tutorial")
	print("CHECK 2 PASSED: saltar termina")

	# 3. Escena real
	GameData.game_mode = "dungeon"
	var scene: TutorialPatio = load("res://scenes/core/tutorial_patio.tscn").instantiate()
	get_tree().root.add_child.call_deferred(scene)
	await get_tree().process_frame
	get_tree().current_scene = scene
	for i in 10:
		await get_tree().process_frame
	assert(is_instance_valid(scene.player), "Hay jugador")
	assert(scene.king != null and scene.mage != null, "Rey y mago en el patio")
	assert(GameData.game_mode == "dungeon" and scene.player.target_lock != null, "El jugador se crea en modo mazmorra (fijar objetivo)")
	assert(scene.find_child("SkipButton", true, false) != null, "Botón de saltar")
	assert(scene.cinematic and scene.cine.running, "Empieza con la invocación")
	assert(not scene.player.visible and scene.director.index < 0, "El héroe aún no ha llegado y el tutorial espera")
	await get_tree().create_timer(FLASH_WAIT).timeout
	assert(scene.player.visible, "Tras el destello aparece el héroe")
	scene.cine.skip()
	await get_tree().create_timer(1.6).timeout
	assert(not scene.cinematic and scene.director.index == 0, "Saltar la intro empieza el tutorial")
	assert(scene.player.process_mode == Node.PROCESS_MODE_INHERIT, "El héroe vuelve a moverse")
	print("CHECK 3a PASSED: invocación -> tutorial")
	# Móvil (RUMBANG_FORCE_MOBILE=1): joystick y botones de combate visibles al acabar la invocación
	var tc := scene.find_child("MobileControls", true, false) as CanvasLayer
	if Quality.is_mobile():
		assert(tc != null and tc.visible and tc.mode == "dungeon", "En móvil el tutorial muestra los controles táctiles")
		assert(scene._hint_text.text == String(TutorialDirector.STEPS[0]["text_touch"]), "Pista con texto táctil")
		print("CHECK 3m PASSED: controles táctiles en el tutorial")
	else:
		assert(tc == null, "En PC no hay controles táctiles")
	scene.director.report("move", 6.5)
	await get_tree().process_frame
	await get_tree().process_frame
	assert(scene.goblin != null and scene.goblin.passive, "Paso de golpear: muñeco pasivo")
	scene.goblin.take_damage(5.0)
	for i in 4:
		await get_tree().process_frame
	assert(scene.director.progress >= 1.0, "El golpe al muñeco cuenta (%s)" % scene.director.progress)
	for i in 5:
		scene.director.report("hit")
	await get_tree().process_frame
	assert(scene.director.current()["id"] == "esquivar", "Pasa a esquivar")
	await get_tree().process_frame
	assert(scene.goblin != null and not scene.goblin.passive, "Paso de esquivar: goblin hostil")
	print("CHECK 3 PASSED: escena del patio con jugador, goblin de práctica y pasos")

	# 4. Saltar desde la escena marca el tutorial como hecho
	scene.skip_tutorial()
	await get_tree().create_timer(0.3).timeout
	assert(DungeonHub.tutorial_done(), "Tras saltar queda marcado como hecho")
	print("CHECK 4 PASSED: saltar marca el tutorial como hecho")
	DirAccess.remove_absolute("user://test_tutorial.cfg")
	get_tree().quit(0)
