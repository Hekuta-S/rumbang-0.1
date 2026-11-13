extends Node

## Disposición del HUD (ver HudLayout y la spec de reorganización): la vida no se mueve, la tira de equipo va a
## su derecha, el oro + pausa en una fila bajo el bloque de vida y el minimapa arriba a la derecha, en escritorio
## y en móvil. Tocar la tira abre el inventario y al cerrarlo se cierra el menú. Carga la mazmorra real.

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

func _near(a: float, b: float) -> bool:
	return absf(a - b) < 1.5

func _ready() -> void:
	print("--- TEST: DISPOSICION DEL HUD ---")
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveManager.save_path = "user://test_hud_layout_save.json"
	GameData.game_mode = "dungeon"
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
	var hud := scene.get_node("HUD")
	var eqh: EquipmentHud = scene.get_node("EquipmentHud")
	var vit: VitalsPanel = hud.vitals
	var bars: ResourceBars = hud.resource_bars
	var mm: Minimap = hud.minimap
	var row: HBoxContainer = hud.vitals_row
	await get_tree().process_frame
	await get_tree().process_frame
	var vp := get_viewport().get_visible_rect().size

	# 1. Escritorio: vida abajo a la izquierda y en su sitio; recursos debajo
	hud.apply_layout(false)
	eqh.apply_layout(false)
	await get_tree().process_frame
	var vr := vit.get_global_rect()
	_check(_near(vr.position.x, HudLayout.MARGIN), "Vida en x=22 (%.0f)" % vr.position.x)
	_check(_near(vr.end.y, vp.y + HudLayout.vitals_bottom_desktop(true)), "Vida con el borde inferior a -127 (%.0f)" % (vr.end.y - vp.y))
	_check(_near(vr.size.x, HudLayout.VITALS_PANEL_W) and _near(vr.size.y, HudLayout.VITALS_H), "Tamaño de la vida = HudLayout (%s)" % str(vr.size))
	var br := bars.get_global_rect()
	_check(br.position.y >= vr.end.y - 1.0 and _near(br.end.y, vp.y + HudLayout.RESOURCES_BOTTOM), "Recursos bajo la vida")
	if not _done(1, "escritorio: vida y recursos en su sitio"): return

	# 2. Escritorio: equipo a la derecha de la vida y centrado con ella; fila bajo el bloque; mapa arriba a la derecha
	var er := eqh.strip_rect()
	_check(_near(er.position.x, HudLayout.MARGIN), "Tira de equipo en el margen izquierdo (x=%.0f)" % er.position.x)
	# La vida flota a la izquierda del personaje, dentro de la pantalla, y solo en escritorio
	var fv: FloatingVitals = hud.floating_vitals
	var cam := get_viewport().get_camera_3d()
	var px := cam.unproject_position(enc.player.global_position + Vector3.UP * FloatingVitals.ANCHOR_UP).x
	_check(fv.visible and fv.is_on_screen(), "Vida flotante visible en escritorio")
	_check(fv.screen_pos().x < px, "Vida flotante a la izquierda del personaje (%.0f vs %.0f)" % [fv.screen_pos().x, px])
	_check(Rect2(Vector2.ZERO, vp).has_point(fv.screen_pos()), "Vida flotante dentro de la pantalla")
	_check(_near(er.get_center().y, vr.get_center().y), "Tira centrada con la vida (%.0f vs %.0f)" % [er.get_center().y, vr.get_center().y])
	var rr := row.get_global_rect()
	_check(_near(rr.position.x, HudLayout.MARGIN) and rr.position.y >= br.end.y + HudLayout.ROW_GAP - 1.0, "Fila de oro + pausa bajo el bloque (y=%.0f)" % rr.position.y)
	_check(rr.end.y <= vp.y, "La fila no se sale por abajo")
	var mr := mm.get_global_rect()
	_check(_near(mr.end.x, vp.x - HudLayout.MAP_MARGIN) and _near(mr.position.y, HudLayout.MAP_MARGIN), "Minimapa arriba a la derecha (%s)" % str(mr))
	_check(mr.position.x > vp.x * 0.5, "El minimapa ya no está a la izquierda")
	_check(not mr.intersects(er) and not mr.intersects(vr), "El mapa no pisa la vida ni la tira")
	var fr: Rect2 = hud.fps_label.get_global_rect()
	_check(fr.position.y >= mr.end.y, "El FPS va bajo el minimapa")
	if not _done(2, "escritorio: tira a la derecha, fila debajo y mapa arriba a la derecha"): return

	# 3. Móvil: la vida sigue arriba a la izquierda; la tira a su derecha; la fila bajo el bloque
	hud.apply_layout(true)
	eqh.apply_layout(true)
	await get_tree().process_frame
	_check(not hud.floating_vitals.visible, "Móvil: sin vida flotante")
	vr = vit.get_global_rect()
	_check(_near(vr.position.x, 22.0) and _near(vr.position.y, 22.0), "Móvil: vida en (22, 22) (%s)" % str(vr.position))
	br = bars.get_global_rect()
	_check(_near(br.position.y, vr.end.y), "Móvil: recursos pegados bajo la vida")
	er = eqh.strip_rect()
	_check(er.position.x >= vr.end.x and _near(er.get_center().y, vr.get_center().y), "Móvil: tira a la derecha de la vida")
	rr = row.get_global_rect()
	_check(_near(rr.position.y, br.end.y + HudLayout.ROW_GAP), "Móvil: fila bajo el bloque (%.0f vs %.0f)" % [rr.position.y, br.end.y + HudLayout.ROW_GAP])
	mr = mm.get_global_rect()
	_check(_near(mr.end.x, vp.x - HudLayout.MAP_MARGIN) and _near(mr.position.y, HudLayout.MAP_MARGIN), "Móvil: minimapa arriba a la derecha")
	# Con la barra de balas la fila baja con las barras
	# (se mide al momento: en el siguiente frame ResourceBars vuelve a lo que diga el inventario)
	var row_y := row.offset_top
	bars._show_ammo = not bars._show_ammo
	bars._layout()
	var dy: float = row.offset_top - row_y
	_check(_near(absf(dy), ResourceBars.GAP + ResourceBars.BAR_H), "Móvil: la fila se mueve 16 px con la barra de balas (%.0f)" % dy)
	bars._show_ammo = not bars._show_ammo
	bars._layout()
	if not _done(3, "móvil: misma disposición relativa"): return

	# 4. La fila contiene el oro y el botón de pausa (oro a la izquierda)
	var gold: Control = row.get_node_or_null("GoldPanel")
	var pause: Button = row.get_node_or_null("PauseButton")
	_check(gold != null and pause != null, "Fila con oro y pausa")
	_check(gold != null and pause != null and gold.get_index() < pause.get_index(), "Oro a la izquierda, pausa a la derecha")
	_check(pause != null and pause.visible, "Botón de pausa visible")
	_check(pause != null and _near(pause.custom_minimum_size.x, HudLayout.PAUSE_MOBILE), "Pausa de 58 px en móvil")
	hud.apply_layout(false)
	eqh.apply_layout(false)
	await get_tree().process_frame
	_check(pause != null and _near(pause.custom_minimum_size.x, HudLayout.PAUSE_DESKTOP), "Pausa de 44 px en escritorio")
	_check(_near(row.get_global_rect().position.y, vp.y + HudLayout.row_top_desktop()), "Escritorio: la fila vuelve a su sitio")
	if not _done(4, "fila de oro + pausa"): return

	# 5. Tocar la tira abre el inventario; cerrarlo cierra el menú
	var pm := get_tree().root.find_child("PauseMenu", true, false)
	_check(pm != null, "Hay menú de pausa")
	if not _done("5a", "menú de pausa presente"): return
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = false
	eqh._on_strip_input(click)
	await get_tree().process_frame
	_check(pm.visible, "El menú de pausa se abre")
	_check(is_instance_valid(pm._equip_panel), "Se abre el inventario (EquipmentPanel)")
	_check(get_tree().paused, "La partida se pausa")
	pm._equip_panel.close()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not pm.visible, "Al cerrar el inventario se cierra el menú")
	_check(not get_tree().paused, "El juego sigue")
	# Tocar un hueco también abre el inventario
	eqh._plate.socket_pressed.emit(0)
	await get_tree().process_frame
	_check(is_instance_valid(pm._equip_panel), "Tocar un hueco abre el inventario")
	pm._equip_panel.close()
	await get_tree().process_frame
	await get_tree().process_frame
	if not _done(5, "tira de equipo -> inventario"): return

	# 6. Mapa: tocar lo amplía y vuelve a tocar lo cierra; textos de ayuda
	mm.apply_layout(false)
	_check(mm.hint_text() == "M · TOCA", "Ayuda compacta en escritorio")
	var tap := InputEventMouseButton.new()
	tap.button_index = MOUSE_BUTTON_LEFT
	tap.pressed = true
	mm._gui_input(tap)
	_check(mm.is_expanded() and mm.hint_text().contains("TOCA PARA CERRAR"), "Tocar amplía el mapa")
	mm._gui_input(tap)
	_check(not mm.is_expanded(), "Volver a tocar lo cierra")
	_check(is_equal_approx(HudLayout.map_compact(800.0), HudLayout.MAP_COMPACT_NARROW), "Pantalla estrecha: mapa de 150")
	if not _done(6, "minimapa pulsable"): return

	print("ALL HUD LAYOUT CHECKS PASSED")
	get_tree().quit(0)
