extends CanvasLayer

@onready var resume_btn = $Control/VBox/ResumeBtn
@onready var menu_btn = $Control/VBox/MenuBtn
@onready var options_btn = $Control/VBox/OptionsBtn
@onready var quit_btn = $Control/VBox/QuitBtn

const Style := preload("res://scripts/ui/rumbang_style.gd")

signal restart_requested

var retry_btn: Button
var equip_btn: Button               ## pestaña EQUIPO (solo mazmorra, ver EquipmentPanel)
var _equip_panel: EquipmentPanel

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_apply_style()
	resume_btn.pressed.connect(_on_resume_pressed)
	menu_btn.pressed.connect(_on_menu_pressed)
	options_btn.pressed.connect(_on_options_pressed)
	quit_btn.pressed.connect(_on_quit_pressed)

func _input(event):
	if event.is_action_pressed("ui_cancel"):
		if is_instance_valid(_equip_panel):
			return   # el panel de equipo se cierra solo con su propio Esc
		toggle()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		# Tab = lo que llevas: abre el menú directo en EQUIPO (equipado + mochila + estadísticas) y lo cierra
		# del todo, también con el panel abierto. Sin sistema de equipo (supervivencia) abre solo la pausa.
		if visible:
			close_menu()
		else:
			open_menu()
			open_equipment()
		get_viewport().set_input_as_handled()

## En Android, el botón "atrás" pausa y reanuda en vez de cerrar el juego.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		toggle()

func toggle() -> void:
	if visible:
		close_menu()
	else:
		open_menu()

var _stats_label: Label

func _apply_style() -> void:
	$Control.theme = Style.get_theme()
	$Control/ColorRect.color = Color(0.02, 0.01, 0.05, 0.72)
	var vb: VBoxContainer = $Control/VBox
	vb.offset_left = -170.0
	vb.offset_right = 170.0
	var title: Label = vb.get_node("Label")
	Style.style_title(title, 32)
	var mobile := Quality.is_mobile()
	# Reintentar (no en red: allí no hay fin de partida ni reinicio)
	retry_btn = Button.new()
	retry_btn.text = "REINTENTAR"
	retry_btn.visible = not Net.is_online()
	retry_btn.pressed.connect(_on_retry_pressed)
	vb.add_child(retry_btn)
	vb.move_child(retry_btn, resume_btn.get_index() + 1)
	equip_btn = Button.new()
	equip_btn.name = "EquipBtn"
	equip_btn.text = "EQUIPO"
	equip_btn.pressed.connect(open_equipment)
	vb.add_child(equip_btn)
	vb.move_child(equip_btn, retry_btn.get_index() + 1)
	# En el móvil los botones son más grandes (dedos) y el panel cabe en pantallas pequeñas
	for btn in [resume_btn, retry_btn, equip_btn, menu_btn, options_btn, quit_btn]:
		btn.custom_minimum_size = Vector2(0, 68 if mobile else 48)
		if mobile:
			btn.add_theme_font_size_override("font_size", 22)
	# Panel con marco detrás de los botones
	# Fila centrada: botones a la izquierda y estadísticas a la derecha
	var row := HBoxContainer.new()
	row.name = "Row"
	row.set_anchors_preset(Control.PRESET_CENTER)
	row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	row.grow_vertical = Control.GROW_DIRECTION_BOTH
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	$Control.add_child(row)
	var panel := PanelContainer.new()
	panel.name = "ButtonsPanel"
	panel.custom_minimum_size = Vector2(minf(380.0, get_viewport().get_visible_rect().size.x - 40.0), 0)
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(panel)
	vb.get_parent().remove_child(vb)
	panel.add_child(vb)
	vb.set_anchors_preset(Control.PRESET_TOP_LEFT)
	vb.add_theme_constant_override("separation", 12)
	NeonFrame.attach(panel)

func _refresh_stats_panel() -> void:
	if _stats_label == null:
		_stats_label = Label.new()
		_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_stats_label.add_theme_font_size_override("font_size", 11)
		_stats_label.add_theme_color_override("font_color", Style.TEXT_DIM)
		var sp := PanelContainer.new()
		sp.name = "StatsPanel"
		sp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sp.add_child(_stats_label)
		$Control/Row.add_child(sp)
		NeonFrame.attach(sp, Style.NEON_MAGENTA)
	var player := get_tree().get_first_node_in_group("player")
	var sb = player.get("stat_block") if player else null
	if sb == null:
		_stats_label.text = ""
		return
	var lines: Array = ["— Estadísticas —"]
	lines.append_array(sb.describe())
	var inv = player.get("inventory")
	if inv:
		lines.append("Objetos: %d" % inv.collected_items.size())
	# Mejoras específicas por arma (p. ej. Espalanza: Hoja extra 2/7)
	var winv = player.get("weapon_inventory")
	if winv:
		for w in winv.weapon_slots:
			if not WeaponUpgrades.has_specific(w):
				continue
			var parts: Array = []
			for d in WeaponUpgrades.for_weapon(w):
				var lvl: int = winv.get_upgrade_level(w, d["id"])
				if lvl > 0:
					parts.append("%s %s" % [d["name"], WeaponUpgrades.level_label(d, lvl)])
			lines.append("%s: %s" % [WeaponSynergies.weapon_name(winv, w), ", ".join(parts) if not parts.is_empty() else "sin mejoras"])
		for syn in WeaponSynergies.active(winv.weapon_slots):
			lines.append("Sinergia " + WeaponSynergies.describe(syn))
	_stats_label.text = "
".join(lines)

## Abre la pestaña EQUIPO encima del menú de pausa.
func open_equipment() -> void:
	var player := get_tree().get_first_node_in_group("player")
	var eq = player.get("equipment") if player else null
	if eq == null or is_instance_valid(_equip_panel):
		return
	_equip_panel = EquipmentPanel.create(eq, player.get("stat_block"))
	$Control/Row.visible = false
	_equip_panel.closed.connect(func():
		$Control/Row.visible = true
		if not Quality.is_mobile():
			_refresh_stats_panel()
		equip_btn.grab_focus.call_deferred())
	$Control.add_child(_equip_panel)

func open_menu():
	var p := get_tree().get_first_node_in_group("player")
	equip_btn.visible = p != null and p.get("equipment") != null
	if not Quality.is_mobile():
		_refresh_stats_panel()
	visible = true
	# En red el mundo no se detiene (los demás siguen jugando)
	get_tree().paused = not Net.is_online()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func close_menu():
	if is_instance_valid(_equip_panel):
		_equip_panel.queue_free()
		$Control/Row.visible = true
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_resume_pressed():
	close_menu()

func _on_retry_pressed():
	visible = false
	get_tree().paused = false
	restart_requested.emit()

func _on_menu_pressed():
	get_tree().paused = false
	Net.leave()
	SceneLoader.load_scene("res://scenes/ui/dungeon_hub.tscn")

func _on_options_pressed():
	var SettingsMenu = load("res://scripts/ui/settings_menu.gd")
	var sm = SettingsMenu.new()
	add_child(sm)

func _on_quit_pressed():
	get_tree().quit()
