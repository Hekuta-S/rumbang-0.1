extends Node
## Capturas de los modelos de daga y maza para comprobar orientaciÃ³n y punto de agarre.
## Ejecutar con ventana: res://tests/shot_melee_models.tscn

const CELL := Vector2i(1600, 900)

var _labels: CanvasLayer

func _ready() -> void:
	_labels = CanvasLayer.new()
	add_child(_labels)

	var cam := Camera3D.new()
	cam.name = "ShotCamera"
	cam.fov = 40.0
	add_child(cam)
	cam.current = true

	get_viewport().size = CELL
	await get_tree().process_frame
	await _shot_daggers(cam)
	await _shot_maces(cam)
	get_tree().quit()

func _clear(keep: Node) -> void:
	for c in get_children():
		if c is Node3D and c != keep:
			c.queue_free()
	for c in _labels.get_children():
		c.queue_free()

func _stage() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.08, 0.08, 0.1)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.82, 0.9)
	e.ambient_light_energy = 1.2
	env.environment = e
	add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, -35, 0)
	key.light_energy = 1.6
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 145, 0)
	fill.light_energy = 0.7
	add_child(fill)

func _line(parent: Node3D, tip: float, color: Color) -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.006
	cyl.bottom_radius = 0.006
	cyl.height = 1.0
	var mi := MeshInstance3D.new()
	mi.mesh = cyl
	mi.scale = Vector3(1, maxf(tip, 0.01), 1)
	mi.position = Vector3(0, tip * 0.5, 0)
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	parent.add_child(mi)
	var ball := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.022
	sph.height = 0.044
	ball.mesh = sph
	ball.position = Vector3(0, 0, 0)
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(1, 0.2, 0.2)
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ball.material_override = bm
	parent.add_child(ball)

## Etiqueta 2D anclada en pantalla: las Label3D con billboard se solapaban entre modelos.
func _label(text: String, world_anchor: Vector3, cam: Camera3D) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	lbl.add_theme_constant_override("outline_size", 5)
	var p := cam.unproject_position(world_anchor)
	lbl.size = Vector2(700, 40)
	lbl.position = Vector2(p.x - 350, p.y)
	_labels.add_child(lbl)

func _shot_daggers(cam: Camera3D) -> void:
	_clear(cam)
	_stage()
	var n := DaggerModels.count()
	var anchors: Array = []
	for i in n:
		var x := (i - (n - 1) * 0.5) * 0.66
		var root := Node3D.new()
		root.position = Vector3(x, 0, 0)
		add_child(root)
		var model := Node3D.new()
		model.add_child(DaggerModels.build(i))
		root.add_child(model)
		_line(root, DaggerModels.tip_y(i), DaggerModels.skin_color(i))
		anchors.append([DaggerModels.skin_name(i), Vector3(x, -0.20, 0)])
	cam.position = Vector3(0, 0.35, 2.1)
	cam.look_at(Vector3(0, 0.15, 0))
	await get_tree().process_frame
	for a in anchors:
		_label(a[0], a[1], cam)
	await _save("res://tests/out_dagas.png")
	print("[Shot] dagas -> res://tests/out_dagas.png")

func _shot_maces(cam: Camera3D) -> void:
	_clear(cam)
	_stage()
	var n := MaceModels.count()
	var cols := 3
	var row_gap := 1.5
	var anchors: Array = []
	for i in n:
		var row := int(i / float(cols))
		var col := i % cols
		var row_count := mini(cols, n - row * cols)
		var spacing := 1.9 if row_count >= 3 else 2.4
		var x := (col - (row_count - 1) * 0.5) * spacing
		var y := -float(row) * row_gap
		var root := Node3D.new()
		root.position = Vector3(x, y, 0)
		add_child(root)
		var model := Node3D.new()
		model.add_child(MaceModels.build(i))
		root.add_child(model)
		_line(root, MaceModels.tip_y(i), MaceModels.skin_color(i))
		anchors.append([MaceModels.skin_name(i), Vector3(x, y - 0.24, 0)])
	cam.position = Vector3(0, 0.15, 4.9)
	cam.look_at(Vector3(0, -0.42, 0))
	await get_tree().process_frame
	for a in anchors:
		_label(a[0], a[1], cam)
	await _save("res://tests/out_mazas.png")
	print("[Shot] mazas -> res://tests/out_mazas.png")

func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)

