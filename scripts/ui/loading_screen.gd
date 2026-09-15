extends Control

@onready var progress_bar = $VBoxContainer/ProgressBar

var progress = []
var scene_load_status = 0
var use_sync_load = false

func _ready():
	if SceneLoader.next_scene_path == "":
		push_error("No scene path provided to SceneLoader")
		return
		
	# En Android, la carga multihilo con Terrain3D a menudo causa deadlocks (bloqueos) en el RenderingServer.
	# Haremos una carga síncrona forzada en móviles.
	if OS.get_name() in ["Android", "iOS"]:
		use_sync_load = true
		progress_bar.value = 10
		_do_sync_load.call_deferred()
	else:
		ResourceLoader.load_threaded_request(SceneLoader.next_scene_path, "", true)

func _do_sync_load() -> void:
	# Permitimos que la pantalla se dibuje 2 frames antes de congelarla con la carga pesada
	await get_tree().process_frame
	await get_tree().process_frame
	
	progress_bar.value = 50
	
	var lbl = Label.new()
	lbl.text = "Generando Mundo 3D...\n(Puede tardar 2-3 minutos en móviles. NO CIERRES EL JUEGO)"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	lbl.position.y -= 100
	lbl.add_theme_font_size_override("font_size", 20)
	add_child(lbl)
	
	GameData.preload_assets()
	await _compile_shaders()
	
	var new_scene = load(SceneLoader.next_scene_path)
	progress_bar.value = 100
	lbl.text = "Inicializando Entorno... (Casi listo)"
	
	await get_tree().process_frame
	get_tree().change_scene_to_packed(new_scene)

func _process(_delta):
	if use_sync_load or SceneLoader.next_scene_path == "":
		return
		
	scene_load_status = ResourceLoader.load_threaded_get_status(SceneLoader.next_scene_path, progress)
	
	if scene_load_status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		progress_bar.value = progress[0] * 100
	elif scene_load_status == ResourceLoader.THREAD_LOAD_LOADED:
		set_process(false)
		var new_scene = ResourceLoader.load_threaded_get(SceneLoader.next_scene_path)
		GameData.preload_assets()
		
		# Compile shaders before switching scene
		var compile_task = _compile_shaders()
		if compile_task is Signal: await compile_task
		elif typeof(compile_task) == TYPE_OBJECT and compile_task.has_signal("completed"): await compile_task
		
		get_tree().change_scene_to_packed(new_scene)
	elif scene_load_status == ResourceLoader.THREAD_LOAD_FAILED or scene_load_status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		push_error("Error loading scene: " + SceneLoader.next_scene_path)
		set_process(false)

func _compile_shaders() -> void:
	var svc = SubViewportContainer.new()
	svc.modulate = Color(1, 1, 1, 0.01)
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(svc)
	
	var vp = SubViewport.new()
	vp.size = Vector2(128, 128)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	svc.add_child(vp)
	
	var cam = Camera3D.new()
	cam.current = true
	vp.add_child(cam)
	
	var light = DirectionalLight3D.new()
	vp.add_child(light)

	await get_tree().process_frame
	
	var z_offset = -2.0
	for path in GameData.cache_enemy_models:
		var packed: PackedScene = GameData.cache_enemy_models[path]
		if packed:
			var instance = packed.instantiate()
			vp.add_child(instance)
			if instance is Node3D:
				instance.position = Vector3(0, 0, z_offset)
				z_offset -= 2.0
			
	var b = preload("res://scenes/objects/bullet.tscn").instantiate()
	vp.add_child(b)
	b.position = Vector3(0, 0, z_offset)
	z_offset -= 2.0
	
	var lbl = Label3D.new()
	lbl.text = "123!"
	lbl.font_size = 46
	lbl.outline_size = 14
	vp.add_child(lbl)
	lbl.position = Vector3(0, 0, z_offset)
	
	for i in range(4):
		await get_tree().process_frame
		
	svc.queue_free()
