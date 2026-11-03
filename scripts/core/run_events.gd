class_name RunEvents
extends Node

## Eventos de la partida de supervivencia (hijo de WaveManager), para que los 7 minutos tengan ritmo:
##  - Cada EVENT_INTERVAL s (EVENT_INTERVAL_ENDLESS en el modo infinito) un evento al azar sin repetir:
##      marea  : un muro de enemigos entra desde un lado (HORDE_*)
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
const EVENTS := ["horde", "elite", "cursed_chest"]

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

const CURSE_TIME := 45.0
const CURSE_CAP_BONUS := 30          ## enemigos vivos de más mientras dura la maldición
const CURSE_COLOR := Color(0.75, 0.3, 1.0)
const CHEST_LIFETIME := 40.0
const CHEST_GOLD := 60

const SHRINES := 2
const SHRINE_RADIUS := 3.5
const SHRINE_CHARGE := 6.0
const SHRINE_RESPAWN := 45.0
const SHRINE_HEAL := 0.15
const SHRINE_AMBUSH := 6
const SHRINE_COLOR := Color(0.3, 0.95, 1.0)

const ItemPickupScene := preload("res://scenes/objects/item_pickup.tscn")

var waves: WaveManager
var player: Node3D
var _running := false
var _next_event_t := FIRST_EVENT
var _last_event := ""
var _miniboss_done := false
var _queue: Array = []               ## [pos, tipo, modificador élite ("" = normal)]
var _elites: Array = []              ## [{enemy, max_hp, marker}]
var _shrines: Array = []             ## [{node, ring_mat, label, progress, ambushed}]
var _shrine_respawn: Array = []      ## instantes (s de partida) en que reaparecen
var _banner: Label

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
	for i in SHRINES:
		_spawn_shrine()

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
	for i in range(_shrine_respawn.size() - 1, -1, -1):
		if t >= float(_shrine_respawn[i]):
			_shrine_respawn.remove_at(i)
			_spawn_shrine()

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
			announce("¡ELITE!" if n == 1 else "¡ELITES!", ELITE_COLOR, "Derrótalo: suelta un objeto")
		"cursed_chest": _spawn_cursed_chest()

func _start_horde() -> void:
	var count := HORDE_BASE + int(_elapsed() / 60.0) * HORDE_PER_MINUTE
	var base_angle := randf() * TAU
	for i in count:
		var a := base_angle + deg_to_rad(randf_range(-HORDE_ARC_DEG, HORDE_ARC_DEG))
		var d := HORDE_DIST + randf_range(-2.0, 3.0)
		var type := EnemyData.EnemyType.ZOMBIE_GOBLIN if randf() < 0.35 else EnemyData.EnemyType.NORMAL_GOBLIN
		_queue.append([_ground(player.global_position + Vector3(cos(a), 0, sin(a)) * d), type, ""])
	announce("¡MAREA!", Color(1.0, 0.55, 0.2), "Una horda llega por un flanco")

func _queue_elite(mod: String, type: int = EnemyData.EnemyType.NORMAL_GOBLIN) -> void:
	var a := randf() * TAU
	_queue.append([_ground(player.global_position + Vector3(cos(a), 0, sin(a)) * 16.0), type, mod])

func _spawn_miniboss() -> void:
	_queue.append([_ground(player.global_position + Vector3(14, 0, 0).rotated(Vector3.UP, randf() * TAU)),
		EnemyData.EnemyType.HEAVY_BRUTE, "miniboss"])
	announce("¡MINIJEFE!", MINIBOSS_COLOR, "El Cacique Goblin se acerca")
	AudioManager.play("boss_sting", -4.0, 1.25)

func _drain_queue() -> void:
	var budget := SPAWNS_PER_FRAME
	while not _queue.is_empty() and budget > 0:
		budget -= 1
		var job: Array = _queue.pop_front()
		var spawned: Array = waves._spawn_single_enemy(job[0], job[1])
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
	en.scale *= float(m["scale"])
	en.hit_radius = 0.45 * en.scale.x
	en.hit_height = 1.6 * en.scale.y
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
	_spawn_item(pos)
	if entry["miniboss"]:
		_spawn_item(pos + Vector3(1.5, 0, 0))
		announce("¡MINIJEFE DERROTADO!", MINIBOSS_COLOR, "")
	HitFeedback.shake(0.3)

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
	get_tree().create_timer(CHEST_LIFETIME).timeout.connect(func():
		if is_instance_valid(chest):
			chest.queue_free())
	announce("COFRE MALDITO", CURSE_COLOR, "Gran botín... a un precio")

func _open_cursed_chest(chest: Node3D) -> void:
	var at := chest.global_position
	chest.queue_free()
	waves.curse(CURSE_TIME)
	GameState.get_instance().add_gold(CHEST_GOLD)
	var scene := get_tree().current_scene
	if scene and scene.get("facade"):
		scene.facade.update_gold(GameState.get_instance().gold)
	NecroVFX.shockwave(scene, at, 6.0, CURSE_COLOR)
	AudioManager.play("boss_sting", -8.0, 1.6)
	announce("¡MALDICION!", CURSE_COLOR, "Muchos más enemigos durante %d s" % int(CURSE_TIME))
	_spawn_item(at)

# ───────────────────────────── Santuarios ─────────────────────────────

func _spawn_shrine() -> void:
	var pos := Vector3.ZERO
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
	mat.albedo_color = Color(SHRINE_COLOR, 0.55)
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
	pmat.emission = SHRINE_COLOR
	pmat.emission_energy_multiplier = 0.6
	pillar.material_override = pmat
	pillar.position.y = 1.1
	node.add_child(pillar)
	var lbl := _label3d("SANTUARIO", SHRINE_COLOR, 22)
	lbl.position.y = 3.0
	node.add_child(lbl)
	get_tree().current_scene.add_child(node)
	node.global_position = pos
	_shrines.append({"node": node, "ring_mat": mat, "label": lbl, "progress": 0.0, "ambushed": false})

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
				_queue.append([_ground(node.global_position + Vector3(cos(a), 0, sin(a)) * 13.0), EnemyData.EnemyType.NORMAL_GOBLIN, ""])
		s["progress"] = clampf(float(s["progress"]) + (delta if inside else -delta * 0.5) / SHRINE_CHARGE, 0.0, 1.0)
		var p: float = s["progress"]
		(s["ring_mat"] as StandardMaterial3D).albedo_color = Color(SHRINE_COLOR.lerp(Color.WHITE, p), 0.55 + 0.45 * p)
		(s["label"] as Label3D).text = "SANTUARIO %d%%" % int(p * 100.0) if p > 0.0 else "SANTUARIO"
		if p >= 1.0:
			_activate_shrine(s)
			_shrines.remove_at(i)

func _activate_shrine(s: Dictionary) -> void:
	var node: Node3D = s["node"]
	RunStats.shrines += 1
	if player.has_method("heal") and player.get("health_comp"):
		player.heal(player.health_comp.max_hp * SHRINE_HEAL)
	NecroVFX.shockwave(get_tree().current_scene, node.global_position, SHRINE_RADIUS * 2.0, SHRINE_COLOR)
	AudioManager.play("kill_burst", -4.0, 1.3)
	announce("SANTUARIO ACTIVADO", SHRINE_COLOR, "Vida recuperada y un objeto")
	_spawn_item(player.global_position)
	node.queue_free()
	_shrine_respawn.append(_elapsed() + SHRINE_RESPAWN)

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
