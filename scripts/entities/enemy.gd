extends CharacterBody3D

signal enemy_died(enemy_ref, position, gold_val)
signal enemy_hit

enum EnemyType { GOBLIN_RANGED, NORMAL_GOBLIN, HEAVY_BRUTE, SNIPER_GOBLIN, ZOMBIE_GOBLIN }

@export var type: EnemyType = EnemyType.GOBLIN_RANGED:
	set(val):
		type = val
		if is_inside_tree():
			_apply_type_config()

@export var max_hp: float = 30.0
var hp: float = 30.0
@export var speed: float = 6.0
@export var attack_range: float = 12.0
@export var damage: float = 2.0
@export var gold_reward: int = 6

var player: Node3D = null
var attack_cooldown: float = 0.0
var attack_windup: float = 0.0

## Slow mechanic (used by Kaionz's skill)
var slow_timer: float = 0.0
var slow_multiplier: float = 1.0

var bullet_scene = preload("res://scenes/objects/bullet.tscn")
var knockback_velocity: Vector3 = Vector3.ZERO

@export var detection_range: float = 40.0
var is_alerted: bool = false

var _logic_timer: float = 0.0
var _cached_ground_y: float = 0.0

# 3D Model & Animation variables
var model: Node3D = null
var anim_player: AnimationPlayer = null
var anim_tree: AnimationTree = null
var playback: AnimationNodeStateMachinePlayback = null
var mesh_instances: Array[MeshInstance3D] = []
var base_color: Color = Color.WHITE

func _ready() -> void:
	add_to_group("enemies")
	player = get_tree().get_first_node_in_group("player")
	if has_node("AnimationTree"):
		anim_tree = $AnimationTree
		playback = anim_tree.get("parameters/playback")
		
	_apply_type_config()

var behavior: EnemyBehavior

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
	
	if behavior:
		behavior.apply_config()
			
	_setup_model()

func _setup_model() -> void:
	if model and is_instance_valid(model):
		model.queue_free()
		model = null
		
	mesh_instances.clear()
	anim_player = null
	anim_tree = null
	playback = null
	
	var idle_path := ""
	var walk_path := ""
	var tex_path := ""
	
	if behavior:
		var paths = behavior.get_model_paths()
		idle_path = paths.get("idle", "")
		walk_path = paths.get("walk", "")
		tex_path = paths.get("tex", "")
		
	var idle_scene: PackedScene = null
	if not GameData.cache_enemy_models.has(idle_path):
		if ResourceLoader.exists(idle_path) or FileAccess.file_exists(idle_path):
			GameData.cache_enemy_models[idle_path] = load(idle_path) as PackedScene
	idle_scene = GameData.cache_enemy_models.get(idle_path)
		
	if idle_scene == null:
		# Fallback to placeholder capsule mesh
		if has_node("MeshInstance3D"):
			$MeshInstance3D.visible = true
			set_enemy_color(base_color)
		return
		
	model = idle_scene.instantiate()
	if model == null:
		if has_node("MeshInstance3D"):
			$MeshInstance3D.visible = true
			set_enemy_color(base_color)
		return

	# Model loaded successfully: hide placeholder mesh
	if has_node("MeshInstance3D"):
		$MeshInstance3D.visible = false

	model.name = "EnemyModel"
	add_child(model)
	
	_fit_model()
	
	var tex: Texture2D = null
	if tex_path != "":
		if not GameData.cache_enemy_textures.has(tex_path):
			if ResourceLoader.exists(tex_path) or FileAccess.file_exists(tex_path):
				GameData.cache_enemy_textures[tex_path] = load(tex_path) as Texture2D
		tex = GameData.cache_enemy_textures.get(tex_path)
		
	_apply_texture_and_collect_meshes(model, tex)
	_setup_animations(walk_path)

func _fit_model() -> void:
	if not model: return
	var model_mesh = _find_first_node_of_type(model, "MeshInstance3D") as MeshInstance3D
	if not model_mesh or not model_mesh.mesh: return
	
	var aabb: AABB = model_mesh.mesh.get_aabb()
	var model_height: float = maxf(aabb.size.y, 0.001)
	var s: float = 1.45 / model_height
	model.scale = Vector3(s, s, s)
	model.rotation.y = PI
	model.position.y = -aabb.position.y * s

func _apply_texture_and_collect_meshes(node: Node, tex: Texture2D) -> void:
	if node is MeshInstance3D:
		if tex != null:
			var mat = StandardMaterial3D.new()
			mat.albedo_texture = tex
			mat.albedo_color = Color.WHITE
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mat.roughness = 0.85
			node.material_override = mat
		mesh_instances.append(node)
	for child in node.get_children():
		_apply_texture_and_collect_meshes(child, tex)

func _setup_animations(walk_path: String) -> void:
	anim_player = _find_first_node_of_type(model, "AnimationPlayer") as AnimationPlayer
	if anim_player == null:
		return

	if not anim_player.has_animation_library(""):
		anim_player.add_animation_library("", AnimationLibrary.new())
	var lib: AnimationLibrary = anim_player.get_animation_library("")

	_rename_first_animation_in_library(lib, "idle")

	if walk_path != "":
		if not GameData.cache_enemy_models.has(walk_path):
			if ResourceLoader.exists(walk_path) or FileAccess.file_exists(walk_path):
				GameData.cache_enemy_models[walk_path] = load(walk_path) as PackedScene
		var walk_scene = GameData.cache_enemy_models.get(walk_path)
		if walk_scene:
			_merge_first_animation_from_scene(walk_scene, lib, "walk", walk_path)

	if lib.has_animation("idle"):
		lib.get_animation("idle").loop_mode = Animation.LOOP_LINEAR
	if lib.has_animation("walk"):
		lib.get_animation("walk").loop_mode = Animation.LOOP_LINEAR

	anim_tree = AnimationTree.new()
	model.add_child(anim_tree)
	anim_tree.anim_player = anim_tree.get_path_to(anim_player)

	var sm := AnimationNodeStateMachine.new()
	var idle_node := AnimationNodeAnimation.new()
	idle_node.animation = "idle"
	sm.add_node("idle", idle_node, Vector2(0, 0))

	if lib.has_animation("walk"):
		var walk_node := AnimationNodeAnimation.new()
		walk_node.animation = "walk"
		sm.add_node("walk", walk_node, Vector2(0, 3))
		_add_transition(sm, "idle", "walk", 0.15)
		_add_transition(sm, "walk", "idle", 0.15)

	anim_tree.tree_root = sm
	playback = anim_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	if playback:
		playback.start("idle")

func _find_first_node_of_type(root: Node, type_name: String) -> Node:
	if root == null or not is_instance_valid(root): return null
	if root.is_class(type_name): return root
	for child in root.get_children():
		var found = _find_first_node_of_type(child, type_name)
		if found: return found
	return null

func _rename_first_animation_in_library(lib: AnimationLibrary, new_name: String) -> void:
	var names = lib.get_animation_list()
	if names.is_empty(): return
	var first = names[0]
	if first == new_name: return
	var anim = lib.get_animation(first)
	lib.remove_animation(first)
	lib.add_animation(new_name, anim)

func _merge_first_animation_from_scene(scene: PackedScene, lib: AnimationLibrary, new_name: String, path_key: String) -> void:
	if GameData.cache_enemy_anims.has(path_key):
		lib.add_animation(new_name, GameData.cache_enemy_anims[path_key].duplicate(true))
		return
		
	var instance = scene.instantiate()
	add_child(instance)
	var ap = _find_first_node_of_type(instance, "AnimationPlayer") as AnimationPlayer
	if ap and ap.has_animation_library(""):
		var src_lib = ap.get_animation_library("")
		var names = src_lib.get_animation_list()
		if not names.is_empty():
			var anim = ap.get_animation(names[0]).duplicate(true)
			GameData.cache_enemy_anims[path_key] = anim
			lib.add_animation(new_name, anim.duplicate(true))
	instance.queue_free()

func _add_transition(sm: AnimationNodeStateMachine, from: String, to: String, xfade: float) -> void:
	for i in range(sm.get_transition_count()):
		if sm.get_transition_from(i) == from and sm.get_transition_to(i) == to:
			return
	var tr := AnimationNodeStateMachineTransition.new()
	tr.switch_mode = 0
	tr.advance_mode = 1
	tr.xfade_time = xfade
	sm.add_transition(from, to, tr)

func set_enemy_color(col: Color) -> void:
	base_color = col
	for mi in mesh_instances:
		if is_instance_valid(mi) and mi.material_override:
			var mat := mi.material_override as StandardMaterial3D
			if mat:
				mat.albedo_color = col

func _physics_process(delta: float) -> void:
	if not player or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
		return

	if attack_cooldown > 0: attack_cooldown -= delta

	# Tick slow effect down
	if slow_timer > 0:
		slow_timer -= delta
		if slow_timer <= 0:
			slow_multiplier = 1.0
			set_enemy_color(base_color)

	if knockback_velocity.length_squared() > 0.01:
		knockback_velocity = knockback_velocity.move_toward(Vector3.ZERO, 30.0 * delta)
	else:
		knockback_velocity = Vector3.ZERO

	var to_player = player.global_position - global_position
	to_player.y = 0
	var dist = to_player.length()

	_logic_timer -= delta
	if _logic_timer <= 0.0:
		_logic_timer = 0.2 + randf() * 0.1 # Staggered check (5 times per sec)
		
		if not is_alerted:
			if to_player.length_squared() <= (detection_range * detection_range) or hp < max_hp:
				is_alerted = true
				
		var main_node = get_tree().current_scene
		if main_node and main_node.has_method("get_floor_y"):
			_cached_ground_y = main_node.get_floor_y(global_position.x, global_position.z)
			
	var ground_y = _cached_ground_y
		
	if global_position.y < ground_y:
		global_position.y = ground_y
		velocity.y = 0.0

	var current_vy = velocity.y
	if not is_on_floor() and global_position.y > ground_y:
		current_vy -= 30.0 * delta
		if current_vy < -25.0:
			current_vy = -25.0

	if not is_alerted:
		velocity = knockback_velocity
		velocity.y = current_vy
		move_and_slide()
		_update_animation_state()
		return

	# Rotate towards player when alerted
	if to_player.length_squared() > 0.01:
		look_at(Vector3(player.global_position.x, global_position.y, player.global_position.z), Vector3.UP)

	# Movement & Combat AI
	var effective_speed := speed * slow_multiplier
	
	var next_vel = Vector3.ZERO
	if behavior:
		next_vel = behavior.process_ai(delta, to_player, dist, effective_speed)

	velocity = next_vel + knockback_velocity
	velocity.y = current_vy
	move_and_slide()
	_update_animation_state()

func _update_animation_state() -> void:
	if not playback or not anim_tree:
		return
	var is_moving: bool = Vector2(velocity.x, velocity.z).length_squared() > 0.2
	var current_state = playback.get_current_node()
	if is_moving:
		if current_state != "walk" and anim_tree.tree_root.has_node("walk"):
			playback.travel("walk")
	else:
		if current_state != "idle" and anim_tree.tree_root.has_node("idle"):
			playback.travel("idle")

func take_damage(amount: float, knockback_dir: Vector3 = Vector3.ZERO) -> void:
	hp -= amount
	emit_signal("enemy_hit")
	AudioManager.play_at("hit", global_position, -10.0, randf_range(0.9, 1.1))
	
	if knockback_dir != Vector3.ZERO:
		var kb_len = knockback_dir.length()
		var kb_norm = knockback_dir.normalized()
		# If a unit vector was passed, use a modest push (3.0) for standard bullets
		var push_speed = kb_len if kb_len > 1.05 else 3.0
		
		if behavior:
			push_speed *= behavior.get_knockback_resistance()
		knockback_velocity = kb_norm * clampf(push_speed, 1.0, 24.0)
		
	# White flash on damage
	_flash_hit()

	var FloatingDamage = load("res://scripts/objects/floating_damage.gd")
	if FloatingDamage:
		var is_crit = amount >= 24.0 or randf() < 0.15
		var col = Color(1.0, 0.32, 0.1) if is_crit else Color(1.0, 0.88, 0.22)
		FloatingDamage.spawn(get_parent(), global_position + Vector3(0, 1.4, 0), amount, col, is_crit)

	if hp <= 0:
		emit_signal("enemy_died", self, global_position, gold_reward)
		queue_free()

func _flash_hit() -> void:
	for mi in mesh_instances:
		if is_instance_valid(mi) and mi.material_override:
			var mat := mi.material_override as StandardMaterial3D
			if mat:
				mat.albedo_color = Color(2.5, 2.5, 2.5)
				
	var tw := create_tween()
	tw.tween_interval(0.08)
	tw.tween_callback(func():
		for mi in mesh_instances:
			if is_instance_valid(mi) and mi.material_override:
				var mat := mi.material_override as StandardMaterial3D
				if mat:
					mat.albedo_color = Color(0.5, 0.8, 1.0) if slow_timer > 0 else base_color
	)

## Apply a slow effect for [duration] seconds at [multiplier] speed fraction (e.g. 0.4 = 40% speed).
## Stacks by taking the more severe (lower) multiplier.
func apply_slow(duration: float, multiplier: float) -> void:
	slow_multiplier = minf(slow_multiplier, multiplier)
	slow_timer = maxf(slow_timer, duration)
	
	for mi in mesh_instances:
		if is_instance_valid(mi) and mi.material_override:
			var mat := mi.material_override as StandardMaterial3D
			if mat:
				mat.albedo_color = Color(0.5, 0.8, 1.0)
