extends Node
class_name LootManager

var weapon_pickup_scene = preload("res://scenes/objects/weapon_pickup.tscn")
var xp_orb_scene = preload("res://scenes/objects/xp_orb.tscn")
var item_pickup_scene = preload("res://scenes/objects/item_pickup.tscn")

## Dentro de la zona jugable de WaveManager (±95 m), con margen: antes eran ±2300 m y los
## objetos y armas del suelo caían fuera del mapa.
const PLAYABLE_MIN_X: float = WaveManager.PLAYABLE_MIN_X + 15.0
const PLAYABLE_MAX_X: float = WaveManager.PLAYABLE_MAX_X - 15.0
const PLAYABLE_MIN_Z: float = WaveManager.PLAYABLE_MIN_Z + 15.0
const PLAYABLE_MAX_Z: float = WaveManager.PLAYABLE_MAX_Z - 15.0

var player: Node3D

func initialize(p_player: Node3D) -> void:
	player = p_player

func spawn_weapon_pickup() -> void:
	# Clear any leftover pickups from a previous floor.
	for pickup in get_tree().get_nodes_in_group("weapon_pickups"):
		pickup.queue_free()

	if not player: return

	var available: Array = []
	for w_type in range(9):
		if not player.weapon_slots.has(w_type):
			available.append(w_type)
	if available.is_empty():
		return

	var pickup = weapon_pickup_scene.instantiate()
	pickup.weapon_type = available[randi() % available.size()]
	
	var px = randf_range(PLAYABLE_MIN_X, PLAYABLE_MAX_X)
	var pz = randf_range(PLAYABLE_MIN_Z, PLAYABLE_MAX_Z)
	var main_node = get_tree().current_scene
	var py = main_node.get_floor_y(px, pz) if main_node.has_method("get_floor_y") else 0.0
	pickup.position = Vector3(px, py + 1.0, pz)
	get_parent().add_child(pickup)

func spawn_item_pickup() -> void:
	var pickup = item_pickup_scene.instantiate()
	var px = randf_range(PLAYABLE_MIN_X, PLAYABLE_MAX_X)
	var pz = randf_range(PLAYABLE_MIN_Z, PLAYABLE_MAX_Z)
	var main_node = get_tree().current_scene
	var py = main_node.get_floor_y(px, pz) if main_node.has_method("get_floor_y") else 0.0
	pickup.position = Vector3(px, py + 0.5, pz)
	get_parent().add_child(pickup)

## Tope de orbes de XP en el suelo (Quality.xp_orbs_max: menos en móvil): pasado el tope, el XP se
## suma al orbe más reciente en vez de crear otro nodo con partículas.
var _xp_orbs: Array[XPOrb] = []

## Una matanza (decenas de bajas en un frame) instanciaba decenas de gemas a la vez: ~0,1 ms cada una
## en PC, el mayor coste del frame de la matanza. Pasado este cupo por frame, las gemas esperan en cola
## y salen en los frames siguientes (unos pocos frames: no se nota en pantalla).
const ORB_SPAWNS_PER_FRAME := 6
var _orb_frame := -1
var _orb_frame_count := 0
var _orb_queue: Array = []          ## [pos, xp] pendientes

func spawn_xp_orb(pos: Vector3, xp: float = 1.0) -> void:
	if not xp_orb_scene:
		return
	var frame := Engine.get_process_frames()
	if frame != _orb_frame:
		_orb_frame = frame
		_orb_frame_count = 0
	if _orb_frame_count >= ORB_SPAWNS_PER_FRAME or not _orb_queue.is_empty():
		if _orb_queue.size() >= Quality.xp_orbs_max():
			_orb_queue[_orb_queue.size() - 1][1] += xp     # cola llena: se funde con la última
		else:
			_orb_queue.append([pos, xp])
		set_process(true)
		return
	_orb_frame_count += 1
	_spawn_xp_orb_now(pos, xp)

func _process(_delta: float) -> void:
	if _orb_queue.is_empty():
		set_process(false)
		return
	var frame := Engine.get_process_frames()
	if frame != _orb_frame:
		_orb_frame = frame
		_orb_frame_count = 0
	while not _orb_queue.is_empty() and _orb_frame_count < ORB_SPAWNS_PER_FRAME:
		var it: Array = _orb_queue.pop_front()
		_orb_frame_count += 1
		_spawn_xp_orb_now(it[0], it[1])

func _spawn_xp_orb_now(pos: Vector3, xp: float) -> void:
	var cap := Quality.xp_orbs_max()
	# Los recogidos se quitan solo al llegar al tope (no un Array nuevo por cada enemigo muerto)
	if _xp_orbs.size() >= cap:
		_xp_orbs = _xp_orbs.filter(func(o): return is_instance_valid(o) and o.is_active())
	if _xp_orbs.size() >= cap:
		var last: XPOrb = _xp_orbs[_xp_orbs.size() - 1]
		last.add_xp(xp)    # fusión: la última gema absorbe la nueva y crece
		return
	var at := pos + Vector3(0, 0.5, 0)
	# Reciclada: una gema ya recogida vuelve a salir (sin instanciar la escena ni liberarla al recogerla)
	while not _free_orbs.is_empty():
		var o = _free_orbs.pop_back()
		if is_instance_valid(o) and o.is_inside_tree() and o.get_parent() == get_parent():
			o.reactivate(at, xp)
			_xp_orbs.append(o)
			return
	var orb = xp_orb_scene.instantiate()
	orb.position = at
	orb.xp_amount = xp
	orb.pool_owner = self
	get_parent().add_child(orb)
	_xp_orbs.append(orb)

## Gemas recogidas esperando la siguiente muerte. Sin tipo: puede guardar gemas ya liberadas
## (cambio de nivel), que se descartan al sacarlas.
var _free_orbs: Array = []

## La gema recogida se esconde y queda para reutilizarla (XPOrb._release).
func recycle_xp_orb(orb: XPOrb) -> void:
	orb.deactivate()
	_xp_orbs.erase(orb)
	if _free_orbs.size() < Quality.xp_orbs_max():
		_free_orbs.append(orb)
	else:
		orb.queue_free()

func spawn_debug_orbs() -> void:
	if not player: return
	for i in range(2):
		var pickup = item_pickup_scene.instantiate()
		var offset = Vector3(randf_range(-2.0, 2.0), 0.0, randf_range(-2.0, 2.0))
		pickup.position = player.global_position + offset
		get_parent().add_child(pickup)
