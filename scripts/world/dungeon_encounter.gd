class_name DungeonEncounter
extends Node

## Encuentros y niveles de la mazmorra:
##  - Cada caverna (salvo la inicial) tiene un grupo numeroso y mezclado de enemigos. Al entrar en ella aparecen en el
##    lado opuesto y barreras rúnicas (DungeonDoor) tapan sus bocas de túnel hasta que mueren todos.
##  - Al limpiar la caverna final aparece un portal (DungeonPortal). Cruzarlo abre la elección entre
##    dos armas al azar (WeaponChoiceUI) y se baja al siguiente nivel: mapa nuevo y algo más difícil.
##  - La arena (vecina de la inicial) tiene el "arena_kind" del mundo (un goblin en las cavernas); la tecla G hace aparecer otro allí (pruebas).

signal encounter_started
signal encounter_cleared
signal level_started(level: int)

const TRIGGER_FRACTION := 0.85        ## entra al pasar del 85 % del radio de la caverna
const SPAWN_DISTANCE := 6.0           ## m desde el centro, del lado contrario al jugador
const SPAWN_SPREAD := 2.6             ## separación lateral entre goblins del mismo grupo
const DOOR_CLEARANCE := 2.2           ## no se cierra una barrera con el jugador encima (m)
const RESPAWN_KEY := KEY_G
const BRUTE_KEY := KEY_B              ## pruebas: hace aparecer un bruto en la arena
const BRUTE_CHANCE := 0.35            ## desde el nivel 2, probabilidad de bruto en cada caverna
const MAGE_KEY := KEY_J               ## pruebas: hace aparecer un mago en la arena
const MAGE_CHANCE := [0.3, 0.45]      ## probabilidad de mago en cada caverna: nivel 1 / desde el nivel 2
const ZOMBIE_KEY := KEY_Z             ## pruebas: hace aparecer un zombi en la arena
const ZOMBIE_CHANCE := 0.4            ## probabilidad de que una caverna tenga zombis (la mitad del grupo)
const BOSS_KEY := KEY_N               ## pruebas: hace aparecer al jefe necromántico en la arena
const BOSS_EVERY := 1                 ## cada cuántos niveles la caverna final es la del jefe (1 = todos)
const GROUP_COLUMNS := 5              ## enemigos por fila al aparecer en grupo
const ROW_DEPTH := 2.4                ## separación entre filas (m)
const MAX_GROUP := 10                 ## tope de enemigos por caverna (sin contar al jefe)
const MAX_SWARM := 14                 ## tope tras multiplicar los enjambres del mundo (WorldDefs "swarm")
## Armas que se pueden elegir en el portal (las que tienen animaciones para la mazmorra).
const PORTAL_WEAPONS := [
	WeaponData.WeaponType.SPEAR_LANCE, WeaponData.WeaponType.FLAME_THROWER,
	WeaponData.WeaponType.SPORE_BAZOOKA, WeaponData.WeaponType.TRI_SHOTGUN,
	WeaponData.WeaponType.DUSTS, WeaponData.WeaponType.SERPENTS,
]

var map: DungeonMap
var player: Node3D
var level := 1
var goblin: DungeonGoblin             ## goblin de la arena (el de la tecla G)
var portal: DungeonPortal
var _pending: Dictionary = {}         ## índice de caverna -> nº de goblins aún por aparecer
var _boss_pending: Dictionary = {}    ## índice de caverna -> el jefe aparece cuando muera su escolta
var _alive: Dictionary = {}           ## índice de caverna -> goblins vivos
var _doors: Dictionary = {}           ## índice de caverna -> [DungeonDoor]
var _doors_waiting: Dictionary = {}   ## índice de caverna -> [bocas por cerrar cuando el jugador se aparte]
var _triggered := false               ## la arena ya se activó (habilita la G)
var _changing_level := false

func setup(p_map: DungeonMap, p_player: Node3D) -> void:
	map = p_map
	player = p_player
	_plan_rooms()
	_spawn_chests()

## Enemigos por caverna: grupos grandes y mezclados que crecen con el nivel. La caverna final trae
## una escolta numerosa y el jefe aparece al final, cuando ya no queda nadie de la escolta.
func _plan_rooms() -> void:
	_pending.clear()
	_alive.clear()
	_boss_pending.clear()
	var extra := (level - 1) / 2
	for i in map.rooms.size():
		var type: String = map.rooms[i]["type"]
		if type == "start" or type == "treasure":
			continue
		if i == map.arena_index:
			_pending[i] = 1 + extra
		elif type == "end":
			_pending[i] = mini(6 + level, MAX_GROUP)
			if is_boss_level():
				_boss_pending[i] = true
		else:
			_pending[i] = mini(randi_range(4, 6) + extra * 2, MAX_GROUP)

func _process(_delta: float) -> void:
	if map == null or not is_instance_valid(player) or _changing_level:
		return
	# En red solo el anfitrión dispara los encuentros (con cualquier jugador vivo); los clientes los reciben.
	for i in ([] if Net.is_client() else _pending.keys()):
		var c := map.room_center(i)
		var trigger: Node3D = null
		for p in NetPlayers.alive():
			var d := Vector2(p.global_position.x - c.x, p.global_position.z - c.z).length()
			if d <= map.room_reach(i) * TRIGGER_FRACTION:
				trigger = p
				break
		if trigger != null:
			var n: int = _pending[i]
			_pending.erase(i)
			_spawn_group(i, n, trigger)
			_close_room(i)
			_net_call("room_started", [i])
			encounter_started.emit()
	_check_treasure()
	# Barreras pendientes: se cierran en cuanto el jugador no está encima
	for room in _doors_waiting.keys():
		var left: Array = []
		for mouth in _doors_waiting[room]:
			if _player_near(mouth):
				left.append(mouth)
			else:
				(_doors[room] as Array).append(DungeonDoor.spawn(get_parent(), mouth))
		if left.is_empty():
			_doors_waiting.erase(room)
		else:
			_doors_waiting[room] = left

# ───────────────────────────── Goblins ─────────────────────────────

func _spawn_group(room: int, count: int, from_player: Node3D = null) -> void:
	var c := map.room_center(room)
	var ref: Node3D = from_player if from_player != null else player
	var away := Vector3(c.x - ref.global_position.x, 0.0, c.z - ref.global_position.z)
	away = away.normalized() if away.length_squared() > 0.01 else Vector3.FORWARD
	var side := away.cross(Vector3.UP)
	if room == map.arena_index:
		_triggered = true
	var kinds := _kinds_for(room, count)
	count = kinds.size()
	for k in count:
		# Cuadrícula: filas de GROUP_COLUMNS, cada fila más cerca del centro de la caverna
		var row := k / GROUP_COLUMNS
		var in_row := mini(GROUP_COLUMNS, count - row * GROUP_COLUMNS)
		var offset := side * ((k % GROUP_COLUMNS) - (in_row - 1) * 0.5) * SPAWN_SPREAD
		var g := _spawn_at(room, c + away * (SPAWN_DISTANCE - row * ROW_DEPTH) + offset, kinds[k])
		if room == map.arena_index:
			goblin = g

## Tipo de cada miembro del grupo (ver NetWorld.KINDS). La arena solo tiene el "arena_kind" del
## mundo (el goblin normal en las cavernas). En las demás, los grupos de 4 o más llevan los tipos
## "guaranteed" del mundo; el resto se reparte al azar según su "kind_weights", y los tipos de "swarm" se multiplican. El jefe va aparte.
func _kinds_for(room: int, count: int) -> Array:
	var kinds: Array = []
	kinds.resize(count)
	kinds.fill(map.world().get("arena_kind", "goblin"))
	if room == map.arena_index or count <= 0:
		return kinds
	var guaranteed: Array = map.world()["guaranteed"] if count >= 4 else []
	for k in count:
		kinds[k] = guaranteed[k] if k < guaranteed.size() else _pick_kind()
	kinds.shuffle()
	# Enjambres: cada tipo de "swarm" ({tipo: [mín, máx]}) aparece en grupitos
	var swarm: Dictionary = map.world().get("swarm", {})
	var out: Array = []
	for k in kinds.size():
		var r: Array = swarm.get(kinds[k], [1, 1])
		var room_left := MAX_SWARM - out.size() - (kinds.size() - k - 1)   # sitio para los que faltan
		for i in clampi(randi_range(int(r[0]), int(r[1])), 1, maxi(room_left, 1)):
			out.append(kinds[k])
	return out

func _pick_kind() -> String:
	var weights: Dictionary = map.world()["kind_weights"]
	var total := 0.0
	for w in weights.values():
		total += float(w)
	var roll := randf() * total
	for kind in weights:
		roll -= float(weights[kind])
		if roll <= 0.0:
			return kind
	return weights.keys().back()          # por redondeo: el último del mundo, nunca uno de otro

func _spawn_at(room: int, pos: Vector3, kind: String = "goblin") -> DungeonGoblin:
	# Si el punto cae en roca o en un prop, se acerca al centro hasta encontrar suelo libre
	var c := map.room_center(room)
	for t in 6:
		var cell := map.world_to_cell(pos)
		if map._cells.has(cell) and not map._walls.has(cell) and not map._blocked.has(cell):
			break
		pos = pos.lerp(c, 0.35)
	var g := NetWorld.create_enemy(kind)
	g.name = {"brute": "DungeonBrute", "mage": "DungeonMage", "zombie": "DungeonZombie", "necro": "DungeonNecromancer",
		"rat": "DungeonRat", "slug": "DungeonSlug", "rat_king": "DungeonRatKing",
		"rat_big": "DungeonBigRat", "slug_red": "DungeonBloater"}.get(kind, "DungeonGoblin")
	g.map = map
	g.position = Vector3(pos.x, 0.1, pos.z)
	get_parent().add_child(g)
	g.global_position = Vector3(pos.x, 0.1, pos.z)
	_track(room, g)
	SpawnDissolve.play(g.get_model(), g, 0.9, Color(1.0, 0.25, 0.1), 1.4)
	return g

## Cuenta un enemigo vivo de la caverna; los que nacen de él (DungeonSlug al dividirse) también.
func _track(room: int, g: DungeonGoblin) -> void:
	_alive[room] = _alive.get(room, 0) + 1
	g.died.connect(func(dead): _on_goblin_died(room); _drop_resources(dead))
	if g.has_signal("spawned"):
		g.spawned.connect(func(child): _track(room, child))

## Los enemigos sueltan balas (si llevas un arma de fuego) o maná.
const AMMO_DROP_CHANCE := 0.3
const MANA_DROP_CHANCE := 0.25

func _drop_resources(dead) -> void:
	if not is_instance_valid(dead) or not is_instance_valid(player):
		return
	var res = player.get("resources")
	if res == null:
		return
	var pos: Vector3 = dead.global_position
	if Net.is_online():
		# Botín personal: cada jugador ve y recoge el suyo
		if randf() < AMMO_DROP_CHANCE:
			_net_call("fx_pickup", [pos + Vector3(randf_range(-0.4, 0.4), 0, randf_range(-0.4, 0.4)), ResourcePickup.Kind.AMMO])
		if randf() < MANA_DROP_CHANCE:
			_net_call("fx_pickup", [pos + Vector3(randf_range(-0.4, 0.4), 0, randf_range(-0.4, 0.4)), ResourcePickup.Kind.MANA])
		return
	var owned: Array = player.weapon_inventory.weapon_slots if player.get("weapon_inventory") else []
	if res.has_any_ammo_weapon(owned) and randf() < AMMO_DROP_CHANCE:
		ResourcePickup.spawn(get_parent(), pos + Vector3(randf_range(-0.4, 0.4), 0, randf_range(-0.4, 0.4)), ResourcePickup.Kind.AMMO)
	if randf() < MANA_DROP_CHANCE:
		ResourcePickup.spawn(get_parent(), pos + Vector3(randf_range(-0.4, 0.4), 0, randf_range(-0.4, 0.4)), ResourcePickup.Kind.MANA)

func _on_goblin_died(room: int) -> void:
	_alive[room] = _alive.get(room, 1) - 1
	if _alive[room] <= 0:
		if _boss_pending.has(room):
			_boss_pending.erase(room)
			_spawn_boss(room)
			return
		_room_cleared(room)
		encounter_cleared.emit()

## El jefe aparece el último: al caer la escolta, del lado contrario al jugador.
func _spawn_boss(room: int) -> void:
	var c := map.room_center(room)
	var away := Vector3(c.x - player.global_position.x, 0.0, c.z - player.global_position.z)
	away = away.normalized() if away.length_squared() > 0.01 else Vector3.FORWARD
	_spawn_at(room, c + away * SPAWN_DISTANCE, map.world().get("boss", "necro"))

# ───────────────────────────── Puertas ─────────────────────────────

## Tapa las bocas de túnel de la caverna (las que tengan al jugador encima, en cuanto se aparte).
func _close_room(room: int) -> void:
	_doors[room] = []
	var waiting: Array = []
	for mouth in map.room_mouths(room):
		if _player_near(mouth):
			waiting.append(mouth)
		else:
			(_doors[room] as Array).append(DungeonDoor.spawn(get_parent(), mouth))
	if not waiting.is_empty():
		_doors_waiting[room] = waiting

func _room_cleared(room: int) -> void:
	_doors_waiting.erase(room)
	for d in _doors.get(room, []):
		if is_instance_valid(d):
			d.open()
	_doors.erase(room)
	_net_call("room_cleared", [room])
	if map.rooms[room]["type"] == "end" and not is_instance_valid(portal):
		_spawn_portal(room)

func _player_near(cells: Array) -> bool:
	for p in NetPlayers.alive():
		for c in cells:
			if Vector2(c.x - p.global_position.x, c.z - p.global_position.z).length() < DOOR_CLEARANCE:
				return true
	return false

## ¿Está la caverna cerrada ahora mismo? (para las pruebas y la interfaz)
func is_room_locked(room: int) -> bool:
	return not (_doors.get(room, []) as Array).is_empty()

# ───────────────────────────── Portal y siguiente nivel ─────────────────────────────

## El centro de la caverna final lo ocupa el altar (con colisión): el portal se abre delante de él,
## del lado por el que está el jugador, sobre suelo libre.
const PORTAL_OFFSET := 4.2

func _spawn_portal(room: int) -> void:
	var c := map.room_center(room)
	var dir := Vector3(player.global_position.x - c.x, 0.0, player.global_position.z - c.z)
	dir = dir.normalized() if dir.length_squared() > 0.01 else Vector3.FORWARD
	var pos := c + dir * PORTAL_OFFSET
	for k in 8:
		var cell := map.world_to_cell(pos)
		if map._cells.has(cell) and not map._walls.has(cell) and not map._blocked.has(cell):
			break
		# Probar girando alrededor del altar
		dir = dir.rotated(Vector3.UP, deg_to_rad(45.0))
		pos = c + dir * PORTAL_OFFSET
	_make_portal(Vector3(pos.x, 0.0, pos.z))
	_net_call("portal_opened", [Vector3(pos.x, 0.0, pos.z)])

func _make_portal(at: Vector3) -> void:
	portal = DungeonPortal.spawn(get_parent(), at)
	portal.player = player
	portal.entered.connect(_on_portal_entered)

func _on_portal_entered() -> void:
	var ui := WeaponChoiceUI.present(get_parent(), _roll_weapons(2), level)
	ui.chosen.connect(_on_weapon_chosen)

## `count` armas al azar, primero las que el jugador aún no tiene.
func _roll_weapons(count: int) -> Array:
	var owned: Array = player.weapon_inventory.weapon_slots if player.get("weapon_inventory") else []
	var fresh: Array = PORTAL_WEAPONS.filter(func(w): return not owned.has(w))
	fresh.shuffle()
	var out: Array = fresh.slice(0, count)
	if out.size() < count:
		var rest: Array = PORTAL_WEAPONS.filter(func(w): return not out.has(w))
		rest.shuffle()
		out.append_array(rest.slice(0, count - out.size()))
	return out

func _on_weapon_chosen(weapon_type: int) -> void:
	give_weapon(weapon_type)
	if Net.is_online():
		# En red se baja todos juntos: avisa al anfitrión y espera a los demás
		_net_call("player_ready_for_next", [])
		_show_waiting_label()
	else:
		next_level()

## Da el arma y la equipa; con los huecos llenos sustituye a la que se lleva en la mano.
func give_weapon(weapon_type: int) -> void:
	var inv = player.get("weapon_inventory")
	if inv == null:
		return
	if not inv.weapon_slots.has(weapon_type):
		if not player.add_weapon(weapon_type):
			inv.weapon_slots[inv.current_slot] = weapon_type
			player.combat_controller.weapon_slots = inv.weapon_slots
	player.select_slot(inv.weapon_slots.find(weapon_type))

## Baja al siguiente nivel: fundido a negro, mapa nuevo, jugador al inicio y cartel con el nivel.
func next_level() -> void:
	if _changing_level:
		return
	_changing_level = true
	level += 1
	var fade := CanvasLayer.new()
	fade.layer = 90
	fade.process_mode = Node.PROCESS_MODE_ALWAYS
	var black := ColorRect.new()
	black.color = Color(0, 0, 0, 0)
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.add_child(black)
	var label := Label.new()
	var themes: Array = map.world()["level_themes"]
	label.text = "NIVEL %d\n%s · %s" % [level, str(map.world()["name"]).to_upper(),
		str(themes[posmod(level - 1, themes.size())]["name"]).to_upper()]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_CENTER)
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.grow_vertical = Control.GROW_DIRECTION_BOTH
	RumbangStyle.style_title(label, 40, RumbangStyle.TITLE, RumbangStyle.NEON_MAGENTA)
	label.theme = RumbangStyle.get_theme()
	label.modulate.a = 0.0
	fade.add_child(label)
	get_parent().add_child(fade)
	var tw := fade.create_tween()
	tw.tween_property(black, "color:a", 1.0, 0.45)
	tw.parallel().tween_property(label, "modulate:a", 1.0, 0.45)
	await tw.finished
	await get_tree().process_frame
	_rebuild_level()
	if player.get("resources"):
		player.resources.refresh_for_new_level()
	await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	var tw2 := fade.create_tween()
	tw2.tween_property(black, "color:a", 0.0, 0.6)
	tw2.parallel().tween_property(label, "modulate:a", 0.0, 1.2).set_delay(0.6)
	tw2.tween_callback(fade.queue_free)
	_changing_level = false
	level_started.emit(level)

func _rebuild_level() -> void:
	for room in _doors:
		for d in _doors[room]:
			if is_instance_valid(d):
				d.queue_free()
	_doors.clear()
	_doors_waiting.clear()
	if is_instance_valid(portal):
		portal.queue_free()
	portal = null
	for e in EnemyRegistry.all():
		if e is DungeonGoblin and is_instance_valid(e):
			e.queue_free()
	goblin = null
	_triggered = false
	map.level_theme = level - 1
	map.generate()
	_plan_rooms()
	_treasure_opened.clear()
	_spawn_chests()
	var start := Vector3.ZERO
	for i in map.rooms.size():
		if map.rooms[i]["type"] == "start":
			start = map.room_center(i)
	player.global_position = Vector3(start.x, 0.3, start.z) + _slot_offset()
	if player is CharacterBody3D:
		(player as CharacterBody3D).velocity = Vector3.ZERO
	player.reset_physics_interpolation()

## Compatibilidad con las pruebas: hace aparecer (o devuelve) el goblin de la arena.
func spawn_goblin() -> DungeonGoblin:
	if is_instance_valid(goblin) and not goblin.is_dead():
		return goblin
	_pending.erase(map.arena_index)
	_triggered = true
	var c := map.room_center(map.arena_index)
	var away := Vector3(c.x - player.global_position.x, 0.0, c.z - player.global_position.z)
	away = away.normalized() if away.length_squared() > 0.01 else Vector3.FORWARD
	goblin = _spawn_at(map.arena_index, c + away * SPAWN_DISTANCE)
	return goblin

## Pruebas: hace aparecer un bruto en la arena, delante del jugador.
func spawn_brute() -> DungeonBrute:
	_pending.erase(map.arena_index)
	_triggered = true
	var c := map.room_center(map.arena_index)
	var away := Vector3(c.x - player.global_position.x, 0.0, c.z - player.global_position.z)
	away = away.normalized() if away.length_squared() > 0.01 else Vector3.FORWARD
	return _spawn_at(map.arena_index, c + away * SPAWN_DISTANCE, "brute") as DungeonBrute

## Pruebas: hace aparecer un mago en la arena, más lejos que los demás (ataca a distancia).
func spawn_mage() -> DungeonMage:
	_pending.erase(map.arena_index)
	_triggered = true
	var c := map.room_center(map.arena_index)
	var away := Vector3(c.x - player.global_position.x, 0.0, c.z - player.global_position.z)
	away = away.normalized() if away.length_squared() > 0.01 else Vector3.FORWARD
	return _spawn_at(map.arena_index, c + away * SPAWN_DISTANCE, "mage") as DungeonMage

## Pruebas: hace aparecer un zombi en la arena.
func spawn_zombie() -> DungeonZombie:
	_pending.erase(map.arena_index)
	_triggered = true
	var c := map.room_center(map.arena_index)
	var away := Vector3(c.x - player.global_position.x, 0.0, c.z - player.global_position.z)
	away = away.normalized() if away.length_squared() > 0.01 else Vector3.FORWARD
	return _spawn_at(map.arena_index, c + away * SPAWN_DISTANCE, "zombie") as DungeonZombie

## El nivel acaba con el jefe necromántico (cada BOSS_EVERY niveles).
func is_boss_level() -> bool:
	return level % BOSS_EVERY == 0

## Pruebas: hace aparecer al jefe del mundo (Nigromante o Rey Rata) en la arena.
func spawn_necromancer() -> DungeonNecromancer:
	_pending.erase(map.arena_index)
	_triggered = true
	var c := map.room_center(map.arena_index)
	var away := Vector3(c.x - player.global_position.x, 0.0, c.z - player.global_position.z)
	away = away.normalized() if away.length_squared() > 0.01 else Vector3.FORWARD
	return _spawn_at(map.arena_index, c + away * SPAWN_DISTANCE, map.world().get("boss", "necro")) as DungeonNecromancer

func _unhandled_input(event: InputEvent) -> void:
	if Net.is_client() or not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == RESPAWN_KEY and _triggered:
		spawn_goblin()
	elif event.keycode == BRUTE_KEY and _triggered:
		spawn_brute()
	elif event.keycode == MAGE_KEY and _triggered:
		spawn_mage()
	elif event.keycode == ZOMBIE_KEY and _triggered:
		spawn_zombie()
	elif event.keycode == BOSS_KEY and _triggered:
		spawn_necromancer()

# ───────────────────────────── Multijugador (ver NetWorld) ─────────────────────────────

## Llama a un método de NetWorld si hay partida en red.
func _net_call(method: String, args: Array) -> void:
	if not Net.is_online():
		return
	var nw := get_parent().get_node_or_null("NetWorld")
	if nw:
		nw.callv(method, args)

## Cada jugador aparece en un punto distinto alrededor del centro de la caverna inicial.
func _slot_offset() -> Vector3:
	if not Net.is_online():
		return Vector3.ZERO
	var a := TAU * float(Net.slot_of(Net.my_id())) / float(Net.MAX_PLAYERS)
	return Vector3(cos(a), 0.0, sin(a)) * 1.6

## Cliente: el anfitrión empezó la caverna (se cierran sus bocas de túnel).
func net_room_started(room: int) -> void:
	_pending.erase(room)
	if room == map.arena_index:
		_triggered = true
	_close_room(room)

## Cliente: caverna despejada (se abren las barreras).
func net_room_cleared(room: int) -> void:
	_doors_waiting.erase(room)
	for d in _doors.get(room, []):
		if is_instance_valid(d):
			d.open()
	_doors.erase(room)

## Cliente: el anfitrión abrió el portal.
func net_spawn_portal(pos: Vector3) -> void:
	if not is_instance_valid(portal):
		_make_portal(pos)

## Todos: bajan al siguiente nivel (la semilla ya está en Net.level_seed).
func net_next_level() -> void:
	next_level()

func _show_waiting_label() -> void:
	var layer := CanvasLayer.new()
	layer.name = "WaitingForPlayers"
	layer.layer = 80
	var l := Label.new()
	l.text = "Esperando a los demás jugadores…"
	l.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	l.offset_top = -120
	l.add_theme_font_size_override("font_size", 22)
	layer.add_child(l)
	get_parent().add_child(layer)
	# Se quita sola cuando empieza el nivel
	level_started.connect(func(_lv): layer.queue_free(), CONNECT_ONE_SHOT)

# ───────────────────────────── Cámara del tesoro ─────────────────────────────

const TREASURE_LOOT := 3              ## recogibles de cada tipo (balas y maná)
var _treasure_opened: Dictionary = {}

## Al entrar en la cámara del tesoro (sin enemigos) aparece un círculo de recogibles y un aviso.
func _check_treasure() -> void:
	if Net.is_client():
		return
	for i in map.rooms.size():
		if map.rooms[i]["type"] != "treasure" or _treasure_opened.has(i):
			continue
		var c := map.room_center(i)
		for p in NetPlayers.alive():
			if Vector2(p.global_position.x - c.x, p.global_position.z - c.z).length() <= map.room_reach(i) * TRIGGER_FRACTION:
				_treasure_opened[i] = true
				_open_treasure(i)
				break

const TREASURE_CHOICES := 3          ## armas al azar que ofrece el cofre
var _chests: Array[TreasureChest] = []

## Un cofre en el centro de cada cámara del tesoro, en todos los pares (el mapa es el mismo para todos).
## Al abrirlo cada jugador elige su arma.
func _spawn_chests() -> void:
	for ch in _chests:
		if is_instance_valid(ch):
			ch.queue_free()
	_chests.clear()
	for i in map.rooms.size():
		if map.rooms[i]["type"] == "treasure":
			var c := map.room_center(i)
			var chest := TreasureChest.spawn(get_parent(), Vector3(c.x, 0.0, c.z), player)
			chest.opened.connect(_on_chest_opened)
			_chests.append(chest)

func _on_chest_opened(_chest: TreasureChest) -> void:
	var ui := WeaponChoiceUI.present(get_parent(), _roll_weapons(TREASURE_CHOICES), level, "¡TESORO!", "ELIGE UN ARMA")
	ui.chosen.connect(give_weapon)

func _open_treasure(room: int) -> void:
	var c := map.room_center(room)
	var n := TREASURE_LOOT * 2
	for k in n:
		var a := TAU * k / n
		var pos := c + Vector3(cos(a), 0.0, sin(a)) * 2.6
		var kind := ResourcePickup.Kind.AMMO if k % 2 == 0 else ResourcePickup.Kind.MANA
		if Net.is_online():
			_net_call("fx_pickup", [pos, kind])
		else:
			ResourcePickup.spawn(get_parent(), pos, kind)
	AudioManager.play("level-up", -6.0, 1.1)
	_show_banner("¡CÁMARA DEL TESORO!")

func _show_banner(text: String) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 70
	var l := Label.new()
	l.text = text
	l.set_anchors_preset(Control.PRESET_CENTER_TOP)
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	l.offset_top = 110
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.theme = RumbangStyle.get_theme()
	RumbangStyle.style_title(l, 26, RumbangStyle.TITLE, RumbangStyle.NEON_CYAN)
	layer.add_child(l)
	get_parent().add_child(layer)
	var tw := l.create_tween()
	l.modulate.a = 0.0
	tw.tween_property(l, "modulate:a", 1.0, 0.3)
	tw.tween_interval(1.8)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(layer.queue_free)
