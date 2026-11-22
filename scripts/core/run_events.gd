class_name RunEvents
extends Node

## Eventos de la partida de supervivencia (hijo de WaveManager), para que los 7 minutos tengan ritmo:
##  - Cada EVENT_INTERVAL s (EVENT_INTERVAL_ENDLESS en el modo infinito) un evento al azar sin repetir:
##      marea  : un muro de enemigos entra desde un lado (HORDE_*)
##      cerco  : un anillo de goblins se cierra desde todos los lados (RING_*)
##      élite  : 1 enemigo grande con modificador (ELITE_MODS); al morir suelta un objeto
##      cofre maldito : cofre morado cerca del jugador; abrirlo da un objeto y oro, pero durante
##                      CURSE_TIME s salen muchos más enemigos (WaveManager.curse)
##  - A los MINIBOSS_TIME s, el minijefe: un bruto élite enorme que suelta dos objetos.
##  - Santuarios (SHRINES a la vez): quedarse dentro SHRINE_CHARGE s los activa (cura y un objeto);
##    al empezar a cargarlo atrae a un grupo. Reaparece otro SHRINE_RESPAWN s después.
## Cada evento se anuncia con un cartel arriba. Los objetos salen con ItemPickup (elección de objeto).

const EVENT_INTERVAL := 90.0
const EVENT_INTERVAL_ENDLESS := 55.0
const FIRST_EVENT := 70.0
const EVENTS := ["horde", "elite", "cursed_chest", "ring"]
## Formación (cuenta según el tiempo de partida; ver ring_count)
const RING_DIST := 20.0

const HORDE_BASE := 16
const HORDE_PER_MINUTE := 3
const HORDE_DIST := 22.0
const HORDE_ARC_DEG := 50.0
const SPAWNS_PER_FRAME := 3

## hp/speed/scale/damage multiplican; gold multiplica la recompensa
const ELITE_MODS := {
	"veloz": {"label": "VELOZ", "hp": 6.0, "speed": 1.7, "scale": 1.35, "damage": 1.3, "gold": 8},
	"acorazado": {"label": "ACORAZADO", "hp": 12.0, "speed": 0.8, "scale": 1.75, "damage": 1.4, "gold": 10},
	"furioso": {"label": "FURIOSO", "hp": 7.0, "speed": 1.2, "scale": 1.5, "damage": 2.2, "gold": 9},
}
const MINIBOSS_MOD := {"label": "MINIJEFE · CACIQUE GOBLIN", "hp": 45.0, "speed": 0.9, "scale": 2.4, "damage": 2.0, "gold": 25}
const MINIBOSS_TIME := 180.0
const ELITE_COLOR := Color(1.0, 0.3, 0.2)
const MINIBOSS_COLOR := Color(1.0, 0.75, 0.2)
const SOULS_COLOR := Color(0.75, 0.85, 1.0)

const CURSE_TIME := 45.0
const CURSE_CAP_BONUS := 30          ## enemigos vivos de más mientras dura la maldición
const CURSE_COLOR := Color(0.75, 0.3, 1.0)
const CHEST_LIFETIME := 40.0

const SHRINES := 4
## Tipos de santuario (se reparten sin repetir mientras se pueda): heal = original; fury y fortune, nuevos.
const SHRINE_KINDS := {
	"heal": {"title": "SANTUARIO", "color": Color(0.3, 0.95, 1.0), "sub": "Vida recuperada y un objeto"},
	"fury": {"title": "SANTUARIO DE FURIA", "color": Color(1.0, 0.35, 0.2), "sub": "Un objeto y FURIA: más daño y velocidad"},
	"fortune": {"title": "SANTUARIO DE FORTUNA", "color": Color(1.0, 0.82, 0.25), "sub": "Una lluvia de botín del cofre"},
}
const SHRINE_FURY_TIME := 30.0
## Torres de saltos (JumpTower) y cofres normales repartidos por el mapa
const TOWERS := 2
const TOWER_RESPAWN := 80.0
const TOWER_MIN_DIST := 18.0
const GROUND_CHESTS := 3
const GROUND_CHEST_RESPAWN := 60.0
const SHRINE_RADIUS := 3.5
const SHRINE_CHARGE := 6.0
const SHRINE_RESPAWN := 45.0
const SHRINE_HEAL := 0.15
const SHRINE_AMBUSH := 6
const SHRINE_COLOR := Color(0.3, 0.95, 1.0)
## Santuario en lo alto de una meseta (si el mapa tiene): sale con esta probabilidad y da oro y XP de más.
const SHRINE_HIGH_CHANCE := 0.6
const SHRINE_HIGH_EXTRA := ["gold", "xp"]
const HIGH_GROUND_COLOR := Color(1.0, 0.85, 0.45)

const ItemPickupScene := preload("res://scenes/objects/item_pickup.tscn")
## Dado del destino (FateDice): el primero a los DICE_FIRST s y luego cada DICE_EVERY (más un azar)
const DICE_FIRST := 45.0
const DICE_EVERY := Vector2(60.0, 100.0)
const DICE_DIST := Vector2(9.0, 15.0)
## Tatan, mercader de paso (SurvivalMerchant): el primero a los MERCHANT_FIRST s y luego cada MERCHANT_EVERY
const MERCHANT_FIRST := 100.0
const MERCHANT_EVERY := Vector2(110.0, 170.0)
const MERCHANT_DIST := Vector2(8.0, 12.0)

var waves: WaveManager
var player: Node3D
var _running := false
var _next_event_t := FIRST_EVENT
var _last_event := ""
var _miniboss_done := false
var _queue: Array = []               ## [pos, tipo, modificador élite ("" = normal), rasgo ("" = ninguno)]
var _elites: Array = []              ## [{enemy, max_hp, marker}]
var _shrines: Array = []             ## [{node, ring_mat, label, progress, ambushed}]
var _shrine_respawn: Array = []      ## instantes (s de partida) en que reaparecen
var _towers: Array = []              ## JumpTower vivas
var _chests: Array = []              ## TreasureChest normales vivos
var _loot_respawn: Array = []        ## [instante, "tower" | "chest"]
var _banner: Label
var _high_ground_told := false
var _mesa_check_t := 0.0
var _next_dice_t := DICE_FIRST
var _next_merchant_t := MERCHANT_FIRST

func start(p_player: Node3D) -> void:
	player = p_player
	_running = true
	_next_event_t = FIRST_EVENT
	_last_event = ""
	_miniboss_done = false
	_queue.clear()
	for e in _elites:
		_drop_marker(e)
	_elites.clear()
	for s in _shrines:
		if is_instance_valid(s["node"]):
			s["node"].queue_free()
	_shrines.clear()
	_shrine_respawn.clear()
	_high_ground_told = false
	_next_dice_t = DICE_FIRST
	_next_merchant_t = MERCHANT_FIRST
	for m in get_tree().get_nodes_in_group("survival_merchants"):
		m.queue_free()
	FateDice.clear_mods()
	for i in SHRINES:
		_spawn_shrine()
	for n in _towers + _chests:
		if is_instance_valid(n):
			n.queue_free()
	_towers.clear()
	_chests.clear()
	_loot_respawn.clear()
	for i in TOWERS:
		_spawn_tower()
	for i in GROUND_CHESTS:
		_spawn_ground_chest()

func _elapsed() -> float:
	return GameState.get_instance().elapsed_time

func _process(delta: float) -> void:
	if not _running or not is_instance_valid(player):
		return
	var t := _elapsed()
	if not waves._running and not waves.endless:
		return                        # partida terminada (victoria sin modo infinito)
	if not _miniboss_done and t >= MINIBOSS_TIME:
		_miniboss_done = true
		_spawn_miniboss()
	if t >= _next_event_t:
		_next_event_t = t + (EVENT_INTERVAL_ENDLESS if waves.endless else EVENT_INTERVAL)
		_start_random_event()
	_drain_queue()
	_update_elites()
	_update_shrines(delta)
	_check_high_ground(delta)
	if t >= _next_dice_t:
		_next_dice_t = t + randf_range(DICE_EVERY.x, DICE_EVERY.y)
		if get_tree().get_nodes_in_group("fate_dice").is_empty():
			spawn_dice()
	if t >= _next_merchant_t:
		_next_merchant_t = t + randf_range(MERCHANT_EVERY.x, MERCHANT_EVERY.y)
		if get_tree().get_nodes_in_group("survival_merchants").is_empty():
			spawn_merchant()
	for i in range(_shrine_respawn.size() - 1, -1, -1):
		if t >= float(_shrine_respawn[i]):
			_shrine_respawn.remove_at(i)
			_spawn_shrine()
	for i in range(_loot_respawn.size() - 1, -1, -1):
		if t >= float(_loot_respawn[i][0]):
			var what: String = _loot_respawn[i][1]
			_loot_respawn.remove_at(i)
			if what == "tower":
				_spawn_tower()
			else:
				_spawn_ground_chest()

# ───────────────────────────── Eventos ─────────────────────────────

func _start_random_event() -> void:
	var options: Array = EVENTS.filter(func(e): return e != _last_event)
	var ev: String = options[randi() % options.size()]
	_last_event = ev
	RunStats.events += 1
	match ev:
		"horde": _start_horde()
		"elite":
			var n := 2 if waves.endless or _elapsed() > 300.0 else 1
			for i in n:
				_queue_elite(ELITE_MODS.keys()[randi() % ELITE_MODS.size()])
			# Sin tilde: la fuente pixel no tiene "É" mayúscula
			announce("¡ELITE!" if n == 1 else "¡ELITES!", ELITE_COLOR, "Derrótalo: suelta un objeto y almas")
		"cursed_chest": _spawn_cursed_chest()
		"ring": _start_ring()

func _start_horde() -> void:
	var count := HORDE_BASE + int(_elapsed() / 60.0) * HORDE_PER_MINUTE
	var base_angle := randf() * TAU
	for i in count:
		var a := base_angle + deg_to_rad(randf_range(-HORDE_ARC_DEG, HORDE_ARC_DEG))
		var d := HORDE_DIST + randf_range(-2.0, 3.0)
		var type := EnemyData.EnemyType.ZOMBIE_GOBLIN if randf() < 0.35 else EnemyData.EnemyType.NORMAL_GOBLIN
		_queue.append([_ground(player.global_position + Vector3(cos(a), 0, sin(a)) * d), type, "", ""])
	announce("¡MAREA!", Color(1.0, 0.55, 0.2), "Una horda llega por un flanco")

static func ring_count(t: float) -> int:
	return clampi(16 + int(t / 60.0) * 3, 16, 40)

## Cerco: anillo completo alrededor del jugador, a RING_DIST, que se cierra al perseguirlo.
func _start_ring() -> void:
	var n := ring_count(_elapsed())
	var off := randf() * TAU
	for i in n:
		var a := off + TAU * float(i) / float(n)
		var type := EnemyData.EnemyType.ZOMBIE_GOBLIN if i % 4 == 0 else EnemyData.EnemyType.NORMAL_GOBLIN
		_queue.append([_ground(player.global_position + Vector3(cos(a), 0, sin(a)) * RING_DIST), type, "", ""])
	announce("¡CERCO!", Color(1.0, 0.45, 0.3), "Te rodean: abre un hueco")

func _queue_elite(mod: String, type: int = EnemyData.EnemyType.NORMAL_GOBLIN) -> void:
	var a := randf() * TAU
	_queue.append([_ground(player.global_position + Vector3(cos(a), 0, sin(a)) * 16.0), type, mod, ""])

func _spawn_miniboss() -> void:
	_queue.append([_ground(player.global_position + Vector3(14, 0, 0).rotated(Vector3.UP, randf() * TAU)),
		EnemyData.EnemyType.HEAVY_BRUTE, "miniboss", ""])
	announce("¡MINIJEFE!", MINIBOSS_COLOR, "El Cacique Goblin se acerca")
	AudioManager.play("boss_sting", -4.0, 1.25)

func _drain_queue() -> void:
	var budget := SPAWNS_PER_FRAME
	while not _queue.is_empty() and budget > 0:
		budget -= 1
		var job: Array = _queue.pop_front()
		var spawned: Array = waves._spawn_single_enemy(job[0], job[1], String(job[3]))
		if job[2] != "" and not spawned.is_empty():
			make_elite(spawned[0], job[2])

# ───────────────────────────── Élites ─────────────────────────────

## Convierte un enemigo normal en élite (o en el minijefe) y le pone su marca.
func make_elite(en: EnemyData, mod: String) -> void:
	var m: Dictionary = MINIBOSS_MOD if mod == "miniboss" else ELITE_MODS[mod]
	en.max_hp *= float(m["hp"])
	en.hp = en.max_hp
	en.speed *= float(m["speed"])
	en.damage *= float(m["damage"])
	en.gold_reward *= int(m["gold"])
	en.xp_reward = XpCurve.XP_MINIBOSS if mod == "miniboss" else XpCurve.XP_ELITE
	en.scale *= float(m["scale"])
	en.hit_radius = 0.45 * en.scale.x
	en.hit_height = 1.6 * en.scale.y
	EnemyManager.mark_dirty(en)
	var col := MINIBOSS_COLOR if mod == "miniboss" else ELITE_COLOR
	var entry := {"enemy": en, "max_hp": en.max_hp, "marker": _make_marker(en, String(m["label"]), col), "miniboss": mod == "miniboss"}
	entry["cb"] = _on_elite_died.bind(entry)
	en.enemy_died.connect(entry["cb"], CONNECT_ONE_SHOT)
	_elites.append(entry)

func _make_marker(en: EnemyData, text: String, col: Color) -> Node3D:
	var root := Node3D.new()
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.85
	torus.outer_radius = 1.0
	ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.scale = Vector3(en.scale.x, 0.25, en.scale.x)
	ring.position.y = 0.08
	root.add_child(ring)
	var lbl := _label3d("★ " + text, col, 26)
	lbl.position.y = 1.9 * en.scale.y + 0.4
	root.add_child(lbl)
	get_tree().current_scene.add_child(root)
	root.global_position = en.global_position
	return root

func _update_elites() -> void:
	for i in range(_elites.size() - 1, -1, -1):
		var e: Dictionary = _elites[i]
		var en: EnemyData = e["enemy"]
		# Reciclado sin morir (o reutilizado por el pool para otro enemigo): se olvida
		if en.recycled or not is_equal_approx(en.max_hp, float(e["max_hp"])):
			_drop_marker(e)
			_elites.remove_at(i)
			continue
		var mk: Node3D = e["marker"]
		if is_instance_valid(mk):
			mk.global_position = en.global_position

func _drop_marker(e: Dictionary) -> void:
	if is_instance_valid(e["marker"]):
		e["marker"].queue_free()
	var en: EnemyData = e["enemy"]
	if e.has("cb") and en.enemy_died.is_connected(e["cb"]):
		en.enemy_died.disconnect(e["cb"])

func _on_elite_died(_ref, pos: Vector3, _gold: int, entry: Dictionary) -> void:
	RunStats.elites += 1
	_drop_marker(entry)
	_elites.erase(entry)
	_award_souls(pos, bool(entry["miniboss"]))
	_spawn_item(pos)
	MapPickup.spawn(get_tree().current_scene, _ground(pos + Vector3(-1.5, 0, 0)), MapPickup.roll_kind())
	if entry["miniboss"]:
		_spawn_item(pos + Vector3(1.5, 0, 0))
		MapPickup.spawn(get_tree().current_scene, _ground(pos + Vector3(0, 0, 1.5)), MapPickup.roll_kind())
		announce("¡MINIJEFE DERROTADO!", MINIBOSS_COLOR, "")
	HitFeedback.shake(0.3)

## Almas del élite (SoulStats): se ingresan ya, para subir estadísticas en el yunque del Salón (mazmorra).
func _award_souls(pos: Vector3, miniboss: bool) -> void:
	var amount := SoulStats.survival_elite_souls(miniboss, _elapsed())
	SoulStats.add_souls(amount)
	RunStats.souls += amount
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("update_souls"):
		hud.update_souls(RunStats.souls)
	var lbl := _label3d("+%d ALMAS" % amount, SOULS_COLOR, 28)
	get_tree().current_scene.add_child(lbl)
	lbl.global_position = pos + Vector3(0, 2.6, 0)
	var tw := lbl.create_tween()
	tw.tween_property(lbl, "global_position:y", lbl.global_position.y + 1.6, 1.4)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 1.4).set_delay(0.5)
	tw.tween_callback(lbl.queue_free)

# ───────────────────────────── Cofre maldito ─────────────────────────────

func _spawn_cursed_chest() -> void:
	var a := randf() * TAU
	var at := _ground(player.global_position + Vector3(cos(a), 0, sin(a)) * 7.0)
	var chest := Area3D.new()
	chest.add_to_group("cursed_chests")
	chest.collision_layer = 0
	chest.collision_mask = 2          # el jugador
	var shape := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 1.4
	shape.shape = sph
	chest.add_child(shape)
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.1, 0.75, 0.75)
	box.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.1, 0.35)
	mat.emission_enabled = true
	mat.emission = CURSE_COLOR
	mat.emission_energy_multiplier = 0.8
	box.material_override = mat
	box.position.y = 0.4
	chest.add_child(box)
	var lbl := _label3d("COFRE MALDITO", CURSE_COLOR, 22)
	lbl.position.y = 1.6
	chest.add_child(lbl)
	get_tree().current_scene.add_child(chest)
	chest.global_position = at
	chest.body_entered.connect(func(body):
		if body.is_in_group("player") and is_instance_valid(chest) and not chest.is_queued_for_deletion():
			_open_cursed_chest(chest))
	var chest_ref: WeakRef = weakref(chest)
	get_tree().create_timer(CHEST_LIFETIME).timeout.connect(func():
		var c: Node = chest_ref.get_ref()
		if c != null:
			c.queue_free())
	announce("COFRE MALDITO", CURSE_COLOR, "Gran botín... a un precio")

func _open_cursed_chest(chest: Node3D) -> void:
	var at := chest.global_position
	chest.queue_free()
	waves.curse(CURSE_TIME)
	var scene := get_tree().current_scene
	NecroVFX.shockwave(scene, at, 6.0, CURSE_COLOR)
	AudioManager.play("boss_sting", -8.0, 1.6)
	var sb = player.get("stat_block") if is_instance_valid(player) else null
	var rewards := ChestRoulette.roll(sb.luck() if sb != null else 0.0)
	announce("¡MALDICION! · " + ChestRoulette.summary(rewards), CURSE_COLOR, "Muchos más enemigos durante %d s" % int(CURSE_TIME))
	HitFeedback.slowmo(0.6, 0.35)
	_grant_rewards(at, rewards)

## Reparte las recompensas del cofre una a una (tono creciente).
func _grant_rewards(at: Vector3, rewards: Array) -> void:
	for i in rewards.size():
		var r: String = rewards[i]
		var ang := TAU * float(i) / float(maxi(rewards.size(), 1))
		var spot := at + Vector3(cos(ang), 0, sin(ang)) * (0.0 if rewards.size() == 1 else 1.8)
		get_tree().create_timer(0.25 + ChestRoulette.STAGGER * i, true, false, true).timeout.connect(func():
			if is_instance_valid(self) and is_instance_valid(player):
				_give_reward(r, spot, i))

func _give_reward(r: String, spot: Vector3, i: int) -> void:
	var scene := get_tree().current_scene
	AudioManager.play("level-up", -6.0, 1.0 + 0.12 * float(i))
	match r:
		"item": _spawn_item(spot)
		"gold":
			GameState.get_instance().add_gold(ChestRoulette.GOLD_EACH)
			if scene and scene.get("facade"):
				scene.facade.update_gold(GameState.get_instance().gold)
		"xp":
			if scene and scene.get("facade"):
				scene.facade.spawn_xp_orb(_ground(spot), ChestRoulette.XP_EACH)
		_:
			MapPickup.spawn(scene, _ground(spot), r)

# ───────────────────────────── Santuarios ─────────────────────────────

## Primera vez que el jugador sube a una meseta: se explica la ventaja de altura.
func _check_high_ground(delta: float) -> void:
	if _high_ground_told:
		return
	_mesa_check_t -= delta
	if _mesa_check_t > 0.0:
		return
	_mesa_check_t = 0.5
	if EnemyMotion.player_mesa(player.global_position) >= 0:
		_high_ground_told = true
		announce("TERRENO ALTO", HIGH_GROUND_COLOR, "+%d %% de daño a los enemigos de abajo · trepan la pared despacio" % int(round((EnemyData.HIGH_GROUND_MULT - 1.0) * 100.0)))

## Cimas de meseta libres (sin santuario cerca y lejos del jugador).
func _free_vantage_points() -> Array:
	var out: Array = []
	var map := get_tree().get_first_node_in_group("procedural_map")
	if map == null or not map.has_method("get_vantage_points"):
		return out
	for v: Vector3 in map.get_vantage_points():
		var taken := false
		for s in _shrines:
			if is_instance_valid(s["node"]) and (s["node"] as Node3D).global_position.distance_to(v) < 6.0:
				taken = true
				break
		if not taken and (not is_instance_valid(player) or Vector2(v.x - player.global_position.x, v.z - player.global_position.z).length() > 20.0):
			out.append(v)
	return out

## Tipo para un santuario nuevo: uno que no esté ya en el mapa si se puede.
func _pick_shrine_kind() -> String:
	var present := _shrines.map(func(s): return s.get("kind", "heal"))
	var free: Array = SHRINE_KINDS.keys().filter(func(k): return not present.has(k))
	return (free if not free.is_empty() else SHRINE_KINDS.keys()).pick_random()

func _spawn_shrine() -> void:
	var kind := _pick_shrine_kind()
	var kcol: Color = SHRINE_KINDS[kind]["color"]
	var ktitle: String = SHRINE_KINDS[kind]["title"]
	var pos := Vector3.ZERO
	var high := false
	var spots := _free_vantage_points()
	if not spots.is_empty() and randf() < SHRINE_HIGH_CHANCE:
		pos = spots.pick_random()
		high = true
	else:
		for attempt in 12:
			pos = Vector3(randf_range(WaveManager.PLAYABLE_MIN_X + 10.0, WaveManager.PLAYABLE_MAX_X - 10.0), 0,
				randf_range(WaveManager.PLAYABLE_MIN_Z + 10.0, WaveManager.PLAYABLE_MAX_Z - 10.0))
			if not is_instance_valid(player) or Vector2(pos.x - player.global_position.x, pos.z - player.global_position.z).length() > 20.0:
				break
		pos = _ground(pos)
	var node := Node3D.new()
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = SHRINE_RADIUS - 0.25
	torus.outer_radius = SHRINE_RADIUS
	ring.mesh = torus
	ring.scale = Vector3(1.0, 0.2, 1.0)
	ring.position.y = 0.1
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(kcol, 0.55)
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(ring)
	var pillar := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.35
	cyl.bottom_radius = 0.5
	cyl.height = 2.2
	pillar.mesh = cyl
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.2, 0.25, 0.3)
	pmat.emission_enabled = true
	pmat.emission = kcol
	pmat.emission_energy_multiplier = 0.6
	pillar.material_override = pmat
	pillar.position.y = 1.1
	node.add_child(pillar)
	var title := ktitle + (" ALTO" if high else "")
	var lbl := _label3d(title, kcol, 22)
	lbl.position.y = 3.0
	node.add_child(lbl)
	get_tree().current_scene.add_child(node)
	node.global_position = pos
	_shrines.append({"node": node, "ring_mat": mat, "label": lbl, "progress": 0.0, "ambushed": false, "high": high, "kind": kind, "title": title, "color": kcol})

func _update_shrines(delta: float) -> void:
	for i in range(_shrines.size() - 1, -1, -1):
		var s: Dictionary = _shrines[i]
		var node: Node3D = s["node"]
		if not is_instance_valid(node):
			_shrines.remove_at(i)
			continue
		var d := Vector2(player.global_position.x - node.global_position.x, player.global_position.z - node.global_position.z).length()
		var inside := d <= SHRINE_RADIUS
		if inside and not s["ambushed"]:
			s["ambushed"] = true
			for k in SHRINE_AMBUSH:
				var a := TAU * float(k) / SHRINE_AMBUSH
				_queue.append([_ground(node.global_position + Vector3(cos(a), 0, sin(a)) * 13.0), EnemyData.EnemyType.NORMAL_GOBLIN, "", ""])
		s["progress"] = clampf(float(s["progress"]) + (delta if inside else -delta * 0.5) / SHRINE_CHARGE, 0.0, 1.0)
		var p: float = s["progress"]
		(s["ring_mat"] as StandardMaterial3D).albedo_color = Color((s["color"] as Color).lerp(Color.WHITE, p), 0.55 + 0.45 * p)
		var title: String = s["title"]
		(s["label"] as Label3D).text = "%s %d%%" % [title, int(p * 100.0)] if p > 0.0 else title
		if p >= 1.0:
			_activate_shrine(s)
			_shrines.remove_at(i)

func _activate_shrine(s: Dictionary) -> void:
	var node: Node3D = s["node"]
	RunStats.shrines += 1
	var kind: String = s.get("kind", "heal")
	var col: Color = s.get("color", SHRINE_COLOR)
	var high: bool = s.get("high", false)
	if kind == "heal" and player.has_method("heal") and player.get("health_comp"):
		player.heal(player.health_comp.max_hp * SHRINE_HEAL)
	NecroVFX.shockwave(get_tree().current_scene, node.global_position, SHRINE_RADIUS * 2.0, col)
	AudioManager.play("kill_burst", -4.0, 1.3)
	var sub: String = SHRINE_KINDS[kind]["sub"]
	match kind:
		"fury":
			# Strategy: reutiliza la misma furia del dado (antes: copia 4 de 4 del código de FURIA)
			FateOutcomes.FuryOutcome.stack("FURIA", 0.5, 0.2, SHRINE_FURY_TIME, col)
		"fortune":
			var sb = player.get("stat_block")
			_grant_rewards(node.global_position, ChestRoulette.roll(sb.luck() if sb != null else 0.0))
	announce("%s ACTIVADO" % s["title"], col, sub + (" · oro y XP" if high else ""))
	if high:
		_grant_rewards(node.global_position, SHRINE_HIGH_EXTRA)
	_spawn_item(player.global_position)
	node.queue_free()
	_shrine_respawn.append(_elapsed() + SHRINE_RESPAWN)

# ───────────────────────────── Torres de saltos y cofres ─────────────────────────────

## Punto libre en el mapa: lejos del jugador y de otras torres/cofres/santuarios, sin salirse de la zona jugable.
func _free_spot(min_player_dist: float) -> Vector3:
	var taken: Array = []
	for n in _towers + _chests:
		if is_instance_valid(n):
			taken.append((n as Node3D).global_position)
	for s in _shrines:
		if is_instance_valid(s["node"]):
			taken.append((s["node"] as Node3D).global_position)
	var pos := Vector3.ZERO
	for attempt in 16:
		pos = Vector3(randf_range(WaveManager.PLAYABLE_MIN_X + 10.0, WaveManager.PLAYABLE_MAX_X - 10.0), 0,
			randf_range(WaveManager.PLAYABLE_MIN_Z + 10.0, WaveManager.PLAYABLE_MAX_Z - 10.0))
		var ok := not is_instance_valid(player) or Vector2(pos.x - player.global_position.x, pos.z - player.global_position.z).length() > min_player_dist
		for o: Vector3 in taken:
			if Vector2(pos.x - o.x, pos.z - o.z).length() < 10.0:
				ok = false
		if ok:
			break
	return _ground(pos)

func _spawn_tower() -> void:
	if get_tree().current_scene == null:
		_loot_respawn.append([_elapsed() + 1.0, "tower"])
		return
	var tower := JumpTower.spawn(get_tree().current_scene, _free_spot(TOWER_MIN_DIST), player)
	_towers.append(tower)
	tower.claimed.connect(_on_tower_claimed)

func _on_tower_claimed(tower: JumpTower) -> void:
	var at := tower.global_position + Vector3(0, tower.top_y, 0)
	var sb = player.get("stat_block")
	var rewards := ChestRoulette.roll((sb.luck() if sb != null else 0.0) + 0.1)
	rewards.append("gold")
	announce("¡COFRE DE ALTURA!", HIGH_GROUND_COLOR, ChestRoulette.summary(rewards))
	NecroVFX.shockwave(get_tree().current_scene, at, 5.0, HIGH_GROUND_COLOR)
	_grant_rewards(at, rewards)
	_towers.erase(tower)
	_loot_respawn.append([_elapsed() + TOWER_RESPAWN, "tower"])
	# Deja la torre un rato (para bajar) y la quita después
	get_tree().create_timer(15.0).timeout.connect(func():
		if is_instance_valid(tower):
			tower.queue_free())

func _spawn_ground_chest() -> void:
	if get_tree().current_scene == null:
		_loot_respawn.append([_elapsed() + 1.0, "chest"])
		return
	var chest := TreasureChest.spawn(get_tree().current_scene, _free_spot(12.0), player)
	_chests.append(chest)
	chest.opened.connect(func(c: TreasureChest):
		var sb = player.get("stat_block")
		var rewards := ChestRoulette.roll(sb.luck() if sb != null else 0.0)
		announce("¡COFRE!", TreasureChest.GOLD, ChestRoulette.summary(rewards))
		_grant_rewards(c.global_position, rewards)
		_chests.erase(c)
		_loot_respawn.append([_elapsed() + GROUND_CHEST_RESPAWN, "chest"])
		get_tree().create_timer(2.5).timeout.connect(func():
			if is_instance_valid(c):
				c.queue_free()))

# ───────────────────────────── Utilidades ─────────────────────────────

func _spawn_item(at: Vector3) -> void:
	var pickup := ItemPickupScene.instantiate()
	get_tree().current_scene.add_child(pickup)
	pickup.global_position = _ground(at)

func _ground(p: Vector3) -> Vector3:
	var x := clampf(p.x, WaveManager.PLAYABLE_MIN_X, WaveManager.PLAYABLE_MAX_X)
	var z := clampf(p.z, WaveManager.PLAYABLE_MIN_Z, WaveManager.PLAYABLE_MAX_Z)
	var scene := get_tree().current_scene
	var y: float = scene.get_floor_y(x, z) if scene and scene.has_method("get_floor_y") else p.y
	return Vector3(x, y, z)

func _label3d(text: String, col: Color, size: int) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.fixed_size = true
	l.pixel_size = 0.0011
	l.font_size = size
	l.outline_size = 8
	l.modulate = col
	l.outline_modulate = Color(0.05, 0.02, 0.05)
	l.no_depth_test = true
	return l

## Dado del destino a unos metros del jugador (también lo usan las pruebas).
func spawn_dice() -> FateDice:
	var a := randf() * TAU
	var at := _ground(player.global_position + Vector3(cos(a), 0, sin(a)) * randf_range(DICE_DIST.x, DICE_DIST.y))
	var d := FateDice.spawn(get_tree().current_scene, at, FateDice.LIFETIME_SURVIVAL)
	announce("DADO DEL DESTINO", FateDice.GOLD_COLOR, "Ha aparecido un dado cerca: ¿te atreves a tirarlo?")
	return d

## Tatan, mercader de paso, a unos metros del jugador (también lo usan las pruebas).
func spawn_merchant() -> SurvivalMerchant:
	var a := randf() * TAU
	var at := _ground(player.global_position + Vector3(cos(a), 0, sin(a)) * randf_range(MERCHANT_DIST.x, MERCHANT_DIST.y))
	var m := SurvivalMerchant.spawn(get_tree().current_scene, at, player, _elapsed())
	if m.offers.is_empty():
		m.queue_free()
		return null
	announce("TATAN, MERCADER DE PASO", SurvivalMerchant.COLOR, "Vende un objeto, un tomo o una mejora · solo una compra")
	m.left.connect(func(bought: bool):
		if not bought:
			announce("TATAN SE HA IDO", SurvivalMerchant.COLOR, ""))
	return m

## Cartel grande arriba (también lo usa main.gd para el modo infinito).
func announce(title: String, col: Color, sub: String) -> void:
	if not is_instance_valid(_banner):
		var layer := CanvasLayer.new()
		layer.layer = 40
		add_child(layer)
		_banner = Label.new()
		_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_banner.position.y = 90.0
		_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(_banner)
	_banner.text = title if sub == "" else "%s\n%s" % [title, sub]
	RumbangStyle.style_title(_banner, 26, col, col)
	_banner.theme = RumbangStyle.get_theme()
	_banner.modulate.a = 0.0
	var tw := _banner.create_tween()
	tw.tween_property(_banner, "modulate:a", 1.0, 0.25)
	tw.tween_interval(2.4)
	tw.tween_property(_banner, "modulate:a", 0.0, 0.6)
