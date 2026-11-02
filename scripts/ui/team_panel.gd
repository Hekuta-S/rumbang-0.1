class_name TeamPanel
extends Control

## Compañeros de la partida en red: nombre y barra de vida de cada uno (arriba a la derecha, bajo los FPS).

const W := 200.0
const ROW_H := 30.0
const BAR_H := 8.0
const PAD := 8.0
const FRAME := Color(0.08, 0.07, 0.09, 0.82)
const BORDER := Color(0.62, 0.56, 0.47)
const HP_COLOR := Color(0.86, 0.16, 0.2)
const DOWN_COLOR := Color(0.45, 0.45, 0.5)

var _font: Font

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -W - PAD * 2.0 - 20.0
	offset_right = -20.0
	offset_top = 140.0 if Quality.is_mobile() else 60.0
	visible = Net.is_online()

func _process(_delta: float) -> void:
	if not visible:
		return
	var n := _mates().size()
	var h := PAD * 2.0 + ROW_H * n if n > 0 else 0.0
	offset_bottom = offset_top + h
	queue_redraw()

func _mates() -> Array:
	var world := get_tree().current_scene.get_node_or_null("NetWorld") if get_tree().current_scene else null
	var out: Array = []
	if world == null:
		return out
	for rp in world.remotes.values():
		if is_instance_valid(rp):
			out.append(rp)
	return out

func _draw() -> void:
	var mates := _mates()
	if mates.is_empty():
		return
	HudDraw.panel(self, Rect2(Vector2.ZERO, size), RumbangStyle.NEON_MAGENTA)
	var y := PAD
	for rp in mates:
		var down: bool = rp.is_dead()
		var ratio := clampf(rp.hp / maxf(rp.max_hp, 1.0), 0.0, 1.0)
		HudDraw.text(self, _font, Vector2(PAD, y + 11.0), ("%s%s" % [Net.name_of(rp.peer_id), "  (caído)" if down else ""]), 12, RumbangStyle.TEXT_DIM if down else Color(1, 1, 1, 0.95))
		HudDraw.bar(self, Rect2(PAD, y + 15.0, W, BAR_H), 0.0 if down else ratio, DOWN_COLOR if down else HP_COLOR, -1.0, 0.25)
		y += ROW_H
