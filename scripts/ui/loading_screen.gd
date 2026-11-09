extends Control

@onready var progress_bar = $VBoxContainer/ProgressBar

## La escena de juego se carga en el hilo principal (cuando la pantalla ya se dibujó) y los datos
## pesados (modelos, texturas, audio) en hilos aparte. Antes la escena también se cargaba por hilos
## a la vez que otros recursos: sus scripts se compilaban en paralelo y, al pisarse, la carga
## fallaba o se bloqueaba al azar y la pantalla se quedaba congelada para siempre.
const DATA_EXTENSIONS := ["fbx", "glb", "png", "jpg", "ogg", "wav", "mp3"]
const DATA_TIMEOUT_S := 30.0      ## si los datos tardan más, se continúa igualmente
const SCENE_TIMEOUT_S := 25.0     ## si la escena no llega, se carga de golpe como último recurso
const BAR_SPEED := 60.0           ## puntos de barra por segundo (la barra avanza suave, nunca a saltos)
var _assets: AssetPreloader
var _target := 5.0

## La barra persigue su objetivo: así no parece congelada entre un paso de carga y el siguiente.
func _process(delta: float) -> void:
	if progress_bar:
		progress_bar.value = move_toward(progress_bar.value, _target, BAR_SPEED * delta)

func _step(text: String, target: float) -> void:
	_target = maxf(_target, target)
	var label := get_node_or_null("VBoxContainer/Label") as Label
	if label:
		label.text = text

func _ready():
	var Style := preload("res://scripts/ui/rumbang_style.gd")
	theme = Style.get_theme()
	$ColorRect.color = Style.BG
	$VBoxContainer/Label.add_theme_color_override("font_color", Style.ACCENT)
	if SceneLoader.next_scene_path == "":
		push_error("No scene path provided to SceneLoader")
		return
	progress_bar.value = 0
	_load.call_deferred()

static func _only_data(list: Array) -> Array:
	return list.filter(func(p): return String(p).get_extension().to_lower() in DATA_EXTENSIONS)

func _load() -> void:
	var mobile: bool = Quality.is_mobile()
	var label := get_node_or_null("VBoxContainer/Label") as Label
	# Deja que la pantalla se dibuje antes de la carga pesada
	await get_tree().process_frame
	await get_tree().process_frame

	var path := SceneLoader.next_scene_path
	_step("Cargando escena...", 12.0)
	var new_scene := await _load_scene(path)
	if new_scene == null:
		push_error("No se pudo cargar la escena: " + path)
		if label:
			label.text = "No se pudo cargar. Volviendo al menú..."
		await get_tree().create_timer(2.5).timeout
		SceneLoader.next_scene_path = "res://scenes/ui/dungeon_hub.tscn"
		get_tree().change_scene_to_file("res://scenes/ui/dungeon_hub.tscn")
		return
	_step("Cargando recursos...", 40.0)
	await get_tree().process_frame

	if mobile:
		# En móviles la carga multihilo con Terrain3D provocaba bloqueos: todo síncrono
		GameData.preload_assets()
	else:
		_assets = AssetPreloader.new()
		_assets.add_many(_only_data(GameData.preload_paths()))
		if GameData.game_mode == "dungeon":
			_assets.add_many(_only_data(DungeonGoblin.asset_paths()))
		_assets.add_many(_only_data(GameData.BOSS_ASSET_PATHS))
		_assets.add_many(_only_data(GameData.get_character_asset_paths(String(GameData.get_selected().get("id", "mikeura")))))
		_assets.start()
		var waited := 0.0
		while not _assets.is_done() and waited < DATA_TIMEOUT_S:
			_step("Cargando recursos...", (0.4 + _assets.progress() * 0.4) * 100.0)
			waited += get_process_delta_time()
			await get_tree().process_frame
		if waited >= DATA_TIMEOUT_S:
			push_warning("Los datos de partida tardaron más de %d s: se continúa." % int(DATA_TIMEOUT_S))
		_assets.collect()
		# Scripts y escenas pequeñas (.gd/.tscn), ya sin hilos en marcha
		GameData.preload_assets()

	_step("Preparando efectos...", 82.0)
	await _compile_shaders()
	_step("¡Listo!", 100.0)
	# La barra termina de llenarse antes de cambiar de escena
	while progress_bar.value < 99.5:
		await get_tree().process_frame
	await get_tree().process_frame
	get_tree().change_scene_to_packed(new_scene)

## Carga la escena en un hilo y avanza la barra mientras tanto (compilar los scripts del juego tarda
## ~2 s y antes dejaba la pantalla congelada). Es la única carga en hilos en ese momento, así que no
## se pisa con la de datos; si falla o tarda demasiado, se carga de golpe.
func _load_scene(path: String) -> PackedScene:
	if ResourceLoader.load_threaded_request(path, "", false) != OK:
		return ResourceLoader.load(path) as PackedScene
	var prog: Array = []
	var waited := 0.0
	while waited < SCENE_TIMEOUT_S:
		var st := ResourceLoader.load_threaded_get_status(path, prog)
		if st == ResourceLoader.THREAD_LOAD_LOADED:
			return ResourceLoader.load_threaded_get(path) as PackedScene
		if st != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			break
		if not prog.is_empty():
			_target = maxf(_target, 12.0 + float(prog[0]) * 26.0)
		waited += get_process_delta_time()
		await get_tree().process_frame
	return ResourceLoader.load(path) as PackedScene

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
	
	if GameData.game_mode == "dungeon":
		z_offset = await _warm_dungeon(vp, z_offset)

	for i in range(4):
		await get_tree().process_frame
		
	svc.queue_free()

## Mazmorra: un modelo de cada enemigo y los objetos propios del modo (almas, recogibles, cofre), de uno en
## uno, para que ni la compilación de sombreadores ni la carga de clips caigan en medio de la partida.
func _warm_dungeon(vp: SubViewport, z0: float) -> float:
	var z := z0
	_step("Preparando criaturas...", 88.0)
	for model in DungeonGoblin.warm_models():
		vp.add_child(model)
		(model as Node3D).position = Vector3(0, -0.8, z)
		z -= 2.0
		await get_tree().process_frame
	_step("Preparando objetos...", 94.0)
	HealSoul.burst(vp, Vector3(0, 0, z), 1)
	ResourcePickup.spawn(vp, Vector3(0.5, 0, z), ResourcePickup.Kind.AMMO)
	ResourcePickup.spawn(vp, Vector3(-0.5, 0, z), ResourcePickup.Kind.MANA)
	await get_tree().process_frame
	z -= 2.0
	var chest := TreasureChest.spawn(vp, Vector3(0, -0.5, z), null)
	chest.scale = Vector3.ONE * 0.5
	await get_tree().process_frame
	return z - 2.0
