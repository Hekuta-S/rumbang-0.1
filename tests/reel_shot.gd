extends Node

## Tomas para el reel (necesita ventana). Se graba con Movie Maker, una toma por ejecución:
##   godot --path . --write-movie out.avi --fixed-fps 30 --resolution 1080x1920 res://tests/reel_shot.tscn -- <toma>
## Tomas: title | hub | combat | cave | fists | survival | play (supervivencia jugada a mano, REEL_SECONDS s)
##   loadout: como play, pero el arsenal cambia cada 10 s (LOADOUTS: 3 armas por tramo)
##   random: como loadout, pero cada REEL_LOADOUT_S s (20 por defecto) sortea RANDOM_WEAPONS armas al azar
## REEL_DAY=1: la luz arranca de día aunque la partida empiece en el minuto REEL_FROM_MIN.
## El proyecto usa stretch "expand", así que el HUD se adapta a vertical.

var _main: Node
var _cam: Camera3D

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var shot: String = args[0] if args.size() > 0 else "title"
	# Movie Maker graba el tamaño de la ventana: forzar vertical (la resolución del CLI no se respeta aquí)
	var size := OS.get_environment("REEL_SIZE").split("x")
	if size.size() == 2:
		get_window().size = Vector2i(size[0].to_int(), size[1].to_int())
	match shot:
		"title": _title.call_deferred()
		"hub": _hub.call_deferred()
		"combat": _combat.call_deferred("dungeon")
		"cave": _combat.call_deferred("caves")
		"fists": _fists.call_deferred()
		"survival": _survival.call_deferred()
		"play": _play_survival.call_deferred()
		"loadout": _play_survival.call_deferred(LOADOUTS)
		"random": _play_survival.call_deferred([], RANDOM_WEAPONS)

func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _title() -> void:
	var t := (load("res://scenes/ui/title_screen.tscn") as PackedScene).instantiate()
	add_child(t)
	await _wait(5.0)
	get_tree().quit(0)

func _hub() -> void:
	DungeonHub.config_path = "user://reel_hub.cfg"
	GameData.armory_path = "user://reel_armeria.cfg"
	DungeonHub.portals_open = false
	DungeonHub.force_intro = false
	DungeonHub.set_intro_seen(true)
	var hub := (load("res://scenes/ui/dungeon_hub.tscn") as PackedScene).instantiate() as DungeonHub
	add_child(hub)
	await _wait(2.0)
	await _go(hub, DungeonHub.STATIONS["yunque"]["pos"] + Vector3(-1.0, 0, 0.2))
	await _go(hub, DungeonHub.MAGE_POS + Vector3(1.2, 0, 0.4))
	SaveManager.mago_rescatado = true   # la mazmorra se abre con el mago rescatado
	hub.use_station("mago")
	await _wait(3.0)
	get_tree().quit(0)

func _go(hub: DungeonHub, p: Vector3) -> void:
	hub.player.move_to(p)
	var t0 := Time.get_ticks_msec()
	while hub.player.move_target != null and Time.get_ticks_msec() - t0 < 6000:
		await get_tree().process_frame
	await _wait(0.4)

func _combat(world: String) -> void:
	GameData.game_mode = "dungeon"
	if WorldDefs.has(world):
		GameData.world = world
	_main = (load(Net.game_scene()) as PackedScene).instantiate()
	get_tree().root.add_child(_main)
	await get_tree().process_frame
	get_tree().current_scene = _main
	await _wait(3.0)
	var player: CharacterBody3D = _main.get_node("Player")
	var map: DungeonMap = _main.get_node("ProceduralMap")
	player.health_comp.max_hp = 99999.0
	player.health_comp.hp = 99999.0
	_cam = Camera3D.new()
	_cam.fov = 55.0
	_main.add_child(_cam)
	_cam.current = true
	var room := mini(1, map.rooms.size() - 1)
	var c := map.room_center(room)
	player.global_position = Vector3(c.x, 0.3, c.z)
	var W := WeaponData.WeaponType
	var weapons := [W.KATANA, W.GREATSWORD, W.FISTS]
	var angle := 0.0
	for w in weapons:
		if not player.weapon_slots.has(w):
			player.add_weapon(w)
		player.select_slot(player.weapon_slots.find(w))
		var frames := 0
		while frames < 120:   # 4 s de juego a 30 fps (el reloj real no sirve con Movie Maker)
			frames += 1
			angle += 0.012
			var p := player.global_position
			_cam.global_position = p + Vector3(sin(angle) * 4.2, 2.2, cos(angle) * 4.2)
			_cam.look_at(p + Vector3(0, 1.1, 0))
			var enc = _main.get_node_or_null("DungeonEncounter")
			if enc and frames % 45 == 1 and _enemies_near(p, 10.0) < 2:   # siempre con alguien delante
				var ang := randf() * TAU
				enc._spawn_at(room, p + Vector3(cos(ang), 0, sin(ang)) * 3.5, "goblin")
			var en := _nearest_enemy(p)
			if en:
				_face(player, en.global_position - p)
				var to_en := en.global_position - p
				to_en.y = 0.0
				if to_en.length() > 1.9:
					player.velocity = to_en.normalized() * 4.0
					player.move_and_slide()
			player.resources.energy = PlayerResources.ENERGY_MAX
			player.combat_controller.attack_cooldown = 0.0
			player.attack()
			await get_tree().process_frame
	get_tree().quit(0)

## Puños de cerca: bloqueos con contragolpe (7 s, con el enemigo aún fresco), combo (5 s) y lluvia de golpes (3 s).
## La cámara se pone de lado a la línea jugador-enemigo para que se vean los dos.
func _fists() -> void:
	GameData.game_mode = "dungeon"
	_main = (load(Net.game_scene()) as PackedScene).instantiate()
	get_tree().root.add_child(_main)
	await get_tree().process_frame
	get_tree().current_scene = _main
	await _wait(3.0)
	var player: CharacterBody3D = _main.get_node("Player")
	var map: DungeonMap = _main.get_node("ProceduralMap")
	player.health_comp.max_hp = 99999.0
	player.health_comp.hp = 99999.0
	_cam = Camera3D.new()
	_cam.keep_aspect = Camera3D.KEEP_WIDTH   # vertical: fijar el ancho para que quepan los dos
	_cam.fov = 62.0
	_main.add_child(_cam)
	_cam.current = true
	var c := map.room_center(mini(1, map.rooms.size() - 1))
	player.global_position = Vector3(c.x, 0.3, c.z)
	# siempre hay a quién pegar: si faltan enemigos cerca, nace un goblin delante (1 en guardia, 2 después)
	var enc = _main.get_node_or_null("DungeonEncounter")
	var room := mini(1, map.rooms.size() - 1)
	var last_spawn := -999
	var W := WeaponData.WeaponType
	if not player.weapon_slots.has(W.FISTS):
		player.add_weapon(W.FISTS)
	player.select_slot(player.weapon_slots.find(W.FISTS))
	var parry: PlayerParryController = player.parry_controller
	var cam_pos := player.global_position + Vector3(3, 2, 3)
	var blocks := [0]   # array: las lambdas de GDScript copian los int capturados
	parry.parried.connect(func(_a): blocks[0] += 1)
	for f in 450:
		var phase := "block" if f < 210 else ("combo" if f < 360 else "special")
		var p := player.global_position
		var want_n := 1 if phase == "block" else 2
		if enc and f - last_spawn > 45 and _enemies_near(p, 10.0) < want_n:
			last_spawn = f
			var ang := randf() * TAU
			enc._spawn_at(room, p + Vector3(cos(ang), 0, sin(ang)) * 4.0, "goblin")
		var e := _nearest_enemy(p)
		var to_e := Vector3.FORWARD
		if e:
			to_e = e.global_position - p
			to_e.y = 0.0
			if to_e.length() > 0.01:
				_face(player, to_e)
			if phase != "block" and to_e.length() > 1.7:
				player.velocity = to_e.normalized() * 4.0
				player.move_and_slide()
		player.resources.energy = PlayerResources.ENERGY_MAX
		player.combat_controller.attack_cooldown = 0.0
		if OS.get_environment("REEL_DEBUG") == "1" and f % 15 == 0 and phase == "block":
			print("DBG f=", f, " hp=", player.health_comp.hp, " guard=", parry.is_guarding(), " act=", parry.is_active(), " dist=", to_e.length(), " e=", e.name if e else "-", " st=", e.get("state") if e else "-")
		match phase:
			"combo":
				player.attack()
			"special":
				if f == 360 or f == 405:
					player.combat_controller.fists_special()
			"block":
				if parry.has_bonus() or (e and e.get("state") == 8):   # 8 = STUNNED
					player.attack()              # contragolpe tras parar
				elif not parry.is_active():
					parry._cooldown = 0.0
					parry.try_parry()
		# cámara de lado, entre jugador y enemigo, algo baja
		var dir := to_e.normalized() if to_e.length() > 0.01 else Vector3.FORWARD
		var side := dir.cross(Vector3.UP).normalized()
		var mid := p + dir * minf(to_e.length(), 3.0) * 0.5
		var want := mid + side * 3.4 - dir * 0.8 + Vector3(0, 1.5, 0)
		cam_pos = cam_pos.lerp(want, 0.08)
		_cam.global_position = cam_pos
		_cam.look_at(mid + Vector3(0, 1.0, 0))
		await get_tree().process_frame
	print("REEL bloqueos=", blocks[0])
	get_tree().quit(0)

func _nearest_enemy(p: Vector3) -> Node3D:
	var best: Node3D = null
	for n in get_tree().get_nodes_in_group("enemies"):
		if n is Node3D and (n as Node3D).is_inside_tree() and (best == null or p.distance_to(n.global_position) < p.distance_to(best.global_position)):
			best = n
	return best

## Gira modelo y brazo de cámara del jugador hacia `dir`: el golpe sale hacia donde apunta su cámara
## (get_attack_forward_dir), no hacia el modelo. El frente de ambos es -Z.
func _face(player: Node3D, dir: Vector3) -> void:
	dir.y = 0.0
	if dir.length() < 0.01:
		return
	var yaw := atan2(-dir.x, -dir.z)
	player.mesh.global_rotation.y = yaw
	player.spring_arm.global_rotation.y = yaw

func _enemies_near(p: Vector3, r: float) -> int:
	var n := 0
	for g in get_tree().get_nodes_in_group("enemies"):
		if g is Node3D and p.distance_to(g.global_position) < r and g.get("state") != 7:   # 7 = DEAD
			n += 1
	return n

## Supervivencia: 32 s de juego con hordas en anillo que crecen, un arma nueva cada 5 s y el jugador
## corriendo en círculo con su propia cámara. Sin subidas de nivel (pausarían la toma).
func _survival() -> void:
	GameData.game_mode = "survival"
	SaveManager.save_path = "user://reel_save.json"
	_main = (load("res://scenes/core/main_procedural.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(_main)
	await get_tree().process_frame
	get_tree().current_scene = _main
	var player = null
	var waves: WaveManager = null
	for i in 900:
		await get_tree().process_frame
		player = _main.get_node_or_null("Player")
		waves = _main.find_child("WaveManager", true, false)
		if player and waves and waves._running:
			break
	player.health_comp.max_hp = 99999.0
	player.health_comp.hp = 99999.0
	var xpc = player.get_node_or_null("ExperienceComponent")
	if xpc:
		xpc.experience_required = 1e12
	var W := WeaponData.WeaponType
	var extra := [W.SPINNING_AXE, W.FLAME_THROWER, W.SERPENTS, W.ELEMENTS_CYCLE, W.RAILGUN, W.SPORE_BAZOOKA]
	var ring_n := 14
	for f in 960:   # 32 s a 30 fps
		var t := f / 30.0
		if f % 150 == 60 and not extra.is_empty():
			player.add_weapon(extra.pop_front())
		if f % 75 == 0:   # anillo de enemigos cada 2,5 s, cada vez más grande
			for i in ring_n:
				var a := TAU * float(i) / float(ring_n)
				waves._spawn_single_enemy(player.global_position + Vector3(cos(a), 0, sin(a)) * randf_range(9.0, 12.0))
			ring_n = mini(ring_n + 6, 60)
		# correr en círculo (entrada simulada, relativa a la cámara)
		var ang := t * 0.9
		Input.action_press("move_forward", clampf(cos(ang), 0, 1))
		Input.action_press("move_backward", clampf(-cos(ang), 0, 1))
		Input.action_press("move_right", clampf(sin(ang), 0, 1))
		Input.action_press("move_left", clampf(-sin(ang), 0, 1))
		player.attack()
		await get_tree().process_frame
	get_tree().quit(0)

## Supervivencia jugada por una persona: invencible, la partida arranca en el minuto REEL_FROM_MIN (ya hay
## cuervos y hordas) y la toma se corta sola a los REEL_SECONDS s de control (30 por defecto).
## Imprime REEL_START=<fotograma> para recortar la carga del vídeo. Engine.max_fps = 30 para que se juegue a
## velocidad real mientras Movie Maker graba
## (Movie Maker se salta ese límite: el bucle espera lo que sobra de cada fotograma).
## Toma "loadout": cada tramo de LOADOUT_S s lleva SOLO estas 3 armas (se cambian todas de golpe).
const LOADOUT_S := 10.0
const LOADOUTS := [
	[WeaponData.WeaponType.FLAME_THROWER, WeaponData.WeaponType.SERPENTS, WeaponData.WeaponType.DUSTS],
	[WeaponData.WeaponType.SPINNING_AXE, WeaponData.WeaponType.GIANT_MACE, WeaponData.WeaponType.CROSSBOW],
	[WeaponData.WeaponType.RAILGUN, WeaponData.WeaponType.SPORE_BAZOOKA, WeaponData.WeaponType.ZOMBIE_ARM],
]

const RANDOM_WEAPONS := 4
## Fuera del sorteo: el ciclo elemental deja sus orbes vivos al quitarlo.
const RANDOM_EXCLUDED := [WeaponData.WeaponType.ELEMENTS_CYCLE]

## `n` armas de supervivencia al azar, primero las que no estaban en `prev` (cada tramo se nota distinto).
static func random_loadout(n: int, prev: Array) -> Array:
	var fresh: Array = []
	var reused: Array = []
	for w in WeaponData.WeaponType.values():
		if RANDOM_EXCLUDED.has(w) or not GameData.weapon_available_in_mode(w):
			continue
		(reused if prev.has(w) else fresh).append(w)
	fresh.shuffle()
	reused.shuffle()
	return (fresh + reused).slice(0, n)

## Cambia todas las armas del jugador por `weapons` (huecos, munición, HUD y modelos).
func _set_loadout(player: Node, weapons: Array) -> void:
	var inv = player.weapon_inventory
	inv.weapon_slots.clear()
	inv.reloading_weapon = -1
	inv.current_slot = 0
	for w in weapons:
		inv.add_weapon(int(w))
	var cc = player.combat_controller
	if cc:
		cc.weapon_slots = inv.weapon_slots
		cc.current_slot = 0
		cc.reloading_weapon = -1
	player.update_weapon_visuals()
	player.emit_signal("weapon_changed", 0, player.weapon_names[player.current_weapon()])
	if weapons.has(WeaponData.WeaponType.ELEMENTS_CYCLE):
		player._try_spawn_elemental_orbs()
	print("REEL_LOADOUT=", weapons.map(func(w): return WeaponData.weapon_names.get(w, str(w))))

func _play_survival(loadouts: Array = [], random_n: int = 0) -> void:
	Engine.max_fps = 30
	var secs := OS.get_environment("REEL_SECONDS").to_float()
	if secs <= 0.0:
		secs = 30.0
	var loadout_s := OS.get_environment("REEL_LOADOUT_S").to_float()
	if loadout_s <= 0.0:
		loadout_s = LOADOUT_S if random_n == 0 else 20.0
	var swaps := random_n > 0 or not loadouts.is_empty()
	var from_min := OS.get_environment("REEL_FROM_MIN").to_float()
	if OS.get_environment("REEL_FROM_MIN") == "":
		from_min = 2.0
	GameData.game_mode = "survival"
	SaveManager.save_path = "user://reel_save.json"
	_main = (load("res://scenes/core/main_procedural.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(_main)
	await get_tree().process_frame
	get_tree().current_scene = _main
	var player = null
	var waves: WaveManager = null
	for i in 900:
		await get_tree().process_frame
		player = _main.get_node_or_null("Player")
		waves = _main.find_child("WaveManager", true, false)
		if player and waves and waves._running:
			break
	player.health_comp.max_hp = 99999.0
	player.health_comp.hp = 99999.0
	GameState.get_instance().elapsed_time = from_min * 60.0
	if OS.get_environment("REEL_DAY") == "1":
		DayNightCycle.light_offset_s = from_min * 60.0
	for i in 2:
		waves.spawn_flyer()
	var start := Engine.get_process_frames()
	var t0 := Time.get_ticks_msec()
	print("REEL_START=", start)
	var frames := int(secs * 30.0)
	var tramo := -1
	if swaps:
		# Sin subidas de nivel (el menú de cartas pausaba la partida en mitad del tramo) ni aviso de mando
		var xpc = player.get_node_or_null("ExperienceComponent")
		if xpc:
			xpc.experience_required = 1e12
		var gp := get_node_or_null("/root/GamepadUI")
		if gp and gp.get("_toast_layer") != null:
			(gp.get("_toast_layer") as CanvasLayer).visible = false
	while Engine.get_process_frames() - start < frames:
		player.health_comp.hp = player.health_comp.max_hp
		if swaps:
			var k := int((Engine.get_process_frames() - start) / (loadout_s * 30.0))
			if random_n == 0:
				k = mini(k, loadouts.size() - 1)
			if k != tramo:
				tramo = k
				_set_loadout(player, loadouts[k] if random_n == 0 else random_loadout(random_n, player.weapon_inventory.weapon_slots))
		# Movie Maker no respeta max_fps: si dibuja más rápido que 30 fps se espera aquí (juego a velocidad real)
		var ahead := t0 + (Engine.get_process_frames() - start) * 1000.0 / 30.0 - Time.get_ticks_msec()
		if ahead > 1.0:
			OS.delay_msec(int(ahead))
		await get_tree().process_frame
	print("REEL_END=", Engine.get_process_frames(), " REAL_S=", (Time.get_ticks_msec() - t0) / 1000.0)
	get_tree().quit(0)
