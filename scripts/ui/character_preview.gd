class_name CharacterPreview
extends SubViewportContainer

## Vista previa 3D de un personaje (modelo idle animado) para la pantalla de
## selección. Usa su propio World3D, así que no interfiere con ninguna escena.
## Arrastra con el mouse para girarlo; en reposo se mece suavemente.

const MODEL_HEIGHT := 1.62      ## misma altura que PlayerAnimationController._fit_model()

var _viewport: SubViewport
var _pivot: Node3D
var _model: Node3D
var _rim_light: OmniLight3D
var _floor_mat: StandardMaterial3D
var _yaw_drag: float = 0.0
var _dragging: bool = false
var _time: float = 0.0
var _tween: Tween
## Cada petición de show_character() sube el contador; si llega otra mientras se espera la carga, la vieja se descarta.
var _serial: int = 0
## Modelos/texturas de la selección cargados en segundo plano (ruta -> recurso). Se vacía al salir de la pantalla.
static var _cache: Dictionary = {}

## Pide en segundo plano el modelo y la textura de TODOS los personajes (el elegido primero),
## para que cambiar de personaje no cargue nada en el hilo principal.
static func preload_all(selected_id: String) -> void:
	var ids: Array[String] = [selected_id]
	for c in GameData.CHARACTERS:
		var cid := String(c.get("id", ""))
		if cid != "" and not ids.has(cid):
			ids.append(cid)
	for cid in ids:
		for path in [GameData.get_idle_model_path(cid), GameData.get_texture_path(cid)]:
			if path != "" and not _cache.has(path) and ResourceLoader.exists(path):
				ResourceLoader.load_threaded_request(path, "", true)

static func clear_cache() -> void:
	_cache.clear()

## Devuelve el recurso cargado; si aún se está cargando espera frame a frame (sin congelar la UI).
func _get_resource(path: String) -> Resource:
	if path == "" or not ResourceLoader.exists(path):
		return null
	if _cache.has(path):
		return _cache[path]
	if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		ResourceLoader.load_threaded_request(path, "", true)
	while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await get_tree().process_frame
	if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_LOADED:
		return null
	var res := ResourceLoader.load_threaded_get(path)
	_cache[path] = res
	return res

func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_scene()

func _build_scene() -> void:
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_2X
	_viewport.handle_input_locally = false
	add_child(_viewport)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.36, 0.5)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_viewport.add_child(we)

	var cam := Camera3D.new()
	cam.fov = 34.0
	cam.position = Vector3(0.0, 1.0, 4.0)
	cam.rotation_degrees = Vector3(-3.0, 0.0, 0.0)
	_viewport.add_child(cam)
	cam.current = true

	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.92, 0.82)
	key.light_energy = 1.5
	key.rotation_degrees = Vector3(-35.0, 35.0, 0.0)
	_viewport.add_child(key)

	_rim_light = OmniLight3D.new()
	_rim_light.position = Vector3(-1.6, 1.8, -1.8)
	_rim_light.omni_range = 6.0
	_rim_light.light_energy = 3.0
	_viewport.add_child(_rim_light)

	# Base circular tenue bajo los pies
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.95
	cyl.bottom_radius = 1.0
	cyl.height = 0.06
	cyl.radial_segments = 40
	disc.mesh = cyl
	disc.position = Vector3(0.0, -0.03, 0.0)
	_floor_mat = StandardMaterial3D.new()
	_floor_mat.albedo_color = Color(0.05, 0.045, 0.08)
	_floor_mat.emission_enabled = true
	_floor_mat.emission = Color(0.3, 0.2, 0.5)
	_floor_mat.emission_energy_multiplier = 0.25
	disc.material_override = _floor_mat
	_viewport.add_child(disc)

	_pivot = Node3D.new()
	_viewport.add_child(_pivot)

func _process(delta: float) -> void:
	_time += delta
	if _pivot and not _dragging:
		_yaw_drag = lerpf(_yaw_drag, 0.0, minf(1.0, delta * 1.2))   # vuelve despacio al frente
	if _pivot:
		_pivot.rotation.y = _yaw_drag + sin(_time * 0.6) * 0.28

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		_yaw_drag += event.relative.x * 0.012

## Muestra el personaje `char_id`; `tint` colorea la luz de contorno y la base.
func show_character(char_id: String, tint: Color) -> void:
	if _pivot == null:
		await ready
	_serial += 1
	var my_serial := _serial
	_rim_light.light_color = tint
	_floor_mat.emission = tint.darkened(0.2)

	var path := GameData.get_idle_model_path(char_id)
	if path == "":
		return
	# El modelo anterior se queda en pantalla mientras llega el nuevo (no se congela ni parpadea)
	var scene_res: Resource = await _get_resource(path)
	var scene := scene_res as PackedScene
	var tex_path := GameData.get_texture_path(char_id)
	var tex_res: Resource = await _get_resource(tex_path)
	var tex := tex_res as Texture2D
	if my_serial != _serial:
		return   # el jugador ya eligió otro personaje
	if scene == null:
		push_warning("[CharacterPreview] No se pudo cargar " + path)
		return
	if _model and is_instance_valid(_model):
		_model.queue_free()
		_model = null
	_yaw_drag = 0.0
	_model = scene.instantiate()
	_pivot.add_child(_model)
	_fit_model(_model)

	if tex:
		_apply_texture(_model, tex)

	var ap := _find_animation_player(_model)
	if ap:
		var names := ap.get_animation_list()
		if not names.is_empty():
			var anim := ap.get_animation(names[0])
			if anim:
				anim.loop_mode = Animation.LOOP_LINEAR
			ap.play(names[0])

	# Entrada: materialización con el shader de disolución (pies -> cabeza)
	if _tween:
		_tween.kill()
	_tween = SpawnDissolve.play(_model, self, 1.0, tint.lerp(Color(1.0, 0.85, 0.1), 0.5), MODEL_HEIGHT)

func _fit_model(model: Node3D) -> void:
	var mi := _find_mesh_instance(model)
	if mi == null or mi.mesh == null:
		return
	var aabb := mi.mesh.get_aabb()
	var s := MODEL_HEIGHT / maxf(aabb.size.y, 0.001)
	model.scale = Vector3(s, s, s)
	model.position.y = -aabb.position.y * s

func _find_mesh_instance(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var r := _find_mesh_instance(c)
		if r:
			return r
	return null

func _find_animation_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_animation_player(c)
		if r:
			return r
	return null

func _apply_texture(n: Node, tex: Texture2D) -> void:
	if n is MeshInstance3D:
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = tex
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		n.material_override = mat
	for c in n.get_children():
		_apply_texture(c, tex)
