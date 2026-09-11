extends Node
class_name WaveManager

signal enemy_died(pos: Vector3, gold_val: int)
signal boss_died(pos: Vector3, gold_val: int)
signal wave_cleared()

var enemy_scene = preload("res://scenes/entities/enemy.tscn")
var boss_scene = preload("res://scenes/entities/boss.tscn")

var spawn_timer: Timer
var enemies_to_spawn_this_floor: int = 0
var enemies_spawned: int = 0
var current_level: int = 1

var player: Node3D

const PLAYABLE_MIN_X: float = -2300.0
const PLAYABLE_MAX_X: float = 2300.0
const PLAYABLE_MIN_Z: float = -2300.0
const PLAYABLE_MAX_Z: float = 2300.0

func _ready() -> void:
	spawn_timer = Timer.new()
	add_child(spawn_timer)
	spawn_timer.timeout.connect(_on_spawn_tick)

func start_wave(lvl: int, p_player: Node3D) -> void:
	current_level = lvl
	player = p_player
	
	# Clear existing enemies
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
		
	spawn_timer.stop()

	if lvl >= 3 and lvl % 3 == 0:
		# BOSS FLOOR
		var boss = boss_scene.instantiate()
		var main_node = get_tree().current_scene
		var boss_y = (main_node.get_floor_y(0, -12) if main_node.has_method("get_floor_y") else 0.0)
		boss.position = Vector3(0, boss_y, -12)
		boss.connect("boss_died", _on_boss_died_internal)
		_scale_boss(boss, int(lvl / 3.0))
		get_parent().add_child(boss)
		AudioManager.play("boss_sting")
	else:
		# NORMAL FLOOR
		enemies_to_spawn_this_floor = 25 + lvl * 15
		enemies_spawned = 0
		
		# Initial burst
		for i in range(5):
			_spawn_single_enemy()
			
		# Spawns every 1.2 seconds, getting slightly faster each level
		var interval = maxf(0.3, 1.2 - (lvl * 0.05))
		spawn_timer.start(interval)

func _on_spawn_tick() -> void:
	if enemies_spawned >= enemies_to_spawn_this_floor:
		spawn_timer.stop()
		return
		
	var batch = 1 + (current_level / 2)
	for i in range(batch):
		if enemies_spawned >= enemies_to_spawn_this_floor:
			break
		_spawn_single_enemy()

func _spawn_single_enemy() -> void:
	var enemy = enemy_scene.instantiate()
	
	var spawn_pos: Vector3
	var player_pos = player.global_position if player else Vector3.ZERO
	var main_node = get_tree().current_scene
	
	for attempt in range(15):
		# Reducir distancia de spawn para evitar que aparezcan en zonas donde el terreno aún no carga sus colisiones
		var dist = randf_range(8.0, 16.0)
		var angle = randf_range(0, TAU)
		var px = player_pos.x + cos(angle) * dist
		var pz = player_pos.z + sin(angle) * dist
		
		px = clamp(px, PLAYABLE_MIN_X, PLAYABLE_MAX_X)
		pz = clamp(pz, PLAYABLE_MIN_Z, PLAYABLE_MAX_Z)
		
		var py = (main_node.get_floor_y(px, pz) if main_node.has_method("get_floor_y") else 0.0)
		spawn_pos = Vector3(px, py, pz)
		
		if spawn_pos.distance_to(player_pos) > 15.0:
			break
			
	enemy.position = spawn_pos
	var roll = randf()
	var type_val = 1
	var is_zombie = false
	if roll < 0.45:
		type_val = 1 # NORMAL_GOBLIN
	elif roll < 0.70:
		type_val = 2 # HEAVY_BRUTE
	elif roll < 0.85:
		type_val = 0 # GOBLIN_RANGED
	elif roll < 0.93:
		type_val = 3 # SNIPER_GOBLIN
	else:
		type_val = 4 # ZOMBIE_GOBLIN
		is_zombie = true
		
	var spawn_count = randi_range(3, 5) if is_zombie else 1
	
	for i in range(spawn_count):
		var en = enemy if i == 0 else enemy_scene.instantiate()
		en.set("type", type_val)
		en.connect("enemy_died", _on_enemy_died_internal)
		
		if i == 0:
			en.position = spawn_pos
		else:
			var offset = Vector3(randf_range(-2.5, 2.5), 0, randf_range(-2.5, 2.5))
			var final_pos = spawn_pos + offset
			final_pos.y = (main_node.get_floor_y(final_pos.x, final_pos.z) if main_node.has_method("get_floor_y") else spawn_pos.y)
			en.position = final_pos
			
		enemies_spawned += 1
		get_parent().add_child(en)

func _scale_boss(boss: Node, tier: int) -> void:
	var scale_mult := 1.0 + 0.5 * float(maxi(tier - 1, 0))
	boss.set("max_hp", 600.0 * scale_mult)
	boss.set("hp", 600.0 * scale_mult)
	boss.set("gold_reward", 150 + 50 * maxi(tier - 1, 0))
	boss.set("speed", minf(4.0 + 0.5 * float(maxi(tier - 1, 0)), 8.0))

func _on_enemy_died_internal(_enemy_ref, pos: Vector3, gold_val: int) -> void:
	enemy_died.emit(pos, gold_val)
	_check_wave_cleared()

func _on_boss_died_internal(pos: Vector3, gold_val: int) -> void:
	boss_died.emit(pos, gold_val)

func _check_wave_cleared() -> void:
	var remaining = get_tree().get_nodes_in_group("enemies").size() - 1
	if enemies_spawned >= enemies_to_spawn_this_floor and remaining <= 0:
		wave_cleared.emit()
