extends CanvasLayer

signal restart_pressed

@onready var hp_bar: ProgressBar = $Control/StatsPanel/Margin/VBox/BarsWithPortrait/DomeClipping/BarsHBox/HPBar
@onready var hp_label: Label = $Control/StatsPanel/Margin/VBox/BarsWithPortrait/LabelsHBox/HPLabel


@onready var floor_label: Label = $Control/TopRight/FloorPanel/Margin/FloorLabel
@onready var gold_label: Label = $Control/TopRight/GoldPanel/Margin/GoldLabel
@onready var time_label: Label = $Control/TimeLabel

@onready var crosshair: Control = $Control/Crosshair
@onready var game_over_screen: Control = $GameOverScreen
@onready var victory_screen: Control = $VictoryScreen

@onready var xp_bar: ProgressBar = $Control/HubImage/XPBar

var fps_label: Label

@onready var weapon_slots: Array = [
	$Control/HubImage/WeaponSlot1/Icon,
	$Control/HubImage/WeaponSlot2/Icon,
	$Control/HubImage/WeaponSlot3/Icon,
	$Control/HubImage/WeaponSlot4/Icon,
	$Control/HubImage/WeaponSlot5/Icon
]

var weapon_textures: Dictionary = {
	"Bazuca de Esporas": preload("res://assets/ui/ingame_hub/armas/bazoka_esporas.png"),
	"Escopeta Triple": preload("res://assets/ui/ingame_hub/armas/escopeta.png"),
	"Escopeta de Humo": preload("res://assets/ui/ingame_hub/armas/escopeta.png"),
	"Espalanza de Mikeura": preload("res://assets/ui/ingame_hub/armas/espalanza.png"),
	"Lanzallamas": preload("res://assets/ui/ingame_hub/armas/lanzallamas.png"),
	"Cañón Railgun": preload("res://assets/ui/ingame_hub/armas/magia-saimon.png"),
	"Rifle de Plasma": preload("res://assets/ui/ingame_hub/armas/pistola.png"),
	"Polvos Alquímicos": preload("res://assets/ui/ingame_hub/armas/polvos.png")
}
@onready var stats_panel: Control = $Control/StatsPanel
var _last_stats: Array = []
## Panel de vida (abajo a la izquierda); sustituye a las barras verticales de StatsPanel
var vitals: VitalsPanel

func _ready() -> void:
	# Ya no hay pisos: se oculta el panel de nivel (el cronómetro es la referencia)
	if floor_label:
		floor_label.get_parent().get_parent().visible = false
	_create_fps_label()
	vitals = VitalsPanel.new()
	vitals.name = "VitalsPanel"
	$Control.add_child(vitals)
	var bars := ResourceBars.new()
	bars.name = "ResourceBars"
	$Control.add_child(bars)
	if Quality.is_mobile():
		_create_pause_button()
	var minimap := Minimap.new()
	minimap.name = "Minimap"
	$Control.add_child(minimap)
	if Net.is_online():
		var team := TeamPanel.new()
		team.name = "TeamPanel"
		$Control.add_child(team)
	if stats_panel:
		stats_panel.visible = false
	if GameData.game_mode == "dungeon":
		_drop_weapon_bar_over_xp()
	call_deferred("_connect_to_player")
	_style_end_screens()
	if time_label:
		RumbangStyle.style_title(time_label, 20)

func _process(delta: float) -> void:
	if is_instance_valid(fps_label):
		fps_label.text = "FPS: %d" % Engine.get_frames_per_second()
	if GameData.game_mode == "dungeon" and stats_panel and stats_panel.visible:
		_follow_player_with_stats(delta)

## Mazmorra: no hay experiencia, así que se oculta su barra y la barra de armas baja hasta tapar ese hueco
## (la franja de la XP queda fuera de pantalla). HubImage está anclado abajo al centro, así que basta moverlo.
const DUNGEON_HUB_DROP := 46.0
func _drop_weapon_bar_over_xp() -> void:
	if xp_bar:
		xp_bar.visible = false
	var hub := $Control/HubImage as Control
	hub.offset_top += DUNGEON_HUB_DROP
	hub.offset_bottom += DUNGEON_HUB_DROP

## Mazmorra (cámara al hombro): el panel de vida sigue al personaje en horizontal,
## manteniendo la misma separación que tenía con el personaje centrado.
var _stats_base_x := NAN
func _follow_player_with_stats(delta: float) -> void:
	if not is_instance_valid(stats_panel):
		return
	if is_nan(_stats_base_x):
		_stats_base_x = stats_panel.position.x
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var cam := get_viewport().get_camera_3d()
	if player == null or cam == null:
		return
	var head := player.global_position + Vector3(0.0, 1.0, 0.0)
	if cam.is_position_behind(head):
		return
	var dx := cam.unproject_position(head).x - get_viewport().get_visible_rect().size.x * 0.5
	var want := _stats_base_x + dx
	stats_panel.position.x = lerpf(stats_panel.position.x, want, 1.0 - exp(-18.0 * delta))

## Botón de pausa táctil (arriba a la derecha): abre el menú de pausa, que en el móvil no tiene tecla Esc.
func _create_pause_button() -> void:
	var b := Button.new()
	b.name = "PauseButton"
	b.text = "II"
	b.focus_mode = Control.FOCUS_NONE
	b.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	b.offset_left = -92.0
	b.offset_right = -20.0
	b.offset_top = 58.0
	b.offset_bottom = 130.0
	b.add_theme_font_size_override("font_size", 28)
	b.theme = RumbangStyle.get_theme()
	b.modulate.a = 0.85
	b.pressed.connect(func():
		var pm := get_tree().root.find_child("PauseMenu", true, false)
		if pm and pm.has_method("open_menu") and not pm.visible:
			pm.open_menu())
	$Control.add_child(b)

func _create_fps_label() -> void:
	fps_label = Label.new()
	fps_label.text = "FPS: 0"
	fps_label.add_theme_font_size_override("font_size", 12)
	fps_label.add_theme_color_override("font_color", Color(RumbangStyle.NEON_CYAN, 0.8))
	fps_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	fps_label.add_theme_constant_override("outline_size", 4)
	
	# Anclar arriba a la derecha
	fps_label.anchor_left = 1.0
	fps_label.anchor_right = 1.0
	fps_label.anchor_top = 0.0
	fps_label.anchor_bottom = 0.0
	
	
	fps_label.offset_left = -150
	fps_label.offset_right = -20
	fps_label.offset_top = 20
	fps_label.offset_bottom = 50
	fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	
	$Control.add_child(fps_label)


func _connect_to_player() -> void:
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_signal("weapon_attacked"):
		if not player.weapon_attacked.is_connected(_on_player_weapon_attacked):
			player.weapon_attacked.connect(_on_player_weapon_attacked)

func _on_player_weapon_attacked(weapon_type: int) -> void:
	trigger_crosshair_kickback(weapon_type)

func trigger_crosshair_kickback(weapon_type: int = -1, strength: float = 1.0) -> void:
	if crosshair and crosshair.has_method("trigger_kickback"):
		crosshair.trigger_kickback(weapon_type, strength)



func update_stats(hp: float, max_hp: float) -> void:
	var stats := [hp, max_hp]
	if stats == _last_stats:
		return
	_last_stats = stats
	if vitals:
		vitals.set_values(hp, max_hp)

	if hp_bar:
		hp_bar.max_value = max_hp
		hp_bar.value = hp
	if hp_label:
		hp_label.text = str(int(ceil(hp)))


func update_xp(_level: int, current_xp: float, required_xp: float) -> void:
	if xp_bar:
		xp_bar.max_value = required_xp
		xp_bar.value = current_xp



func update_weapons(active_index: int, weapons_list: Array) -> void:
	print("UPDATE WEAPONS CALLED, active: ", active_index, ", list size: ", weapons_list.size())
	for i in range(weapon_slots.size()):
		var slot_icon = weapon_slots[i]
		if i < weapons_list.size():
			var w_name = weapons_list[i].get("name", "")
			print("Slot ", i, " weapon: ", w_name)
			if weapon_textures.has(w_name):
				slot_icon.texture = weapon_textures[w_name]
			else:
				# Fallback a pistola si no hay imagen
				slot_icon.texture = preload("res://assets/ui/ingame_hub/armas/pistola.png")
				print("WARNING: Texture not found for ", w_name, ", using fallback")
			
			slot_icon.modulate = Color(1, 1, 1, 1.0)
			slot_icon.pivot_offset = slot_icon.size / 2.0
			
			if i == active_index:
				slot_icon.scale = Vector2(1.15, 1.15)
			else:
				slot_icon.scale = Vector2(0.85, 0.85)
		else:
			slot_icon.texture = null

func update_reload(_weapon_type: int, _ammo: int, _max_ammo: int, is_reloading: bool, progress: float) -> void:
	pass

func update_elapsed_time(elapsed_seconds: float) -> void:
	if not time_label:
		return
	var total_seconds := maxi(0, int(elapsed_seconds))
	var minutes := total_seconds / 60
	var seconds := total_seconds % 60
	time_label.text = "%02d:%02d" % [minutes, seconds]

func play_level_up_confetti() -> void:
	var overlay := Control.new()
	overlay.name = "LevelUpConfetti"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$Control.add_child(overlay)

	var flash := ColorRect.new()
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.color = Color(1.0, 0.9, 0.45, 0.16)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(flash)
	var flash_tween := overlay.create_tween()
	flash_tween.tween_property(flash, "modulate:a", 0.0, 0.35)

	var viewport_size := get_viewport().get_visible_rect().size
	var colors := [
		Color(1.0, 0.25, 0.35),
		Color(1.0, 0.8, 0.2),
		Color(0.25, 0.85, 1.0),
		Color(0.35, 1.0, 0.55),
		Color(0.8, 0.4, 1.0)
	]

	for i in range(120):
		var piece := ColorRect.new()
		piece.color = colors[i % colors.size()]
		piece.size = Vector2(randf_range(4.0, 9.0), randf_range(8.0, 16.0))
		piece.position = Vector2(randf_range(0.0, viewport_size.x), viewport_size.y + randf_range(0.0, 80.0))
		piece.rotation = randf_range(-0.8, 0.8)
		piece.pivot_offset = piece.size * 0.5
		piece.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.add_child(piece)

		var rise_time := randf_range(1.4, 2.5)
		var rise_tween := overlay.create_tween().set_parallel(true)
		rise_tween.tween_property(piece, "position:y", -40.0, rise_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		rise_tween.tween_property(piece, "position:x", piece.position.x + randf_range(-160.0, 160.0), rise_time)
		rise_tween.tween_property(piece, "rotation", piece.rotation + randf_range(-5.0, 5.0), rise_time)
		rise_tween.tween_property(piece, "modulate:a", 0.0, rise_time * 0.35).set_delay(rise_time * 0.65)

	var cleanup := overlay.create_tween()
	cleanup.tween_interval(2.7)
	cleanup.tween_callback(overlay.queue_free)

func update_gold(gold: int) -> void:
	if gold_label:
		gold_label.text = "🪙 " + str(gold)

func show_game_over() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if game_over_screen:
		_reveal_end_screen(game_over_screen)

func show_victory() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if victory_screen:
		_reveal_end_screen(victory_screen)

## Pantallas de fin (caída y victoria) con el estilo común: panel con marco, título con brillo y una línea con
## el tiempo y el oro de la partida. Se construye una vez, al empezar.
func _style_end_screens() -> void:
	for pair in [[game_over_screen, RumbangStyle.DANGER, RumbangStyle.NEON_MAGENTA, "Tu cuerpo se desvanece en la oscuridad…"],
			[victory_screen, Color(0.45, 1.0, 0.6), RumbangStyle.NEON_CYAN, "La mazmorra guarda silencio."]]:
		var screen: Control = pair[0]
		if screen == null:
			continue
		screen.theme = RumbangStyle.get_theme()
		var bg := screen.get_node_or_null("ColorRect") as ColorRect
		if bg:
			bg.color = Color(0.02, 0.01, 0.05, 0.82)
		var vb := screen.get_node_or_null("VBox") as VBoxContainer
		if vb == null:
			continue
		var panel := PanelContainer.new()
		panel.name = "EndPanel"
		panel.set_anchors_preset(Control.PRESET_CENTER)
		panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
		panel.grow_vertical = Control.GROW_DIRECTION_BOTH
		panel.custom_minimum_size = Vector2(460, 0)
		screen.add_child(panel)
		screen.remove_child(vb)
		panel.add_child(vb)
		vb.set_anchors_preset(Control.PRESET_TOP_LEFT)
		vb.add_theme_constant_override("separation", 14)
		var title := vb.get_node_or_null("Title") as Label
		if title:
			RumbangStyle.style_title(title, 30, pair[1], pair[2])
		var sub := Label.new()
		sub.name = "Sub"
		sub.text = pair[3]
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub.add_theme_color_override("font_color", RumbangStyle.TEXT_DIM)
		sub.add_theme_font_size_override("font_size", 11)
		vb.add_child(sub)
		vb.move_child(sub, 1)
		var stats := Label.new()
		stats.name = "Stats"
		stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stats.add_theme_color_override("font_color", RumbangStyle.ACCENT)
		stats.add_theme_font_size_override("font_size", 13)
		vb.add_child(stats)
		vb.move_child(stats, 2)
		NeonFrame.attach(panel, pair[2])

func _reveal_end_screen(screen: Control) -> void:
	var stats := screen.find_child("Stats", true, false) as Label
	if stats:
		var gs := GameState.get_instance()
		stats.text = "TIEMPO %s     ORO %d" % [time_label.text if time_label else "--:--", gs.gold]
	screen.visible = true
	screen.modulate.a = 0.0
	var panel := screen.get_node_or_null("EndPanel") as Control
	var tw := screen.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(screen, "modulate:a", 1.0, 0.45)
	if panel:
		panel.pivot_offset = panel.size * 0.5
		panel.scale = Vector2(0.92, 0.92)
		tw.parallel().tween_property(panel, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_restart_button_pressed() -> void:
	emit_signal("restart_pressed")
