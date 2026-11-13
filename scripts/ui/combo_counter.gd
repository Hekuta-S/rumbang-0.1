class_name ComboCounter
extends Control

## Fase 4 del plan de juice (docs/PLAN_JUICE.md): contador de combo de la mazmorra (a la derecha).
## Cada golpe directo suma 1 (y 1 más si mata); si pasan WINDOW s sin golpear, el combo se cae.
## Rangos D → C → B → A → S según los golpes: la letra crece y cambia de color, y al subir de rango
## suena y salta. Si te golpean, el combo se rompe ("ROTO" en rojo, temblando).
## Lo alimenta HitFeedback (register_hit / break_combo); solo existe en la mazmorra.

const WINDOW := 3.0                  ## s sin golpear antes de que se caiga
const MIN_SHOW := 3                  ## golpes para que aparezca
## [golpes mínimos, letra, color]
const RANKS := [
	[0, "", Color(0.75, 0.78, 0.85)],
	[5, "D", Color(0.6, 0.72, 0.95)],
	[12, "C", Color(0.35, 0.9, 1.0)],
	[22, "B", Color(0.4, 1.0, 0.5)],
	[35, "A", Color(1.0, 0.65, 0.2)],
	[55, "S", Color(1.0, 0.3, 0.75)],
]

static var _inst: ComboCounter

var count := 0
var _timer := 0.0
var _rank := 0
var _ending := false
var _rank_lbl: Label
var _count_lbl: Label

## Pura: índice de RANKS para `hits` golpes.
static func rank_for(hits: int) -> int:
	var r := 0
	for i in RANKS.size():
		if hits >= int(RANKS[i][0]):
			r = i
	return r

static func register_hit(killed: bool) -> void:
	if is_instance_valid(_inst):
		_inst._hit(killed)

static func break_combo() -> void:
	if is_instance_valid(_inst):
		_inst._end(true)

func _ready() -> void:
	_inst = self
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	offset_left = -210.0
	offset_right = -28.0
	offset_top = -150.0
	offset_bottom = -30.0
	_rank_lbl = _make_label(64)
	_rank_lbl.position = Vector2(0, 0)
	_rank_lbl.size = Vector2(182, 72)
	_count_lbl = _make_label(26)
	_count_lbl.position = Vector2(0, 70)
	_count_lbl.size = Vector2(182, 32)
	visible = false

func _exit_tree() -> void:
	if _inst == self:
		_inst = null

func _make_label(font_size: int) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.06))
	l.add_theme_constant_override("outline_size", 10)
	add_child(l)
	return l

func _hit(killed: bool) -> void:
	if _ending:
		_reset()
	count += 2 if killed else 1
	_timer = WINDOW
	var r := rank_for(count)
	var col: Color = RANKS[r][2]
	if count >= MIN_SHOW:
		visible = true
		modulate.a = 1.0
	_count_lbl.text = "x%d" % count
	_count_lbl.add_theme_color_override("font_color", Color.WHITE.lerp(col, 0.4))
	_rank_lbl.text = String(RANKS[r][1])
	_rank_lbl.add_theme_color_override("font_color", col)
	_rank_lbl.add_theme_font_size_override("font_size", 52 + r * 6)
	UiJuice.punch(_count_lbl, 1.35, 0.18)
	if r > _rank:
		UiJuice.punch(_rank_lbl, 1.8, 0.35)
		AudioManager.play("orb_cast", -9.0, 1.0 + 0.12 * r)
	_rank = r
	queue_redraw()

## Fin del combo: si `broken` (te golpearon) se marca en rojo y tiembla; si no, se desvanece sin más.
func _end(broken: bool) -> void:
	if count < MIN_SHOW or _ending:
		_reset()
		visible = false
		return
	_ending = true
	_timer = 0.0
	var tw := create_tween()
	if broken:
		_count_lbl.text = "ROTO"
		_count_lbl.add_theme_color_override("font_color", Color(1.0, 0.25, 0.2))
		AudioManager.play("goblin_hurt", -14.0, 1.6)
		for i in 6:
			tw.tween_property(self, "position:x", position.x + (8.0 if i % 2 == 0 else -8.0), 0.035)
		tw.tween_property(self, "position:x", position.x, 0.035)
	tw.tween_interval(0.35 if broken else 0.0)
	tw.tween_property(self, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func():
		visible = false
		_reset())

func _reset() -> void:
	count = 0
	_rank = 0
	_ending = false
	modulate.a = 1.0

func _process(delta: float) -> void:
	if count == 0 or _ending:
		return
	_timer -= delta
	if _timer <= 0.0:
		_end(false)
	elif visible:
		queue_redraw()

## Barra de tiempo restante bajo el contador.
func _draw() -> void:
	if count < MIN_SHOW or _ending:
		return
	var col: Color = RANKS[_rank][2]
	var w := 140.0
	var r := Rect2(size.x - w, 106.0, w, 5.0)
	draw_rect(r, Color(0, 0, 0, 0.55))
	draw_rect(Rect2(r.position, Vector2(w * clampf(_timer / WINDOW, 0.0, 1.0), r.size.y)), col)
