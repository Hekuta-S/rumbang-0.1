extends Node
class_name WaveManager

## Aparición CONTINUA de enemigos: no hay oleadas ni pisos. Los enemigos salen siempre y la
## presión sube con el tiempo de partida (GameState.elapsed_time): intervalo menor, lotes más
## grandes, más enemigos vivos a la vez, tipos nuevos y más vida/daño. A los BOSS_TIME_S
## aparece el Nigromante (una sola vez) y la aparición normal baja mientras siga vivo.
## Al morir el jefe se emite boss_died y se detiene la aparición (salvo en el modo infinito:
## continue_endless() la reanuda y la dificultad sigue subiendo sin tope).
## RunEvents (hijo) añade los eventos de la partida: mareas, élites, minijefe, cofre maldito y santuarios.

signal enemy_died(pos: Vector3, gold_val: int, xp: float)
signal boss_died(pos: Vector3, gold_val: int)

## 6 min + 70 s = 7:10
const BOSS_TIME_S: float = 430.0
## Fracción de la aparición normal que se mantiene mientras el jefe está vivo.
const BOSS_SPAWN_FACTOR: float = 0.35

# Curva de intensidad: se interpola de "inicio" a "final" entre 0 y BOSS_TIME_S.
const INTERVAL_START: float = 2.4
const INTERVAL_END: float = 0.25
const BATCH_START: int = 1
const BATCH_END: int = 6
const ALIVE_CAP_START: int = 18
## Escalado por minuto de partida.
const HP_PER_MINUTE: float = 0.15
const DAMAGE_PER_MINUTE: float = 0.06
## Inicio más suave: la vida arranca en EARLY_HP_FACTOR y sube a 100 % en EARLY_RAMP_S segundos
## (el goblin normal, 35 PV, muere de 1 golpe al principio).
const EARLY_HP_FACTOR: float = 0.28
const EARLY_RAMP_S: float = 180.0
## Modo infinito: vida y daño extra por minuto pasado el jefe.
const ENDLESS_HP_PER_MINUTE: float = 0.45
const ENDLESS_DAMAGE_PER_MINUTE: float = 0.12
## Menos enemigos en toda la partida (ajuste global sobre el director): el intervalo entre lotes se
## multiplica por SPAWN_INTERVAL_MULT y el tope de vivos por ALIVE_CAP_MULT.
const SPAWN_INTERVAL_MULT: float = 1.25
const ALIVE_CAP_MULT: float = 0.85
## Los enemigos que aparecen van siendo más rápidos: +SPEED_PER_MINUTE por minuto de partida, hasta
## +SPEED_MAX_BONUS (se alcanza hacia el minuto 9; el modo infinito no lo supera).
const SPEED_PER_MINUTE: float = 0.04
const SPEED_MAX_BONUS: float = 0.35
## Cofre maldito: más enemigos por lote mientras dura.
const CURSE_BATCH_MULT: float = 1.6

## = ProceduralMap.play_half (143) menos un margen: el mapa de Supervivencia mide 320 m de lado (antes ±95).
const PLAYABLE_MIN_X: float = -140.0
const PLAYABLE_MAX_X: float = 140.0
const PLAYABLE_MIN_Z: float = -140.0
const PLAYABLE_MAX_Z: float = 140.0

var spawn_timer: Timer
var player: Node3D
var wave_config: Dictionary = {}

var _running: bool = false
## Apariciones pendientes: se instancian como máximo MAX_SPAWNS_PER_FRAME por frame para repartir el coste.
const MAX_SPAWNS_PER_FRAME := 2
var _pending_spawns: int = 0
var _boss: Node = null
var _boss_spawned: bool = false
var endless: bool = false
var events: RunEvents
var _curse_until: float = 0.0

## Beta: si ningún enemigo está a menos de ISOLATED_DIST m del jugador (se ha alejado de la horda o los ha
## ido matando), los siguientes aparecen CERCA (a NEAR_RING m, no a 16–24) y el tope de vivos no los frena.
const ISOLATED_DIST := 34.0
const ISOLATED_FROM := 8.0           ## s de partida antes de aplicarlo (el arranque ya es tranquilo)
const NEAR_RING := Vector2(9.0, 14.0)
const ISOLATED_MIN_BATCH := 3
const ISOLATED_INTERVAL_MULT := 0.5
var _near_pending: int = 0           ## apariciones pendientes que salen en el anillo cercano
var _near_scratch: Array = []

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
	events = RunEvents.new()
	events.name = "RunEvents"
	events.waves = self
	add_child(events)
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
	_near_pending = 0
	_flyer_next = 0.0
	endless = false
	_rush_announced = false
	_curse_until = 0.0
	_running = true
	_pending_spawns = 2
	spawn_timer.start(_current_interval())
	events.start(p_player)

## Tras vencer al jefe: la partida sigue sin final y cada minuto más dura.
func continue_endless() -> void:
	endless = true
	_running = true
	spawn_timer.start(_current_interval())

## Cofre maldito: CURSE_BATCH_MULT veces más enemigos durante `seconds`.
func curse(seconds: float) -> void:
	_curse_until = _elapsed() + seconds

func is_cursed() -> bool:
	return _elapsed() < _curse_until

func _process(_delta: float) -> void:
	var budget := MAX_SPAWNS_PER_FRAME
	while _pending_spawns > 0 and budget > 0:
		_pending_spawns -= 1
		budget -= 1
		_spawn_single_enemy()
	_tick_flyers()
	_tick_critters()

# ── Voladores (cuervos) ──────────────────────────────────────────────────
## Desde FLYER_FROM s sueltan cuervos (DungeonCrow) aparte de la horda: son nodos con su propia IA, no EnemyData.
## El tope sube con el tiempo (flyer_cap) y se reparte el aparecer cada FLYER_GAP s.
const FLYER_FROM := 60.0
const FLYER_GAP := 11.0
const FLYER_HEIGHT := 3.0             ## m sobre el suelo a los que aparecen
var _flyer_next := 0.0

## Cuervos vivos a la vez que permite el minuto `minutes` de partida.
static func flyer_cap(minutes: float) -> int:
	return clampi(1 + int(minutes * 1.1), 1, 7)

func flyer_count() -> int:
	var n := 0
	for e in get_tree().get_nodes_in_group("flyers"):
		if is_instance_valid(e) and not e.is_dead():
			n += 1
	return n

func _tick_flyers() -> void:
	if not _running or GameData.game_mode != "survival" or player == null or not is_instance_valid(player):
		return
	var t := _elapsed()
	if t < FLYER_FROM or t < _flyer_next:
		return
	_flyer_next = t + FLYER_GAP * randf_range(0.8, 1.3)
	if flyer_count() >= int(ceil(flyer_cap(t / 60.0) * Quality.crowd_factor)):
		return
	spawn_flyer()

## Suelta un cuervo (en el anillo de aparición, en el aire) con la vida y el daño del momento de la partida.
func spawn_flyer(at: Vector3 = Vector3.INF) -> DungeonCrow:
	var pos: Vector3 = _random_spawn_pos() if at == Vector3.INF else at
	pos.y += FLYER_HEIGHT
	var crow := DungeonCrow.new()
	crow.name = "Crow"
	crow.position = pos
	crow.add_to_group("flyers")
	var sc := _stat_scale()
	get_parent().add_child(crow)
	crow.max_hp *= sc.x
	crow.hp = crow.max_hp
	crow.damage_mult = 1.6 * sc.y         # un mordisco de 1,5 → lo que pega un goblin normal de supervivencia
	crow.died.connect(_on_flyer_died)
	return crow

func _on_flyer_died(crow: DungeonGoblin) -> void:
	RunStats.kills += 1
	var p := crow.global_position
	var ground: float = crow.ground_y() if crow.has_method("ground_y") else p.y
	var xp := XpCurve.xp_for_type(EnemyData.EnemyType.NORMAL_GOBLIN) * DungeonCrow.XP_MULT
	enemy_died.emit(Vector3(p.x, ground, p.z), crow.gold_reward, xp * xp_rush_mult(_elapsed(), wave_config))

# ── Criaturas de las cloacas (ratas y babosas) ───────────────────────────
## Desde CRITTER_FROM s salen ratas, babosas y babosas rojas aparte de la horda. Son EnemyData como los goblins
## (los mueve EnemySimNative en C++, con el enrutado de mesetas y rampas) y se dibujan como sprites 2D horneados
## (EnemyVisuals.CREATURE_KEYS). Aparecen en el anillo normal; dentro del Barrio del Desagüe hay más y salen antes.
const CRITTER_FROM := 40.0
const CRITTER_FROM_SEWERS := 8.0      ## mapa de Cloacas: casi desde el principio
const SEWER_KIND_PACE := 2.0          ## y babosas, rojas y gordas llegan el doble de pronto
const CRITTER_GAP := 8.0
## tipo, peso, minuto desde el que salen, tamaño del grupo
const CRITTER_KINDS := {
	"rat": {"type": EnemyData.EnemyType.RAT, "weight": 5.0, "from": 0.0, "pack": [3, 5]},
	"slug": {"type": EnemyData.EnemyType.SLUG, "weight": 2.0, "from": 1.5, "pack": [1, 1]},
	"bloater": {"type": EnemyData.EnemyType.BLOATER, "weight": 1.5, "from": 2.0, "pack": [1, 2]},
	"rat_big": {"type": EnemyData.EnemyType.RAT_BIG, "weight": 1.2, "from": 2.5, "pack": [1, 1]},
}
const CRITTER_SEWER_BONUS := 1.6      ## el tope sube así dentro del barrio
const CRITTER_SEWER_GAP := 0.6        ## y el intervalo se acorta así
const SLUG_SPLIT := 2                 ## crías que suelta la babosa al morir
var _critter_next := 0.0

## Criaturas vivas a la vez que permite el minuto `minutes` de partida.
static func critter_cap(minutes: float) -> int:
	return clampi(4 + int(minutes * 2.0), 4, 18)

func critter_count() -> int:
	var n := 0
	for e in EnemyRegistry.all():
		if e is EnemyData and not e.recycled and EnemyVisuals.is_creature_idx(e.vat_idx):
			n += 1
	return n

## ¿Está el jugador dentro del Barrio del Desagüe? (en el mapa de Cloacas, siempre)
func _player_in_sewers() -> bool:
	if map_theme() == "sewers":
		return true
	var map := _map_node()
	return map != null and player != null and map.has_method("in_district") \
		and map.in_district(Vector2(player.global_position.x, player.global_position.z))

func _map_node() -> Node:
	var scene := get_tree().current_scene if is_inside_tree() else null
	return scene.get_node_or_null("ProceduralMap") if scene else null

## Tema del mapa de la partida ("forest" / "sewers").
func map_theme() -> String:
	var map := _map_node()
	return String(map.get_theme()) if map and map.has_method("get_theme") else "forest"

## Mapa de Cloacas: fracción de la horda normal que sale como fauna de cloaca (ratas y babosas) en vez de
## goblins y zombis. Sube un poco con el tiempo; el resto sigue siendo la horda de siempre.
static func sewer_fauna_share(minutes: float) -> float:
	return clampf(0.7 + minutes * 0.015, 0.7, 0.8)

func _tick_critters() -> void:
	if not _running or GameData.game_mode != "survival" or player == null or not is_instance_valid(player):
		return
	if not EnemyVisuals.creatures_available():
		return
	var t := _elapsed()
	var city := map_theme() == "sewers"
	if t < (CRITTER_FROM_SEWERS if city else CRITTER_FROM) or t < _critter_next:
		return
	var sewers := _player_in_sewers()
	_critter_next = t + CRITTER_GAP * randf_range(0.8, 1.3) * (CRITTER_SEWER_GAP if sewers else 1.0)
	var cap := float(critter_cap(t / 60.0)) * Quality.crowd_factor * (CRITTER_SEWER_BONUS if sewers else 1.0)
	if critter_count() >= int(ceil(cap)):
		return
	spawn_critter_pack(_pick_critter_kind(t / 60.0 * (SEWER_KIND_PACE if city else 1.0)))

func _pick_critter_kind(minutes: float) -> String:
	var total := 0.0
	for k: String in CRITTER_KINDS:
		if minutes >= float(CRITTER_KINDS[k]["from"]):
			total += float(CRITTER_KINDS[k]["weight"])
	var r := randf() * total
	for k: String in CRITTER_KINDS:
		if minutes < float(CRITTER_KINDS[k]["from"]):
			continue
		r -= float(CRITTER_KINDS[k]["weight"])
		if r <= 0.0:
			return k
	return "rat"

func spawn_critter_pack(kind: String, at: Vector3 = Vector3.INF) -> Array:
	var pos: Vector3 = _random_spawn_pos() if at == Vector3.INF else at
	var main_node = get_tree().current_scene
	var pack: Array = CRITTER_KINDS[kind]["pack"]
	var out: Array = []
	for i in randi_range(int(pack[0]), int(pack[1])):
		var p := pos + Vector3(randf_range(-1.5, 1.5), 0.0, randf_range(-1.5, 1.5))
		p.y = main_node.get_floor_y(p.x, p.z) if main_node.has_method("get_floor_y") else pos.y
		out.append_array(_spawn_single_enemy(p, int(CRITTER_KINDS[kind]["type"])))
	return out

## La babosa grande suelta crías al morir; la roja, si la matan antes de reventar, revienta igual tras un momento.
func _creature_death(type_val: int, trait_name: String, burst_done: bool, dmg: float, pos: Vector3) -> void:
	match type_val:
		EnemyData.EnemyType.SLUG:
			if trait_name == "slug_small" or (not _running and not endless):
				return
			for i in SLUG_SPLIT:
				if EnemyRegistry.count() + _pending_spawns >= _alive_cap() + 10:
					return
				var off := Vector3(randf_range(-0.9, 0.9), 0.0, randf_range(-0.9, 0.9))
				_spawn_single_enemy(pos + off, EnemyData.EnemyType.SLUG, "slug_small")
		EnemyData.EnemyType.BLOATER:
			if burst_done:
				return                    # ya reventó (EnemyBehavior.fire_burst)
			var root := get_tree().current_scene
			if root != null:
				GroundBlast.spawn(root, pos, EnemyBehavior.BLOAT_DEATH_RADIUS, EnemyBehavior.BLOAT_DEATH_FUSE,
						dmg * EnemyBehavior.BLOAT_DEATH_DAMAGE_MULT, EnemyBehavior.BLOAT_RED)

func stop_run() -> void:
	_running = false
	_pending_spawns = 0
	spawn_timer.stop()

# ── Director de intensidad ───────────────────────────────────────────────
## La presión sale de wave_config.json["director"]: una línea temporal escrita a mano (intervalo, lote y
## tope de vivos por instante, interpolados) y, encima, un pulso cada block_s segundos
## (acumulación -> pico -> calma) para que haya respiro y sustos en vez de una rampa lineal.

## Parámetros del director en el segundo `t`: {interval, batch (float), cap (0..1), phase}.
## Pura (sin estado) para poder probarla. Sin "director" en la config cae a la curva lineal antigua.
static func director_params(t: float, cfg: Dictionary) -> Dictionary:
	var d: Dictionary = cfg.get("director", {})
	var tl: Array = d.get("timeline", [])
	if tl.is_empty():
		var p := clampf(t / BOSS_TIME_S, 0.0, 1.0)
		return {"interval": lerpf(INTERVAL_START, INTERVAL_END, p), "batch": lerpf(BATCH_START, BATCH_END, p), "cap": p, "phase": "build"}
	var a: Dictionary = tl[0]
	var b: Dictionary = tl[tl.size() - 1]
	if t >= float(b["t"]):
		a = b
	elif t > float(a["t"]):
		for i in range(1, tl.size()):
			if t <= float(tl[i]["t"]):
				a = tl[i - 1]
				b = tl[i]
				break
	var span := float(b["t"]) - float(a["t"])
	var f := 0.0 if span <= 0.0 else clampf((t - float(a["t"])) / span, 0.0, 1.0)
	var out := {
		"interval": lerpf(float(a["interval"]), float(b["interval"]), f),
		"batch": lerpf(float(a["batch"]), float(b["batch"]), f),
		"cap": lerpf(float(a["cap"]), float(b["cap"]), f),
		"phase": "build",
	}
	var block := float(d.get("block_s", 30.0))
	if t >= float(d.get("pulse_from", 45.0)) and block > 0.0:
		var pos := fmod(t, block) / block
		for ph in d.get("phases", []):
			if pos <= float(ph["until"]):
				out["interval"] = float(out["interval"]) * float(ph["interval_mult"])
				out["batch"] = float(out["batch"]) * float(ph["batch_mult"])
				out["phase"] = String(ph["name"])
				break
	return out

func current_phase() -> String:
	return String(director_params(_elapsed(), wave_config)["phase"])

## Factor de vida por la potencia del jugador: si va por delante del nivel esperado a esta altura, los
## enemigos aguantan más; si va por detrás, menos (una mala partida no se vuelve imposible).
func power_factor() -> float:
	var pw: Dictionary = wave_config.get("director", {}).get("power", {})
	if pw.is_empty() or player == null:
		return 1.0
	var xp = player.get("experience_comp")
	if xp == null:
		return 1.0
	var expected := 1.0 + _elapsed() * float(pw.get("expected_level_per_s", 0.0625))
	return clampf(1.0 + (float(xp.level) - expected) * float(pw.get("per_level", 0.02)),
		float(pw.get("min", 0.8)), float(pw.get("max", 1.35)))

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
	var interval: float = float(director_params(_elapsed(), wave_config)["interval"]) * RunModifiers.spawn_interval_mult() * SPAWN_INTERVAL_MULT
	if _tryhard():
		interval *= PlayerStatBlock.TRYHARD_SPAWN_INTERVAL
	if _boss_alive():
		interval /= BOSS_SPAWN_FACTOR
	return interval

func _current_batch() -> int:
	var batch := int(round(float(director_params(_elapsed(), wave_config)["batch"])))
	if _tryhard():
		batch = int(round(batch * PlayerStatBlock.TRYHARD_SPAWN_RATE))
	if is_cursed():
		batch = int(round(batch * CURSE_BATCH_MULT))
	return maxi(batch, 1)

func _alive_cap() -> int:
	var cap_frac: float = director_params(_elapsed(), wave_config)["cap"]
	return int(round(lerpf(ALIVE_CAP_START, Quality.alive_cap_end(), cap_frac) * Quality.crowd_factor * ALIVE_CAP_MULT))

# ── Bucle de aparición ───────────────────────────────────────────────────

func _on_spawn_tick() -> void:
	if not _running:
		return
	if not _boss_spawned and _elapsed() >= BOSS_TIME_S:
		_spawn_boss()
	_check_xp_rush()

	var alive := EnemyRegistry.count() + _pending_spawns
	var cap := _alive_cap() + (RunEvents.CURSE_CAP_BONUS if is_cursed() else 0)
	var isolated := is_player_isolated()
	var batch := _current_batch()
	if isolated:
		batch = maxi(batch, ISOLATED_MIN_BATCH)
		cap += batch                    # los lejanos no deben impedir que aparezcan cerca
	for i in range(batch):
		if alive >= cap:
			break
		_pending_spawns += 1
		alive += 1
		if isolated:
			_near_pending += 1
	spawn_timer.start(_current_interval() * (ISOLATED_INTERVAL_MULT if isolated else 1.0))

## ¿No hay ningún enemigo cerca del jugador? (la rejilla de EnemyRegistry; una consulta por tick de aparición)
func is_player_isolated() -> bool:
	if player == null or not is_instance_valid(player) or _elapsed() < ISOLATED_FROM:
		return false
	if _boss_alive():
		return false
	EnemyRegistry.query_radius_into(player.global_position, ISOLATED_DIST, _near_scratch)
	return _near_scratch.is_empty()

func _random_spawn_pos() -> Vector3:
	var player_pos = player.global_position if player else Vector3.ZERO
	var main_node = get_tree().current_scene
	# Anillo perimetral de 16 a 24 m en 360° alrededor del jugador (de 9 a 14 m si está aislado)
	var theta := randf_range(0.0, TAU)
	var dist := randf_range(16.0, 24.0)
	if _near_pending > 0:
		_near_pending -= 1
		dist = randf_range(NEAR_RING.x, NEAR_RING.y)
	var px: float = clamp(player_pos.x + cos(theta) * dist, PLAYABLE_MIN_X, PLAYABLE_MAX_X)
	var pz: float = clamp(player_pos.z + sin(theta) * dist, PLAYABLE_MIN_Z, PLAYABLE_MAX_Z)
	var py: float = (main_node.get_floor_y(px, pz) if main_node.has_method("get_floor_y") else 0.0)
	return Vector3(px, py, pz)

## Tabla de enemigos vigente: el último tramo cuyo "from" (segundos) ya pasó.
func _current_pool() -> Array:
	var stages: Array = wave_config.get("stages", [])
	var pool: Array = wave_config.get("default", [])
	var t := _elapsed()
	for stage in stages:
		if t >= float(stage.get("from", 0.0)):
			pool = stage.get("pool", pool)
	return pool

## Escala de vida (x) y de daño (y) de los enemigos que aparecen ahora (tiempo de partida, dificultad, modo infinito).
func _stat_scale() -> Vector2:
	var minutes := _elapsed() / 60.0
	var hp_mult := (1.0 + HP_PER_MINUTE * minutes) * lerpf(EARLY_HP_FACTOR, 1.0, clampf(_elapsed() / EARLY_RAMP_S, 0.0, 1.0)) * power_factor() * RunModifiers.enemy_hp_mult()
	var dmg_mult := (1.0 + DAMAGE_PER_MINUTE * minutes) * RunModifiers.enemy_damage_mult()
	if endless:
		var extra := maxf(_elapsed() - BOSS_TIME_S, 0.0) / 60.0
		hp_mult += ENDLESS_HP_PER_MINUTE * extra
		dmg_mult += ENDLESS_DAMAGE_PER_MINUTE * extra
	return Vector2(hp_mult, dmg_mult)

## Multiplicador de velocidad de los enemigos que aparecen ahora (sube poco a poco con el tiempo de partida).
func speed_mult() -> float:
	return 1.0 + minf(SPEED_PER_MINUTE * _elapsed() / 60.0, SPEED_MAX_BONUS)

## Crea un enemigo (o un grupo de zombis) y devuelve los que añadió. `at` fija el sitio (las
## mareas de RunEvents) y `type_override` el tipo (sin grupo de zombis).
func _spawn_single_enemy(at: Vector3 = Vector3.INF, type_override: int = -1, trait_override: String = "") -> Array:
	var spawn_pos: Vector3 = _random_spawn_pos() if at == Vector3.INF else at
	var main_node = get_tree().current_scene
	var type_val = 1
	var is_zombie = false
	var trait_id := trait_override

	var pool: Array = _current_pool()
	var minutes := _elapsed() / 60.0
	if type_override >= 0:
		type_val = type_override
	elif map_theme() == "sewers" and EnemyVisuals.creatures_available() and randf() < sewer_fauna_share(minutes):
		type_val = int(CRITTER_KINDS[_pick_critter_kind(minutes * SEWER_KIND_PACE)]["type"])
	elif pool.size() > 0:
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
				trait_id = String(entry.get("trait", ""))
				break

	var scale_hd := _stat_scale()
	var hp_mult: float = scale_hd.x
	var dmg_mult: float = scale_hd.y
	var spd_mult := speed_mult()
	var spawned: Array = []
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
		en.speed *= spd_mult
		en.xp_reward = XpCurve.xp_for_type(type_val)
		if trait_id != "":
			en.apply_trait(trait_id)
		EnemyManager.mark_dirty(en)       # la simulación nativa lee la velocidad nueva
		spawned.append(en)
	return spawned

# ── Jefe ─────────────────────────────────────────────────────────────────

func _spawn_boss() -> void:
	_boss_spawned = true
	var boss = NecromancerBossCreator.new().create_enemy()
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

func _on_enemy_died_internal(enemy_ref, pos: Vector3, gold_val: int) -> void:
	RunStats.kills += 1
	if enemy_ref != null and enemy_ref.trait_id == "splitter":
		_split.call_deferred(pos)
	if enemy_ref != null and EnemyVisuals.is_creature_idx(enemy_ref.vat_idx):
		_creature_death.call_deferred(enemy_ref.type, enemy_ref.trait_id, enemy_ref.special_hit, enemy_ref.damage, pos)
	var xp := float(enemy_ref.xp_reward) if enemy_ref != null else 1.0
	enemy_died.emit(pos, gold_val, xp * xp_rush_mult(_elapsed(), wave_config))

## Frenesí final (wave_config director.xp_rush): desde `from` s hasta el jefe las gemas valen `mult` veces
## más, para que antes del jefe se note una racha de subidas de nivel. Pura, para las pruebas.
static func xp_rush_mult(t: float, cfg: Dictionary) -> float:
	var r: Dictionary = cfg.get("director", {}).get("xp_rush", {})
	if r.is_empty() or t < float(r.get("from", 1e9)) or t >= BOSS_TIME_S:
		return 1.0
	return float(r.get("mult", 1.0))

var _rush_announced := false

func _check_xp_rush() -> void:
	if _rush_announced or endless:
		return
	if xp_rush_mult(_elapsed(), wave_config) > 1.0:
		_rush_announced = true
		if events != null:
			events.announce("¡FRENESÍ!", Color(0.35, 1.0, 0.45), "Las gemas valen más hasta que llegue el jefe")

## El hinchado suelta dos crías (si hay sitio bajo el tope de vivos).
func _split(pos: Vector3) -> void:
	if not _running and not endless:
		return
	for i in 2:
		if EnemyRegistry.count() + _pending_spawns >= _alive_cap() + 10:
			return
		var off := Vector3(randf_range(-1.2, 1.2), 0.0, randf_range(-1.2, 1.2))
		_spawn_single_enemy(pos + off, EnemyData.EnemyType.NORMAL_GOBLIN, "mini")

func _on_boss_died_internal(pos: Vector3, gold_val: int) -> void:
	RunStats.boss_killed = true
	if GameData.game_mode != "dungeon" and events:
		events.award_boss_souls(pos)   # sinergia entre modos: almas para el yunque (NIVEL de la mazmorra)
	stop_run()
	boss_died.emit(pos, gold_val)

## Reparte el pool de enemigos por tipo (según su frecuencia de aparición) hasta el tope de vivos de la calidad.
func _prefill_enemy_pool() -> void:
	var total := Quality.alive_cap_end()
	var share := {0: 0.2, 1: 0.3, 2: 0.12, 3: 0.1, 4: 0.18, 5: 0.1, 6: 0.1, 7: 0.03, 8: 0.05, 9: 0.04}
	var counts := {}
	for t in share:
		counts[t] = int(ceil(total * share[t]))
	EnemyManager.prefill(counts)
