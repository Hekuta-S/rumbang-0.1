class_name LoadingVisual
extends RefCounted

## Aspecto compartido de la pantalla de carga y de la tapa que la sustituye mientras la escena nueva se
## monta (SceneLoader.hold_cover): al ser idénticas, el cambio de escena no se nota.
## Crea bajo `root`: ColorRect, Title, VBoxContainer/{Label, ProgressBar, Tip}.

const Style := preload("res://scripts/ui/rumbang_style.gd")

const TITLES := {
	"dungeon_hub.tscn": "EL SALÓN",
	"character_select.tscn": "PERSONAJE",
	"tutorial_patio.tscn": "PATIO DE ENTRENAMIENTO",
	"main_procedural.tscn": "SUPERVIVENCIA",
}

const TIPS: Array[String] = [
	"Esquivar en el último momento te salva de casi todo.",
	"Un parry a tiempo deja al enemigo abierto.",
	"Solo conservas el equipo que llevas puesto al salir de la mazmorra.",
	"Los enemigos de élite pegan más fuerte, pero sueltan mejor botín.",
	"Rompe barriles y vasijas: a veces guardan algo útil.",
	"Cada arma tiene su propio combo. Prueba varias antes de elegir.",
]
const TIPS_PC: Array[String] = [
	"Pulsa C para fijar a un enemigo.",
	"Pulsa Q para cambiar de arma.",
	"Pulsa Tab para abrir el menú de pausa.",
]

static func title_for(path: String) -> String:
	var file := path.get_file()
	if TITLES.has(file):
		return TITLES[file]
	return "MAZMORRA" if GameData.game_mode == "dungeon" else "RUMBANG"

static func pick_tip() -> String:
	var pool: Array[String] = TIPS.duplicate()
	if not Quality.is_mobile():
		pool.append_array(TIPS_PC)
	return pool[randi() % pool.size()]

static func build(root: Control, title: String, tip: String, step: String, value: float) -> void:
	root.theme = Style.get_theme()

	var bg := ColorRect.new()
	bg.name = "ColorRect"
	bg.color = Style.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)

	var head := Label.new()
	head.name = "Title"
	head.text = title
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 26)
	head.add_theme_color_override("font_color", Style.TITLE)
	head.anchor_left = 0.0
	head.anchor_right = 1.0
	head.anchor_top = 0.4
	head.anchor_bottom = 0.4
	head.offset_top = -24.0
	head.offset_bottom = 24.0
	root.add_child(head)

	var box := VBoxContainer.new()
	box.name = "VBoxContainer"
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 0.8
	box.anchor_bottom = 0.8
	box.offset_left = -260.0
	box.offset_right = 260.0
	box.offset_top = -48.0
	box.offset_bottom = 48.0
	box.add_theme_constant_override("separation", 10)
	root.add_child(box)

	var label := Label.new()
	label.name = "Label"
	label.text = step
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Style.ACCENT)
	box.add_child(label)

	var bar := ProgressBar.new()
	bar.name = "ProgressBar"
	bar.custom_minimum_size = Vector2(0, 18)
	bar.value = value
	box.add_child(bar)

	var hint := Label.new()
	hint.name = "Tip"
	hint.text = tip
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Style.TEXT_DIM)
	box.add_child(hint)
