extends Control

@onready var progress_bar = $VBoxContainer/ProgressBar

var progress = []
var scene_load_status = 0
var use_sync_load = false
## Recursos de partida (enemigos, personaje elegido, jefe) cargados en segundo plano mientras carga la escena.
var _assets: AssetPreloader

func _ready():
	var Style := preload("res://scripts/ui/rumbang_style.gd")
	theme = Style.get_theme()
	$ColorRect.color = Style.BG
	$VBoxContainer/Label.add_theme_color_override("font_color", Style.ACCENT)
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
		_assets = AssetPreloader.new()
		_assets.add_many(GameData.preload_paths())
		_assets.add_many(GameData.BOSS_ASSET_PATHS)
		_assets.add_many(GameData.get_character_asset_paths(String(GameData.get_selected().get("id", "mikeura"))))
		_assets.start()

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
	
	var assets_progress: float = _assets.progress() if _assets else 1.0
	if scene_load_status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		progress_bar.value = (float(progress[0]) * 0.7 + assets_progress * 0.3) * 100.0
	elif scene_load_status == ResourceLoader.THREAD_LOAD_LOADED:
		# Esperar a que terminen también los recursos de partida (sin bloquear: se sigue dibujando)
		if _assets and not _assets.is_done():
			progress_bar.value = (0.7 + assets_progress * 0.3) * 100.0
			return
		set_process(false)
		var new_scene = ResourceLoader.load_threaded_get(SceneLoader.next_scene_path)
		if _assets:
			_assets.collect()
		GameData.preload_assets()
		progress_bar.value = 100.0
		
		# Compile shaders before switching scene
		await _compile_shaders()
		
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
