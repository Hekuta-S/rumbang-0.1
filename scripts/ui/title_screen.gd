class_name TitleScreen
extends Control

## Pantalla de título (la primera al abrir el juego): panorama del mapa al estilo Minecraft
## (MenuBackground: la cámara orbita despacio sobre el mapa procedural), el logo y
## "Presiona cualquier tecla para continuar" ("Toca para continuar" en móvil). Cualquier tecla, clic,
## toque o botón del mando funde a negro y pasa al Salón de la Invocación (DungeonHub), que la primera
## vez empieza con la intro. Desde el salón, Esc vuelve aquí.

const Style := preload("res://scripts/ui/rumbang_style.gd")
const HUB := "res://scenes/ui/dungeon_hub.tscn"

signal continued

var leaving := false
var prompt: Label
var _bg_container: SubViewportContainer
var _fade: ColorRect
var _time := 0.0

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	theme = Style.get_theme()
	set_anchors_preset(PRESET_FULL_RECT)
	_build()
	_fade.color.a = 1.0
	create_tween().tween_property(_fade, "color:a", 0.0, 1.0)

static func prompt_text() -> String:
	return "Toca para continuar" if Quality.is_mobile() or DisplayServer.is_touchscreen_available() and not OS.has_feature("pc") \
		else "Presiona cualquier tecla para continuar"

func _build() -> void:
	var fallback := ColorRect.new()
	fallback.set_anchors_preset(PRESET_FULL_RECT)
	fallback.color = Style.BG
	add_child(fallback)

	_bg_container = SubViewportContainer.new()
	_bg_container.set_anchors_preset(PRESET_FULL_RECT)
	_bg_container.stretch = true
	_bg_container.stretch_shrink = 2 if Quality.is_mobile() else 1
	_bg_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg_container)
	var vp := SubViewport.new()
	vp.handle_input_locally = false
	vp.msaa_3d = Viewport.MSAA_DISABLED if Quality.is_mobile() else Viewport.MSAA_2X
	_bg_container.add_child(vp)
	var bg3d := MenuBackground.new()
	vp.add_child(bg3d)
	bg3d.fade_requested.connect(func(to_black: bool, d: float):
		create_tween().tween_property(_bg_container, "modulate", Color(0, 0, 0, 1) if to_black else Color.WHITE, d))

	# viñeta: centro claro, bordes oscuros
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0.1))
	grad.set_color(1, Color(0.02, 0.01, 0.05, 0.8))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.9)
	var vignette := TextureRect.new()
	vignette.texture = tex
	vignette.set_anchors_preset(PRESET_FULL_RECT)
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)

	var col := VBoxContainer.new()
	col.set_anchors_preset(PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 16)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	var logo := Label.new()
	logo.name = "Logo"
	logo.text = "RUMBANG"
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	logo.add_theme_font_override("font", Style.FONT)
	logo.add_theme_font_size_override("font_size", 84)
	logo.add_theme_color_override("font_color", Style.TITLE)
	logo.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.10))
	logo.add_theme_constant_override("outline_size", 16)
	logo.add_theme_color_override("font_shadow_color", Color(Style.GLOW, 0.8))
	logo.add_theme_constant_override("shadow_offset_x", 0)
	logo.add_theme_constant_override("shadow_offset_y", 8)
	logo.add_theme_constant_override("shadow_outline_size", 18)
	col.add_child(logo)
	var pulse := create_tween().set_loops()
	pulse.tween_property(logo, "theme_override_colors/font_shadow_color", Color(Style.NEON_MAGENTA, 0.4), 1.6).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(logo, "theme_override_colors/font_shadow_color", Color(Style.GLOW, 0.85), 1.6).set_trans(Tween.TRANS_SINE)
	var sub := Label.new()
	sub.text = "Dark Fantasy Roguelike"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 16)
	sub.add_theme_color_override("font_color", Style.TEXT_DIM)
	col.add_child(sub)

	prompt = Label.new()
	prompt.name = "Continuar"
	prompt.text = prompt_text()
	prompt.set_anchors_preset(PRESET_CENTER_BOTTOM)
	prompt.offset_left = -400
	prompt.offset_right = 400
	prompt.offset_top = -120
	prompt.offset_bottom = -90
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_font_size_override("font_size", 16)
	prompt.add_theme_color_override("font_color", Color(1.0, 0.92, 0.6))
	prompt.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.10))
	prompt.add_theme_constant_override("outline_size", 8)
	prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(prompt)

	var ver := Label.new()
	ver.text = "v0.1 - Alpha"
	ver.set_anchors_preset(PRESET_BOTTOM_RIGHT)
	ver.offset_left = -260
	ver.offset_top = -36
	ver.offset_right = -16
	ver.offset_bottom = -12
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ver.add_theme_font_size_override("font_size", 11)
	ver.add_theme_color_override("font_color", Style.TEXT_DIM)
	add_child(ver)

	_fade = ColorRect.new()
	_fade.set_anchors_preset(PRESET_FULL_RECT)
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)

func _process(delta: float) -> void:
	_time += delta
	if prompt and not leaving:
		prompt.modulate.a = 0.35 + 0.65 * (0.5 + 0.5 * sin(_time * 3.2))   # parpadeo suave

func _input(event: InputEvent) -> void:
	if leaving:
		return
	var pressed: bool = (event is InputEventKey and event.pressed and not event.echo) \
		or (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed) \
		or (event is InputEventJoypadButton and event.pressed)
	if pressed and _time > 0.3:
		get_viewport().set_input_as_handled()
		continue_to_hub()

## Funde a negro y pasa al Salón (lo usan también los tests sin cambiar de escena: change = false).
func continue_to_hub(change: bool = true) -> void:
	if leaving:
		return
	leaving = true
	AudioManager.play("ui_click", -4.0)
	prompt.modulate.a = 1.0
	continued.emit()
	var t := create_tween()
	t.tween_property(_fade, "color:a", 1.0, 0.6)
	if change:
		t.tween_callback(func(): SceneLoader.load_scene(HUB))
