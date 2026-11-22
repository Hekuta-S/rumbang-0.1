class_name LevelUpBurst
extends Control

## Subida de nivel en estilo cómic: estallido de rayos dorados con borde de tinta y cartel "¡NIVEL!" que
## salta. Sustituye al confeti (120 nodos y 360 tweens de golpe, que además se quedaban congelados con el
## juego en pausa). Un solo Control que dibuja con _draw: sin nodos por pieza y sin tweens.
## Corre con el juego en pausa (lo usa la pantalla de cartas).

const LIFE := 0.95
const RAYS := 14
const GOLD := Color(1.0, 0.82, 0.25)
const GOLD_LIGHT := Color(1.0, 0.95, 0.65)
const INK := Color(0.06, 0.03, 0.05)

var _t := 0.0
var _label: Label
var _seed := randf() * TAU

static func play(parent: Control, text: String = "¡NIVEL!") -> LevelUpBurst:
	var b := LevelUpBurst.new()
	b.name = "LevelUpBurst"
	b.process_mode = Node.PROCESS_MODE_ALWAYS
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b._build_label(text)
	# Capa propia por encima de todo (el menú de cartas y su fondo oscuro tapaban el HUD)
	var layer := CanvasLayer.new()
	layer.name = "LevelUpBurstLayer"
	layer.layer = 110
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	layer.add_child(b)
	parent.get_tree().root.add_child.call_deferred(layer)     # diferido: la raíz puede estar montando hijos
	return b

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _build_label(text: String) -> void:
	_label = Label.new()
	_label.text = text
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	RumbangStyle.style_title(_label, 40, GOLD_LIGHT, INK)
	_label.theme = RumbangStyle.get_theme()
	add_child(_label)

func _process(delta: float) -> void:
	_t += delta
	if _t >= LIFE:
		get_parent().queue_free()
		return
	var c := _center()
	_label.size = Vector2(360, 56)
	_label.pivot_offset = _label.size * 0.5
	_label.position = c - _label.size * 0.5
	# Salta (sobrepasa y se asienta) y se desvanece al final
	var k := clampf(_t / 0.22, 0.0, 1.0)
	var pop := 1.0 + 0.35 * sin(k * PI) if k < 1.0 else 1.0
	_label.scale = Vector2.ONE * pop * lerpf(0.4, 1.0, k)
	_label.rotation = deg_to_rad(-4.0)
	_label.modulate.a = clampf((LIFE - _t) / 0.25, 0.0, 1.0)
	queue_redraw()

func _center() -> Vector2:
	var s := get_viewport_rect().size
	return Vector2(s.x * 0.5, s.y * 0.2)

func _draw() -> void:
	var c := _center()
	var p := clampf(_t / LIFE, 0.0, 1.0)
	var grow := 1.0 - pow(1.0 - clampf(p * 2.2, 0.0, 1.0), 3.0)     # sale rápido y frena
	var fade := clampf((1.0 - p) * 2.0, 0.0, 1.0)
	var inner := 34.0 + 30.0 * grow
	for i in RAYS:
		var a := _seed + TAU * float(i) / RAYS
		var long := (150.0 if i % 2 == 0 else 95.0) * grow
		var half := deg_to_rad(5.5 if i % 2 == 0 else 4.0)
		var pts := PackedVector2Array([
			c + Vector2(cos(a - half), sin(a - half)) * inner,
			c + Vector2(cos(a), sin(a)) * (inner + long),
			c + Vector2(cos(a + half), sin(a + half)) * inner])
		var outline := Color(INK, fade)
		draw_colored_polygon(_grow_poly(pts, c, 1.18), outline)
		draw_colored_polygon(pts, Color(GOLD, fade))
	draw_arc(c, inner, 0.0, TAU, 40, Color(INK, fade), 8.0)
	draw_arc(c, inner, 0.0, TAU, 40, Color(GOLD_LIGHT, fade), 4.0)

## Copia del triángulo algo más grande desde `c`: hace de borde de tinta.
func _grow_poly(pts: PackedVector2Array, c: Vector2, f: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v in pts:
		out.append(c + (v - c) * f)
	return out
