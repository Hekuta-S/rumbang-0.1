class_name TutorialPatio
extends Node3D

## Patio del castillo: el tutorial de la primera partida. El mago invoca al héroe delante del rey (que solo
## aparece aquí) y un goblin de práctica enseña moverse, golpear, esquivar y parry (TutorialDirector).
## Al acabar (o al saltarlo) se marca como hecho y un destello lleva al Salón (DungeonHub).
## Se arma con lo que ya hay: texturas y materiales del salón, modelos del rey y el mago, Player y HUD reales.

const HUB := "res://scenes/ui/dungeon_hub.tscn"
const KING_PATH := "res://assets/models/salon/rey.glb"
const MAGE_PATH := "res://assets/models/salon/mago.glb"
const HALF := 14.0                       ## medio lado del patio
const WALL_H := 6.0
const PLAYER_START := Vector3(0.0, 0.3, 2.5)   ## el círculo de invocación (TutorialCinematic.CIRCLE)
const BALCONY_TOP := 1.6
const SPEAKERS := {"rey": ["El Rey", Color(1.0, 0.78, 0.3)], "mago": ["El Mago", Color(0.45, 0.8, 1.0)]}
const OUTRO := [
	["mago", "Nada mal para alguien en calzones. Te llevo al salón: allí están los portales."],
	["rey", "¡Y vuelve vivo! Las mazmorras no se limpian solas."],
]

signal finished

var player: CharacterBody3D
var hud: Node
var director := TutorialDirector.new()
var king: Node3D
var mage: Node3D
var goblin: DungeonGoblin
var leaving := false
var cinematic := false                    ## la invocación está en marcha
var cine: TutorialCinematic
var _letterbox: Array[ColorRect] = []
var _skip_btn: Button
var _ui: CanvasLayer
var _hint_panel: PanelContainer
var _hint_title: Label
var _hint_text: Label
var _hint_bar: ProgressBar
var _sub_panel: PanelContainer
var _sub_name: Label
var _sub_text: Label
var _fade: ColorRect
var _voice: AudioStreamPlayer
var _last_pos := Vector3.ZERO
var _last_gob_hp := -1.0
var _was_dodging := false
var _touch_controls: CanvasLayer   ## MobileControls (modo mazmorra) en móvil; null en PC

## El modo mazmorra se fija ANTES de que existan los hijos: el Player decide su cámara, fijar objetivo, parry y
## animaciones de mazmorra en su _ready, que corre antes que el de esta escena.
func _init() -> void:
	GameData.game_mode = "dungeon"
	GameData.selected_index = GameData.custom_index()

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	GameData.game_mode = "dungeon"
	_build_world()
	_setup_player()
	_build_ui()
	_build_touch_controls()
	director.step_changed.connect(_on_step_changed)
	director.progressed.connect(_on_progressed)
	director.finished.connect(_on_finished)
	MusicDirector.play("patio")
	_intro()

# ───────────────────────────── mundo ─────────────────────────────

func _build_world() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.32, 0.5, 0.8)
	sky_mat.sky_horizon_color = Color(0.78, 0.82, 0.88)
	sky_mat.ground_horizon_color = Color(0.62, 0.6, 0.56)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	Quality.tune_environment(env, get_viewport())
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	Quality.add_governor(self, get_viewport())
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.93, 0.8)
	sun.light_energy = 1.1
	sun.rotation_degrees = Vector3(-48.0, 35.0, 0.0)
	Quality.tune_light(sun)
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)

	# Suelo de losas y muros de ladrillo
	_block("Suelo", Vector3(0, -0.5, 0), Vector3(HALF * 2.0, 1.0, HALF * 2.0), "salon_floor", 0.55)
	for w in [[Vector3(0, WALL_H / 2.0, -HALF - 0.5), Vector3(HALF * 2.0 + 2.0, WALL_H, 1.0)],
			[Vector3(0, WALL_H / 2.0, HALF + 0.5), Vector3(HALF * 2.0 + 2.0, WALL_H, 1.0)],
			[Vector3(-HALF - 0.5, WALL_H / 2.0, 0), Vector3(1.0, WALL_H, HALF * 2.0)],
			[Vector3(HALF + 0.5, WALL_H / 2.0, 0), Vector3(1.0, WALL_H, HALF * 2.0)]]:
		_block("Muro", w[0], w[1], "salon_brick", 0.45)
	# Balcón del rey, al fondo
	_block("Balcon", Vector3(0, BALCONY_TOP / 2.0, -HALF + 2.0), Vector3(9.0, BALCONY_TOP, 4.0), "salon_stone", 0.5)
	# Columnas con antorcha a los lados y postes de práctica de adorno
	for sx in [-1.0, 1.0]:
		for z in [-8.0, -1.0, 6.0]:
			_pillar(Vector3(sx * (HALF - 1.4), 0.0, z))
	for p in [Vector3(-9, 0, -4), Vector3(9, 0, -4), Vector3(-9, 0, 3), Vector3(9, 0, 3)]:
		_post(p)
	_decorate()
	cine = TutorialCinematic.new()
	cine.name = "Cinematic"
	add_child(cine)
	cine.build(self)
	cine.finished.connect(_end_cinematic)
	king = _spawn_npc(KING_PATH, Vector3(0.0, BALCONY_TOP, -HALF + 2.6), 0.0, _look("Rey", Color(0.86, 0.64, 0.52), Color(0.34, 0.22, 0.13)))
	mage = _spawn_npc(MAGE_PATH, Vector3(-3.0, 0.0, 1.6), PI * 0.5, _look("Mago", Color(0.93, 0.8, 0.72), Color(0.82, 0.8, 0.76)))
	_play(king, "rey_idle")
	_play(mage, "mago_idle")

## Adornos con lo que hay: almenas, estandartes, portón de entrada, ruedo de tierra, barriles, heno y armero.
func _decorate() -> void:
	var stone := _mat("salon_stone", 0.5)
	# Almenas sobre los muros
	for i in range(-6, 7):
		var x := i * 2.0
		for z in [-HALF - 0.5, HALF + 0.5]:
			_deco_box(Vector3(x, WALL_H + 0.5, z), Vector3(1.0, 1.0, 1.0), stone)
		_deco_box(Vector3(-HALF - 0.5, WALL_H + 0.5, x), Vector3(1.0, 1.0, 1.0), stone)
		_deco_box(Vector3(HALF + 0.5, WALL_H + 0.5, x), Vector3(1.0, 1.0, 1.0), stone)
	# Estandartes rojos y azules en los muros laterales y detrás del balcón
	var red := _mat("salon_banner_red", 1.0)
	var blue := _mat("salon_banner_blue", 1.0)
	red.albedo_color = Color(0.62, 0.1, 0.1)
	blue.albedo_color = Color(0.14, 0.26, 0.62)
	for z in [-5.0, 2.5, 9.0]:
		_deco_box(Vector3(-HALF + 0.08, 3.6, z), Vector3(0.06, 3.2, 1.3), blue)
		_deco_box(Vector3(HALF - 0.08, 3.6, z), Vector3(0.06, 3.2, 1.3), red)
	for x in [-3.2, 3.2]:
		_deco_box(Vector3(x, 3.4, -HALF + 0.08), Vector3(1.5, 3.8, 0.06), red)
	# Portón de entrada (muro sur): marco de piedra y hojas de madera cerradas
	var dark := _mat("salon_stone_dark", 0.5)
	_deco_box(Vector3(-2.0, 2.4, HALF - 0.2), Vector3(0.7, 4.8, 0.7), dark)
	_deco_box(Vector3(2.0, 2.4, HALF - 0.2), Vector3(0.7, 4.8, 0.7), dark)
	_deco_box(Vector3(0.0, 4.9, HALF - 0.2), Vector3(4.7, 0.7, 0.7), dark)
	_deco_box(Vector3(0.0, 2.2, HALF - 0.1), Vector3(3.3, 4.4, 0.2), _mat("salon_wood", 1.0))
	for sx in [-1.0, 1.0]:
		_deco_box(Vector3(sx * 3.4, 3.0, HALF - 0.3), Vector3(0.14, 0.14, 0.14), dark)
	# Ruedo de entrenamiento: tierra apisonada con borde de piedra
	var dirt := StandardMaterial3D.new()
	dirt.albedo_color = Color(0.42, 0.32, 0.22)
	dirt.roughness = 1.0
	_deco_cyl(Vector3(0, 0.02, -1.0), 6.6, 0.04, dirt)
	_deco_cyl(Vector3(0, 0.015, -1.0), 7.0, 0.03, dark.duplicate())
	# Barriles, heno y armero en los rincones
	var wood := _mat("salon_wood", 1.0)
	for p in [Vector3(-12, 0, -11.5), Vector3(-11.2, 0, -12), Vector3(12, 0, -11.5), Vector3(11.3, 0, -10.8)]:
		_deco_cyl(p + Vector3(0, 0.45, 0), 0.4, 0.9, wood, true)
	var hay := StandardMaterial3D.new()
	hay.albedo_color = Color(0.78, 0.64, 0.28)
	hay.roughness = 1.0
	for p in [Vector3(-11.5, 0.3, 11.5), Vector3(-10.2, 0.3, 11.8), Vector3(-11.0, 0.9, 11.6), Vector3(11.5, 0.3, 11.5)]:
		_deco_box(p, Vector3(1.2, 0.6, 0.8), hay, true)
	# Armero (lado este): travesaño con lanzas y espadas de madera
	_deco_box(Vector3(HALF - 1.2, 0.9, -2.0), Vector3(0.12, 1.8, 3.2), wood, true)
	for k in 5:
		_deco_box(Vector3(HALF - 1.45, 1.0, -3.2 + k * 0.6), Vector3(0.08, 1.5, 0.08), _mat("salon_steel", 1.0))

func _deco_box(pos: Vector3, size: Vector3, m: Material, solid: bool = false) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	if solid:
		var body := StaticBody3D.new()
		body.position = pos
		body.add_child(mi)
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		body.add_child(cs)
		add_child(body)
	else:
		mi.position = pos
		add_child(mi)

func _deco_cyl(pos: Vector3, radius: float, height: float, m: Material, solid: bool = false) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 24
	mi.mesh = cm
	mi.material_override = m
	if solid:
		var body := StaticBody3D.new()
		body.position = pos
		body.add_child(mi)
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = radius
		sh.height = height
		cs.shape = sh
		body.add_child(cs)
		add_child(body)
	else:
		mi.position = pos
		add_child(mi)

var _mat_cache := {}   ## un material por (nombre, escala): pilares, almenas y muros lo comparten

func _mat(mat_name: String, uv: float) -> StandardMaterial3D:
	var key := "%s|%s" % [mat_name, uv]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := DungeonHub.salon_material(mat_name, null) as StandardMaterial3D
	m.vertex_color_use_as_albedo = false
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * uv
	_mat_cache[key] = m
	return m

func _block(n: String, pos: Vector3, size: Vector3, mat_name: String, uv: float) -> void:
	var body := StaticBody3D.new()
	body.name = n
	body.position = pos
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(mat_name, uv)
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body.add_child(cs)
	add_child(body)

func _pillar(pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.5
	cm.bottom_radius = 0.55
	cm.height = 4.2
	mi.mesh = cm
	mi.position.y = 2.1
	mi.material_override = _mat("salon_stone", 0.5)
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 0.55
	sh.height = 4.2
	cs.shape = sh
	cs.position.y = 2.1
	body.add_child(cs)
	var fire := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.18
	sm.height = 0.5
	fire.mesh = sm
	fire.position = Vector3(0, 4.45, 0)
	fire.material_override = DungeonHub.salon_material("salon_glow_flame", null)
	body.add_child(fire)
	# Móvil: solo 2 de las 6 antorchas son luz real (las del medio); el resto queda con la llama emisiva
	if not Quality.is_mobile() or (absf(pos.z + 1.0) < 0.1):
		var l := OmniLight3D.new()
		l.position = Vector3(0, 4.6, 0)
		l.light_color = Color(1.0, 0.6, 0.28)
		l.light_energy = 1.4
		l.omni_range = 7.0
		l.visible = Quality.lights_enabled()
		body.add_child(l)
	add_child(body)

func _post(pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var m := _mat("salon_wood", 1.0)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.16
	cm.bottom_radius = 0.2
	cm.height = 1.7
	mi.mesh = cm
	mi.position.y = 0.85
	mi.material_override = m
	body.add_child(mi)
	var arm := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.0, 0.14, 0.14)
	arm.mesh = bm
	arm.position.y = 1.25
	arm.material_override = m
	body.add_child(arm)
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.2
	hm.height = 0.4
	head.mesh = hm
	head.position.y = 1.85
	var straw := StandardMaterial3D.new()
	straw.albedo_color = Color(0.78, 0.64, 0.28)
	straw.roughness = 1.0
	head.material_override = straw
	body.add_child(head)
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 0.25
	sh.height = 1.7
	cs.shape = sh
	cs.position.y = 0.85
	body.add_child(cs)
	add_child(body)

# ───────────────────────────── personajes ─────────────────────────────

func _look(char_name: String, skin: Color, hair: Color) -> CharacterLook:
	var l := CharacterLook.new()
	l.char_name = char_name
	l.hair_style = "rapado"
	l.colors["skin"] = skin
	l.colors["hair"] = hair
	return l

func _spawn_npc(path: String, pos: Vector3, yaw: float, look: CharacterLook) -> Node3D:
	var n: Node3D = null
	if ResourceLoader.exists(path):
		n = (load(path) as PackedScene).instantiate() as Node3D
	if n == null:
		n = Node3D.new()
	add_child(n)
	n.position = pos
	n.rotation.y = yaw
	CharacterLookApplier.apply_to(n, look)
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		if String(mi.name).begins_with(CharacterLookApplier.BODY_NODE):
			continue
		var mesh := (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var src := mesh.surface_get_material(i)
			var m := DungeonHub.salon_material(src.resource_name if src else "", src) as StandardMaterial3D
			m.vertex_color_use_as_albedo = false
			(mi as MeshInstance3D).set_surface_override_material(i, m)
	var ap := _anim(n)
	if ap:
		for a in ap.get_animation_list():
			var an := ap.get_animation(a)
			if an and not ("sorpresa" in a or "reverencia" in a):
				an.loop_mode = Animation.LOOP_LINEAR
	return n

func _anim(n: Node) -> AnimationPlayer:
	var found := n.find_children("*", "AnimationPlayer", true, false)
	return found[0] as AnimationPlayer if not found.is_empty() else null

func _play(who: Node3D, clip: String) -> void:
	var ap := _anim(who) if who else null
	if ap != null and ap.has_animation(clip):
		ap.play(clip, 0.3)

# ───────────────────────────── jugador ─────────────────────────────

func _setup_player() -> void:
	player = get_node("Player") as CharacterBody3D
	hud = get_node("HUD")
	var ui_manager := UIManager.new()
	ui_manager.name = "UIManager"
	add_child(ui_manager)
	ui_manager.initialize(hud, player)
	var inv = player.get("inventory")
	if inv and inv.has_method("clear_items"):
		inv.clear_items()
	var winv = player.get("weapon_inventory")
	if winv and winv.has_method("reset_progress"):
		winv.reset_progress()
	GameData.apply_to_player(player)
	var eq = player.get("equipment")
	if eq:
		eq.start_run()
	var sb = player.get("stat_block")
	if sb and sb.has_method("rebase_equipment_hp"):
		sb.rebase_equipment_hp()
	player.global_position = PLAYER_START
	player.hp = player.max_hp
	player.emit_signal("stats_changed", player.hp, player.max_hp)
	ui_manager.refresh_weapon_ui()
	_last_pos = player.global_position
	var pc = player.get("parry_controller")
	if pc:
		pc.parried.connect(func(_a): director.report("parry"))

# ───────────────────────────── interfaz ─────────────────────────────

func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.09, 0.82)
	sb.border_color = Color(1.0, 0.78, 0.3, 0.9)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 30
	add_child(_ui)
	# Pista del paso (arriba al centro)
	_hint_panel = PanelContainer.new()
	_hint_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_hint_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint_panel.position.y = 56
	_hint_panel.add_theme_stylebox_override("panel", _panel_style())
	_hint_panel.visible = false
	_hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	_hint_title = Label.new()
	_hint_title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.4))
	_hint_title.add_theme_font_size_override("font_size", 16)
	_hint_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_text = Label.new()
	_hint_text.add_theme_font_size_override("font_size", 14)
	_hint_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_bar = ProgressBar.new()
	_hint_bar.custom_minimum_size = Vector2(260, 12)
	_hint_bar.show_percentage = false
	vb.add_child(_hint_title)
	vb.add_child(_hint_text)
	vb.add_child(_hint_bar)
	_hint_panel.add_child(vb)
	_ui.add_child(_hint_panel)
	# Subtítulos (abajo)
	_sub_panel = PanelContainer.new()
	_sub_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_sub_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_sub_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_sub_panel.position.y = -130
	_sub_panel.add_theme_stylebox_override("panel", _panel_style())
	_sub_panel.visible = false
	_sub_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sv := VBoxContainer.new()
	_sub_name = Label.new()
	_sub_name.add_theme_font_size_override("font_size", 14)
	_sub_text = Label.new()
	_sub_text.add_theme_font_size_override("font_size", 16)
	_sub_text.custom_minimum_size = Vector2(520, 0)
	_sub_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sv.add_child(_sub_name)
	sv.add_child(_sub_text)
	_sub_panel.add_child(sv)
	_ui.add_child(_sub_panel)
	# Botón de saltar (arriba a la derecha)
	var skip := Button.new()
	skip.name = "SkipButton"
	skip.text = "SALTAR TUTORIAL ▶"
	skip.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	skip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	skip.position = Vector2(-16, 16)
	skip.focus_mode = Control.FOCUS_NONE
	skip.pressed.connect(_on_skip_pressed)
	_ui.add_child(skip)
	_skip_btn = skip
	for top in [true, false]:   # bandas de cine (solo en la invocación)
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.set_anchors_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
		bar.offset_top = 0.0 if top else -64.0
		bar.offset_bottom = 64.0 if top else 0.0
		bar.visible = false
		_ui.add_child(bar)
		_letterbox.append(bar)
	# Fundido
	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_fade)
	_voice = AudioStreamPlayer.new()
	_voice.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	add_child(_voice)

## Móvil: joystick y botones de combate (como en la mazmorra). La escena no pasa por GameStartFacade,
## que es quien los crea en las partidas, así que se añaden aquí. Ocultos durante la cinemática.
func _build_touch_controls() -> void:
	if not Quality.is_mobile():
		return
	_touch_controls = load("res://scripts/ui/mobile_controls.gd").new()
	_touch_controls.name = "MobileControls"
	_touch_controls.mode = "dungeon"
	_touch_controls.visible = false
	add_child(_touch_controls)

func _set_touch_visible(on: bool) -> void:
	if is_instance_valid(_touch_controls):
		_touch_controls.visible = on

## Texto del paso según la plataforma ("text_touch" en móvil si el paso lo trae).
static func step_text(st: Dictionary) -> String:
	if Quality.is_mobile() and st.has("text_touch"):
		return String(st["text_touch"])
	return String(st["text"])

func _say(who: String, text: String) -> float:
	var sp: Array = SPEAKERS[who]
	_sub_name.text = String(sp[0])
	_sub_name.add_theme_color_override("font_color", sp[1])
	_sub_text.text = text
	_sub_panel.visible = true
	var wav := Murmur.make(text, who)
	if wav:
		_voice.stream = wav
		_voice.volume_db = -4.0
		_voice.play()
	return maxf(2.2, text.length() * 0.055)

func _dialogue(lines: Array) -> void:
	for l in lines:
		if leaving:
			return
		await get_tree().create_timer(_say(String(l[0]), String(l[1]))).timeout
	_sub_panel.visible = false

# ───────────────────────────── flujo ─────────────────────────────

func _intro() -> void:
	start_cinematic()

func _on_skip_pressed() -> void:
	if cinematic:
		cine.skip()
	else:
		skip_tutorial()

## La invocación: sin control del jugador, con bandas de cine y la cámara de la cinemática.
func start_cinematic() -> void:
	cinematic = true
	_skip_btn.text = "SALTAR INTRO ▶"
	hud.visible = false
	for b in _letterbox:
		b.visible = true
	player.visible = false
	player.process_mode = Node.PROCESS_MODE_DISABLED
	_set_touch_visible(false)
	cine.start()

func _end_cinematic() -> void:
	if not cinematic or leaving:
		return
	cinematic = false
	_sub_panel.visible = false
	_skip_btn.text = "SALTAR TUTORIAL ▶"
	for b in _letterbox:
		b.visible = false
	hud.visible = true
	player.visible = true
	player.process_mode = Node.PROCESS_MODE_INHERIT
	_set_touch_visible(true)
	if player.camera:
		player.camera.make_current()
	_last_pos = player.global_position
	if director.index < 0:
		director.start()

func _on_step_changed(i: int) -> void:
	var st: Dictionary = TutorialDirector.STEPS[i]
	_hint_title.text = st["title"]
	_hint_text.text = step_text(st)
	_hint_bar.max_value = float(st["goal"])
	_hint_bar.value = 0.0
	_hint_panel.visible = true
	if i > 0:
		AudioManager.play("coin", -4.0, 1.2)
	_last_pos = player.global_position
	_spawn_for_step(String(st["id"]))

func _on_progressed(p: float, _g: float) -> void:
	_hint_bar.value = p

func _on_finished() -> void:
	if leaving:
		return
	_hint_panel.visible = false
	_clear_goblin()
	_finish_with_dialogue()

func _finish_with_dialogue() -> void:
	if not skipped:
		await _dialogue(OUTRO)
	_leave()

var skipped := false

## Saltar el tutorial (botón): marca como hecho y va directo al salón.
func skip_tutorial() -> void:
	if leaving:
		return
	skipped = true
	if cinematic:
		cine.running = false
		cinematic = false
		hud.visible = true
		player.visible = true
		player.process_mode = Node.PROCESS_MODE_INHERIT
		for b in _letterbox:
			b.visible = false
		if player.camera:
			player.camera.make_current()
	if director.index < 0:
		director.start()
	director.skip_all()

func _leave() -> void:
	if leaving:
		return
	leaving = true
	_set_touch_visible(false)
	DungeonHub.set_tutorial_done(true)
	_clear_goblin()
	_hint_panel.visible = false
	_sub_panel.visible = false
	AudioManager.play("impact_magic", 2.0, 0.8)
	_fade.color = Color(0.8, 0.92, 1.0, 0.0)
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.6)
	tw.tween_callback(func():
		MusicDirector.stop(0.3)
		finished.emit()
		SceneLoader.load_scene(HUB))

# ───────────────────────────── enemigo de práctica ─────────────────────────────

func _spawn_for_step(id: String) -> void:
	_clear_goblin()
	match id:
		"golpear":
			_spawn_goblin(Vector3(0, 0.1, 1.0), true)
		"esquivar", "parry", "combate":
			_spawn_goblin(Vector3(0, 0.1, -3.0), false)

func _spawn_goblin(pos: Vector3, passive: bool) -> void:
	var g := NetWorld.create_enemy("goblin") as DungeonGoblin
	g.name = "GoblinPractica"
	g.passive = passive
	if passive:
		g.hp_mult = 60.0
	else:
		g.damage_mult = 0.35
	add_child(g)
	g.global_position = pos
	g.died.connect(func(_d): director.report("kill"))
	goblin = g
	_last_gob_hp = g.hp
	SpawnDissolve.play(g.get_model(), g, 0.9, Color(1.0, 0.25, 0.1), 1.4)

func _clear_goblin() -> void:
	if is_instance_valid(goblin):
		goblin.queue_free()
	goblin = null

# ───────────────────────────── seguimiento ─────────────────────────────

func _process(_delta: float) -> void:
	if leaving or not is_instance_valid(player):
		return
	# Que el tutorial no mate: se cura al bajar de un tercio
	if player.hp < player.max_hp * 0.35:
		player.heal(player.max_hp)
	if director.index < 0 or director.done:
		return
	match String(director.current().get("id", "")):
		"mover":
			var p := player.global_position
			var d := Vector2(p.x - _last_pos.x, p.z - _last_pos.z).length()
			_last_pos = p
			if d < 2.0:
				director.report("move", d)
		"golpear":
			if is_instance_valid(goblin):
				if goblin.hp < _last_gob_hp - 0.01:
					director.report("hit")
				if goblin.hp < goblin.max_hp * 0.6:
					goblin.hp = goblin.max_hp
				_last_gob_hp = goblin.hp
		"esquivar":
			_watch_dodge()
			_respawn_if_dead()
		"parry":
			_respawn_if_dead()

func _watch_dodge() -> void:
	var mc = player.get("movement_controller")
	if mc == null:
		return
	var dodging: bool = mc.is_dodging()
	if dodging and not _was_dodging and is_instance_valid(goblin) \
			and (goblin.state == DungeonGoblin.State.WINDUP or goblin.state == DungeonGoblin.State.ATTACK) \
			and goblin.global_position.distance_to(player.global_position) < 6.0:
		director.report("dodge")
	_was_dodging = dodging

## En esquivar y parry, si el goblin cae por los golpes del jugador aparece otro (no cuenta como baja).
func _respawn_if_dead() -> void:
	if goblin == null or (is_instance_valid(goblin) and not goblin.is_dead()):
		return
	_spawn_goblin(Vector3(0, 0.1, -3.0), false)
