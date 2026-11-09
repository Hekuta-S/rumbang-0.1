class_name NetWorld
extends Node

## Sincronización de la partida de mazmorra en red (hijo de la escena de juego, mismo nombre en todos los equipos).
##
## Autoridad: el ANFITRIÓN simula enemigos, encuentros (puertas, portal), niveles y vida de los jugadores
## caídos. Cada jugador controla su propio personaje y manda su estado ~20 veces por segundo.
##  - Jugadores: cada equipo crea un RemotePlayer por cada otro jugador y le aplica el estado recibido.
##  - Enemigos: el anfitrión avisa de cada enemigo nuevo (_spawn_enemy) y manda instantáneas (_snapshot);
##    los clientes los muestran como "puppets" (DungeonGoblin con puppet = true: sin IA). Un golpe sobre
##    un puppet se reenvía al anfitrión (_enemy_hit), que aplica el daño real.
##  - Daño a jugadores: los enemigos golpean al RemotePlayer; el anfitrión lo reenvía a su dueño (_take_damage).
##  - Efectos de enemigos (orbes, explosiones) y recogibles se replican como efectos visuales.
##  - Flujo: puertas, portal y cambio de nivel los decide el anfitrión; todos eligen arma y bajan juntos.
##  - Caídos: el jugador sin vida pasa a espectador (fantasma que sigue a un compañero) y revive con la mitad de
##    vida al despejar la caverna. Si caen todos, termina la partida.
##  - Servidor dedicado (Net.is_dedicated()): el anfitrión no juega. Su personaje local existe (la escena lo
##    necesita) pero queda congelado, invisible y fuera de "net_players": los enemigos solo ven a los clientes.

const PLAYER_HZ := 20.0
const ENEMY_HZ := 15.0
const SPECTATE_HEIGHT := 0.0
const REVIVE_HP := 0.5
const GAME_OVER_DELAY := 4.0

var player: CharacterBody3D           ## el jugador local
var encounter: DungeonEncounter
var remotes: Dictionary = {}          ## peer_id -> RemotePlayer
var _enemies: Dictionary = {}         ## id -> DungeonGoblin
var _next_id := 1
var _player_t := 0.0
var _enemy_t := 0.0
var _downed: Dictionary = {}          ## peer_id -> true (solo el anfitrión es la autoridad)
var _ready_next: Dictionary = {}      ## peer_id -> true (jugadores listos para bajar de nivel)
var _spectating := false
var _spec_target := 0
var _ghost_saved := {}

# ───────────────────────────── Arranque ─────────────────────────────

func setup(p_player: CharacterBody3D, p_encounter: DungeonEncounter) -> void:
	player = p_player
	encounter = p_encounter
	name = "NetWorld"
	Net.peer_left.connect(_on_peer_left)
	if Net.is_dedicated():
		_freeze_server_player()
		get_tree().node_added.connect(_on_node_added)
		for id in Net.peer_ids():
			_ensure_remote(id)
		Net.announce_world_ready()
		return
	player.add_to_group("net_players")
	Net.disconnected.connect(_on_disconnected)
	get_tree().node_added.connect(_on_node_added)
	# Las acciones de animación del jugador local (golpes, rodar, disparos) se avisan a los demás
	var ac = player.get("animation_controller")
	if ac:
		ac.net_action.connect(func(n: String, f: float, s: float): _to_ready(&"_recv_action", [n, f, s]))
		ac.net_held_shot.connect(func(s: float): _to_ready(&"_recv_held_shot", [s]))
	for id in Net.peer_ids():
		if id != Net.my_id():
			_ensure_remote(id)
	Net.announce_world_ready()

## RPC a los equipos que ya cargaron la partida (a los demás se perdería y llenaría su registro de errores).
func _to_ready(method: StringName, args: Array) -> void:
	for id in Net.world_ready:
		if id != Net.my_id():
			callv(&"rpc_id", [id, method] + args)

## Servidor dedicado: el personaje local no juega ni se ve (ni lo apuntan los enemigos).
func _freeze_server_player() -> void:
	player.set_meta("downed", true)
	player.collision_layer = 0
	player.collision_mask = 0
	player.visible = false
	player.process_mode = Node.PROCESS_MODE_DISABLED

func _ensure_remote(id: int) -> RemotePlayer:
	if remotes.has(id) and is_instance_valid(remotes[id]):
		return remotes[id]
	var rp := RemotePlayer.new()
	rp.name = "RP_%d" % id
	rp.peer_id = id
	rp.char_index = Net.char_of(id)
	get_parent().add_child(rp)
	remotes[id] = rp
	return rp

func _on_disconnected(_reason: String) -> void:
	# Se perdió la conexión (o el anfitrión cerró la partida): de vuelta al menú
	if is_inside_tree():
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/ui/dungeon_hub.tscn")

func _on_peer_left(id: int) -> void:
	if remotes.has(id):
		if is_instance_valid(remotes[id]):
			remotes[id].queue_free()
		remotes.erase(id)
	_downed.erase(id)
	_ready_next.erase(id)
	if Net.is_host():
		_check_all_down()
		_check_next_level()

# ───────────────────────────── Bucle ─────────────────────────────

func _physics_process(delta: float) -> void:
	if not is_instance_valid(player):
		return
	_player_t += delta
	if _player_t >= 1.0 / PLAYER_HZ and not Net.is_dedicated():
		_player_t = 0.0
		_to_ready(&"_recv_player_state", [_local_state()])
	if Net.is_host():
		_enemy_t += delta
		if _enemy_t >= 1.0 / ENEMY_HZ:
			_enemy_t = 0.0
			_send_snapshot()
	if _spectating:
		_follow_teammate(delta)

func _local_state() -> Array:
	var ac = player.get("animation_controller")
	var firing: bool = ac != null and Time.get_ticks_msec() / 1000.0 < float(ac.held_fire_until)
	var weapon: int = player.current_weapon() if player.has_method("current_weapon") else -1
	var eq := player.get("equipment") as PlayerEquipment
	var helmet := EquipmentDB.helmet_of(eq.get_item("casco")) if eq else ""
	var chest := EquipmentDB.armor_of(eq.get_item("pechera")) if eq else ""
	var legs := EquipmentDB.armor_of(eq.get_item("pantalones")) if eq else ""
	return [player.global_position, player.mesh.rotation.y, player.velocity, player.is_on_floor(), weapon,
		float(player.get("hp")), float(player.get("max_hp")), bool(player.get_meta("downed", false)), firing,
		CharacterLookApplier.helmet_net_index(helmet), CharacterLookApplier.armor_net_index(chest),
		CharacterLookApplier.armor_net_index(legs)]

@rpc("any_peer", "reliable")
func _recv_action(anim_name: String, from_time: float, speed: float) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if remotes.has(sender) and is_instance_valid(remotes[sender]):
		remotes[sender].play_action(anim_name, from_time, speed)

@rpc("any_peer", "reliable")
func _recv_held_shot(speed: float) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if remotes.has(sender) and is_instance_valid(remotes[sender]):
		remotes[sender].play_held_shot(speed)

@rpc("any_peer", "unreliable_ordered")
func _recv_player_state(state: Array) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender == Net.my_id() or not Net.players.has(sender):
		return
	_ensure_remote(sender).apply_state(state)

# ───────────────────────────── Enemigos (anfitrión) ─────────────────────────────

const KINDS := ["goblin", "brute", "mage", "zombie", "necro", "rat", "slug", "slug_small", "rat_king", "rat_big", "slug_red"]

static func kind_of(e: Node) -> String:
	if e is DungeonRatKing: return "rat_king"
	if e is DungeonNecromancer: return "necro"
	if e is DungeonBrute: return "brute"
	if e is DungeonMage: return "mage"
	if e is DungeonZombie: return "zombie"
	if e is DungeonBigRat: return "rat_big"
	if e is DungeonRat: return "rat"
	if e is DungeonBloater: return "slug_red"
	if e is DungeonSlug: return "slug_small" if e.small else "slug"
	return "goblin"

static func create_enemy(kind: String) -> DungeonGoblin:
	match kind:
		"brute": return DungeonBrute.new()
		"mage": return DungeonMage.new()
		"zombie": return DungeonZombie.new()
		"necro": return DungeonNecromancer.new()
		"rat": return DungeonRat.new()
		"slug": return DungeonSlug.new()
		"slug_small": return DungeonSlug.new().make_small()
		"rat_king": return DungeonRatKing.new()
		"rat_big": return DungeonBigRat.new()
		"slug_red": return DungeonBloater.new()
	return DungeonGoblin.new()

## Lo llama cada enemigo del anfitrión al entrar en escena (incluye los invocados por el Nigromante).
func register_enemy(e: DungeonGoblin) -> void:
	if not Net.is_host() or e.puppet:
		return
	var id := _next_id
	_next_id += 1
	e.net_id = id
	_enemies[id] = e
	e.died.connect(func(_g): _on_enemy_died(id))
	e.tree_exited.connect(func(): _enemies.erase(id))
	_spawn_enemy.rpc(id, kind_of(e), e.global_position, e.rotation.y)

func _on_enemy_died(id: int) -> void:
	_enemy_died.rpc(id)

@rpc("authority", "reliable")
func _spawn_enemy(id: int, kind: String, pos: Vector3, yaw: float) -> void:
	var e := create_enemy(kind)
	e.puppet = true
	e.net_id = id
	e.map = encounter.map
	e.name = "Puppet_%d" % id
	get_parent().add_child(e)
	e.global_position = pos
	e.rotation.y = yaw
	_enemies[id] = e
	e.tree_exited.connect(func(): _enemies.erase(id))
	SpawnDissolve.play(e.get_model(), e, 0.9, Color(1.0, 0.25, 0.1), 1.4)

func _send_snapshot() -> void:
	var list: Array = []
	for id in _enemies:
		var e: DungeonGoblin = _enemies[id]
		if not is_instance_valid(e) or e.is_dead():
			continue
		list.append([id, e.global_position, e.rotation.y, int(e.state), e.hp, e.attack_name(), e.attack_target(), e.stun_fraction()])
	if not list.is_empty():
		_snapshot.rpc(list)

@rpc("authority", "unreliable_ordered")
func _snapshot(list: Array) -> void:
	for s in list:
		var e: DungeonGoblin = _enemies.get(int(s[0]))
		if is_instance_valid(e):
			e.net_apply(s[1], s[2], int(s[3]), float(s[4]), str(s[5]), s[6])
			e.net_stun(float(s[7]))

@rpc("authority", "reliable")
func _enemy_died(id: int) -> void:
	var e: DungeonGoblin = _enemies.get(id)
	if is_instance_valid(e):
		e.net_die()

## Los clientes avisan al anfitrión de cada golpe que dan a un enemigo.
func send_enemy_hit(id: int, amount: float, kb: Vector3) -> void:
	_enemy_hit.rpc_id(1, id, amount, kb)

@rpc("any_peer", "reliable")
func _enemy_hit(id: int, amount: float, kb: Vector3) -> void:
	if not Net.is_host():
		return
	var e: DungeonGoblin = _enemies.get(id)
	if is_instance_valid(e) and not e.is_dead():
		e.take_damage(amount, kb)

# ───────────────────────────── Daño a jugadores ─────────────────────────────

## El anfitrión reenvía el golpe al dueño del personaje (que lleva su vida real).
func damage_player(peer: int, amount: float, dir: Vector3) -> void:
	if peer == Net.my_id():
		_apply_local_damage(amount, dir)
	else:
		_take_damage.rpc_id(peer, amount, dir)

@rpc("authority", "reliable")
func _take_damage(amount: float, dir: Vector3) -> void:
	_apply_local_damage(amount, dir)

func _apply_local_damage(amount: float, dir: Vector3) -> void:
	if is_instance_valid(player) and not bool(player.get_meta("downed", false)):
		player.take_damage(amount, dir)

# ───────────────────────────── Proyectiles de los jugadores ─────────────────────────────

## Escenas de proyectiles y efectos de las armas del jugador que se replican como copias visuales.
const PROJECTILE_SCENES := [
	"res://scenes/objects/bullet.tscn",
	"res://scenes/objects/spore_projectile.tscn",
	"res://scenes/objects/spore_cloud.tscn",
	"res://scenes/objects/dust_projectile.tscn",
	"res://scenes/objects/serpent_projectile.tscn",
	"res://scenes/objects/spear_projectile.tscn",
	"res://scenes/objects/spinning_axe_projectile.tscn",
	"res://scripts/objects/zombie_arm_projectile.tscn",
]
var _proj_seq := 0
var _ghosts: Dictionary = {}          ## "peer:id" -> nodo copia

func _on_node_added(node: Node) -> void:
	if node.has_meta("net_ghost") or node.scene_file_path == "" or not PROJECTILE_SCENES.has(node.scene_file_path):
		return
	if node is Node3D:
		_track_projectile.call_deferred(node)

## Mide hacia dónde y a qué velocidad va el proyectil (cuando su arma ya lo configuró) y lo anuncia.
func _track_projectile(node: Node3D) -> void:
	if not is_instance_valid(node) or not node.is_inside_tree():
		return
	await get_tree().physics_frame
	if not is_instance_valid(node):
		return
	var p0 := node.global_position
	await get_tree().physics_frame
	if not is_instance_valid(node):
		return
	var delta_p := node.global_position - p0
	var dt := get_physics_process_delta_time()
	var speed := delta_p.length() / dt
	var dir := delta_p.normalized() if delta_p.length() > 0.0001 else Vector3.ZERO
	_proj_seq += 1
	var id := _proj_seq
	_to_ready(&"_fx_proj", [id, PROJECTILE_SCENES.find(node.scene_file_path), node.global_position, Quaternion(node.global_basis.orthonormalized()), dir, speed])
	node.tree_exiting.connect(func(): _to_ready(&"_fx_proj_end", [id]))

@rpc("any_peer", "reliable")
func _fx_proj(id: int, scene_idx: int, pos: Vector3, rot: Quaternion, dir: Vector3, speed: float) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if scene_idx < 0 or scene_idx >= PROJECTILE_SCENES.size():
		return
	var scene := load(PROJECTILE_SCENES[scene_idx]) as PackedScene
	if scene == null:
		return
	var key := "%d:%d" % [sender, id]
	var ghost := NetGhost.spawn(get_parent(), scene, pos, rot, dir, speed)
	if ghost:
		_ghosts[key] = ghost

@rpc("any_peer", "reliable")
func _fx_proj_end(id: int) -> void:
	var key := "%d:%d" % [multiplayer.get_remote_sender_id(), id]
	var ghost = _ghosts.get(key)
	_ghosts.erase(key)
	if is_instance_valid(ghost):
		ghost.queue_free()

# ───────────────────────────── Efectos replicados ─────────────────────────────

func fx_orb(from: Vector3, dir: Vector3, speed: float, damage: float, color: Color) -> void:
	if Net.is_host():
		_fx_orb.rpc(from, dir, speed, damage, color)

@rpc("authority", "reliable")
func _fx_orb(from: Vector3, dir: Vector3, speed: float, damage: float, color: Color) -> void:
	var o := MageOrb.spawn(get_parent(), from, dir, speed, damage, color, RID())
	o.visual_only = true

func fx_blast(at: Vector3, radius: float, delay: float, damage: float, color: Color) -> void:
	if Net.is_host():
		_fx_blast.rpc(at, radius, delay, damage, color)

@rpc("authority", "reliable")
func _fx_blast(at: Vector3, radius: float, delay: float, damage: float, color: Color) -> void:
	var b := GroundBlast.spawn(get_parent(), at, radius, delay, damage, color)
	b.visual_only = true

## Recogibles: cada jugador tiene el suyo (botín personal), así que se crean en todos los equipos.
func fx_pickup(pos: Vector3, kind: int) -> void:
	if Net.is_host():
		_fx_pickup.rpc(pos, kind)
		if not Net.is_dedicated():
			_fx_pickup(pos, kind)

@rpc("authority", "reliable")
func _fx_pickup(pos: Vector3, kind: int) -> void:
	ResourcePickup.spawn(get_parent(), pos, kind)

# ───────────────────────────── Encuentros, portal y niveles ─────────────────────────────

func room_started(room: int) -> void:
	if Net.is_host():
		_room_started.rpc(room)

@rpc("authority", "reliable")
func _room_started(room: int) -> void:
	encounter.net_room_started(room)

func room_cleared(room: int) -> void:
	if Net.is_host():
		_room_cleared.rpc(room)
		_revive_downed()

@rpc("authority", "reliable")
func _room_cleared(room: int) -> void:
	encounter.net_room_cleared(room)

func portal_opened(pos: Vector3) -> void:
	if Net.is_host():
		_portal.rpc(pos)

@rpc("authority", "reliable")
func _portal(pos: Vector3) -> void:
	encounter.net_spawn_portal(pos)

## Este jugador ya eligió arma y está listo para bajar.
func player_ready_for_next() -> void:
	_ready_for_next.rpc_id(1)

@rpc("any_peer", "call_local", "reliable")
func _ready_for_next() -> void:
	if not Net.is_host():
		return
	_ready_next[multiplayer.get_remote_sender_id()] = true
	_check_next_level()

func _check_next_level() -> void:
	if not Net.is_host() or _ready_next.is_empty():
		return
	for id in Net.peer_ids():
		if not _ready_next.has(id) and not _downed.has(id):
			return
	_ready_next.clear()
	_next_level.rpc(randi())

@rpc("authority", "call_local", "reliable")
func _next_level(p_seed: int) -> void:
	Net.level_seed = p_seed
	_downed.clear()
	if _spectating:
		_end_spectate(1.0)
	encounter.net_next_level()

# ───────────────────────────── Caídos, espectador y reanimación ─────────────────────────────

## El jugador local se quedó sin vida.
func on_local_death() -> void:
	_player_down.rpc_id(1)
	_begin_spectate()

@rpc("any_peer", "call_local", "reliable")
func _player_down() -> void:
	if not Net.is_host():
		return
	var peer := multiplayer.get_remote_sender_id()
	if peer == 0:
		peer = 1
	_downed[peer] = true
	_check_all_down()
	_check_next_level()

func _check_all_down() -> void:
	if not Net.is_host() or Net.players.is_empty():
		return
	for id in Net.peer_ids():
		if not _downed.has(id):
			return
	_game_over.rpc()

@rpc("authority", "call_local", "reliable")
func _game_over() -> void:
	if Net.is_dedicated():
		# Los clientes ven el fin y salen; el servidor vuelve a la sala tras el mismo rato
		await get_tree().create_timer(GAME_OVER_DELAY + 1.0).timeout
		Net.server_back_to_lobby()
		return
	var facade = get_tree().current_scene.get("facade")
	if facade:
		facade.ui_manager.show_game_over()
	await get_tree().create_timer(GAME_OVER_DELAY).timeout
	var tree := get_tree()
	Net.leave("Fin de la partida")   # _on_disconnected ya vuelve al menú
	if is_instance_valid(tree) and tree.current_scene and tree.current_scene.get_node_or_null("NetWorld") == self:
		tree.change_scene_to_file("res://scenes/ui/dungeon_hub.tscn")

## Al despejar una caverna todos los caídos reviven con media vida junto a un compañero.
func _revive_downed() -> void:
	for peer in _downed.keys():
		if peer == 1 and not Net.is_dedicated():
			_revive()
		else:
			_revive.rpc_id(peer)
	_downed.clear()

@rpc("authority", "reliable")
func _revive() -> void:
	_end_spectate(REVIVE_HP)

func _begin_spectate() -> void:
	if _spectating or not is_instance_valid(player):
		return
	_spectating = true
	_spec_target = 0
	player.set_meta("downed", true)
	_ghost_saved = {"layer": player.collision_layer, "mask": player.collision_mask}
	player.collision_layer = 0
	player.collision_mask = 0
	player.set_physics_process(false)
	var model: Node3D = player.animation_controller.model if player.animation_controller else null
	if model:
		model.visible = false
	for wm in player.weapon_models.values():
		if is_instance_valid(wm):
			wm.visible = false
	if is_instance_valid(player.get("health_comp")):
		player.health_comp.set_invincibility(9999.0)

func _end_spectate(hp_fraction: float) -> void:
	if not _spectating:
		return
	_spectating = false
	player.remove_meta("downed")
	player.collision_layer = int(_ghost_saved.get("layer", 2))
	player.collision_mask = int(_ghost_saved.get("mask", 5))
	player.set_physics_process(true)
	player.is_playing_death_scan = false
	var model: Node3D = player.animation_controller.model if player.animation_controller else null
	if model:
		model.visible = true
	if player.has_method("_get_player_character_meshes"):
		for m in player._get_player_character_meshes():
			m.material_override = null
	var hc = player.get("health_comp")
	if is_instance_valid(hc):
		hc.invincibility_time = 1.5
		hc.hp = maxf(hc.max_hp * hp_fraction, 1.0)
		hc.heal(0.0)
	player.velocity = Vector3.ZERO

## Como fantasma, el cuerpo local sigue a un compañero vivo (la cámara va con él). Cualquier clic de ataque
## cambia de compañero.
func _follow_teammate(delta: float) -> void:
	var mates: Array = []
	for rp in remotes.values():
		if is_instance_valid(rp) and not rp.is_dead():
			mates.append(rp)
	if mates.is_empty():
		return
	if Input.is_action_just_pressed("attack") or VirtualInput.is_attacking:
		_spec_target += 1
	var tgt: Node3D = mates[_spec_target % mates.size()]
	player.global_position = player.global_position.lerp(tgt.global_position + Vector3(0, SPECTATE_HEIGHT, 0), 1.0 - exp(-8.0 * delta))
