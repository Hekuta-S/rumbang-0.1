extends Node

## Modos de resolución (Quality.RES_*): nativa, reducida y alturas 3D fijas (1080p/900p/720p/540p).
## Comprueba que solo se ofrecen las alturas que caben en la ventana, que el modo fijo pasa a stretch
## "viewport" y dibuja el 3D a esa altura (sin pasar de la pantalla) y que nativa lo devuelve todo.
var _fail := false
var _n := 0

func _check(ok: bool, msg: String) -> void:
	_n += 1
	print("CHECK %d %s: %s" % [_n, "PASSED" if ok else "FAILED", msg])
	if not ok:
		_fail = true

func _ready() -> void:
	await get_tree().process_frame     # SettingsManager aplica la resolución guardada en diferido
	var win := get_tree().root
	var saved := Quality.resolution_mode()
	var screen_h := win.size.y
	print("ventana: %s" % str(win.size))

	var modes := Quality.resolution_modes_available()
	_check(modes[0] == Quality.RES_NATIVE and modes[1] == Quality.RES_REDUCED, "nativa y reducida siempre están")
	var fits := true
	for m in modes:
		var h := int(Quality.RES_HEIGHTS.get(m, 0))
		fits = fits and h <= screen_h
	_check(fits, "no se ofrecen alturas mayores que la ventana (%d filas): %s" % [screen_h, str(modes)])
	_check(Quality.resolution_label(Quality.RES_900) == "900p" and Quality.resolution_label(Quality.RES_NATIVE) == "Nativa", "etiquetas")

	Quality.apply_resolution(Quality.RES_540)
	await get_tree().process_frame
	_check(win.content_scale_mode == Window.CONTENT_SCALE_MODE_VIEWPORT, "modo fijo usa stretch viewport")
	_check(Quality.fixed_height() == 540, "altura fija 540")
	var vis_h := win.get_visible_rect().size.y
	var rows := vis_h * win.scaling_3d_scale
	# --headless usa una ventana de 64×64: la escala choca con el mínimo de Godot (0.25). Ahí no se mide.
	var real_window := screen_h >= 540
	if real_window:
		_check(absf(rows - 540.0) < 2.0, "el 3D se dibuja a ~540 filas (%.1f)" % rows)
	else:
		print("SKIP: ventana de %d filas (headless); ejecutar con ventana para medir las filas" % screen_h)
	_check(is_equal_approx(Quality.scale_3d_floor(), Quality.scale_3d() * 0.7), "la gobernadora solo baja un 30 %")

	Quality.apply_resolution(Quality.RES_1080)
	await get_tree().process_frame
	rows = win.get_visible_rect().size.y * win.scaling_3d_scale
	if real_window:
		_check(rows <= float(screen_h) + 2.0, "1080p nunca supera la ventana (%.1f <= %d)" % [rows, screen_h])

	Quality.apply_resolution(99)
	_check(Quality.resolution_mode() == Quality.RES_NATIVE, "modo inválido -> nativa")
	await get_tree().process_frame
	_check(win.content_scale_mode == Window.CONTENT_SCALE_MODE_CANVAS_ITEMS and Quality.fixed_height() == 0, "nativa vuelve a canvas_items y la calidad manda")

	Quality.apply_resolution(saved)
	print("ALL PASSED" if not _fail else "SOME FAILED")
	get_tree().quit(1 if _fail else 0)
