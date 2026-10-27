class_name EnemyData
extends RefCounted

## Enemigo normal como DATOS (sin nodo): posición, vida, IA y estado viven en este objeto ligero.
## Lo mueve EnemyManager (un solo bucle para todos), lo dibuja EnemyVisuals (MultiMesh + animación
## horneada) y las armas lo encuentran por EnemyRegistry / EnemyQuery (rejilla espacial).
## Expone la misma interfaz que usaban los enemigos-nodo (global_position, take_damage, apply_slow,
## apply_status, is_in_group...), así que las armas no necesitan saber la diferencia.

signal enemy_died(enemy_ref, position, gold_val)
signal enemy_hit

enum EnemyType { GOBLIN_RANGED, NORMAL_GOBLIN, HEAVY_BRUTE, SNIPER_GOBLIN, ZOMBIE_GOBLIN, MORTAR_GOBLIN }

var type: int = EnemyType.GOBLIN_RANGED

# --- Atributos (los fija el comportamiento del tipo) ---
var max_hp: float = 30.0
var hp: float = 30.0
var speed: float = 6.0
var attack_range: float = 12.0
var damage: float = 2.0
var gold_reward: int = 6
var detection_range: float = 40.0

# --- Estado espacial ---
var global_position: Vector3 = Vector3.ZERO
var prev_position: Vector3 = Vector3.ZERO   ## posición del tick anterior (interpolación visual)
var velocity: Vector3 = Vector3.ZERO
var scale: Vector3 = Vector3.ONE
var yaw: float = 0.0
var hit_radius: float = 0.45
var hit_height: float = 1.6

# --- IA ---
var player: Node3D = null
var behavior: EnemyBehavior
var attack_cooldown: float = 0.0
var attack_windup: float = 0.0
var is_alerted: bool = false
var knockback_velocity: Vector3 = Vector3.ZERO
var slow_timer: float = 0.0
var slow_multiplier: float = 1.0
var base_color: Color = Color.WHITE
var recycled: bool = false
var active_idx: int = -1            ## posición en EnemyManager._active (-1 = no activo)

## Frecuencia de actualización según la distancia al jugador: cerca cada tick de física; a media distancia
## cada 2 ticks; lejos (o sin alertar) cada 4. EnemyManager acumula el tiempo y llama a update() con el
## delta acumulado; EnemyVisuals interpola la posición sobre ese intervalo.
const SPAN_MID_DIST := 14.0
const SPAN_FAR_DIST := 40.0
const SEP_RADIUS := 1.0
const SEP_STRENGTH := 2.2
const FloatingDamage = preload("res://scripts/objects/floating_damage.gd")
var _logic_timer: float = 0.0
var tick_span: int = 1          ## cada cuántos ticks se actualiza (1, 2 o 4)
var tick_age: int = 0           ## ticks transcurridos desde la última actualización
var _sep: Vector3 = Vector3.ZERO
var _cached_ground_y: float = 0.0
var ground_y: float = 0.0   ## altura del suelo bajo el enemigo (la mantiene EnemyMotion)
var _last_dist: float = 0.0

# --- Dibujo (ver EnemyVisuals) ---
var vat_key: String = ""
var vat_idx: int = -1               ## índice del modelo en EnemyVisuals (-1 = ninguno)
var vis_slot: int = -1              ## casilla fija en el cubo de impostores (-1 = ninguna)
var vat_idx_seed: int = 0           ## reparte el culling de cámara entre frames
var vat_phase: float = 0.0
var vat_walking: bool = false
var vat_flash: float = 0.0
var _offscreen: bool = false

# --- Daño continuo: agrupa números flotantes, sonido y destello ---
const DOT_THRESHOLD := 4.0
const DOT_NUMBER_INTERVAL := 0.4
const DOT_SFX_INTERVAL := 0.3
const DOT_FLASH_INTERVAL := 0.25
var _dot_pending: float = 0.0
var _last_number_t: float = -10.0
var _last_sfx_t: float = -10.0
var _last_flash_t: float = -10.0
## Lo activa StatusEffects durante el tick de veneno/sangrado/quemadura.
var _force_dot: bool = false
## Componente de estados (veneno...) que vive bajo el EnemyManager.
var status_fx: Node = null

func _init(p_type: int = EnemyType.GOBLIN_RANGED) -> void:
	type = p_type
	vat_phase = randf() * 10.0
	vat_key = EnemyVisuals.key_for_type(type)
	vat_idx = EnemyVisuals.index_for_type(type)
	vat_idx_seed = randi() % 3
	_apply_type_config()

func _apply_type_config() -> void:
	match type:
		EnemyType.GOBLIN_RANGED:
			behavior = EnemyBehavior.RangedGoblinBehavior.new(self)
		EnemyType.NORMAL_GOBLIN:
			behavior = EnemyBehavior.NormalGoblinBehavior.new(self)
		EnemyType.HEAVY_BRUTE:
			behavior = EnemyBehavior.HeavyBruteBehavior.new(self)
		EnemyType.SNIPER_GOBLIN:
			behavior = EnemyBehavior.SniperGoblinBehavior.new(self)
		EnemyType.ZOMBIE_GOBLIN:
			behavior = EnemyBehavior.ZombieGoblinBehavior.new(self)
		EnemyType.MORTAR_GOBLIN:
			behavior = EnemyBehavior.MortarGoblinBehavior.new(self)
	_reset_stats()

## Fija los atributos del tipo (vida, velocidad...) y el tamaño de impacto según la escala.
func _reset_stats() -> void:
	if behavior:
		behavior.apply_config()
	hp = max_hp
	hit_radius = 0.45 * scale.x
	hit_height = 1.6 * scale.y

# ───────────────────────────── Compatibilidad con la interfaz de nodo ─────────────────────────────

func is_in_group(group_name: StringName) -> bool:
	return group_name == &"enemies"

func get_rid() -> RID:
	return RID()

func is_inside_tree() -> bool:
	return not recycled

func apply_knockback(v: Vector3) -> void:
	knockback_velocity = (knockback_velocity + v).limit_length(24.0)

func set_enemy_color(col: Color) -> void:
	base_color = col

func get_transform_at(fraction: float) -> Transform3D:
	var pos := prev_position.lerp(global_position, fraction)
	var b := Basis(Vector3.UP, yaw).scaled(scale)
	return Transform3D(b, pos)

# ───────────────────────────── Ciclo de vida (pool) ─────────────────────────────

## Reutiliza este enemigo (venga del pool o recién creado) en `pos` con estado limpio.
func reactivate(pos: Vector3) -> void:
	recycled = false
	global_position = pos
	prev_position = pos
	_reset_stats()
	is_alerted = false
	attack_windup = 0.0
	slow_timer = 0.0
	slow_multiplier = 1.0
	knockback_velocity = Vector3.ZERO
	velocity = Vector3.ZERO
	_sep = Vector3.ZERO
	_dot_pending = 0.0
	_logic_timer = randf() * 0.2
	tick_span = 1
	tick_age = randi() % 4          # reparte las actualizaciones entre ticks
	_offscreen = false
	vat_flash = 0.0
	_cached_ground_y = pos.y
	ground_y = EnemyMotion.height_at(pos.x, pos.z) if EnemyMotion.available() else pos.y
	EnemyRegistry.register(self)
	if EnemyVisuals.instance != null:
		EnemyVisuals.instance.attach(self)

## En vez de destruirse vuelve al pool de su tipo.
func recycle() -> void:
	if recycled:
		return
	recycled = true
	EnemyRegistry.unregister(self)
	if EnemyVisuals.instance != null:
		EnemyVisuals.instance.detach(self)
	velocity = Vector3.ZERO
	if is_instance_valid(status_fx):
		StatusEffects.release_to_pool(status_fx)
	status_fx = null
	EnemyManager.release(self)

# ───────────────────────────── IA (la llama EnemyManager en cada tick de física) ─────────────────────────────

func update(delta: float) -> void:
	if recycled:
		return
	prev_position = global_position
	if player == null or not is_instance_valid(player):
		player = EnemyManager.player_node()
		return

	if attack_cooldown > 0.0:
		attack_cooldown -= delta
	if slow_timer > 0.0:
		slow_timer -= delta
		if slow_timer <= 0.0:
			slow_multiplier = 1.0
	if knockback_velocity.length_squared() > 0.01:
		knockback_velocity = knockback_velocity.move_toward(Vector3.ZERO, 30.0 * delta)
	else:
		knockback_velocity = Vector3.ZERO
	vat_flash = maxf(vat_flash - delta, 0.0)

	var to_player: Vector3 = player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()
	_last_dist = dist

	# Próxima frecuencia de actualización (lejos o sin alertar: menos veces)
	if not is_alerted or dist > SPAN_FAR_DIST:
		tick_span = 4
	elif dist > SPAN_MID_DIST:
		tick_span = 2
	else:
		tick_span = 1

	_logic_timer -= delta
	if _logic_timer <= 0.0:
		_logic_timer = 0.2 + randf() * 0.1
		if not is_alerted:
			if to_player.length_squared() <= detection_range * detection_range or hp < max_hp:
				is_alerted = true
		# Con mapa procedural la altura la mantiene EnemyMotion (ground_y); floor_y solo se usa como respaldo
		if not EnemyMotion.available():
			_cached_ground_y = EnemyManager.floor_y(global_position.x, global_position.z)
		_compute_separation()

	if not is_alerted:
		velocity = knockback_velocity
		_move(delta)
		vat_walking = Vector2(velocity.x, velocity.z).length_squared() > 0.2
		return

	if to_player.length_squared() > 0.01:
		yaw = atan2(-to_player.x, -to_player.z)

	var effective_speed := speed * slow_multiplier
	var next_vel := Vector3.ZERO
	if behavior:
		next_vel = behavior.process_ai(delta, to_player, dist, effective_speed)
	velocity = next_vel + knockback_velocity + _sep
	_move(delta)
	vat_walking = Vector2(velocity.x, velocity.z).length_squared() > 0.2

func _move(delta: float) -> void:
	velocity.y = 0.0
	if EnemyMotion.available():
		EnemyMotion.move(self, velocity, delta, player.global_position if player else global_position)
	else:
		global_position.x += velocity.x * delta
		global_position.z += velocity.z * delta
		global_position.y = _cached_ground_y

## Empuje suave para que los enemigos no se apilen en el mismo punto (usa la rejilla espacial).
func _compute_separation() -> void:
	_sep = Vector3.ZERO
	if not is_alerted:
		return
	var push := EnemyRegistry.separation_push(self, SEP_RADIUS)
	if push.length_squared() > 0.0001:
		_sep = push.limit_length(1.0) * SEP_STRENGTH

# ───────────────────────────── Daño, estados y efectos ─────────────────────────────

func apply_slow(duration: float, multiplier: float) -> void:
	slow_multiplier = minf(slow_multiplier, multiplier)
	slow_timer = maxf(slow_timer, duration)

## Aplica veneno/sangrado/quemadura (ver StatusEffects).
func apply_status(effect_id: String, dps: float, duration: float, source: Node = null,
		source_weapon: int = -1, stacks: int = 1) -> void:
	StatusEffects.apply_to(self, effect_id, dps, duration, source, source_weapon, stacks)

func take_damage(amount: float, knockback_dir: Vector3 = Vector3.ZERO) -> void:
	if recycled:
		return
	hp -= amount
	enemy_hit.emit()
	var now := Time.get_ticks_msec() / 1000.0
	var is_dot := amount < DOT_THRESHOLD or _force_dot

	if not is_dot or now - _last_sfx_t >= DOT_SFX_INTERVAL:
		_last_sfx_t = now
		AudioManager.play_at("hit", global_position, -10.0, randf_range(0.9, 1.1))

	if knockback_dir != Vector3.ZERO:
		var kb_len := knockback_dir.length()
		var kb_norm := knockback_dir.normalized()
		var push_speed: float = kb_len if kb_len > 1.05 else 3.0
		if behavior:
			push_speed *= behavior.get_knockback_resistance()
		knockback_velocity = kb_norm * clampf(push_speed, 1.0, 24.0)

	if not is_dot or now - _last_flash_t >= DOT_FLASH_INTERVAL:
		_last_flash_t = now
		vat_flash = 0.08
		if EnemyVisuals.instance != null:
			EnemyVisuals.instance.flash(self)

	# Número flotante: inmediato para golpes normales; agrupado para daño continuo
	var shown := amount
	var show_number := true
	if is_dot:
		_dot_pending += amount
		if now - _last_number_t >= DOT_NUMBER_INTERVAL:
			shown = _dot_pending
			_dot_pending = 0.0
		else:
			show_number = false
	if show_number:
		_last_number_t = now
		var root := EnemyManager.scene_root()
		if root:
			var is_crit := shown >= 24.0 or randf() < 0.15
			var col := Color(1.0, 0.32, 0.1) if is_crit else Color(1.0, 0.88, 0.22)
			FloatingDamage.spawn(root, global_position + Vector3(0, 1.4 * scale.y, 0), shown, col, is_crit)

	if not is_dot:
		HitFeedback.on_enemy_hit(self, amount, knockback_dir, hp <= 0.0)

	if hp <= 0.0:
		enemy_died.emit(self, global_position, gold_reward)
		recycle()
