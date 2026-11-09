extends Control

## Línea de tiempo de una animación de ataque para tools/melee_grip_editor.gd.
## Muestra los fotogramas (a `fps`), el cabezal y las ventanas de daño (rojo), que se arrastran por los bordes o
## enteras. La ventana de enlace (azul) y las de la tabla original (contorno discontinuo) son solo de referencia.
##
## Ratón: clic/arrastre en vacío = mover el cabezal · arrastrar borde = cambiar inicio/fin · arrastrar ventana =
## moverla · doble clic en vacío = nueva ventana · clic derecho en una ventana = quitarla. Shift = sin imán a fotograma.

signal scrubbed(time: float)
signal windows_edited
signal selection_changed(index: int)

const RULER_H := 22.0
const PAD_X := 12.0
const HANDLE_PX := 7.0
const NEW_WINDOW_FRAMES := 6.0

const COL_BG := Color(0.06, 0.065, 0.08, 1.0)
const COL_TRACK := Color(0.11, 0.12, 0.145, 1.0)
const COL_TICK := Color(1, 1, 1, 0.16)
const COL_TICK_MAJOR := Color(1, 1, 1, 0.38)
const COL_TEXT := Color(1, 1, 1, 0.6)
const COL_HIT := Color(0.93, 0.27, 0.24)
const COL_LINK := Color(0.32, 0.6, 0.95)
const COL_GHOST := Color(1, 1, 1, 0.45)
const COL_HEAD := Color(1.0, 0.78, 0.3)

var fps := 30.0
var length := 1.0                    ## duración del clip (s)
var time := 0.0                      ## cabezal (s)
var windows: Array = []              ## [[ini_s, fin_s], ...] — se edita aquí
var original: Array = []             ## ventanas de la tabla del código (referencia)
var link_window: Array = []          ## [ini_s, fin_s] o vacío
var selected := -1

var _drag := ""                      ## "", "head", "start", "end", "move"
var _drag_index := -1
var _drag_grab := 0.0
var _hover_index := -1
var _hover_part := ""

func _ready() -> void:
	custom_minimum_size = Vector2(300, 92)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_CLICK
	clip_contents = true

func set_clip(clip_length: float, clip_windows: Array, table_windows: Array, link: Array) -> void:
	length = maxf(clip_length, 1.0 / fps)
	windows = clip_windows
	original = table_windows
	link_window = link
	selected = 0 if not windows.is_empty() else -1
	time = clampf(time, 0.0, length)
	queue_redraw()

func frame_count() -> int:
	return maxi(int(ceil(length * fps - 0.001)), 1)

func is_time_active(t: float) -> bool:
	for w in windows:
		if t >= float(w[0]) and t <= float(w[1]):
			return true
	return false

# ── Geometría ────────────────────────────────────────────────────────────────

func _track_rect() -> Rect2:
	return Rect2(PAD_X, RULER_H, size.x - PAD_X * 2.0, size.y - RULER_H - 6.0)

func _t_to_x(t: float) -> float:
	var r := _track_rect()
	return r.position.x + (t / length) * r.size.x

func _x_to_t(x: float) -> float:
	var r := _track_rect()
	return clampf((x - r.position.x) / maxf(r.size.x, 1.0) * length, 0.0, length)

func _snap(t: float) -> float:
	if Input.is_key_pressed(KEY_SHIFT):
		return t
	return clampf(round(t * fps) / fps, 0.0, length)

func _hit_test(pos: Vector2) -> Array:
	## [índice, parte] de la ventana bajo el ratón; parte = "start", "end" o "move".
	var r := _track_rect()
	if pos.y < r.position.y:
		return [-1, ""]
	for i in range(windows.size() - 1, -1, -1):
		var x0 := _t_to_x(float(windows[i][0]))
		var x1 := _t_to_x(float(windows[i][1]))
		if absf(pos.x - x0) <= HANDLE_PX:
			return [i, "start"]
		if absf(pos.x - x1) <= HANDLE_PX:
			return [i, "end"]
		if pos.x > x0 and pos.x < x1:
			return [i, "move"]
	return [-1, ""]

# ── Entrada ──────────────────────────────────────────────────────────────────

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				var hit := _hit_test(mb.position)
				if mb.double_click and hit[0] < 0:
					_add_window_at(_snap(_x_to_t(mb.position.x)))
				elif hit[0] >= 0:
					_select(hit[0])
					_drag = hit[1]
					_drag_index = hit[0]
					_drag_grab = _x_to_t(mb.position.x) - float(windows[hit[0]][0])
				else:
					_drag = "head"
					_set_time(_snap(_x_to_t(mb.position.x)))
			else:
				if _drag in ["start", "end", "move"]:
					windows_edited.emit()
				_drag = ""
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			var hit := _hit_test(mb.position)
			if hit[0] >= 0:
				remove_window(hit[0])
			accept_event()
		elif mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and mb.pressed:
			var step := 1.0 / fps * (1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1.0)
			_set_time(clampf(round((time + step) * fps) / fps, 0.0, length))
			accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _drag == "head":
			_set_time(_snap(_x_to_t(mm.position.x)))
		elif _drag != "" and _drag_index >= 0 and _drag_index < windows.size():
			_drag_window(_x_to_t(mm.position.x))
		else:
			var hit := _hit_test(mm.position)
			if hit[0] != _hover_index or hit[1] != _hover_part:
				_hover_index = hit[0]
				_hover_part = hit[1]
				queue_redraw()
			mouse_default_cursor_shape = Control.CURSOR_HSIZE if _hover_part in ["start", "end"] \
				else (Control.CURSOR_MOVE if _hover_part == "move" else Control.CURSOR_ARROW)

func _drag_window(t: float) -> void:
	var w: Array = windows[_drag_index]
	var min_len := 1.0 / fps
	match _drag:
		"start":
			w[0] = clampf(_snap(t), 0.0, float(w[1]) - min_len)
		"end":
			w[1] = clampf(_snap(t), float(w[0]) + min_len, length)
		"move":
			var span := float(w[1]) - float(w[0])
			var s := clampf(_snap(t - _drag_grab), 0.0, length - span)
			w[0] = s
			w[1] = s + span
	queue_redraw()
	windows_edited.emit()

func _set_time(t: float) -> void:
	time = t
	queue_redraw()
	scrubbed.emit(time)

func _select(index: int) -> void:
	if selected != index:
		selected = index
		selection_changed.emit(index)
	queue_redraw()

# ── Edición desde fuera (botones del editor) ─────────────────────────────────

func _add_window_at(t: float) -> void:
	var span := NEW_WINDOW_FRAMES / fps
	var s := clampf(t, 0.0, maxf(length - span, 0.0))
	windows.append([s, minf(s + span, length)])
	windows.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	for i in windows.size():
		if is_equal_approx(float(windows[i][0]), s):
			_select(i)
			break
	queue_redraw()
	windows_edited.emit()

func add_window_at_head() -> void:
	_add_window_at(time)

func remove_window(index: int) -> void:
	if index < 0 or index >= windows.size():
		return
	windows.remove_at(index)
	_select(mini(index, windows.size() - 1))
	queue_redraw()
	windows_edited.emit()

func set_selected_edge(edge: int, t: float) -> void:
	if selected < 0 or selected >= windows.size():
		return
	var w: Array = windows[selected]
	var min_len := 1.0 / fps
	if edge == 0:
		w[0] = clampf(t, 0.0, float(w[1]) - min_len)
	else:
		w[1] = clampf(t, float(w[0]) + min_len, length)
	queue_redraw()
	windows_edited.emit()

func set_time_external(t: float) -> void:
	time = clampf(t, 0.0, length)
	queue_redraw()

# ── Dibujo ───────────────────────────────────────────────────────────────────

func _draw() -> void:
	var font := get_theme_default_font()
	var fsize := 11
	draw_rect(Rect2(Vector2.ZERO, size), COL_BG)
	var r := _track_rect()
	draw_rect(r, COL_TRACK)

	# Regla de fotogramas: marca cada fotograma si caben, número cada 5 o 10
	var frames := frame_count()
	var px_per_frame := r.size.x / maxf(length * fps, 1.0)
	var label_every := 5 if px_per_frame >= 7.0 else (10 if px_per_frame >= 3.0 else 20)
	for f in frames + 1:
		var x := _t_to_x(minf(float(f) / fps, length))
		var major := f % label_every == 0
		if px_per_frame >= 3.0 or major:
			draw_line(Vector2(x, RULER_H - (9.0 if major else 4.0)), Vector2(x, RULER_H), COL_TICK_MAJOR if major else COL_TICK)
		if major:
			draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), Color(1, 1, 1, 0.04))
			var tw := font.get_string_size(str(f), HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
			var tx := x + 2.0 if x + 2.0 + tw <= size.x - 2.0 else x - 2.0 - tw
			draw_string(font, Vector2(tx, RULER_H - 9.0), str(f), HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, COL_TEXT)

	# Ventana de enlace (abajo, azul)
	if link_window.size() >= 2:
		var lx0 := _t_to_x(float(link_window[0]))
		var lx1 := _t_to_x(minf(float(link_window[1]), length))
		var lr := Rect2(lx0, r.end.y - 9.0, maxf(lx1 - lx0, 1.0), 7.0)
		draw_rect(lr, Color(COL_LINK, 0.55))

	# Ventanas de la tabla original (contorno discontinuo, referencia)
	for w in original:
		var gx0 := _t_to_x(float(w[0]))
		var gx1 := _t_to_x(minf(float(w[1]), length))
		var gy0 := r.position.y + 4.0
		var gy1 := r.end.y - 14.0
		for pts in [[Vector2(gx0, gy0), Vector2(gx1, gy0)], [Vector2(gx0, gy1), Vector2(gx1, gy1)],
				[Vector2(gx0, gy0), Vector2(gx0, gy1)], [Vector2(gx1, gy0), Vector2(gx1, gy1)]]:
			draw_dashed_line(pts[0], pts[1], COL_GHOST, 1.0, 4.0)

	# Ventanas de daño
	for i in windows.size():
		var x0 := _t_to_x(float(windows[i][0]))
		var x1 := _t_to_x(float(windows[i][1]))
		var wr := Rect2(x0, r.position.y + 6.0, maxf(x1 - x0, 2.0), r.size.y - 22.0)
		var sel := i == selected
		var hover := i == _hover_index
		draw_rect(wr, Color(COL_HIT, 0.42 if sel else (0.32 if hover else 0.24)))
		draw_rect(wr, Color(COL_HIT, 1.0 if sel else 0.7), false, 2.0 if sel else 1.0)
		for edge in [[x0, "start"], [x1, "end"]]:
			var hot: bool = hover and _hover_part == edge[1]
			var hr := Rect2(float(edge[0]) - 3.0, wr.position.y + wr.size.y * 0.25, 6.0, wr.size.y * 0.5)
			draw_rect(hr, Color(1, 1, 1, 0.95) if hot or sel else Color(COL_HIT, 0.95))
		var f0 := int(round(float(windows[i][0]) * fps))
		var f1 := int(round(float(windows[i][1]) * fps))
		var tag := "%d–%d" % [f0, f1]
		if wr.size.x > 44.0:
			draw_string(font, Vector2(wr.position.x + 6.0, wr.position.y + 14.0), tag,
				HORIZONTAL_ALIGNMENT_LEFT, wr.size.x - 8.0, fsize, Color(1, 1, 1, 0.92))

	# Cabezal
	var hx := _t_to_x(time)
	var active := is_time_active(time)
	var hc := COL_HIT.lightened(0.25) if active else COL_HEAD
	draw_line(Vector2(hx, 2.0), Vector2(hx, size.y), hc, 2.0)
	draw_colored_polygon(PackedVector2Array([Vector2(hx - 6, 2), Vector2(hx + 6, 2), Vector2(hx, 11)]), hc)
