extends Node

## Editor visual del agarre de espadones, dagas, mazas, espadas y arcos (mano izquierda), y de las ventanas de daño de sus ataques.
## Abrir tools/melee_grip_editor.tscn (o greatsword_grip_editor.tscn) con F6, con ventana normal (no headless).
##
## Panel izquierdo — AGARRE: elige arma, modelo (y mano, en las dagas), mueve posición/rotación/escala, a mano o con
## el gizmo sobre el arma (como el editor de ropa: W mover, E rotar, R escalar). H / Tab ocultan los paneles. Guardar escribe
## resources/greatsword_grip.json, dagger_grip.json, mace_grip.json y sword_grip.json.
## Panel inferior — VENTANAS DE DAÑO: elige un ataque de la lista y recórrelo fotograma a fotograma (30 fps). Las
## franjas rojas son los fotogramas en los que el arma hace daño: arrastra sus bordes o pulsa I / O para poner el
## inicio / fin en el cabezal. Guardar escribe resources/attack_windows.json, que manda sobre
## PlayerAnimationController.ATTACK_WINDOWS. Con un ataque en pantalla también se puede retocar el agarre en esa pose.
##
## Convención del agarre: la rotación (grados) se aplica en los ejes locales del modelo normalizado (Y = hoja/mango
## hacia la punta/cabeza) antes de alinearlo a la mano; por eso X/Z inclinan el arma y Y la gira sobre su eje.

const Timeline := preload("res://tools/hit_window_timeline.gd")

const UI_MARGIN := 12.0
const SIDEBAR_W := 360.0
const CAM_START_YAW := 35.0
const CAM_START_PITCH := 10.0
const CAM_START_DIST := 2.6
const CAM_MIN_DIST := 0.6
const CAM_MAX_DIST := 8.0
const FPS := 30.0

const CAT_GS := 0
const CAT_DAGGER := 1
const CAT_MACE := 2
const CAT_SWORD := 3
const CAT_BOW := 4
const CAT_KATANA := 5
const CAT_COUNT := 6
const CAT_NAMES := ["Espadones", "Dagas", "Mazas", "Espadas", "Arcos", "Katanas"]
## Prefijo de las acciones de combo de cada categoría (PlayerAnimationController.MELEE_ACTIONS).
const CAT_ANIM_PREFIX := ["gs", "dagger", "mace", "sw", "bow", "kt"]
const SPEEDS := [["0,25×", 0.25], ["0,5×", 0.5], ["1× (juego)", 1.0]]

# Paleta
const C_ACCENT := Color(0.95, 0.55, 0.22)
const C_PANEL := Color(0.075, 0.08, 0.1, 0.94)
const C_FIELD := Color(0.13, 0.14, 0.17)
const C_BTN := Color(0.17, 0.18, 0.22)
const C_BTN_HOVER := Color(0.23, 0.245, 0.3)
const C_TEXT_DIM := Color(1, 1, 1, 0.55)
const C_OK := Color(0.45, 0.85, 0.5)
const C_WARN := Color(1.0, 0.75, 0.3)
const C_ERR := Color(1.0, 0.4, 0.38)
const C_HIT := Color(0.93, 0.27, 0.24)
const AXIS_COLORS := [Color(0.95, 0.38, 0.38), Color(0.5, 0.85, 0.4), Color(0.4, 0.6, 1.0)]

var _main: Node
var _player: CharacterBody3D
var _vis: PlayerWeaponVisuals
var _cam: Camera3D
var _yaw := CAM_START_YAW
var _pitch := CAM_START_PITCH
var _dist := CAM_START_DIST
var _dragging := false

var _cat := CAT_GS
var _skin := 0
var _hand := "right"
## _values[cat][skin] -> {"pos","rot"} (espadón/maza/espada) o {"right": {...}, "left": {...}} (dagas).
var _values: Dictionary = {}
var _syncing := false
var _frozen := true  ## Pose congelada por defecto.
var _grip_dirty := false
var _win_dirty := false

# Ventanas de daño / vista previa del ataque
var _win_edit: Dictionary = {}       ## anim -> [[ini_s, fin_s], ...] (se edita en sitio)
var _anim_names: Array[String] = []
var _anim_name := ""
var _preview := false
var _playing := false
var _preview_t := 0.0
var _rate := 1.0
var _saved_anim := ""
var _saved_pos := 0.0

# UI
var _theme: Theme
var _sidebar: PanelContainer
var _bottom: PanelContainer
var _bottom_body: Control
var _collapse_btn: Button
var _subtitle: Label
var _cat_select: OptionButton
var _skin_select: OptionButton
var _hand_select: OptionButton
var _hand_row: Control
var _copy_hand_btn: Button
var _freeze_check: CheckButton
var _fine_check: CheckButton
var _pos_spins: Array[SpinBox] = []
var _rot_spins: Array[SpinBox] = []
var _pos_sliders: Array[HSlider] = []
var _rot_sliders: Array[HSlider] = []
var _scl_spins: Array[SpinBox] = []
var _scl_sliders: Array[HSlider] = []
var _ui_layer: CanvasLayer
var _hide_hint: Label
var _status: Label
var _status_dot: Panel
var _anim_list: ItemList
var _timeline: Timeline
var _play_btn: Button
var _loop_check: CheckButton
var _speed_select: OptionButton
var _frame_label: Label
var _hit_chip: PanelContainer
var _hit_chip_label: Label
var _win_start: SpinBox
var _win_end: SpinBox
var _win_info: Label

func _ready() -> void:
	get_window().title = "Rumbang · Editor de agarre y daño cuerpo a cuerpo"
	GameData.game_mode = "dungeon"
	_main = (load(Net.game_scene()) as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(_main)
	_run.call_deferred()

func _run() -> void:
	await get_tree().process_frame
	get_tree().current_scene = _main

	var player := _main.get_node_or_null("Player") as CharacterBody3D
	if player == null:
		_fail("No se encontró el Player en la escena de mazmorra.")
		return
	_player = player
	if _player.health_comp:
		_player.health_comp.max_hp = 99999.0
		_player.health_comp.hp = 99999.0

	await get_tree().create_timer(3.0).timeout

	# Desactivar todo lo que no sea visual.
	var enc := _main.get_node_or_null("DungeonEncounter")
	if enc:
		enc.process_mode = Node.PROCESS_MODE_DISABLED
	for e in get_tree().get_nodes_in_group("enemies"):
		(e as Node).queue_free()
	for c in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(c as CanvasLayer).visible = false

	var map := _main.get_node_or_null("ProceduralMap")
	if map and map.has_method("room_center"):
		_player.global_position = map.room_center(0) + Vector3(0, 0.3, 0)
	_player.velocity = Vector3.ZERO
	_player.mesh.rotation.y = 0.0

	# Sin input del jugador: los clics son para la UI y la cámara orbital.
	_player.input_controller.set_physics_process(false)
	_player.input_controller.set_process_unhandled_input(false)
	_player.input_controller.set_process_input(false)

	_vis = _player.weapon_visuals
	if _vis == null or not _vis.has_method("set_greatsword_grip") \
			or not _vis.has_method("set_dagger_grip") or not _vis.has_method("set_mace_grip") \
			or not _vis.has_method("set_sword_grip") or not _vis.has_method("set_bow_grip"):
		_fail("PlayerWeaponVisuals no expone los ajustes de agarre.")
		return
	_cat = CAT_GS
	_skin = _player.greatsword_skin()
	_load_values()
	_build_camera()
	_build_ui()
	_ensure_weapon_selected()
	_apply_skin()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Esperar a que el AnimationTree aplique la pose del arma al esqueleto
	await get_tree().process_frame
	await get_tree().process_frame

	# Congelar la pose del personaje: totalmente estático.
	_freeze_pose(true)
	_refresh_anim_list()
	_set_status("Listo · %s" % _model_name(_cat, _skin), C_OK)
	print("[MeleeGripEditor] Listo: ", _model_name(_cat, _skin), " · holder=", _active_holder(),
		" · ataques=", _anim_names)

func _fail(message: String) -> void:
	push_error(message)
	printerr(message)
	get_tree().quit(1)

# ══════════════════════════════════════════════════════════════════════════════
# Congelado de pose — el personaje queda como una estatua
# ══════════════════════════════════════════════════════════════════════════════

func _freeze_pose(frozen: bool) -> void:
	_frozen = frozen
	if not is_instance_valid(_player):
		return
	if not frozen and _preview:
		_exit_preview(false)

	_player.set_physics_process(not frozen)
	for ctrl in [_player.movement_controller, _player.combat_controller, _player.parry_controller,
			_player.finisher_controller, _player.get("target_lock")]:
		if ctrl:
			(ctrl as Node).set_physics_process(not frozen)
			(ctrl as Node).set_process(not frozen)

	# El controlador de animación: su _process() actualiza locomotion, strafe, etc.
	var anim_ctrl = _player.animation_controller
	if anim_ctrl:
		anim_ctrl.set_process(not frozen)
		anim_ctrl.set_physics_process(not frozen)
		# El AnimationTree reproduce la idle en bucle y mueve el modelo.
		if is_instance_valid(anim_ctrl.anim_tree):
			anim_ctrl.anim_tree.active = not frozen
		if is_instance_valid(anim_ctrl.anim_player):
			if frozen:
				anim_ctrl.anim_player.pause()
			else:
				anim_ctrl.anim_player.play()
		if anim_ctrl.foot_ik:
			anim_ctrl.foot_ik.active = not frozen

	# Cualquier otro SkeletonModifier3D (LookHeadModifier, HandIKModifier…).
	if anim_ctrl and is_instance_valid(anim_ctrl.model):
		for modifier in anim_ctrl.model.find_children("*", "SkeletonModifier3D", true, false):
			(modifier as SkeletonModifier3D).active = not frozen

	_player.velocity = Vector3.ZERO
	if _freeze_check:
		_freeze_check.set_pressed_no_signal(frozen)

## Reactiva brevemente la animación para que el esqueleto adopte la postura del arma, y vuelve a congelar.
func _settle_pose_then_freeze() -> void:
	if not _frozen:
		return
	_freeze_pose(false)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_freeze_pose(true)

# ══════════════════════════════════════════════════════════════════════════════
# Cámara orbital centrada en la mano del arma
# ══════════════════════════════════════════════════════════════════════════════

func _build_camera() -> void:
	_cam = Camera3D.new()
	_cam.name = "GripEditorCamera"
	_cam.fov = 45.0
	_cam.near = 0.05
	_cam.far = 80.0
	_main.add_child(_cam)
	_cam.current = true

	var key := OmniLight3D.new()
	key.name = "GripEditorKey"
	key.omni_range = 10.0
	key.light_energy = 3.0
	key.shadow_enabled = false
	_main.add_child(key)
	key.global_position = _player.global_position + Vector3(2.0, 3.0, 2.0)

	var fill := OmniLight3D.new()
	fill.name = "GripEditorFill"
	fill.omni_range = 8.0
	fill.light_energy = 1.2
	fill.light_color = Color(0.75, 0.85, 1.0)
	fill.shadow_enabled = false
	_main.add_child(fill)
	fill.global_position = _player.global_position + Vector3(-2.0, 1.6, 1.5)

func _process(delta: float) -> void:
	# La partida captura el ratón al arrancar; aquí siempre debe quedar libre.
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _frozen and is_instance_valid(_player):
		_player.velocity = Vector3.ZERO

	if _preview and _playing and _anim_name != "":
		var length := _clip_length(_anim_name)
		_preview_t += delta * _rate * _combo_speed(_anim_name)
		if _preview_t > length:
			if _loop_check.button_pressed:
				_preview_t = fmod(_preview_t, length)
			else:
				_preview_t = length
				_set_playing(false)
		_pose_at(_preview_t)
		_timeline.set_time_external(_preview_t)
		_update_frame_label()

	if not is_instance_valid(_cam) or _player == null:
		return
	var target := _player.global_position + Vector3(0.0, 1.1, 0.0)
	var holder := _active_holder()
	if is_instance_valid(holder):
		target = target.lerp(holder.global_position, 0.55)
	var yaw := deg_to_rad(_yaw)
	var pitch := deg_to_rad(_pitch)
	var offset := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * _dist
	_cam.global_position = target + offset
	_cam.look_at(target, Vector3.UP)
	_update_gizmo()

func _unhandled_input(event: InputEvent) -> void:
	if _gizmo_input(event):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_dist = clampf(_dist - 0.15, CAM_MIN_DIST, CAM_MAX_DIST)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_dist = clampf(_dist + 0.15, CAM_MIN_DIST, CAM_MAX_DIST)
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
				_dragging = mb.pressed
			MOUSE_BUTTON_MIDDLE:
				if mb.pressed:
					_yaw = CAM_START_YAW
					_pitch = CAM_START_PITCH
					_dist = CAM_START_DIST
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * 0.4
		_pitch = clampf(_pitch + mm.relative.y * 0.3, -70.0, 80.0)
	elif event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed:
			return
		var handled := true
		if key.keycode == KEY_S and key.ctrl_pressed:
			_on_save()
		elif key.keycode == KEY_SPACE:
			_freeze_check.button_pressed = not _freeze_check.button_pressed
		elif key.keycode == KEY_K:
			_on_play_pressed()
		elif key.keycode == KEY_LEFT:
			_step_frames(-1)
		elif key.keycode == KEY_RIGHT:
			_step_frames(1)
		elif key.keycode == KEY_HOME:
			_seek_preview(0.0)
		elif key.keycode == KEY_END:
			_seek_end()
		elif key.keycode == KEY_I:
			_set_edge_at_head(0)
		elif key.keycode == KEY_O:
			_set_edge_at_head(1)
		elif key.keycode == KEY_H or key.keycode == KEY_TAB:
			_toggle_ui()
		elif key.keycode == KEY_W and not key.ctrl_pressed:
			_set_gizmo_mode(GIZMO_MOVE)
		elif key.keycode == KEY_E and not key.ctrl_pressed:
			_set_gizmo_mode(GIZMO_ROTATE)
		elif key.keycode == KEY_R and not key.ctrl_pressed:
			_set_gizmo_mode(GIZMO_SCALE)
		elif key.keycode == KEY_X:
			_local_check.button_pressed = not _local_check.button_pressed
		elif key.keycode == KEY_Z and key.ctrl_pressed:
			_undo_grip()
		elif key.keycode == KEY_ESCAPE and _gz_drag >= 0:
			_cancel_gizmo_drag()
		else:
			handled = false
		if handled:
			get_viewport().set_input_as_handled()

# ══════════════════════════════════════════════════════════════════════════════
# Tema
# ══════════════════════════════════════════════════════════════════════════════

func _box(bg: Color, radius := 6, border := Color(0, 0, 0, 0), margin := 8.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	if border.a > 0.0:
		sb.border_color = border
		sb.set_border_width_all(1)
	sb.content_margin_left = margin
	sb.content_margin_right = margin
	sb.content_margin_top = margin * 0.6
	sb.content_margin_bottom = margin * 0.6
	return sb

func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 12

	var panel := _box(C_PANEL, 10, Color(1, 1, 1, 0.07), 14.0)
	panel.shadow_color = Color(0, 0, 0, 0.35)
	panel.shadow_size = 8
	t.set_stylebox("panel", "PanelContainer", panel)

	var normal := _box(C_BTN, 6, Color(1, 1, 1, 0.06))
	var hover := _box(C_BTN_HOVER, 6, Color(1, 1, 1, 0.1))
	var pressed := _box(C_ACCENT.darkened(0.25), 6)
	var disabled := _box(Color(C_BTN, 0.5), 6)
	var focus := _box(Color(0, 0, 0, 0), 6, Color(C_ACCENT, 0.7))
	focus.draw_center = false
	for cls in ["Button", "OptionButton", "CheckButton"]:
		t.set_stylebox("normal", cls, normal if cls != "CheckButton" else _box(Color(0, 0, 0, 0), 6))
		t.set_stylebox("hover", cls, hover if cls != "CheckButton" else _box(Color(1, 1, 1, 0.04), 6))
		t.set_stylebox("pressed", cls, pressed if cls != "CheckButton" else _box(Color(0, 0, 0, 0), 6))
		t.set_stylebox("hover_pressed", cls, pressed if cls != "CheckButton" else _box(Color(1, 1, 1, 0.04), 6))
		t.set_stylebox("disabled", cls, disabled)
		t.set_stylebox("focus", cls, focus)
		t.set_color("font_hover_color", cls, Color.WHITE)
		t.set_color("font_pressed_color", cls, Color.WHITE)

	var field := _box(C_FIELD, 5, Color(1, 1, 1, 0.06), 6.0)
	var field_focus := _box(C_FIELD, 5, Color(C_ACCENT, 0.8), 6.0)
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", field_focus)
	t.set_color("selection_color", "LineEdit", Color(C_ACCENT, 0.4))

	var rail := StyleBoxFlat.new()
	rail.bg_color = Color(1, 1, 1, 0.1)
	rail.set_corner_radius_all(2)
	rail.content_margin_top = 2
	rail.content_margin_bottom = 2
	var rail_fill := rail.duplicate() as StyleBoxFlat
	rail_fill.bg_color = Color(C_ACCENT, 0.75)
	t.set_stylebox("slider", "HSlider", rail)
	t.set_stylebox("grabber_area", "HSlider", rail_fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", rail_fill)

	var list_bg := _box(Color(0.05, 0.055, 0.07), 6, Color(1, 1, 1, 0.06), 4.0)
	t.set_stylebox("panel", "ItemList", list_bg)
	t.set_stylebox("focus", "ItemList", _box(Color(0, 0, 0, 0), 6))
	t.set_stylebox("selected", "ItemList", _box(Color(C_ACCENT, 0.3), 4))
	t.set_stylebox("selected_focus", "ItemList", _box(Color(C_ACCENT, 0.4), 4))
	t.set_stylebox("hovered", "ItemList", _box(Color(1, 1, 1, 0.06), 4))
	t.set_constant("v_separation", "ItemList", 6)

	var sep := StyleBoxLine.new()
	sep.color = Color(1, 1, 1, 0.08)
	sep.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_color("font_color", "TooltipLabel", Color.WHITE)
	return t

# ══════════════════════════════════════════════════════════════════════════════
# UI
# ══════════════════════════════════════════════════════════════════════════════

func _build_ui() -> void:
	_theme = _make_theme()
	var layer := CanvasLayer.new()
	_ui_layer = layer
	layer.name = "GripEditorUI"
	layer.layer = 100
	add_child(layer)

	var root := Control.new()
	root.theme = _theme
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)

	_build_bottom(root)
	_build_sidebar(root)
	_bottom.resized.connect(_layout)
	_layout.call_deferred()

	_hand_row.visible = _cat == CAT_DAGGER
	_refresh_skin_select()
	_show_values(_current_entry())
	# Aviso con el menú oculto (en su propia capa)
	var hint_layer := CanvasLayer.new()
	hint_layer.layer = 101
	add_child(hint_layer)
	_hide_hint = Label.new()
	_hide_hint.text = "Menú oculto · H para mostrar"
	_hide_hint.position = Vector2(UI_MARGIN, UI_MARGIN)
	_hide_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	_hide_hint.visible = false
	hint_layer.add_child(_hide_hint)
	_build_gizmo()
	_set_gizmo_mode(GIZMO_MOVE)

func _layout() -> void:
	if _sidebar and _bottom:
		_sidebar.offset_bottom = -(_bottom.size.y + UI_MARGIN * 2.0)

func _build_sidebar(root: Control) -> void:
	_sidebar = PanelContainer.new()
	_sidebar.anchor_left = 0.0
	_sidebar.anchor_top = 0.0
	_sidebar.anchor_bottom = 1.0
	_sidebar.offset_left = UI_MARGIN
	_sidebar.offset_top = UI_MARGIN
	_sidebar.offset_right = UI_MARGIN + SIDEBAR_W
	root.add_child(_sidebar)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_sidebar.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)

	# — Cabecera —
	var title := Label.new()
	title.text = "Agarre cuerpo a cuerpo"
	title.add_theme_font_size_override("font_size", 19)
	box.add_child(title)
	_subtitle = Label.new()
	_subtitle.add_theme_font_size_override("font_size", 12)
	_subtitle.add_theme_color_override("font_color", C_ACCENT)
	box.add_child(_subtitle)

	var toggles := HBoxContainer.new()
	_freeze_check = CheckButton.new()
	_freeze_check.text = "Congelar pose"
	_freeze_check.tooltip_text = "Espacio. Desactívalo para ver la animación en reposo en vivo."
	_freeze_check.button_pressed = true
	_freeze_check.toggled.connect(_on_freeze_toggled)
	toggles.add_child(_freeze_check)
	_fine_check = CheckButton.new()
	_fine_check.text = "Paso fino"
	_fine_check.tooltip_text = "Pasos de 1 mm y 0,1° en vez de 5 mm y 1°"
	_fine_check.toggled.connect(_on_fine_toggled)
	toggles.add_child(_fine_check)
	box.add_child(toggles)

	# — Arma —
	box.add_child(_section("ARMA"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	box.add_child(grid)

	grid.add_child(_dim_label("Tipo"))
	_cat_select = OptionButton.new()
	_cat_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in CAT_COUNT:
		_cat_select.add_item(CAT_NAMES[i], i)
	_cat_select.select(_cat)
	_cat_select.item_selected.connect(_on_category_selected)
	grid.add_child(_cat_select)

	grid.add_child(_dim_label("Modelo"))
	_skin_select = OptionButton.new()
	_skin_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skin_select.item_selected.connect(_on_skin_selected)
	grid.add_child(_skin_select)

	# — Mano (solo dagas) —
	_hand_row = HBoxContainer.new()
	_hand_row.add_theme_constant_override("separation", 6)
	var hand_label := _dim_label("Mano")
	hand_label.custom_minimum_size.x = 50
	_hand_row.add_child(hand_label)
	_hand_select = OptionButton.new()
	_hand_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hand_select.add_item("Derecha", 0)
	_hand_select.add_item("Izquierda", 1)
	_hand_select.select(0)
	_hand_select.item_selected.connect(_on_hand_selected)
	_hand_row.add_child(_hand_select)
	_copy_hand_btn = Button.new()
	_copy_hand_btn.text = "Copiar → izq."
	_copy_hand_btn.tooltip_text = "Copia posición y rotación a la otra mano"
	_copy_hand_btn.pressed.connect(_on_copy_to_other_hand)
	_hand_row.add_child(_copy_hand_btn)
	box.add_child(_hand_row)

	# — Posición / rotación —
	box.add_child(_section("POSICIÓN  (m)"))
	for i in 3:
		_add_axis_row(box, i, -1.0, 1.0, 0.005, " m", _pos_spins, _pos_sliders)
	box.add_child(_section("ROTACIÓN  (°)"))
	for i in 3:
		_add_axis_row(box, i, -180.0, 180.0, 1.0, "°", _rot_spins, _rot_sliders)
	box.add_child(_section("ESCALA  (×)"))
	for i in 3:
		_add_axis_row(box, i, 0.05, 4.0, 0.01, "×", _scl_spins, _scl_sliders)

	# — Gizmo —
	box.add_child(_section("GIZMO"))
	var gz_row := HBoxContainer.new()
	gz_row.add_theme_constant_override("separation", 4)
	for m in 3:
		var b := Button.new()
		b.text = GIZMO_MODE_NAMES[m]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_set_gizmo_mode.bind(m))
		gz_row.add_child(b)
		_gz_buttons.append(b)
	box.add_child(gz_row)
	var gz_row2 := HBoxContainer.new()
	_local_check = CheckButton.new()
	_local_check.text = "Ejes del arma (X)"
	_local_check.focus_mode = Control.FOCUS_NONE
	_local_check.button_pressed = true
	gz_row2.add_child(_local_check)
	_snap_check = CheckButton.new()
	_snap_check.text = "Imán (Ctrl)"
	_snap_check.focus_mode = Control.FOCUS_NONE
	gz_row2.add_child(_snap_check)
	box.add_child(gz_row2)

	# — Acciones —
	box.add_child(HSeparator.new())
	var save := Button.new()
	save.text = "Guardar todo   (Ctrl+S)"
	save.tooltip_text = "Escribe los *_grip.json y resources/attack_windows.json"
	save.add_theme_stylebox_override("normal", _box(C_ACCENT.darkened(0.1), 6))
	save.add_theme_stylebox_override("hover", _box(C_ACCENT, 6))
	save.add_theme_stylebox_override("pressed", _box(C_ACCENT.darkened(0.3), 6))
	save.add_theme_color_override("font_color", Color(0.08, 0.06, 0.04))
	save.add_theme_color_override("font_hover_color", Color(0.05, 0.04, 0.02))
	save.custom_minimum_size.y = 34
	save.pressed.connect(_on_save)
	box.add_child(save)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	var reset := _button("Restablecer", "Vuelve al agarre por defecto de la mano (sin guardar)", _on_reset)
	var reload := _button("Recargar", "Descarta los cambios sin guardar y relee los JSON", _on_reload)
	var close := _button("Cerrar", "Salir del editor", func() -> void: get_tree().quit(0))
	var hide_btn := _button("Ocultar (H)", "Oculta los paneles; H o Tab los vuelven a mostrar", _toggle_ui)
	for b in [reset, reload, hide_btn, close]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		buttons.add_child(b)
	box.add_child(buttons)

	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 8)
	_status_dot = Panel.new()
	_status_dot.custom_minimum_size = Vector2(9, 9)
	_status_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	status_row.add_child(_status_dot)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.add_theme_font_size_override("font_size", 12)
	status_row.add_child(_status)
	box.add_child(status_row)

	var hint := Label.new()
	hint.text = "Vista: arrastrar = orbitar · rueda = zoom · botón central = reiniciar\n" \
		+ "Gizmo: W mover · E rotar · R escalar · X ejes · Ctrl imán · Ctrl+Z deshacer · H / Tab = ocultar menú\n" \
		+ "Ataque: K = reproducir · ←/→ = fotograma · I / O = inicio / fin del daño"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	box.add_child(hint)

func _build_bottom(root: Control) -> void:
	_bottom = PanelContainer.new()
	_bottom.anchor_left = 0.0
	_bottom.anchor_right = 1.0
	_bottom.anchor_top = 1.0
	_bottom.anchor_bottom = 1.0
	_bottom.offset_left = UI_MARGIN
	_bottom.offset_right = -UI_MARGIN
	_bottom.offset_bottom = -UI_MARGIN
	_bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(_bottom)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	_bottom.add_child(outer)

	# — Cabecera con transporte —
	var head := HFlowContainer.new()
	head.add_theme_constant_override("h_separation", 6)
	head.add_theme_constant_override("v_separation", 6)
	outer.add_child(head)
	_collapse_btn = Button.new()
	_collapse_btn.flat = true
	_collapse_btn.text = "▾  VENTANAS DE DAÑO"
	_collapse_btn.add_theme_color_override("font_color", C_ACCENT)
	_collapse_btn.add_theme_color_override("font_hover_color", C_ACCENT.lightened(0.2))
	_collapse_btn.tooltip_text = "Mostrar / ocultar el panel"
	_collapse_btn.pressed.connect(_on_collapse)
	head.add_child(_collapse_btn)

	var spacer := Control.new()
	spacer.custom_minimum_size.x = 8
	head.add_child(spacer)
	head.add_child(_button("⏮", "Primer fotograma (Inicio)", func() -> void: _seek_preview(0.0)))
	head.add_child(_button("◀", "Fotograma anterior (←)", func() -> void: _step_frames(-1)))
	_play_btn = _button("▶  Reproducir", "Reproducir / pausar (K)", _on_play_pressed)
	_play_btn.custom_minimum_size.x = 120
	head.add_child(_play_btn)
	head.add_child(_button("▶", "Fotograma siguiente (→)", func() -> void: _step_frames(1)))
	head.add_child(_button("⏭", "Último fotograma (Fin)", _seek_end))
	_speed_select = OptionButton.new()
	for i in SPEEDS.size():
		_speed_select.add_item(SPEEDS[i][0], i)
	_speed_select.select(1)
	_rate = SPEEDS[1][1]
	_speed_select.tooltip_text = "Velocidad de reproducción (1× = la del combo en el juego)"
	_speed_select.item_selected.connect(func(i: int) -> void: _rate = float(SPEEDS[i][1]))
	head.add_child(_speed_select)
	_loop_check = CheckButton.new()
	_loop_check.text = "Bucle"
	_loop_check.button_pressed = true
	head.add_child(_loop_check)

	_frame_label = Label.new()
	_frame_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_frame_label.add_theme_font_size_override("font_size", 13)
	head.add_child(_frame_label)
	_hit_chip = PanelContainer.new()
	_hit_chip_label = Label.new()
	_hit_chip_label.add_theme_font_size_override("font_size", 11)
	_hit_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_hit_chip.add_child(_hit_chip_label)
	head.add_child(_hit_chip)

	# — Cuerpo: lista + línea de tiempo —
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	outer.add_child(body)
	_bottom_body = body

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	body.add_child(left)
	_anim_list = ItemList.new()
	_anim_list.custom_minimum_size = Vector2(200, 112)
	_anim_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_anim_list.tooltip_text = "Ataques del arma (fotogramas · golpes). • = cambios sin guardar"
	_anim_list.item_selected.connect(_on_anim_selected)
	left.add_child(_anim_list)
	_win_info = Label.new()
	_win_info.custom_minimum_size.x = 200
	_win_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_win_info.add_theme_font_size_override("font_size", 11)
	_win_info.add_theme_color_override("font_color", C_TEXT_DIM)
	left.add_child(_win_info)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	body.add_child(right)

	_timeline = Timeline.new()
	_timeline.fps = FPS
	_timeline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_timeline.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_timeline.custom_minimum_size = Vector2(300, 96)
	_timeline.tooltip_text = "Rojo = daño · azul = ventana de enlace · discontinuo = tabla del código
" 		+ "Clic = mover cabezal · arrastrar borde/franja = editar · doble clic = nueva ventana" \
		+ " · clic derecho = quitar · Shift = sin imán · rueda = fotograma"
	_timeline.scrubbed.connect(_on_timeline_scrubbed)
	_timeline.windows_edited.connect(_on_windows_edited)
	_timeline.selection_changed.connect(func(_i: int) -> void: _sync_window_fields())
	right.add_child(_timeline)

	var edit := HFlowContainer.new()
	edit.add_theme_constant_override("h_separation", 6)
	edit.add_theme_constant_override("v_separation", 6)
	right.add_child(edit)
	edit.add_child(_dim_label("Inicio"))
	_win_start = _frame_spin()
	_win_start.value_changed.connect(func(v: float) -> void: _on_window_field(0, v))
	edit.add_child(_win_start)
	edit.add_child(_dim_label("Fin"))
	_win_end = _frame_spin()
	_win_end.value_changed.connect(func(v: float) -> void: _on_window_field(1, v))
	edit.add_child(_win_end)
	edit.add_child(_button("Inicio aquí [I]", "Pone el inicio de la ventana en el cabezal", func() -> void: _set_edge_at_head(0)))
	edit.add_child(_button("Fin aquí [O]", "Pone el fin de la ventana en el cabezal", func() -> void: _set_edge_at_head(1)))
	edit.add_child(_button("+ Ventana", "Añade una ventana de daño en el cabezal (o doble clic)", _add_window))
	edit.add_child(_button("Quitar", "Quita la ventana seleccionada (o clic derecho en ella)", _remove_window))
	edit.add_child(_button("Tabla original", "Vuelve a las ventanas del código (ATTACK_WINDOWS)", _on_windows_reset))
	edit.add_child(_button("Pose de reposo", "Sale de la vista del ataque y vuelve a la postura del arma",
		func() -> void: _exit_preview(true)))
	_update_frame_label()

func _section(text: String) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", C_ACCENT)
	v.add_child(label)
	v.add_child(HSeparator.new())
	return v

func _dim_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", C_TEXT_DIM)
	return label

func _button(text: String, tip: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b

func _frame_spin() -> SpinBox:
	var s := SpinBox.new()
	s.min_value = 0.0
	s.max_value = 999.0
	s.step = 0.1
	s.custom_arrow_step = 1.0
	s.suffix = "f"
	s.custom_minimum_size.x = 116
	return s

func _add_axis_row(parent: VBoxContainer, axis: int, min_value: float, max_value: float, step: float,
		suffix: String, spins: Array[SpinBox], sliders: Array[HSlider]) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.text = ["X", "Y", "Z"][axis]
	label.custom_minimum_size.x = 14
	label.add_theme_color_override("font_color", AXIS_COLORS[axis])
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.focus_mode = Control.FOCUS_NONE
	row.add_child(slider)
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	spin.suffix = suffix
	spin.custom_minimum_size.x = 150
	spin.share(slider)
	spin.value_changed.connect(_on_values_changed)
	row.add_child(spin)
	parent.add_child(row)
	spins.append(spin)
	sliders.append(slider)

func _set_status(text: String, color: Color) -> void:
	if _status == null:
		return
	_status.text = text
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(5)
	_status_dot.add_theme_stylebox_override("panel", sb)
	_subtitle.text = "%s · %s" % [CAT_NAMES[_cat], _model_name(_cat, _skin)] \
		+ (" · mano %s" % ("izquierda" if _hand == "left" else "derecha") if _cat == CAT_DAGGER else "")

func _mark_dirty() -> void:
	var parts: Array[String] = []
	if _grip_dirty:
		parts.append("agarre")
	if _win_dirty:
		parts.append("ventanas de daño")
	_set_status("Sin guardar: %s" % ", ".join(parts), C_WARN)

# ══════════════════════════════════════════════════════════════════════════════
# Datos y previsualización del agarre
# ══════════════════════════════════════════════════════════════════════════════

func _model_count(cat: int) -> int:
	match cat:
		CAT_GS:
			return GreatswordModels.count()
		CAT_DAGGER:
			return DaggerModels.count()
		CAT_SWORD:
			return SwordModels.count()
		CAT_BOW:
			return BowModels.count()
		CAT_KATANA:
			return KatanaModels.count()
		_:
			return MaceModels.count()

func _model_name(cat: int, skin: int) -> String:
	match cat:
		CAT_GS:
			return GreatswordModels.skin_name(skin)
		CAT_DAGGER:
			return DaggerModels.skin_name(skin)
		CAT_SWORD:
			return SwordModels.skin_name(skin)
		CAT_BOW:
			return BowModels.skin_name(skin)
		CAT_KATANA:
			return KatanaModels.skin_name(skin)
		_:
			return MaceModels.skin_name(skin)

func _cat_weapon(cat: int) -> int:
	match cat:
		CAT_GS:
			return WeaponData.WeaponType.GREATSWORD
		CAT_DAGGER:
			return WeaponData.WeaponType.DAGGERS
		CAT_SWORD:
			return WeaponData.WeaponType.SWORD
		CAT_BOW:
			return WeaponData.WeaponType.BOW
		CAT_KATANA:
			return WeaponData.WeaponType.KATANA
		_:
			return WeaponData.WeaponType.MACE

func _config_path(cat: int) -> String:
	match cat:
		CAT_GS:
			return PlayerWeaponVisuals.GS_GRIP_CONFIG_PATH
		CAT_DAGGER:
			return PlayerWeaponVisuals.DAGGER_GRIP_CONFIG_PATH
		CAT_SWORD:
			return PlayerWeaponVisuals.SWORD_GRIP_CONFIG_PATH
		CAT_BOW:
			return PlayerWeaponVisuals.BOW_GRIP_CONFIG_PATH
		CAT_KATANA:
			return PlayerWeaponVisuals.KATANA_GRIP_CONFIG_PATH
		_:
			return PlayerWeaponVisuals.MACE_GRIP_CONFIG_PATH

func _default_offset(cat: int) -> Vector3:
	if cat == CAT_SWORD:
		return PlayerWeaponVisuals.SWORD_GRIP_OFFSET
	if cat == CAT_BOW:
		return PlayerWeaponVisuals.BOW_GRIP_OFFSET
	if cat == CAT_KATANA:
		return PlayerWeaponVisuals.KATANA_GRIP_OFFSET
	return PlayerWeaponVisuals.GS_GRIP_OFFSET if cat == CAT_GS else PlayerWeaponVisuals.MELEE_GRIP_OFFSET

func _active_holder() -> Node3D:
	if _vis == null:
		return null
	match _cat:
		CAT_GS:
			return _vis.greatsword_holder()
		CAT_DAGGER:
			return _vis.dagger_holder(_hand)
		CAT_SWORD:
			return _vis.sword_holder()
		CAT_BOW:
			return _vis.bow_holder()
		CAT_KATANA:
			return _vis.katana_holder()
		_:
			return _vis.mace_holder()

func _load_values(cat: int = -1) -> void:
	if cat < 0:
		for c in CAT_COUNT:
			_load_values(c)
		return
	_values[cat] = {}
	match cat:
		CAT_GS:
			for i in GreatswordModels.count():
				_values[cat][i] = PlayerWeaponVisuals.gs_grip_values(i)
		CAT_DAGGER:
			for i in DaggerModels.count():
				_values[cat][i] = {
					"right": PlayerWeaponVisuals.dagger_grip_values(i, "right"),
					"left": PlayerWeaponVisuals.dagger_grip_values(i, "left"),
				}
		CAT_MACE:
			for i in MaceModels.count():
				_values[cat][i] = PlayerWeaponVisuals.mace_grip_values(i)
		CAT_SWORD:
			for i in SwordModels.count():
				_values[cat][i] = PlayerWeaponVisuals.sword_grip_values(i)
		CAT_BOW:
			for i in BowModels.count():
				_values[cat][i] = PlayerWeaponVisuals.bow_grip_values(i)
		CAT_KATANA:
			for i in KatanaModels.count():
				_values[cat][i] = PlayerWeaponVisuals.katana_grip_values(i)

func _current_values() -> Dictionary:
	return {
		"pos": Vector3(_pos_spins[0].value, _pos_spins[1].value, _pos_spins[2].value),
		"rot": Vector3(_rot_spins[0].value, _rot_spins[1].value, _rot_spins[2].value),
		"scale": Vector3(_scl_spins[0].value, _scl_spins[1].value, _scl_spins[2].value),
	}

func _current_entry() -> Dictionary:
	if _cat == CAT_DAGGER:
		return _values[CAT_DAGGER][_skin][_hand]
	return _values[_cat][_skin]

func _show_values(value: Dictionary) -> void:
	_syncing = true
	var pos: Vector3 = value["pos"]
	var rot: Vector3 = value["rot"]
	var scl: Vector3 = value.get("scale", Vector3.ONE)
	for i in 3:
		_pos_spins[i].value = pos[i]
		_rot_spins[i].value = rot[i]
		_scl_spins[i].value = scl[i]
	_syncing = false

func _store_current() -> void:
	if _cat == CAT_DAGGER:
		_values[CAT_DAGGER][_skin][_hand] = _current_values()
	else:
		_values[_cat][_skin] = _current_values()

func _apply_entry() -> void:
	if _vis == null:
		return
	var value := _current_entry()
	match _cat:
		CAT_GS:
			_vis.set_greatsword_grip(value["pos"], value["rot"], value.get("scale", Vector3.ONE))
		CAT_DAGGER:
			_vis.set_dagger_grip(_hand, value["pos"], value["rot"], value.get("scale", Vector3.ONE))
		CAT_SWORD:
			_vis.set_sword_grip(value["pos"], value["rot"], value.get("scale", Vector3.ONE))
		CAT_BOW:
			_vis.set_bow_grip(value["pos"], value["rot"], value.get("scale", Vector3.ONE))
		CAT_KATANA:
			_vis.set_katana_grip(value["pos"], value["rot"], value.get("scale", Vector3.ONE))
		_:
			_vis.set_mace_grip(value["pos"], value["rot"], value.get("scale", Vector3.ONE))

func _apply_dagger_hand(hand: String) -> void:
	var value: Dictionary = _values[CAT_DAGGER][_skin][hand]
	_vis.set_dagger_grip(hand, value["pos"], value["rot"], value.get("scale", Vector3.ONE))

func _refresh_skin_select() -> void:
	_skin_select.clear()
	for i in _model_count(_cat):
		_skin_select.add_item(_model_name(_cat, i), i)
	_skin_select.select(_skin)

func _ensure_weapon_selected() -> void:
	var w := _cat_weapon(_cat)
	var slots: Array = _player.weapon_slots
	if not slots.has(w):
		if not _player.add_weapon(w):
			if _player.weapon_inventory:
				_player.weapon_inventory.weapon_slots[0] = w
	slots = _player.weapon_slots
	var idx := slots.find(w)
	if idx >= 0:
		_player.select_slot(idx)

func _apply_skin() -> void:
	if _vis == null:
		return
	match _cat:
		CAT_GS:
			GameData.greatsword_skin = _skin
			_vis.set_greatsword_skin(_skin)
		CAT_DAGGER:
			GameData.dagger_skin = _skin
			_vis.set_dagger_skin(_skin)
		CAT_MACE:
			GameData.mace_skin = _skin
			_vis.set_mace_skin(_skin)
		CAT_SWORD:
			GameData.sword_skin = _skin
			_vis.set_sword_skin(_skin)
		CAT_BOW:
			GameData.bow_skin = _skin
			_vis.set_bow_skin(_skin)
		CAT_KATANA:
			_vis.set_katana_skin(_skin)
	_show_values(_current_entry())
	if _cat == CAT_DAGGER:
		_apply_dagger_hand("right")
		_apply_dagger_hand("left")
	else:
		_apply_entry()

# ══════════════════════════════════════════════════════════════════════════════
# Ventanas de daño y vista previa del ataque
# ══════════════════════════════════════════════════════════════════════════════

func _anim_player() -> AnimationPlayer:
	var ac = _player.animation_controller if is_instance_valid(_player) else null
	return ac.anim_player if ac and is_instance_valid(ac.anim_player) else null

func _clip(anim_name: String) -> Animation:
	var ap := _anim_player()
	if ap == null or not ap.has_animation(anim_name):
		return null
	return ap.get_animation(anim_name)

func _clip_length(anim_name: String) -> float:
	var a := _clip(anim_name)
	return a.length if a else 1.0

func _combo_speed(anim_name: String) -> float:
	var cfg: Dictionary = PlayerAnimationController.COMBOS.get(_cat_weapon(_cat), {})
	var speeds: Dictionary = cfg.get("speeds", {})
	return float(speeds.get(anim_name, cfg.get("speed", 1.0)))

func _windows_for(anim_name: String) -> Array:
	if not _win_edit.has(anim_name):
		_win_edit[anim_name] = PlayerAnimationController.attack_windows(anim_name)
	return _win_edit[anim_name]

func _table_windows(anim_name: String) -> Array:
	return PlayerAnimationController.normalize_windows(PlayerAnimationController.ATTACK_WINDOWS.get(anim_name, []))

func _windows_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if absf(float(a[i][0]) - float(b[i][0])) > 0.0005 or absf(float(a[i][1]) - float(b[i][1])) > 0.0005:
			return false
	return true

func _refresh_anim_list() -> void:
	var prefix: String = CAT_ANIM_PREFIX[_cat]
	_anim_names.clear()
	for anim_name in PlayerAnimationController.MELEE_ACTIONS + PlayerAnimationController.BOW_ACTIONS:
		if String(anim_name).begins_with(prefix) and _clip(anim_name) != null:
			_anim_names.append(anim_name)
	_anim_list.clear()
	for anim_name in _anim_names:
		_anim_list.add_item(_anim_item_text(anim_name))
	var keep := _anim_names.find(_anim_name)
	if _anim_names.is_empty():
		_anim_name = ""
		_win_info.text = "Este arma no tiene ataques cargados todavía"
		return
	_select_anim(keep if keep >= 0 else 0, keep < 0)

func _anim_item_text(anim_name: String) -> String:
	var n := _windows_for(anim_name).size()
	var edited := not _windows_equal(_windows_for(anim_name), PlayerAnimationController.attack_windows(anim_name))
	return "%s%s  %df · %d✕" % ["• " if edited else "", anim_name,
		int(ceil(_clip_length(anim_name) * FPS - 0.001)), n]

func _update_anim_items() -> void:
	for i in _anim_names.size():
		_anim_list.set_item_text(i, _anim_item_text(_anim_names[i]))

func _select_anim(index: int, reset_time: bool) -> void:
	_anim_list.select(index)
	_anim_name = _anim_names[index]
	var link: Array = PlayerAnimationController.LINK_WINDOWS.get(_anim_name, [])
	_timeline.set_clip(_clip_length(_anim_name), _windows_for(_anim_name), _table_windows(_anim_name), link)
	if reset_time:
		var w := _windows_for(_anim_name)
		_preview_t = float(w[0][0]) if not w.is_empty() else 0.0
	_preview_t = clampf(_preview_t, 0.0, _clip_length(_anim_name))
	_timeline.set_time_external(_preview_t)
	_sync_window_fields()
	if _preview:
		_pose_at(_preview_t)
	_update_frame_label()

func _enter_preview() -> void:
	if _anim_name == "":
		return
	if not _frozen:
		_freeze_pose(true)
	if not _preview:
		var ap := _anim_player()
		if ap:
			_saved_anim = ap.assigned_animation
			_saved_pos = ap.current_animation_position if _saved_anim != "" else 0.0
		_preview = true

func _exit_preview(settle: bool) -> void:
	if not _preview:
		return
	_preview = false
	_set_playing(false)
	var ap := _anim_player()
	if ap and _saved_anim != "" and ap.has_animation(_saved_anim):
		ap.play(_saved_anim)
		ap.seek(_saved_pos, true)
		ap.pause()
	if settle:
		_settle_pose_then_freeze()
	_update_frame_label()

func _pose_at(t: float) -> void:
	var ap := _anim_player()
	if ap == null or _anim_name == "":
		return
	ap.active = true
	if ap.assigned_animation != _anim_name:
		ap.play(_anim_name)
	ap.seek(t, true)
	ap.pause()

func _seek_preview(t: float) -> void:
	if _anim_name == "":
		return
	_enter_preview()
	_preview_t = clampf(t, 0.0, _clip_length(_anim_name))
	_pose_at(_preview_t)
	_timeline.set_time_external(_preview_t)
	_update_frame_label()

func _step_frames(n: int) -> void:
	if _anim_name == "":
		return
	_set_playing(false)
	_seek_preview((round(_preview_t * FPS) + n) / FPS)

func _set_playing(on: bool) -> void:
	_playing = on
	if _play_btn:
		_play_btn.text = "⏸  Pausa" if on else "▶  Reproducir"

func _update_frame_label() -> void:
	if _frame_label == null:
		return
	if _anim_name == "":
		_frame_label.text = "—"
		_hit_chip.visible = false
		return
	var length := _clip_length(_anim_name)
	var frames := int(ceil(length * FPS - 0.001))
	var f := _preview_t * FPS
	_frame_label.text = "F %s / %d  ·  %.2f s  (%.2f s en juego)" % [
		("%d" % int(round(f))) if is_equal_approx(f, round(f)) else ("%.1f" % f), frames, _preview_t,
		_preview_t / _combo_speed(_anim_name)]
	_frame_label.add_theme_color_override("font_color", Color.WHITE if _preview else C_TEXT_DIM)
	var active: bool = _timeline.is_time_active(_preview_t)
	_hit_chip.visible = true
	_hit_chip.add_theme_stylebox_override("panel",
		_box(Color(C_HIT, 0.9) if active else Color(1, 1, 1, 0.08), 10, Color(0, 0, 0, 0), 10.0))
	_hit_chip_label.text = "● HACE DAÑO" if active else "○ sin daño"
	_hit_chip_label.add_theme_color_override("font_color", Color.WHITE if active else C_TEXT_DIM)

func _sync_window_fields() -> void:
	if _win_start == null:
		return
	var sel: int = _timeline.selected
	var w := _windows_for(_anim_name) if _anim_name != "" else []
	var has := sel >= 0 and sel < w.size()
	_syncing = true
	_win_start.editable = has
	_win_end.editable = has
	var max_f := _clip_length(_anim_name) * FPS if _anim_name != "" else 999.0
	_win_start.max_value = max_f
	_win_end.max_value = max_f
	if has:
		_win_start.value = float(w[sel][0]) * FPS
		_win_end.value = float(w[sel][1]) * FPS
	_syncing = false
	if _anim_name != "":
		var link: Array = PlayerAnimationController.LINK_WINDOWS.get(_anim_name, [])
		_win_info.text = "Combo a %.2f×%s" % [_combo_speed(_anim_name),
			(" · enlace %d–%d f" % [int(round(float(link[0]) * FPS)), int(round(float(link[1]) * FPS))]) if link.size() >= 2 else ""]

func _seek_end() -> void:
	if _anim_name != "":
		_seek_preview(_clip_length(_anim_name))

func _add_window() -> void:
	if _anim_name != "":
		_timeline.add_window_at_head()

func _remove_window() -> void:
	if _anim_name != "":
		_timeline.remove_window(_timeline.selected)

func _on_window_field(edge: int, frames: float) -> void:
	if _syncing or _anim_name == "":
		return
	_timeline.set_selected_edge(edge, frames / FPS)

func _set_edge_at_head(edge: int) -> void:
	if _anim_name == "":
		return
	if _timeline.selected < 0:
		_timeline.add_window_at_head()
		return
	_timeline.set_selected_edge(edge, round(_preview_t * FPS) / FPS)

func _on_timeline_scrubbed(t: float) -> void:
	_set_playing(false)
	_seek_preview(t)

func _on_windows_edited() -> void:
	_win_dirty = true
	_sync_window_fields()
	_update_anim_items()
	_update_frame_label()
	_mark_dirty()

func _on_windows_reset() -> void:
	if _anim_name == "":
		return
	var w := _windows_for(_anim_name)
	w.clear()
	for x in _table_windows(_anim_name):
		w.append(x)
	_timeline.selected = 0 if not w.is_empty() else -1
	_timeline.queue_redraw()
	_on_windows_edited()

func _on_anim_selected(index: int) -> void:
	_set_playing(false)
	_select_anim(index, true)
	_seek_preview(_preview_t)

func _on_play_pressed() -> void:
	if _anim_name == "":
		return
	_enter_preview()
	if not _playing and _preview_t >= _clip_length(_anim_name) - 0.001:
		_preview_t = 0.0
	_set_playing(not _playing)

func _on_collapse() -> void:
	_bottom_body.visible = not _bottom_body.visible
	_collapse_btn.text = ("▾" if _bottom_body.visible else "▸") + "  VENTANAS DE DAÑO"
	_bottom.reset_size.call_deferred()
	_layout.call_deferred()

# ══════════════════════════════════════════════════════════════════════════════
# Callbacks de la UI (agarre)
# ══════════════════════════════════════════════════════════════════════════════

func _on_freeze_toggled(pressed: bool) -> void:
	_freeze_pose(pressed)

func _on_fine_toggled(fine: bool) -> void:
	for i in 3:
		_scl_spins[i].step = 0.001 if fine else 0.01
		_scl_sliders[i].step = _scl_spins[i].step
		_pos_spins[i].step = 0.001 if fine else 0.005
		_pos_sliders[i].step = _pos_spins[i].step
		_rot_spins[i].step = 0.1 if fine else 1.0
		_rot_sliders[i].step = _rot_spins[i].step

func _on_values_changed(_value: float) -> void:
	if _syncing:
		return
	_store_current()
	_apply_entry()
	_grip_dirty = true
	_mark_dirty()

func _on_category_selected(index: int) -> void:
	_store_current()
	_exit_preview(false)
	_cat = _cat_select.get_item_id(index)
	if _cat == CAT_GS:
		_skin = _player.greatsword_skin()
	elif _cat == CAT_DAGGER:
		_skin = _player.dagger_skin()
	elif _cat == CAT_SWORD:
		_skin = _player.sword_skin()
	elif _cat == CAT_BOW:
		_skin = _player.bow_skin()
	elif _cat == CAT_KATANA:
		_skin = 0
	else:
		_skin = _player.mace_skin()
	_hand = "right"
	_hand_select.select(0)
	_hand_row.visible = _cat == CAT_DAGGER
	_copy_hand_btn.text = "Copiar → izq."
	_refresh_skin_select()
	_ensure_weapon_selected()
	_apply_skin()
	await _settle_pose_then_freeze()
	_anim_name = ""
	_refresh_anim_list()
	_set_status("Editando %s" % _model_name(_cat, _skin), C_OK if not (_grip_dirty or _win_dirty) else C_WARN)

func _on_hand_selected(index: int) -> void:
	_store_current()
	_hand = "left" if _hand_select.get_item_id(index) == 1 else "right"
	_show_values(_current_entry())
	_apply_entry()
	_copy_hand_btn.text = "Copiar → %s" % ("izq." if _hand == "right" else "der.")
	_set_status("Editando %s · mano %s" % [_model_name(_cat, _skin),
			"izquierda" if _hand == "left" else "derecha"], C_WARN if _grip_dirty else C_OK)

func _on_copy_to_other_hand() -> void:
	if _cat != CAT_DAGGER:
		return
	_store_current()
	var other := "left" if _hand == "right" else "right"
	_values[CAT_DAGGER][_skin][other] = _current_values().duplicate()
	_apply_dagger_hand(other)
	_grip_dirty = true
	_set_status("Copiado a mano %s · sin guardar" % ("izquierda" if other == "left" else "derecha"), C_WARN)

func _on_skin_selected(index: int) -> void:
	_store_current()
	_skin = _skin_select.get_item_id(index)
	_apply_skin()
	_set_status("Editando %s" % _model_name(_cat, _skin), C_WARN if _grip_dirty else C_OK)

func _on_reset() -> void:
	var entry := _current_entry()
	entry["pos"] = _default_offset(_cat)
	entry["rot"] = Vector3.ZERO
	entry["scale"] = Vector3.ONE
	_show_values(entry)
	_apply_entry()
	_grip_dirty = true
	_set_status("Agarre restablecido · %s (sin guardar)" % _model_name(_cat, _skin), C_WARN)

func _on_reload() -> void:
	match _cat:
		CAT_GS:
			PlayerWeaponVisuals.reload_gs_grip_config()
		CAT_DAGGER:
			PlayerWeaponVisuals.reload_dagger_grip_config()
		CAT_MACE:
			PlayerWeaponVisuals.reload_mace_grip_config()
		CAT_SWORD:
			PlayerWeaponVisuals.reload_sword_grip_config()
		CAT_BOW:
			PlayerWeaponVisuals.reload_bow_grip_config()
		CAT_KATANA:
			PlayerWeaponVisuals.reload_katana_grip_config()
	_load_values(_cat)
	_apply_skin()
	PlayerAnimationController.reload_attack_windows_config()
	_win_edit.clear()
	_grip_dirty = false
	_win_dirty = false
	if not _anim_names.is_empty():
		_refresh_anim_list()
	_set_status("Recargado desde los JSON", C_OK)

func _on_save() -> void:
	_store_current()
	for cat in CAT_COUNT:
		if not _save_category(cat):
			return
	if not _save_windows():
		return
	PlayerWeaponVisuals.reload_gs_grip_config()
	PlayerWeaponVisuals.reload_dagger_grip_config()
	PlayerWeaponVisuals.reload_mace_grip_config()
	PlayerWeaponVisuals.reload_sword_grip_config()
	PlayerWeaponVisuals.reload_bow_grip_config()
	PlayerAnimationController.reload_attack_windows_config()
	var ac = _player.animation_controller
	if ac and ac.has_method("refresh_hit_windows"):
		for anim_name in _win_edit:
			ac.refresh_hit_windows(anim_name)
	_grip_dirty = false
	_win_dirty = false
	_update_anim_items()
	_set_status("Guardado · *_grip.json y attack_windows.json", C_OK)

func _save_windows() -> bool:
	var path := PlayerAnimationController.ATTACK_WINDOWS_CONFIG_PATH
	var config: Dictionary = PlayerAnimationController.attack_windows_config().duplicate(true)
	var changed := false
	for anim_name in _win_edit:
		var w: Array = _win_edit[anim_name]
		var before: Variant = config.get(anim_name)
		if _windows_equal(w, _table_windows(anim_name)):
			config.erase(anim_name)
		else:
			var rounded: Array = []
			for x in w:
				rounded.append([snappedf(float(x[0]), 0.001), snappedf(float(x[1]), 0.001)])
			config[anim_name] = rounded
		changed = changed or str(config.get(anim_name)) != str(before)
	if not changed:
		return true
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_set_status("ERROR al escribir %s: %s" % [path, error_string(FileAccess.get_open_error())], C_ERR)
		push_error(_status.text)
		return false
	var keys := config.keys()
	keys.sort()
	var ordered := {}
	for k in keys:
		ordered[k] = config[k]
	file.store_string(JSON.stringify(ordered, "\t") + "\n")
	file.close()
	return true

func _save_category(cat: int) -> bool:
	var path := _config_path(cat)
	var config: Dictionary = {}
	var existing := FileAccess.get_file_as_string(path)
	if existing != "":
		var parsed: Variant = JSON.parse_string(existing)
		if parsed is Dictionary:
			config = parsed
	match cat:
		CAT_GS:
			for i in GreatswordModels.count():
				var id := String(GreatswordModels.skin(i)["id"])
				config[id] = _to_json_values(_values[cat][i])
		CAT_DAGGER:
			for i in DaggerModels.count():
				var id := String(DaggerModels.skin(i)["id"])
				for hand in ["right", "left"]:
					config[id + "_" + hand] = _to_json_values(_values[cat][i][hand])
		CAT_MACE:
			for i in MaceModels.count():
				var id := String(MaceModels.skin(i)["id"])
				config[id] = _to_json_values(_values[cat][i])
		CAT_SWORD:
			for i in SwordModels.count():
				var id := String(SwordModels.skin(i)["id"])
				config[id] = _to_json_values(_values[cat][i])
		CAT_BOW:
			for i in BowModels.count():
				var id := String(BowModels.skin(i)["id"])
				config[id] = _to_json_values(_values[cat][i])
		CAT_KATANA:
			for i in KatanaModels.count():
				var id := String(KatanaModels.skin(i)["id"])
				config[id] = _to_json_values(_values[cat][i])
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_set_status("ERROR al escribir %s: %s" % [path, error_string(FileAccess.get_open_error())], C_ERR)
		push_error(_status.text)
		return false
	file.store_string(JSON.stringify(config, "\t") + "\n")
	file.close()
	return true

func _to_json_values(value: Dictionary) -> Dictionary:
	var pos: Vector3 = value["pos"]
	var rot: Vector3 = value["rot"]
	var scl: Vector3 = value.get("scale", Vector3.ONE)
	var out := {
		"pos": [pos.x, pos.y, pos.z],
		"rot": [rot.x, rot.y, rot.z],
	}
	if not scl.is_equal_approx(Vector3.ONE):
		out["scale"] = [scl.x, scl.y, scl.z]
	return out

# ══════════════════════════════════════════════════════════════════════════════
# Gizmo (como el editor de ropa): W = mover, E = rotar, R = escalar sobre el arma
# ══════════════════════════════════════════════════════════════════════════════
## Mover y rotar trabajan en el mundo y se traducen a pos/rot del agarre; escalar, en los ejes del arma (la escala
## va en el modelo, antes de la rotación del agarre). X = ejes del arma / del mundo (escalar siempre en los del arma).

const GIZMO_MOVE := 0
const GIZMO_ROTATE := 1
const GIZMO_SCALE := 2
const GIZMO_MODE_NAMES := ["Mover (W)", "Rotar (E)", "Escalar (R)"]
const GIZMO_K := 0.11
const GIZMO_PICK_PX := 12.0
const GIZMO_SNAP_MOVE := 0.005
const GIZMO_SNAP_ROT := 5.0
const GIZMO_SNAP_SCALE := 0.05
const C_CENTER := Color(0.95, 0.95, 0.95)

var _gizmo: Node3D
var _gz: Array[Node3D] = []
var _gz_mats: Array = []
var _gz_buttons: Array[Button] = []
var _local_check: CheckButton
var _snap_check: CheckButton
var _gz_mode := GIZMO_MOVE
var _gz_hover := -1
var _gz_drag := -1
var _gz_undo: Array = []
# Estado al empezar a arrastrar
var _d_axes: Array[Vector3] = []
var _d_origin := Vector3.ZERO
var _d_gs := 1.0
var _d_entry: Dictionary = {}
var _d_global := Transform3D.IDENTITY
var _d_t0 := 0.0
var _d_hit0 := Vector3.ZERO
var _d_u := Vector3.ZERO
var _d_v := Vector3.ZERO
var _d_prev := 0.0
var _d_total := 0.0
var _d_dist0 := 1.0

func _toggle_ui() -> void:
	if _ui_layer == null:
		return
	_ui_layer.visible = not _ui_layer.visible
	_hide_hint.visible = not _ui_layer.visible

func _gz_mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.no_depth_test = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	m.render_priority = 100
	return m

func _gz_add(parent: Node3D, mesh: Mesh, mat: Material, xf: Transform3D) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = xf
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)

func _build_gizmo() -> void:
	_gizmo = Node3D.new()
	_gizmo.name = "GripGizmo"
	_main.add_child(_gizmo)
	for m in 3:
		var holder := Node3D.new()
		_gizmo.add_child(holder)
		_gz.append(holder)
		_gz_mats.append([])
	var axes := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	for i in 3:
		var a: Vector3 = axes[i]
		var to_axis := Basis(Quaternion(Vector3.UP, a))
		var mv := _gz_mat(AXIS_COLORS[i])
		(_gz_mats[GIZMO_MOVE] as Array).append(mv)
		var shaft := CylinderMesh.new()
		shaft.top_radius = 0.022
		shaft.bottom_radius = 0.022
		shaft.height = 0.78
		shaft.radial_segments = 8
		_gz_add(_gz[GIZMO_MOVE], shaft, mv, Transform3D(to_axis, a * 0.39))
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.075
		cone.height = 0.22
		cone.radial_segments = 12
		_gz_add(_gz[GIZMO_MOVE], cone, mv, Transform3D(to_axis, a * 0.89))
		var rt := _gz_mat(AXIS_COLORS[i])
		(_gz_mats[GIZMO_ROTATE] as Array).append(rt)
		var ring := TorusMesh.new()
		ring.inner_radius = 0.965
		ring.outer_radius = 1.0
		ring.rings = 64
		ring.ring_segments = 8
		_gz_add(_gz[GIZMO_ROTATE], ring, rt, Transform3D(to_axis, Vector3.ZERO))
		var sc := _gz_mat(AXIS_COLORS[i])
		(_gz_mats[GIZMO_SCALE] as Array).append(sc)
		var sshaft := CylinderMesh.new()
		sshaft.top_radius = 0.022
		sshaft.bottom_radius = 0.022
		sshaft.height = 0.85
		sshaft.radial_segments = 8
		_gz_add(_gz[GIZMO_SCALE], sshaft, sc, Transform3D(to_axis, a * 0.425))
		var cube := BoxMesh.new()
		cube.size = Vector3.ONE * 0.13
		_gz_add(_gz[GIZMO_SCALE], cube, sc, Transform3D(Basis.IDENTITY, a * 0.92))
	var c_move := _gz_mat(Color(C_CENTER, 0.9))
	(_gz_mats[GIZMO_MOVE] as Array).append(c_move)
	var ball := SphereMesh.new()
	ball.radius = 0.075
	ball.height = 0.15
	_gz_add(_gz[GIZMO_MOVE], ball, c_move, Transform3D.IDENTITY)
	var c_scale := _gz_mat(Color(C_CENTER, 0.9))
	(_gz_mats[GIZMO_SCALE] as Array).append(c_scale)
	var cbox := BoxMesh.new()
	cbox.size = Vector3.ONE * 0.16
	_gz_add(_gz[GIZMO_SCALE], cbox, c_scale, Transform3D.IDENTITY)

func _set_gizmo_mode(m: int) -> void:
	_gz_mode = m
	for i in 3:
		_gz[i].visible = i == m
	for i in _gz_buttons.size():
		_gz_buttons[i].set_pressed_no_signal(i == m)
	_refresh_gizmo_colors()

func _refresh_gizmo_colors() -> void:
	for m in 3:
		var mats: Array = _gz_mats[m]
		for i in mats.size():
			var base: Color = AXIS_COLORS[i] if i < 3 else C_CENTER
			var hot := (i == _gz_hover and _gz_drag < 0) or (i == _gz_drag and m == _gz_mode)
			(mats[i] as StandardMaterial3D).albedo_color = Color(base.lightened(0.55), 1.0) if hot else Color(base, 0.9)

func _gizmo_size() -> float:
	var h := _active_holder()
	if h == null or _cam == null:
		return 0.1
	return _cam.global_position.distance_to(h.global_position) * GIZMO_K

func _gizmo_basis(h: Node3D) -> Basis:
	if _local_check.button_pressed or _gz_mode == GIZMO_SCALE:
		return h.global_transform.basis.orthonormalized()
	return Basis.IDENTITY

func _update_gizmo() -> void:
	if _gizmo == null:
		return
	var h := _active_holder()
	if h == null or not h.is_visible_in_tree():
		_gizmo.visible = false
		return
	_gizmo.visible = true
	var gs := _d_gs if _gz_drag >= 0 else _gizmo_size()
	var b := _gizmo_basis(h) if _gz_drag < 0 else Basis(_d_axes[0], _d_axes[1], _d_axes[2])
	_gizmo.global_transform = Transform3D(b * Basis.from_scale(Vector3.ONE * gs), h.global_position)

func _gz_axes() -> Array[Vector3]:
	var b := _gizmo.global_transform.basis
	return [b.x.normalized(), b.y.normalized(), b.z.normalized()]

func _gz_screen(p: Vector3) -> Variant:
	if _cam.is_position_behind(p):
		return null
	return _cam.unproject_position(p)

func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)

## Asa bajo el ratón: 0-2 = eje X/Y/Z, 3 = centro, -1 = ninguna.
func _pick_handle(mp: Vector2) -> int:
	if _gizmo == null or not _gizmo.visible:
		return -1
	var o := _gizmo.global_position
	var gs := _gizmo_size()
	var axes := _gz_axes()
	var best := -1
	var best_d := GIZMO_PICK_PX
	if _gz_mode != GIZMO_ROTATE:
		var so: Variant = _gz_screen(o)
		if so != null and mp.distance_to(so) < GIZMO_PICK_PX:
			return 3
		for i in 3:
			var se: Variant = _gz_screen(o + axes[i] * gs)
			if so == null or se == null:
				continue
			var d := _seg_dist(mp, so, se)
			if d < best_d:
				best_d = d
				best = i
	else:
		var to_cam := (_cam.global_position - o).normalized()
		for i in 3:
			var u := axes[(i + 1) % 3]
			var v := axes[(i + 2) % 3]
			var prev: Variant = null
			for k in 49:
				var t := TAU * float(k) / 48.0
				var dir := u * cos(t) + v * sin(t)
				var sp: Variant = _gz_screen(o + dir * gs) if dir.dot(to_cam) > -0.12 else null
				if sp != null and prev != null:
					var d := _seg_dist(mp, prev, sp)
					if d < best_d:
						best_d = d
						best = i
				prev = sp
	return best

func _ray(mp: Vector2) -> Array:
	return [_cam.project_ray_origin(mp), _cam.project_ray_normal(mp)]

func _axis_t(o: Vector3, a: Vector3, mp: Vector2) -> float:
	var r := _ray(mp)
	var ro: Vector3 = r[0]
	var rd: Vector3 = r[1]
	var w0 := o - ro
	var b := a.dot(rd)
	var c := a.dot(w0)
	var e := rd.dot(w0)
	var den := 1.0 - b * b
	if absf(den) < 0.0001:
		return NAN
	return (b * e - c) / den

func _ray_plane(o: Vector3, n: Vector3, mp: Vector2) -> Variant:
	var r := _ray(mp)
	var ro: Vector3 = r[0]
	var rd: Vector3 = r[1]
	var den := n.dot(rd)
	if absf(den) < 0.0001:
		return null
	return ro + rd * (n.dot(o - ro) / den)

func _ring_angle(o: Vector3, mp: Vector2) -> float:
	var hit: Variant = _ray_plane(o, _d_axes[_gz_drag], mp)
	if hit == null:
		return NAN
	var vec: Vector3 = (hit as Vector3) - o
	return atan2(vec.dot(_d_v), vec.dot(_d_u))

func _gz_snap() -> bool:
	return _snap_check.button_pressed != Input.is_key_pressed(KEY_CTRL)

## Ratón sobre el gizmo: resaltar, empezar/seguir/acabar el arrastre. true = evento consumido.
func _gizmo_input(event: InputEvent) -> bool:
	if _gizmo == null:
		return false
	if event is InputEventMouseMotion:
		var mp := (event as InputEventMouseMotion).position
		if _gz_drag >= 0:
			_update_gizmo_drag(mp)
			return true
		if not _dragging:
			var h := _pick_handle(mp)
			if h != _gz_hover:
				_gz_hover = h
				_refresh_gizmo_colors()
		return false
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			var h := _pick_handle(mb.position)
			if h < 0:
				return false
			_begin_gizmo_drag(h, mb.position)
			return true
		if _gz_drag >= 0:
			_gz_drag = -1
			_refresh_gizmo_colors()
			return true
	return false

func _begin_gizmo_drag(h: int, mp: Vector2) -> void:
	var holder := _active_holder()
	_gz_undo.append([_cat, _skin, _hand, _current_entry().duplicate()])
	if _gz_undo.size() > 60:
		_gz_undo.pop_front()
	_gz_drag = h
	_d_axes = _gz_axes()
	_d_origin = holder.global_position
	_d_gs = _gizmo_size()
	_d_entry = _current_entry().duplicate()
	_d_global = holder.global_transform
	match _gz_mode:
		GIZMO_MOVE:
			if h < 3:
				_d_t0 = _axis_t(_d_origin, _d_axes[h], mp)
			else:
				var hit: Variant = _ray_plane(_d_origin, -_cam.global_transform.basis.z, mp)
				_d_hit0 = hit if hit != null else _d_origin
		GIZMO_ROTATE:
			var n := _d_axes[h]
			_d_u = n.cross(Vector3.UP)
			if _d_u.length() < 0.2:
				_d_u = n.cross(Vector3.RIGHT)
			_d_u = _d_u.normalized()
			_d_v = n.cross(_d_u)
			_d_prev = _ring_angle(_d_origin, mp)
			_d_total = 0.0
		GIZMO_SCALE:
			if h < 3:
				_d_t0 = _axis_t(_d_origin, _d_axes[h], mp)
			else:
				var so: Variant = _gz_screen(_d_origin)
				_d_dist0 = maxf(mp.distance_to(so) if so != null else 1.0, 24.0)
	_refresh_gizmo_colors()

func _update_gizmo_drag(mp: Vector2) -> void:
	var holder := _active_holder()
	if holder == null:
		return
	var parent_inv: Transform3D = (holder.get_parent() as Node3D).global_transform.affine_inverse()
	var entry: Dictionary = _d_entry.duplicate()
	var snap := _gz_snap()
	match _gz_mode:
		GIZMO_MOVE:
			var delta_w := Vector3.ZERO
			if _gz_drag < 3:
				var t := _axis_t(_d_origin, _d_axes[_gz_drag], mp)
				if is_nan(t) or is_nan(_d_t0):
					return
				var d := t - _d_t0
				if snap:
					d = snappedf(d, GIZMO_SNAP_MOVE)
				delta_w = _d_axes[_gz_drag] * d
			else:
				var hit: Variant = _ray_plane(_d_origin, -_cam.global_transform.basis.z, mp)
				if hit == null:
					return
				delta_w = (hit as Vector3) - _d_hit0
			var pos: Vector3 = parent_inv * (_d_origin + delta_w)
			if snap and _gz_drag == 3:
				pos = pos.snapped(Vector3.ONE * GIZMO_SNAP_MOVE)
			entry["pos"] = pos
		GIZMO_ROTATE:
			var ang := _ring_angle(_d_origin, mp)
			if is_nan(ang) or is_nan(_d_prev):
				return
			if absf(_d_axes[_gz_drag].dot(_cam.global_transform.basis.z)) < 0.12:
				return
			_d_total += wrapf(ang - _d_prev, -PI, PI)
			_d_prev = ang
			var delta := _d_total
			if snap:
				delta = snappedf(delta, deg_to_rad(GIZMO_SNAP_ROT))
			# Base fija del agarre (lo que no es rot/escala): F = B0 · (R0 · S0)⁻¹, en el espacio del padre
			var b0: Basis = (parent_inv.basis * _d_global.basis)
			var r0 := Basis.from_euler((_d_entry["rot"] as Vector3) * (PI / 180.0))
			var s0: Vector3 = _d_entry.get("scale", Vector3.ONE)
			var f := b0 * (r0 * Basis.from_scale(s0)).inverse()
			var axis_local: Vector3 = (parent_inv.basis * _d_axes[_gz_drag]).normalized()
			var b1 := Basis(axis_local, delta) * b0
			var rs := f.inverse() * b1
			var r1 := Basis(rs.x.normalized(), rs.y.normalized(), rs.z.normalized()).orthonormalized()
			entry["rot"] = r1.get_euler() * (180.0 / PI)
		GIZMO_SCALE:
			var ratio := 1.0
			if _gz_drag < 3:
				var t := _axis_t(_d_origin, _d_axes[_gz_drag], mp)
				if is_nan(t) or is_nan(_d_t0):
					return
				ratio = 1.0 + (t - _d_t0) / _d_gs
			else:
				var so: Variant = _gz_screen(_d_origin)
				if so == null:
					return
				ratio = mp.distance_to(so) / _d_dist0
			ratio = maxf(ratio, 0.02)
			var scl: Vector3 = _d_entry.get("scale", Vector3.ONE)
			if _gz_drag < 3:
				scl[_gz_drag] *= ratio
			else:
				scl *= ratio
			if snap:
				scl = Vector3(snappedf(scl.x, GIZMO_SNAP_SCALE), snappedf(scl.y, GIZMO_SNAP_SCALE), snappedf(scl.z, GIZMO_SNAP_SCALE))
			entry["scale"] = scl.clamp(Vector3.ONE * 0.05, Vector3.ONE * 4.0)
	_show_values(entry)
	_store_current()
	_apply_entry()
	_grip_dirty = true
	_mark_dirty()

func _cancel_gizmo_drag() -> void:
	_gz_drag = -1
	_undo_grip()
	_refresh_gizmo_colors()

func _undo_grip() -> void:
	if _gz_undo.is_empty():
		return
	var u: Array = _gz_undo.pop_back()
	if int(u[0]) != _cat or int(u[1]) != _skin or String(u[2]) != _hand:
		return
	_show_values(u[3])
	_store_current()
	_apply_entry()
	_grip_dirty = true
	_mark_dirty()
