extends Control

@onready var progress_bar = $VBoxContainer/ProgressBar

## La escena de juego se carga en el hilo principal (cuando la pantalla ya se dibujó) y los datos
## pesados (modelos, texturas, audio) en hilos aparte. Antes la escena también se cargaba por hilos
## a la vez que otros recursos: sus scripts se compilaban en paralelo y, al pisarse, la carga
## fallaba o se bloqueaba al azar y la pantalla se quedaba congelada para siempre.
const DATA_EXTENSIONS := ["fbx", "glb", "png", "jpg", "ogg", "wav", "mp3"]
const DATA_TIMEOUT_S := 30.0      ## si los datos tardan más, se continúa igualmente
var _assets: AssetPreloader

func _ready():
	var Style := preload("res://scripts/ui/rumbang_style.gd")
	theme = Style.get_theme()
	$ColorRect.color = Style.BG
	$VBoxContainer/Label.add_theme_color_override("font_color", Style.ACCENT)
	if SceneLoader.next_scene_path == "":
		push_error("No scene path provided to SceneLoader")
		return
	progress_bar.value = 5
	_load.call_deferred()

static func _only_data(list: Array) -> Array:
	return list.filter(func(p): return String(p).get_extension().to_lower() in DATA_EXTENSIONS)

func _load() -> void:
	var mobile: bool = OS.get_name() in ["Android", "iOS"]
	var label := get_node_or_null("VBoxContainer/Label") as Label
	# Deja que la pantalla se dibuje antes de la carga pesada
	await get_tree().process_frame
	await get_tree().process_frame

	var path := SceneLoader.next_scene_path
	var new_scene := ResourceLoader.load(path) as PackedScene
	if new_scene == null:
		push_error("No se pudo cargar la escena: " + path)
		if label:
			label.text = "No se pudo cargar. Volviendo al menú..."
		await get_tree().create_timer(2.5).timeout
		SceneLoader.next_scene_path = "res://scenes/ui/main_menu.tscn"
		get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
		return
	progress_bar.value = 40
	await get_tree().process_frame

	if mobile:
		# En móviles la carga multihilo con Terrain3D provocaba bloqueos: todo síncrono
		GameData.preload_assets()
	else:
		_assets = AssetPreloader.new()
		_assets.add_many(_only_data(GameData.preload_paths()))
		_assets.add_many(_only_data(GameData.BOSS_ASSET_PATHS))
		_assets.add_many(_only_data(GameData.get_character_asset_paths(String(GameData.get_selected().get("id", "mikeura")))))
		_assets.start()
		var waited := 0.0
		while not _assets.is_done() and waited < DATA_TIMEOUT_S:
			progress_bar.value = (0.4 + _assets.progress() * 0.5) * 100.0
			waited += get_process_delta_time()
			await get_tree().process_frame
		if waited >= DATA_TIMEOUT_S:
			push_warning("Los datos de partida tardaron más de %d s: se continúa." % int(DATA_TIMEOUT_S))
		_assets.collect()
		# Scripts y escenas pequeñas (.gd/.tscn), ya sin hilos en marcha
		GameData.preload_assets()

	progress_bar.value = 95
	await _compile_shaders()
	progress_bar.value = 100
	await get_tree().process_frame
	get_tree().change_scene_to_packed(new_scene)

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
