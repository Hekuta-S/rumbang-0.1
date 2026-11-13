extends "res://tools/melee_grip_editor.gd"
## Prueba visual del gizmo del editor de agarre (ventana, no headless): katana, mover/rotar/escalar con el gizmo,
## ocultar el menú. Guarda capturas en la ruta del primer argumento de usuario.

func _ready() -> void:
	super()
	_drive.call_deferred()

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)

func _drive() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://gz"
	for i in 900:
		await get_tree().process_frame
		if _gizmo != null and _anim_names.size() > 0:
			break
	_cat_select.select(CAT_KATANA)
	_on_category_selected(CAT_KATANA)
	for i in 10:
		await get_tree().process_frame
	var e0: Dictionary = _current_entry().duplicate()
	var h := _active_holder()
	var o: Vector2 = _cam.unproject_position(h.global_position)
	var ax: Vector2 = _cam.unproject_position(h.global_position + _gz_axes()[1] * _gizmo_size())
	# Mover por el eje Y del arma
	_set_gizmo_mode(GIZMO_MOVE)
	await get_tree().process_frame
	var mid := o.lerp(ax, 0.6)
	print("pick move: ", _pick_handle(mid))
	_begin_gizmo_drag(_pick_handle(mid), mid)
	_update_gizmo_drag(mid + (ax - o) * 0.5)
	_gz_drag = -1
	var e1: Dictionary = _current_entry().duplicate()
	print("MOVE pos ", e0["pos"], " -> ", e1["pos"])
	await _shot(out + "_move.png")
	# Escalar uniforme desde el centro
	_set_gizmo_mode(GIZMO_SCALE)
	await get_tree().process_frame
	o = _cam.unproject_position(h.global_position)
	_begin_gizmo_drag(3, o + Vector2(40, 0))
	_update_gizmo_drag(o + Vector2(60, 0))
	_gz_drag = -1
	print("SCALE ", _current_entry()["scale"], " holder basis len y ", h.transform.basis.y.length())
	# Rotar sobre el eje 0
	_set_gizmo_mode(GIZMO_ROTATE)
	await get_tree().process_frame
	var b0 := h.global_transform.basis
	_begin_gizmo_drag(0, o)
	_d_prev = 0.0
	_d_total = deg_to_rad(30.0) - 0.0
	_d_prev = _ring_angle(_d_origin, o + Vector2(0, -80))
	_d_total = deg_to_rad(30.0)
	_update_gizmo_drag(o + Vector2(0, -80))
	_gz_drag = -1
	var b1 := h.global_transform.basis
	var ang := rad_to_deg(b0.orthonormalized().get_rotation_quaternion().angle_to(b1.orthonormalized().get_rotation_quaternion()))
	print("ROTATE rot ", _current_entry()["rot"], " giro real %.1f°" % ang, " eje ", _d_axes[0])
	# Comprobar que el giro es alrededor del eje del gizmo: ese eje no cambia en el arma
	var a_local0: Vector3 = b0.orthonormalized().inverse() * _d_axes[0]
	var a_local1: Vector3 = b1.orthonormalized().inverse() * _d_axes[0]
	print("ROTATE eje fijo: ", a_local0.distance_to(a_local1) < 0.01)
	await _shot(out + "_rot.png")
	_toggle_ui()
	await _shot(out + "_hidden.png")
	print("JSON ", _to_json_values(_current_entry()))
	print("GIZMO TEST DONE")
	get_tree().quit(0)
