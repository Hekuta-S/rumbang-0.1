extends Control

var progress_bar: ProgressBar

## La escena de juego se carga en el hilo principal (cuando la pantalla ya se dibujó) y los datos
## pesados (modelos, texturas, audio) en hilos aparte. Antes la escena también se cargaba por hilos
## a la vez que otros recursos: sus scripts se compilaban en paralelo y, al pisarse, la carga
## fallaba o se bloqueaba al azar y la pantalla se quedaba congelada para siempre.
const DATA_EXTENSIONS := ["fbx", "glb", "png", "jpg", "ogg", "wav", "mp3", "res"]
const DATA_TIMEOUT_S := 30.0      ## si los datos tardan más, se continúa igualmente
const SCENE_TIMEOUT_S := 25.0     ## si la escena no llega, se carga de golpe como último recurso
const BAR_SPEED := 60.0           ## puntos de barra por segundo (la barra avanza suave, nunca a saltos)
var _assets: AssetPreloader
var _target := 5.0
var _title := ""
var _tip := ""
var _time := 0.0

## La barra persigue su objetivo: así no parece congelada entre un paso de carga y el siguiente.
func _process(delta: float) -> void:
	if progress_bar:
		progress_bar.value = move_toward(progress_bar.value, _target, BAR_SPEED * delta)
	# El título late: aunque un paso tarde, se ve que el juego sigue vivo
	_time += delta
	var head := get_node_or_null("Title") as Label
	if head:
		head.modulate.a = 0.78 + 0.22 * sin(_time * 3.0)

func _step(text: String, target: float) -> void:
	_target = maxf(_target, target)
	var label := get_node_or_null("VBoxContainer/Label") as Label
	if label:
		label.text = text

func _ready():
	_title = LoadingVisual.title_for(SceneLoader.next_scene_path)
	_tip = LoadingVisual.pick_tip()
	LoadingVisual.build(self, _title, _tip, "Cargando...", 0.0)
	progress_bar = $VBoxContainer/ProgressBar
	if SceneLoader.next_scene_path == "":
		push_error("No scene path provided to SceneLoader")
		return
	_load.call_deferred()

static func _only_data(list: Array) -> Array:
	return list.filter(func(p): return String(p).get_extension().to_lower() in DATA_EXTENSIONS)

## Datos pesados de la partida que se dejan en GameData.cache_preloaded: modelos y clips de los enemigos
## de la mazmorra, jefes y el personaje. Si nadie los retiene, Godot los descarta al liberar los modelos
## de calentamiento y el primer enemigo de cada tipo los vuelve a leer del disco en plena partida.
static func run_data_paths() -> Array:
	var out: Array = []
	if GameData.game_mode == "dungeon":
		out.append_array(DungeonGoblin.asset_paths())
	out.append_array(GameData.BOSS_ASSET_PATHS)
	out.append_array(GameData.get_character_asset_paths(String(GameData.get_selected().get("id", "mikeura"))))
	out.append_array(manifest_paths(SceneLoader.next_scene_path))
	return _only_data(out)

## Lo que cada escena de juego leía del disco al montarse (texturas del mapa, de la ropa, de las armas...):
## lista medida con tests/bench_scene_mount.tscn (WRITE_MANIFEST=1). Se precarga en segundo plano con el resto
## para que montar la escena no congele la pantalla. Volver a medir tras añadir mapas, ropa o armas.
const MANIFEST := "res://resources/preload_manifest.json"
static var _manifest: Dictionary = {}
static var _manifest_read := false

static func read_manifest() -> Dictionary:
	if not _manifest_read:
		_manifest_read = true
		if FileAccess.file_exists(MANIFEST):
			var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
			if data is Dictionary:
				_manifest = data
	return _manifest

static func manifest_paths(scene_path: String) -> Array:
	return read_manifest().get(scene_path.get_file(), [])

## Móvil (sin hilos): carga síncrona de run_data_paths() en la caché. Con `step`, se llama tras cada
## recurso (para avanzar la barra y ceder un frame).
static func cache_run_data_sync(step: Callable = Callable()) -> void:
	var paths := run_data_paths()
	for i in paths.size():
		var p := String(paths[i])
		if not GameData.cache_preloaded.has(p) and ResourceLoader.exists(p):
			GameData.cache_preloaded[p] = load(p)
		if step.is_valid():
			await step.call(float(i + 1) / float(paths.size()))

func _load() -> void:
	var mobile: bool = Quality.is_mobile()
	var label := get_node_or_null("VBoxContainer/Label") as Label
	# Deja que la pantalla se dibuje antes de la carga pesada
	await get_tree().process_frame
	await get_tree().process_frame

	var path := SceneLoader.next_scene_path
	# De vuelta al Salón en móvil: se libera lo que la partida retenía en memoria
	if mobile and path.ends_with("dungeon_hub.tscn"):
		GameData.release_run_cache()
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

	var light := light_asset_paths(path)
	if not light.is_empty():
		# Salón / personaje / patio: solo sus modelos y texturas, en hilos (sin Terrain3D, así que es seguro
		# también en móvil). Sin esto la escena los cargaba de golpe al entrar, con la pantalla congelada.
		await _preload_light_assets(light)
		await _finish(new_scene, "¡Listo!")
		return

	if mobile:
		# En móviles la carga multihilo con Terrain3D provocaba bloqueos: todo síncrono
		GameData.preload_assets()
		# ...y lo pesado de la partida retenido en caché (antes solo en PC: en móvil el primer enemigo
		# de cada tipo releía su modelo del disco en plena partida)
		await cache_run_data_sync(func(f: float):
			_step("Cargando recursos...", (0.4 + f * 0.4) * 100.0)
			await get_tree().process_frame)
	else:
		_assets = AssetPreloader.new()
		_assets.add_many(_only_data(GameData.preload_paths()))
		_assets.add_many(run_data_paths())
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
	await _finish(new_scene, "Generando mundo...")

## La barra termina de llenarse y la tapa de SceneLoader (idéntica a esta pantalla) toma el relevo: montar
## la escena y generar su mundo congela frames, y la tapa los cubre hasta que la escena está lista.
func _finish(scene: PackedScene, step: String) -> void:
	_step(step, 100.0)
	while progress_bar.value < 99.5:
		await get_tree().process_frame
	SceneLoader.hold_cover(step, _title, _tip)
	await get_tree().process_frame
	get_tree().change_scene_to_packed(scene)

## Escenas ligeras (sin partida): qué precargar para cada una. Vacío = escena de juego (carga completa).
static func light_asset_paths(path: String) -> Array:
	if path.ends_with("dungeon_hub.tscn"):
		return menu_asset_paths()
	if path.ends_with("character_select.tscn"):
		return GameData.get_character_asset_paths("riva")
	if path.ends_with("tutorial_patio.tscn"):
		return patio_asset_paths()
	return []

## Patio del tutorial: el rey, el mago, el personaje y los goblins (antes pasaba por la carga de partida
## completa: jefes, sombreadores de supervivencia...).
static func patio_asset_paths() -> Array:
	var out: Array = [
		"res://assets/models/salon/rey.glb",
		"res://assets/models/salon/mago.glb",
		"res://assets/audio/patio_theme.wav",
	]
	out.append_array(GameData.get_character_asset_paths("riva"))
	out.append_array(DungeonGoblin.asset_paths())
	return out

## Modelos, texturas y música del Salón (lo que su _ready cargaría de forma síncrona).
static func menu_asset_paths() -> Array:
	var out: Array = [
		"res://assets/models/salon/salon_trono.glb",
		"res://assets/models/salon/rey.glb",
		"res://assets/models/salon/mago.glb",
		"res://assets/models/riva/riva-caminar.fbx",
		"res://assets/models/riva/riva-correr.fbx",
		"res://assets/audio/hub_theme.wav",
	]
	for tex in ["brick", "flagstone", "stone", "wood", "hide", "straw"]:
		out.append("res://assets/textures/dungeon/%s_albedo.png" % tex)
		out.append("res://assets/textures/dungeon/%s_normal.png" % tex)
	out.append_array(GameData.get_character_asset_paths("riva"))
	return out

func _preload_light_assets(paths: Array) -> void:
	_assets = AssetPreloader.new()
	_assets.add_many(_only_data(paths))
	_assets.start()
	var waited := 0.0
	while not _assets.is_done() and waited < DATA_TIMEOUT_S:
		_step("Cargando recursos...", (0.4 + _assets.progress() * 0.55) * 100.0)
		waited += get_process_delta_time()
		await get_tree().process_frame
	_assets.collect()

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
