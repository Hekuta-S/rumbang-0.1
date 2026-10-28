class_name DungeonEncounter
extends Node

## Encuentros y niveles de la mazmorra:
##  - Cada caverna (salvo la inicial) tiene su grupo de goblins. Al entrar en ella aparecen en el
##    lado opuesto y barreras rúnicas (DungeonDoor) tapan sus bocas de túnel hasta que mueren todos.
##  - Al limpiar la caverna final aparece un portal (DungeonPortal). Cruzarlo abre la elección entre
##    dos armas al azar (WeaponChoiceUI) y se baja al siguiente nivel: mapa nuevo y algo más difícil.
##  - La arena (vecina de la inicial) tiene un goblin; la tecla G hace aparecer otro allí (pruebas).

signal encounter_started
signal encounter_cleared
signal level_started(level: int)

const TRIGGER_FRACTION := 0.85        ## entra al pasar del 85 % del radio de la caverna
const SPAWN_DISTANCE := 6.0           ## m desde el centro, del lado contrario al jugador
const SPAWN_SPREAD := 2.6             ## separación lateral entre goblins del mismo grupo
const DOOR_CLEARANCE := 2.2           ## no se cierra una barrera con el jugador encima (m)
const RESPAWN_KEY := KEY_G
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
var _alive: Dictionary = {}           ## índice de caverna -> goblins vivos
var _doors: Dictionary = {}           ## índice de caverna -> [DungeonDoor]
var _doors_waiting: Dictionary = {}   ## índice de caverna -> [bocas por cerrar cuando el jugador se aparte]
var _triggered := false               ## la arena ya se activó (habilita la G)
var _changing_level := false

func setup(p_map: DungeonMap, p_player: Node3D) -> void:
	map = p_map
	player = p_player
	_plan_rooms()

## Goblins por caverna; cada dos niveles, uno más por caverna (y la final crece cada nivel).
func _plan_rooms() -> void:
	_pending.clear()
	_alive.clear()
	var extra := (level - 1) / 2
	for i in map.rooms.size():
		var type: String = map.rooms[i]["type"]
		if type == "start":
			continue
		if i == map.arena_index:
			_pending[i] = 1 + extra
		elif type == "end":
			_pending[i] = mini(3 + level - 1, 6)
		else:
			_pending[i] = randi_range(1, 2) + extra

func _process(_delta: float) -> void:
	if map == null or not is_instance_valid(player) or _changing_level:
		return
	for i in _pending.keys():
		var c := map.room_center(i)
		var d := Vector2(player.global_position.x - c.x, player.global_position.z - c.z).length()
		if d <= map.room_reach(i) * TRIGGER_FRACTION:
			var n: int = _pending[i]
			_pending.erase(i)
			_spawn_group(i, n)
			_close_room(i)
			encounter_started.emit()
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

func _spawn_group(room: int, count: int) -> void:
	var c := map.room_center(room)
	var away := Vector3(c.x - player.global_position.x, 0.0, c.z - player.global_position.z)
	away = away.normalized() if away.length_squared() > 0.01 else Vector3.FORWARD
	var side := away.cross(Vector3.UP)
	if room == map.arena_index:
		_triggered = true
	for k in count:
		var offset := side * (k - (count - 1) * 0.5) * SPAWN_SPREAD
		var g := _spawn_at(room, c + away * SPAWN_DISTANCE + offset)
		if room == map.arena_index:
			goblin = g

func _spawn_at(room: int, pos: Vector3) -> DungeonGoblin:
	# Si el punto cae en roca o en un prop, se acerca al centro hasta encontrar suelo libre
	var c := map.room_center(room)
	for t in 6:
		var cell := map.world_to_cell(pos)
		if map._cells.has(cell) and not map._walls.has(cell) and not map._blocked.has(cell):
			break
		pos = pos.lerp(c, 0.35)
	var g := DungeonGoblin.new()
	g.name = "DungeonGoblin"
	g.map = map
	get_parent().add_child(g)
	g.global_position = Vector3(pos.x, 0.1, pos.z)
	_alive[room] = _alive.get(room, 0) + 1
	g.died.connect(func(_g): _on_goblin_died(room))
	SpawnDissolve.play(g.get_model(), g, 0.9, Color(1.0, 0.25, 0.1), 1.4)
	return g

func _on_goblin_died(room: int) -> void:
	_alive[room] = _alive.get(room, 1) - 1
	if _alive[room] <= 0:
		_room_cleared(room)
		encounter_cleared.emit()

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
	if map.rooms[room]["type"] == "end" and not is_instance_valid(portal):
		_spawn_portal(room)

func _player_near(cells: Array) -> bool:
	for c in cells:
		if Vector2(c.x - player.global_position.x, c.z - player.global_position.z).length() < DOOR_CLEARANCE:
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
	portal = DungeonPortal.spawn(get_parent(), Vector3(pos.x, 0.0, pos.z))
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
	label.text = "NIVEL %d" % level
	label.set_anchors_preset(Control.PRESET_CENTER)
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.grow_vertical = Control.GROW_DIRECTION_BOTH
	label.add_theme_font_size_override("font_size", 40)
	label.add_theme_color_override("font_color", Color(0.75, 0.55, 1.0))
	label.modulate.a = 0.0
	fade.add_child(label)
	get_parent().add_child(fade)
	var tw := fade.create_tween()
	tw.tween_property(black, "color:a", 1.0, 0.45)
	tw.parallel().tween_property(label, "modulate:a", 1.0, 0.45)
	await tw.finished
	await get_tree().process_frame
	_rebuild_level()
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
	map.generate()
	_plan_rooms()
	var start := Vector3.ZERO
	for i in map.rooms.size():
		if map.rooms[i]["type"] == "start":
			start = map.room_center(i)
	player.global_position = Vector3(start.x, 0.3, start.z)
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

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == RESPAWN_KEY:
		if _triggered:
			spawn_goblin()
