extends CanvasLayer

signal restart_pressed

@onready var hp_bar: ProgressBar = $Control/StatsPanel/Margin/VBox/BarsWithPortrait/DomeClipping/BarsHBox/HPBar
@onready var hp_label: Label = $Control/StatsPanel/Margin/VBox/BarsWithPortrait/LabelsHBox/HPLabel


@onready var floor_label: Label = $Control/TopRight/FloorPanel/Margin/FloorLabel
@onready var gold_label: Label = $Control/VitalsRow/GoldPanel/Margin/GoldLabel
## Fila bajo el bloque de vida: oro a la izquierda y botón de pausa a la derecha (ver HudLayout)
@onready var vitals_row: HBoxContainer = $Control/VitalsRow
@onready var time_label: Label = $Control/TimeLabel

@onready var crosshair: Control = $Control/Crosshair
@onready var game_over_screen: Control = $GameOverScreen
@onready var victory_screen: Control = $VictoryScreen

@onready var xp_bar: ProgressBar = $Control/HubImage/XPBar

var fps_label: Label
var _fps_shown := -1

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
	"Polvos Alquímicos": preload("res://assets/ui/ingame_hub/armas/polvos.png"),
	"Dagas Gemelas": preload("res://assets/ui/ingame_hub/armas/dagas.png"),
	"Maza Rúnica": preload("res://assets/ui/ingame_hub/armas/maza.png")
}
@onready var stats_panel: Control = $Control/StatsPanel
var _last_stats: Array = []
## Panel de vida (abajo a la izquierda); sustituye a las barras verticales de StatsPanel
var vitals: VitalsPanel
var resource_bars: ResourceBars
## Escritorio: vida y recursos en vertical, flotando junto al personaje
var floating_vitals: FloatingVitals
var minimap: Minimap
## Supervivencia: bolsa de cuero a la derecha con tomos y objetos (BagPanel)
var bag: BagPanel
var pause_button: Button
var _mobile := false

## Contorno de tinta (cómic) de la tira de armas y de sus iconos (scripts/ui/ink_outline.gdshader).
const INK_OUTLINE := preload("res://scripts/ui/ink_outline.gdshader")

const STRIP_INK := {"ink_px": 6.0, "shadow_px": Vector2(7.0, 9.0)}     # la imagen es grande (2172 px): 6 px de textura ≈ 2 en pantalla
const ICON_INK := {"ink_px": 14.0, "shadow_px": Vector2(10.0, 14.0)}   # iconos de 648 px dibujados a ~45: hace falta más grosor
const ICON_SCALE_ACTIVE := 1.15
const ICON_SCALE_IDLE := 0.85
## Tinta horneada (InkBake) en vez del shader por frame; false sin render (headless): queda el shader.
var _ink_baked := false
var _icon_mat: ShaderMaterial

func _ink_strip() -> void:
	var hub := get_node_or_null("Control/HubImage") as TextureRect
	if hub == null:
		return
	var m := ShaderMaterial.new()
	m.shader = INK_OUTLINE
	m.set_shader_parameter("ink_px", STRIP_INK["ink_px"])
	m.set_shader_parameter("shadow_px", STRIP_INK["shadow_px"])
	hub.material = m
	_icon_mat = ShaderMaterial.new()
	_icon_mat.shader = INK_OUTLINE
	_icon_mat.set_shader_parameter("ink_px", ICON_INK["ink_px"])
	_icon_mat.set_shader_parameter("shadow_px", ICON_INK["shadow_px"])
	for icon in weapon_slots:
		if icon is CanvasItem:
			(icon as CanvasItem).material = _icon_mat
	_ink_baked = DisplayServer.get_name() != "headless"
	if not _ink_baked:
		return
	# Tinta horneada: la tira y cada icono se dibujan como texturas normales. Los huecos dejan de recortar con
	# clip_children (un pase de render aparte por hueco): el círculo va horneado en el icono activo.
	for icon in weapon_slots:
		var slot := (icon as Control).get_parent() as Panel
		if slot:
			slot.clip_children = CanvasItem.CLIP_CHILDREN_DISABLED
			slot.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var src := hub.texture
	hub.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	InkBake.request(src, _screen_px(hub, hub.size), STRIP_INK, func(t: Texture2D) -> void:
		if t and is_instance_valid(hub) and hub.texture == src:
			hub.texture = t
			hub.material = InkBake.material())

## Píxeles reales de pantalla que ocupa `size` de `ci` (escala del lienzo y de la ventana), redondeado a 16.
func _screen_px(ci: CanvasItem, size: Vector2) -> Vector2i:
	var s := ci.get_global_transform_with_canvas().get_scale().abs() * size
	var root := get_tree().root
	var vis := root.get_visible_rect().size
	var ratio := maxf(1.0, float(root.size.y) / maxf(vis.y, 1.0))
	s *= ratio
	return Vector2i(ceili(s.x / 16.0) * 16, ceili(s.y / 16.0) * 16)

## Icono de arma con tinta horneada; el activo, recortado al círculo del hueco (radio 0.5 / su escala).
func _bake_icon(icon: TextureRect, src: Texture2D, active: bool) -> void:
	icon.set_meta("ink_src", src)
	var cached_tex := _icon_baked_tex(icon, src, active, true)
	if cached_tex:
		icon.texture = cached_tex
		icon.material = InkBake.material()
		return
	icon.texture = src
	icon.material = _icon_mat
	_icon_baked_tex(icon, src, active, false)

func _icon_baked_tex(icon: TextureRect, src: Texture2D, active: bool, only_cached: bool) -> Texture2D:
	var slot := icon.get_parent() as Control
	var px := _screen_px(slot, icon.size * ICON_SCALE_ACTIVE)
	var params := ICON_INK.duplicate()
	if active:
		params["clip_radius"] = 0.5 / ICON_SCALE_ACTIVE
	if only_cached:
		return InkBake.cached(src, px, params)
	InkBake.request(src, px, params, func(t: Texture2D) -> void:
		if t and is_instance_valid(icon) and icon.get_meta("ink_src", null) == src and (icon.scale.x > 1.0) == active:
			icon.texture = t
			icon.material = InkBake.material())
	return null

func _ready() -> void:
	_ink_strip()
	add_to_group("hud")
	# Ya no hay pisos: se oculta el panel de nivel (el cronómetro es la referencia)
	if floor_label:
		floor_label.get_parent().get_parent().visible = false
	_create_fps_label()
	# Supervivencia: sin crosshair (el personaje se mueve libre y los ataques salen hacia la camara)
	if GameData.game_mode != "dungeon" and crosshair:
		crosshair.visible = false
	vitals = VitalsPanel.new()
	vitals.name = "VitalsPanel"
	$Control.add_child(vitals)
	resource_bars = ResourceBars.new()
	resource_bars.name = "ResourceBars"
	$Control.add_child(resource_bars)
	resource_bars.layout_changed.connect(_layout_row)
	floating_vitals = FloatingVitals.new()
	floating_vitals.name = "FloatingVitals"
	floating_vitals.setup(vitals, resource_bars)
	floating_vitals.visible = not Quality.is_mobile()
	$Control.add_child(floating_vitals)
	if GameData.game_mode == "dungeon":
		var combo := ComboCounter.new()
		combo.name = "ComboCounter"
		$Control.add_child(combo)
	_create_pause_button()
	minimap = Minimap.new()
	minimap.name = "Minimap"
	$Control.add_child(minimap)
	if GameData.game_mode != "dungeon":
		bag = BagPanel.new()
		$Control.add_child(bag)
		bag.place_right()
	_mobile = Quality.is_mobile()
	_layout_row()
	_layout_fps()
	get_viewport().size_changed.connect(_layout_fps)
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

var combat_label: Label
var _dps_samples: Array = []      ## [tiempo, daño total] de los últimos DPS_WINDOW s
var _combat_t := 0.0
const DPS_WINDOW := 5.0

## Supervivencia: bajas y daño por segundo (media de los últimos DPS_WINDOW s) bajo el FPS.
func _update_combat_label(delta: float) -> void:
	if GameData.game_mode == "dungeon":
		return
	_combat_t += delta
	if combat_label == null:
		combat_label = Label.new()
		combat_label.add_theme_font_size_override("font_size", 12)
		combat_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.3, 0.9))
		combat_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		combat_label.add_theme_constant_override("outline_size", 4)
		combat_label.anchor_left = 1.0
		combat_label.anchor_right = 1.0
		combat_label.offset_left = -220
		combat_label.offset_right = -20
		combat_label.offset_top = 50     # bajo el FPS, sin solaparse
		combat_label.offset_bottom = 96
		combat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		combat_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		$Control.add_child(combat_label)
	var total := RunStats.total_damage()
	_dps_samples.append([_combat_t, total])
	while _dps_samples.size() > 1 and _combat_t - float(_dps_samples[0][0]) > DPS_WINDOW:
		_dps_samples.remove_at(0)
	var first: Array = _dps_samples[0]
	var span := maxf(_combat_t - float(first[0]), 0.001)
	combat_label.text = "BAJAS %d\nDPS %d" % [RunStats.kills, int((total - float(first[1])) / span)]

func _process(delta: float) -> void:
	_update_combat_label(delta)
	if is_instance_valid(fps_label):
		# Solo cuando cambia: evita formatear un String nuevo en cada frame
		var fps := int(Engine.get_frames_per_second())
		if fps != _fps_shown:
			_fps_shown = fps
			fps_label.text = "FPS: %d" % fps
	if GameData.game_mode == "dungeon" and stats_panel and stats_panel.visible:
		_follow_player_with_stats(delta)
	if GameData.game_mode == "dungeon" and crosshair:
		crosshair.visible = wants_crosshair()

## Mazmorra con cámara centrada (estilo Elden Ring): la mira solo sale con el arco en la mano.
func wants_crosshair() -> bool:
	var player := get_tree().get_first_node_in_group("player")
	return player != null and player.has_method("current_weapon") \
		and int(player.current_weapon()) == WeaponData.WeaponType.BOW

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

## Botón de pausa (en la fila de oro, a su derecha), en las dos plataformas: en el móvil no hay tecla Esc.
func _create_pause_button() -> void:
	var b := Button.new()
	b.name = "PauseButton"
	b.text = "II"
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.theme = RumbangStyle.get_theme()
	b.modulate.a = 0.85
	b.pressed.connect(func():
		var pm := get_tree().root.find_child("PauseMenu", true, false)
		if pm and pm.has_method("open_menu") and not pm.visible:
			pm.open_menu())
	vitals_row.add_child(b)
	pause_button = b

## Recoloca todo el bloque de la izquierda y el mapa para una plataforma (lo usa la prueba de disposición).
func apply_layout(mobile: bool) -> void:
	_mobile = mobile
	vitals.apply_layout(mobile)
	resource_bars.apply_layout(mobile)   # emite layout_changed: recoloca la fila
	floating_vitals.visible = not mobile
	minimap.apply_layout(mobile)
	_layout_row()
	_layout_fps()

## Fila de oro + pausa bajo el bloque de vida. En escritorio no se mueve (las barras de recursos tienen el
## borde inferior fijo); en móvil baja o sube con la barra de balas.
func _layout_row() -> void:
	if vitals_row == null or not is_instance_valid(resource_bars):
		return
	var side := HudLayout.pause_side(_mobile)
	if pause_button:
		pause_button.custom_minimum_size = Vector2(side, side)
		pause_button.add_theme_font_size_override("font_size", 28 if _mobile else 22)
	var h := maxf(HudLayout.ROW_H, side)
	vitals_row.offset_left = HudLayout.MARGIN
	vitals_row.offset_right = HudLayout.MARGIN + HudLayout.VITALS_PANEL_W
	if _mobile:
		vitals_row.set_anchors_preset(Control.PRESET_TOP_LEFT)
		vitals_row.offset_top = HudLayout.row_top_mobile(resource_bars.used_height())
	else:
		vitals_row.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		vitals_row.offset_top = HudLayout.row_top_desktop()
	vitals_row.offset_bottom = vitals_row.offset_top + h

## FPS: en la mazmorra, bajo el minimapa (arriba a la derecha); en supervivencia, en la esquina.
func _layout_fps() -> void:
	if not is_instance_valid(fps_label):
		return
	var top := 20.0
	if GameData.game_mode == "dungeon":
		top = HudLayout.below_map_y(get_viewport().get_visible_rect().size.x)
	fps_label.offset_right = -HudLayout.MAP_MARGIN
	fps_label.offset_left = fps_label.offset_right - 130.0
	fps_label.offset_top = top
	fps_label.offset_bottom = top + 20.0

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
	# La bolsa se rehace cuando cambian tomos u objetos (los dos recalculan las estadísticas)
	var sb = player.get("stat_block") if player else null
	if bag and sb and sb.has_signal("stats_recalculated") and not sb.stats_recalculated.is_connected(refresh_bag):
		sb.stats_recalculated.connect(refresh_bag)
	refresh_bag()

func refresh_bag() -> void:
	if bag == null:
		return
	var player = get_tree().get_first_node_in_group("player")
	bag.refresh(player.get("inventory") if player else null)

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


var _xp_glow_tw: Tween

func update_xp(_level: int, current_xp: float, required_xp: float) -> void:
	if xp_bar:
		var gained := current_xp > xp_bar.value
		xp_bar.max_value = required_xp
		xp_bar.value = current_xp
		# Brillo al ganar XP (un tween a la vez: con muchas gemas seguidas se queda encendida)
		if gained:
			if _xp_glow_tw and _xp_glow_tw.is_valid():
				_xp_glow_tw.kill()
			xp_bar.modulate = Color(1.5, 1.5, 1.8)
			_xp_glow_tw = xp_bar.create_tween()
			_xp_glow_tw.tween_property(xp_bar, "modulate", Color.WHITE, 0.25)



func update_weapons(active_index: int, weapons_list: Array) -> void:
	for i in range(weapon_slots.size()):
		var slot_icon = weapon_slots[i]
		if i < weapons_list.size():
			var w_name = weapons_list[i].get("name", "")
			# Primero la imagen del arma por tipo (la misma de las cartas y la elección de arma)
			var icon_path := String(WeaponChoiceUI.ICONS.get(int(weapons_list[i].get("type", -1)), ""))
			var src: Texture2D
			if icon_path != "" and ResourceLoader.exists(icon_path):
				src = load(icon_path)
			elif weapon_textures.has(w_name):
				src = weapon_textures[w_name]
			else:
				# Fallback a pistola si no hay imagen
				src = preload("res://assets/ui/ingame_hub/armas/pistola.png")
				push_warning("Sin icono para el arma %s: se usa el de la pistola" % w_name)

			slot_icon.modulate = Color(1, 1, 1, 1.0)
			slot_icon.pivot_offset = slot_icon.size / 2.0

			var active: bool = i == active_index
			var sc := ICON_SCALE_ACTIVE if active else ICON_SCALE_IDLE
			slot_icon.scale = Vector2(sc, sc)
			if _ink_baked:
				_bake_icon(slot_icon, src, active)
			else:
				slot_icon.texture = src
		else:
			slot_icon.texture = null
			slot_icon.remove_meta("ink_src")
	_update_synergy_badges(weapons_list)
	refresh_bag()          # por si el jugador aún no existía al conectar la señal

# ── Sinergias activas (supervivencia) ──────────────────────────────────────
## Encima de la barra de armas, una insignia por sinergia activa (icono de la etiqueta + 2 o 3), con el mismo
## icono que las cartas de subida de nivel (design/ux/level-up-cards.md). Sin texto: el detalle está en las
## cartas. Una sinergia nueva o que sube de nivel "salta" con un destello.
const SYNERGY_BADGE_PX := 30
const SYNERGY_ROW_ABOVE_BAR := 128.0     ## px desde abajo: justo encima de la tira de armas (1280×720)
var _synergy_row: HBoxContainer
var _synergy_tiers: Dictionary = {}      ## etiqueta -> nivel mostrado (para saber qué es nuevo)

func _update_synergy_badges(weapons_list: Array) -> void:
	if GameData.game_mode == "dungeon":
		return
	if _synergy_row == null:
		# En $Control y no dentro de HubImage: la tira de armas está girada 180° y escalada a 0.4
		_synergy_row = HBoxContainer.new()
		_synergy_row.name = "SynergyBadges"
		_synergy_row.alignment = BoxContainer.ALIGNMENT_CENTER
		_synergy_row.add_theme_constant_override("separation", 10)
		_synergy_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_synergy_row.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		_synergy_row.offset_left = -220.0
		_synergy_row.offset_right = 220.0
		_synergy_row.offset_bottom = -SYNERGY_ROW_ABOVE_BAR
		_synergy_row.offset_top = -SYNERGY_ROW_ABOVE_BAR - SYNERGY_BADGE_PX
		$Control.add_child(_synergy_row)
	var slots: Array = []
	for info in weapons_list:
		if info.has("type"):
			slots.append(int(info["type"]))
	var active := WeaponSynergies.active(slots)
	var now := {}
	for s in active:
		now[s["tag"]] = int(s["tier"])
	if now == _synergy_tiers and _synergy_row.get_child_count() == now.size():
		return
	for c in _synergy_row.get_children():
		c.queue_free()
	for s in active:
		var tag: String = s["tag"]
		var info: Dictionary = WeaponSynergies.TAG_INFO[tag]
		var badge := HBoxContainer.new()
		badge.add_theme_constant_override("separation", 2)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var icon := TextureRect.new()
		var path := WeaponSynergies.tag_icon_path(tag)
		icon.texture = load(path) if ResourceLoader.exists(path) else null
		icon.custom_minimum_size = Vector2(SYNERGY_BADGE_PX, SYNERGY_BADGE_PX)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_child(icon)
		var lbl := Label.new()
		lbl.text = str(mini(int(s["count"]), 3))
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_color_override("font_color", info["color"])
		lbl.add_theme_color_override("font_outline_color", Color(0.03, 0.022, 0.05))
		lbl.add_theme_constant_override("outline_size", 5)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_child(lbl)
		_synergy_row.add_child(badge)
		if int(s["tier"]) > int(_synergy_tiers.get(tag, 0)):
			_pop_badge.call_deferred(badge)
	_synergy_tiers = now

## Una sinergia nueva salta y destella (también con el juego en pausa: se elige en la pantalla de cartas).
func _pop_badge(badge: Control) -> void:
	if not is_instance_valid(badge):
		return
	badge.pivot_offset = badge.size / 2.0
	badge.scale = Vector2(1.6, 1.6)
	badge.modulate = Color(2.0, 2.0, 1.6)
	var tw := badge.create_tween().set_parallel(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(badge, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(badge, "modulate", Color.WHITE, 0.4)

func update_reload(_weapon_type: int, _ammo: int, _max_ammo: int, is_reloading: bool, progress: float) -> void:
	pass

func update_elapsed_time(elapsed_seconds: float) -> void:
	if not time_label:
		return
	var total_seconds := maxi(0, int(elapsed_seconds))
	var minutes := total_seconds / 60
	var seconds := total_seconds % 60
	time_label.text = "%02d:%02d" % [minutes, seconds]

## Triángulos dorados desde los bordes mientras se eligen las cartas (LevelUpEdges).
func play_level_up_edges() -> void:
	for old in get_tree().root.find_children("LevelUpEdges", "ColorRect", true, false):
		old.get_parent().queue_free()
	LevelUpEdges.play(self)

## Cartel de subida de nivel / evolución (LevelUpBurst), tras elegir la mejora. Conserva el nombre antiguo.
func play_level_up_confetti(text: String = "¡NIVEL!") -> void:
	for old in get_tree().root.find_children("LevelUpBurst", "Control", true, false):
		old.get_parent().queue_free()
	LevelUpBurst.play($Control, text)

var _shown_gold := -1
var _souls_label: Label

## Almas de la partida en curso (mazmorra, SoulStats). La etiqueta se crea al primer uso junto al oro.
func update_souls(souls: int) -> void:
	if _souls_label == null:
		_souls_label = Label.new()
		_souls_label.name = "SoulsLabel"
		_souls_label.add_theme_font_size_override("font_size", 12)
		_souls_label.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
		_souls_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		_souls_label.add_theme_constant_override("outline_size", 4)
		_souls_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var gold_panel := gold_label.get_parent().get_parent() if gold_label else null
		if vitals_row and gold_panel and gold_panel.get_parent() == vitals_row:
			vitals_row.add_child(_souls_label)
			vitals_row.move_child(_souls_label, gold_panel.get_index() + 1)
		else:
			$Control.add_child(_souls_label)
	_souls_label.text = "ALMAS %d" % souls

func update_gold(gold: int) -> void:
	if gold_label:
		gold_label.text = "🪙 " + str(gold)
		# Sube el oro: el contador da un salto y brilla
		if _shown_gold >= 0 and gold > _shown_gold:
			gold_label.pivot_offset = gold_label.size * 0.5
			var tw := gold_label.create_tween().set_ignore_time_scale(true)
			gold_label.scale = Vector2.ONE * 1.3
			gold_label.modulate = Color(1.6, 1.4, 0.6)
			tw.tween_property(gold_label, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.parallel().tween_property(gold_label, "modulate", Color.WHITE, 0.3)
		_shown_gold = gold

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
	var fb := screen.find_children("*", "Button", true, false)
	if not fb.is_empty():
		(fb[0] as Button).grab_focus.call_deferred()
	var panel := screen.get_node_or_null("EndPanel") as Control
	var tw := screen.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(screen, "modulate:a", 1.0, 0.45)
	if panel:
		panel.pivot_offset = panel.size * 0.5
		panel.scale = Vector2(0.92, 0.92)
		tw.parallel().tween_property(panel, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_restart_button_pressed() -> void:
	emit_signal("restart_pressed")
