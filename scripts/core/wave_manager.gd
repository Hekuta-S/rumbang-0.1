extends Node
class_name WaveManager

## Aparición CONTINUA de enemigos: no hay oleadas ni pisos. Los enemigos salen siempre y la
## presión sube con el tiempo de partida (GameState.elapsed_time): intervalo menor, lotes más
## grandes, más enemigos vivos a la vez, tipos nuevos y más vida/daño. A los BOSS_TIME_S
## aparece el Nigromante (una sola vez) y la aparición normal baja mientras siga vivo.
## Al morir el jefe se emite boss_died y se detiene la aparición.

signal enemy_died(pos: Vector3, gold_val: int)
signal boss_died(pos: Vector3, gold_val: int)

## 6 min + 70 s = 7:10
const BOSS_TIME_S: float = 430.0
## Fracción de la aparición normal que se mantiene mientras el jefe está vivo.
const BOSS_SPAWN_FACTOR: float = 0.35

# Curva de intensidad: se interpola de "inicio" a "final" entre 0 y BOSS_TIME_S.
const INTERVAL_START: float = 1.4
const INTERVAL_END: float = 0.25
const BATCH_START: int = 1
const BATCH_END: int = 6
const ALIVE_CAP_START: int = 40
## Escalado por minuto de partida.
const HP_PER_MINUTE: float = 0.15
const DAMAGE_PER_MINUTE: float = 0.06

const PLAYABLE_MIN_X: float = -95.0
const PLAYABLE_MAX_X: float = 95.0
const PLAYABLE_MIN_Z: float = -95.0
const PLAYABLE_MAX_Z: float = 95.0

var spawn_timer: Timer
var player: Node3D
var wave_config: Dictionary = {}

var _running: bool = false
## Apariciones pendientes: se instancian como máximo MAX_SPAWNS_PER_FRAME por frame para repartir el coste.
const MAX_SPAWNS_PER_FRAME := 2
var _pending_spawns: int = 0
var _boss: Node = null
var _boss_spawned: bool = false

func _ready() -> void:
	spawn_timer = Timer.new()
	spawn_timer.one_shot = true
	add_child(spawn_timer)
	spawn_timer.timeout.connect(_on_spawn_tick)
	var manager := EnemyManager.new()    # IA y pool de los enemigos normales (datos)
	manager.name = "EnemyManager"
	add_child(manager)
	var visuals := EnemyVisuals.new()    # los dibuja con MultiMesh
	visuals.name = "EnemyVisuals"
	add_child(visuals)
	_load_wave_config()

func _load_wave_config() -> void:
	var path = "res://resources/wave_config.json"
	if FileAccess.file_exists(path):
		var file = FileAccess.open(path, FileAccess.READ)
		var json = JSON.new()
		if json.parse(file.get_as_text()) == OK:
			wave_config = json.data

## Arranca (o reinicia) la partida: limpia enemigos y empieza a spawnear sin parar.
func start_run(p_player: Node3D) -> void:
	player = p_player
	# Los enemigos normales vuelven al pool; los jefes (nodos) se destruyen
	EnemyManager.recycle_all()
	_prefill_enemy_pool()
	for enemy in EnemyRegistry.all().duplicate():
		if enemy is Node:
			enemy.queue_free()
	_boss = null
	_boss_spawned = false
	_running = true
	_pending_spawns = 5
	spawn_timer.start(_current_interval())

func _process(_delta: float) -> void:
	var budget := MAX_SPAWNS_PER_FRAME
	while _pending_spawns > 0 and budget > 0:
		_pending_spawns -= 1
		budget -= 1
		_spawn_single_enemy()

func stop_run() -> void:
	_running = false
	_pending_spawns = 0
	spawn_timer.stop()

# ── Curva de dificultad ──────────────────────────────────────────────────

func _elapsed() -> float:
	return GameState.get_instance().elapsed_time

## 0..1 según el avance hacia el jefe (sigue en 1 después).
func _progress() -> float:
	return clampf(_elapsed() / BOSS_TIME_S, 0.0, 1.0)

func _boss_alive() -> bool:
	return _boss != null and is_instance_valid(_boss)

func _tryhard() -> bool:
	var sb = player.get("stat_block") if player else null
	return sb != null and sb.is_tryhard()

func _current_interval() -> float:
	var interval := lerpf(INTERVAL_START, INTERVAL_END, _progress())
	if _tryhard():
		interval *= PlayerStatBlock.TRYHARD_SPAWN_INTERVAL
	if _boss_alive():
		interval /= BOSS_SPAWN_FACTOR
	return interval

func _current_batch() -> int:
	var batch := int(round(lerpf(BATCH_START, BATCH_END, _progress())))
	if _tryhard():
		batch = int(round(batch * PlayerStatBlock.TRYHARD_SPAWN_RATE))
	return maxi(batch, 1)

func _alive_cap() -> int:
	return int(round(lerpf(ALIVE_CAP_START, Quality.alive_cap_end(), _progress())))

# ── Bucle de aparición ───────────────────────────────────────────────────

func _on_spawn_tick() -> void:
	if not _running:
		return
	if not _boss_spawned and _elapsed() >= BOSS_TIME_S:
		_spawn_boss()

	var alive := EnemyRegistry.count() + _pending_spawns
	var cap := _alive_cap()
	for i in range(_current_batch()):
		if alive >= cap:
			break
		_pending_spawns += 1
		alive += 1
	spawn_timer.start(_current_interval())

func _random_spawn_pos() -> Vector3:
	var player_pos = player.global_position if player else Vector3.ZERO
	var main_node = get_tree().current_scene
	var spawn_pos: Vector3 = player_pos
	for attempt in range(15):
		# Cerca del jugador para que no aparezcan donde el terreno aún no tiene colisiones
		var dist = randf_range(8.0, 16.0)
		var angle = randf_range(0, TAU)
		var px = clamp(player_pos.x + cos(angle) * dist, PLAYABLE_MIN_X, PLAYABLE_MAX_X)
		var pz = clamp(player_pos.z + sin(angle) * dist, PLAYABLE_MIN_Z, PLAYABLE_MAX_Z)
		var py = (main_node.get_floor_y(px, pz) if main_node.has_method("get_floor_y") else 0.0)
		spawn_pos = Vector3(px, py, pz)
		if spawn_pos.distance_to(player_pos) > 15.0:
			break
	return spawn_pos

## Tabla de enemigos vigente: el último tramo cuyo "from" (segundos) ya pasó.
func _current_pool() -> Array:
	var stages: Array = wave_config.get("stages", [])
	var pool: Array = wave_config.get("default", [])
	var t := _elapsed()
	for stage in stages:
		if t >= float(stage.get("from", 0.0)):
			pool = stage.get("pool", pool)
	return pool

## Crea un enemigo (o un grupo de zombis) y devuelve cuántos añadió.
func _spawn_single_enemy() -> int:
	var spawn_pos: Vector3 = _random_spawn_pos()
	var main_node = get_tree().current_scene
	var type_val = 1
	var is_zombie = false

	var pool: Array = _current_pool()
	if pool.size() > 0:
		var total_weight = 0.0
		for entry in pool:
			total_weight += float(entry.get("weight", 0))
		var roll = randf() * total_weight
		var current_weight = 0.0
		for entry in pool:
			current_weight += float(entry.get("weight", 0))
			if roll <= current_weight:
				type_val = int(entry.get("type", 1))
				is_zombie = bool(entry.get("is_zombie", false))
				break

	var minutes := _elapsed() / 60.0
	var hp_mult := 1.0 + HP_PER_MINUTE * minutes
	var dmg_mult := 1.0 + DAMAGE_PER_MINUTE * minutes
	var spawn_count = randi_range(3, 5) if is_zombie else 1
	for i in range(spawn_count):
		var pos: Vector3 = spawn_pos
		if i > 0:
			pos = spawn_pos + Vector3(randf_range(-2.5, 2.5), 0, randf_range(-2.5, 2.5))
			pos.y = (main_node.get_floor_y(pos.x, pos.z) if main_node.has_method("get_floor_y") else spawn_pos.y)
		var en: EnemyData = EnemyManager.spawn(type_val, pos)
		if en == null:
			continue
		if not en.enemy_died.is_connected(_on_enemy_died_internal):
			en.enemy_died.connect(_on_enemy_died_internal)
		# El tipo fija vida y daño base en _ready (al entrar al árbol): escalar después.
		en.max_hp *= hp_mult
		en.hp = en.max_hp
		en.damage *= dmg_mult
	return spawn_count

# ── Jefe ─────────────────────────────────────────────────────────────────

func _spawn_boss() -> void:
	_boss_spawned = true
	var boss = EnemyFactory.create_enemy("necromancer")
	if boss == null:
		return
	var player_pos = player.global_position if player else Vector3.ZERO
	var angle = randf_range(0, TAU)
	var px = clamp(player_pos.x + cos(angle) * 14.0, PLAYABLE_MIN_X, PLAYABLE_MAX_X)
	var pz = clamp(player_pos.z + sin(angle) * 14.0, PLAYABLE_MIN_Z, PLAYABLE_MAX_Z)
	var main_node = get_tree().current_scene
	var py = (main_node.get_floor_y(px, pz) if main_node.has_method("get_floor_y") else 0.0)
	boss.position = Vector3(px, py, pz)
	boss.connect("boss_died", _on_boss_died_internal)
	get_parent().add_child(boss)
	_boss = boss
	AudioManager.play("boss_sting")

func _exit_tree() -> void:
	EnemyMotion.reset()

func _on_enemy_died_internal(_enemy_ref, pos: Vector3, gold_val: int) -> void:
	enemy_died.emit(pos, gold_val)

func _on_boss_died_internal(pos: Vector3, gold_val: int) -> void:
	stop_run()
	boss_died.emit(pos, gold_val)

## Reparte el pool de enemigos por tipo (según su frecuencia de aparición) hasta el tope de vivos de la calidad.
func _prefill_enemy_pool() -> void:
	var total := Quality.alive_cap_end()
	var share := {0: 0.2, 1: 0.3, 2: 0.12, 3: 0.1, 4: 0.18, 5: 0.1}
	var counts := {}
	for t in share:
		counts[t] = int(ceil(total * share[t]))
	EnemyManager.prefill(counts)
