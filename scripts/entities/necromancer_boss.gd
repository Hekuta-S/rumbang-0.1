extends CharacterBody3D

signal boss_died(position, gold_val)
signal boss_hit

@export var max_hp: float = 1000.0
var hp: float = 1000.0
@export var speed: float = 2.0
@export var gold_reward: int = 500

@export var zombie_scene: PackedScene
@export var eruption_scene: PackedScene

var player: Node3D = null

enum BossState { MOVING, IDLE_LIFESTEAL, SUMMONING, ERUPTING }
var state: BossState = BossState.MOVING
var state_timer: float = 0.0
var ability_cooldown: float = 2.0
@onready var ray_mesh: MeshInstance3D = get_node_or_null("LifeStealRay")

# 3D Model & Animation variables
var model: Node3D = null
var anim_player: AnimationPlayer = null
var anim_tree: AnimationTree = null
var playback: AnimationNodeStateMachinePlayback = null
var mesh_instances: Array[MeshInstance3D] = []

func _ready() -> void:
	add_to_group("enemies")
	add_to_group("boss")
	hp = max_hp
	player = get_tree().get_first_node_in_group("player")
	
	if not zombie_scene:
		zombie_scene = load("res://scenes/entities/enemy.tscn")
	if not eruption_scene:
		eruption_scene = load("res://scenes/objects/eruption.tscn")
		
	_setup_model()

func _setup_model() -> void:
	if model and is_instance_valid(model):
		model.queue_free()
		model = null
		
	mesh_instances.clear()
	anim_player = null
	anim_tree = null
	playback = null
	
	var idle_path = "res://assets/models/entities/enemigos/goblins/bosses/necromancer/ataque_idle_necroboss.fbx"
	var walk_path = "res://assets/models/entities/enemigos/goblins/bosses/necromancer/caminar_necro_boss.fbx"
	var zombie_path = "res://assets/models/entities/enemigos/goblins/bosses/necromancer/invocar_zombies_necro.fbx"
	var erupt_path = "res://assets/models/entities/enemigos/goblins/bosses/necromancer/invocar_erupciones.fbx"
	var tex_path = "res://assets/textures/enemigos/textura_necro_boss.png"
		
	var idle_scene: PackedScene = load(idle_path) as PackedScene
	if idle_scene == null:
		return
		
	model = idle_scene.instantiate()
	if model == null:
		return

	if has_node("MeshInstance3D"):
		$MeshInstance3D.visible = false

	model.name = "EnemyModel"
	add_child(model)
	
	_fit_model()
	
	var tex: Texture2D = load(tex_path) as Texture2D
	_apply_texture_and_collect_meshes(model, tex)
	_setup_animations(walk_path, zombie_path, erupt_path)

func _fit_model() -> void:
	if not model: return
	var model_mesh = _find_first_node_of_type(model, "MeshInstance3D") as MeshInstance3D
	if not model_mesh or not model_mesh.mesh: return
	
	var aabb: AABB = model_mesh.mesh.get_aabb()
	var model_height: float = maxf(aabb.size.y, 0.001)
	var s: float = 4.5 / model_height
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

func _setup_animations(walk_path: String, zombie_path: String, erupt_path: String) -> void:
	anim_player = _find_first_node_of_type(model, "AnimationPlayer") as AnimationPlayer
	if anim_player == null:
		return

	if not anim_player.has_animation_library(""):
		anim_player.add_animation_library("", AnimationLibrary.new())
	var lib: AnimationLibrary = anim_player.get_animation_library("")

	_rename_first_animation_in_library(lib, "idle")

	var walk_scene = load(walk_path) as PackedScene
	if walk_scene:
		_merge_first_animation_from_scene(walk_scene, lib, "walk")
		
	var zombie_scene = load(zombie_path) as PackedScene
	if zombie_scene:
		_merge_first_animation_from_scene(zombie_scene, lib, "summon")
		
	var erupt_scene = load(erupt_path) as PackedScene
	if erupt_scene:
		_merge_first_animation_from_scene(erupt_scene, lib, "erupt")

	if lib.has_animation("idle"):
		lib.get_animation("idle").loop_mode = Animation.LOOP_LINEAR
	if lib.has_animation("walk"):
		lib.get_animation("walk").loop_mode = Animation.LOOP_LINEAR

	anim_tree = AnimationTree.new()
	model.add_child(anim_tree)
	anim_tree.anim_player = anim_tree.get_path_to(anim_player)

	var sm := AnimationNodeStateMachine.new()
	
	# Create nodes
	var idle_node := AnimationNodeAnimation.new(); idle_node.animation = "idle"
	var walk_node := AnimationNodeAnimation.new(); walk_node.animation = "walk"
	var summon_node := AnimationNodeAnimation.new(); summon_node.animation = "summon"
	var erupt_node := AnimationNodeAnimation.new(); erupt_node.animation = "erupt"
	
	sm.add_node("idle", idle_node, Vector2(0, 0))
	sm.add_node("walk", walk_node, Vector2(0, 3))
	sm.add_node("summon", summon_node, Vector2(3, 0))
	sm.add_node("erupt", erupt_node, Vector2(3, 3))

	# Add transitions from anywhere to anywhere we need
	_add_transition(sm, "idle", "walk", 0.15)
	_add_transition(sm, "walk", "idle", 0.15)
	
	_add_transition(sm, "idle", "summon", 0.15)
	_add_transition(sm, "walk", "summon", 0.15)
	_add_transition(sm, "summon", "walk", 0.15)
	
	_add_transition(sm, "idle", "erupt", 0.15)
	_add_transition(sm, "walk", "erupt", 0.15)
	_add_transition(sm, "erupt", "walk", 0.15)

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

func _merge_first_animation_from_scene(scene: PackedScene, lib: AnimationLibrary, new_name: String) -> void:
	var instance = scene.instantiate()
	add_child(instance)
	var ap = _find_first_node_of_type(instance, "AnimationPlayer") as AnimationPlayer
	if ap and ap.has_animation_library(""):
		var src_lib = ap.get_animation_library("")
		var names = src_lib.get_animation_list()
		if not names.is_empty():
			lib.add_animation(new_name, ap.get_animation(names[0]).duplicate(true))
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

func play_animation(anim_name: String):
	if playback:
		var current = playback.get_current_node()
		if current != anim_name:
			playback.travel(anim_name)

func _physics_process(delta: float) -> void:
	if not player or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
		return
			
	# Mathematical floor lock: Caminar sobre el mapa matemático si la física no ha cargado
	var ground_y = 0.0
	var main_node = get_tree().current_scene
	if main_node and main_node.has_method("get_floor_y"):
		ground_y = main_node.get_floor_y(global_position.x, global_position.z)
		
	if global_position.y < ground_y:
		global_position.y = ground_y
		velocity.y = 0.0

	var current_vy = velocity.y
	if not is_on_floor() and global_position.y > ground_y:
		current_vy -= 30.0 * delta
		if current_vy < -25.0:
			current_vy = -25.0

	var to_player = player.global_position - global_position
	to_player.y = 0

	# Mirar al jugador
	if to_player.length_squared() > 0.01:
		look_at(Vector3(player.global_position.x, global_position.y, player.global_position.z), Vector3.UP)

	if ability_cooldown > 0:
		ability_cooldown -= delta

	match state:
		BossState.MOVING:
			velocity = to_player.normalized() * speed
			velocity.y = current_vy
			move_and_slide()
			play_animation("walk")
			
			if ability_cooldown <= 0:
				choose_next_ability()
				
		BossState.IDLE_LIFESTEAL:
			state_timer -= delta
			velocity = Vector3.ZERO
			velocity.y = current_vy
			move_and_slide()
			play_animation("idle")
			
			if ray_mesh:
				ray_mesh.visible = true
				var dist = global_position.distance_to(player.global_position)
				ray_mesh.scale.z = dist
				ray_mesh.look_at(player.global_position, Vector3.UP)
			
			if Engine.get_physics_frames() % 10 == 0:
				if global_position.distance_to(player.global_position) < 15.0:
					if player.has_method("take_damage"):
						player.take_damage(2.0)
						heal(2.0)
			
			if state_timer <= 0:
				if ray_mesh:
					ray_mesh.visible = false
				state = BossState.MOVING
				ability_cooldown = randf_range(2.0, 4.0)

		BossState.SUMMONING:
			state_timer -= delta
			velocity = Vector3.ZERO
			velocity.y = current_vy
			move_and_slide()
			play_animation("summon")
				
			if state_timer <= 0:
				spawn_zombies()
				state = BossState.MOVING
				ability_cooldown = randf_range(4.0, 6.0)

		BossState.ERUPTING:
			state_timer -= delta
			velocity = Vector3.ZERO
			velocity.y = current_vy
			move_and_slide()
			play_animation("erupt")
				
			if state_timer <= 0:
				spawn_eruptions()
				state = BossState.MOVING
				ability_cooldown = randf_range(3.0, 5.0)

func choose_next_ability():
	var roll = randf()
	if roll < 0.4:
		state = BossState.IDLE_LIFESTEAL
		state_timer = 3.0
	elif roll < 0.7:
		state = BossState.SUMMONING
		state_timer = 1.5
	else:
		state = BossState.ERUPTING
		state_timer = 2.0

func spawn_zombies():
	if not zombie_scene: return
	var num_zombies = 3
	for i in range(num_zombies):
		var z = zombie_scene.instantiate()
		get_parent().add_child(z)
		var offset = Vector3(randf_range(-3.0, 3.0), 0, randf_range(-3.0, 3.0))
		z.global_position = global_position + offset

func spawn_eruptions():
	if not eruption_scene or not player: return
	
	var e = eruption_scene.instantiate()
	get_parent().add_child(e)
	e.global_position = player.global_position
	
	var num_eruptions = 4
	for i in range(num_eruptions):
		var er = eruption_scene.instantiate()
		get_parent().add_child(er)
		var offset = Vector3(randf_range(-6.0, 6.0), 0, randf_range(-6.0, 6.0))
		er.global_position = player.global_position + offset

func take_damage(amount: float, _knockback_dir: Vector3 = Vector3.ZERO) -> void:
	hp -= amount
	emit_signal("boss_hit")
	
	_flash_hit()

	var FloatingDamage = load("res://scripts/objects/floating_damage.gd")
	if FloatingDamage:
		var is_crit = amount >= 24.0 or randf() < 0.2
		var col = Color(1.0, 0.25, 0.1) if is_crit else Color(1.0, 0.85, 0.2)
		FloatingDamage.spawn(get_parent(), global_position + Vector3(0, 2.2, 0), amount, col, is_crit)

	if hp <= 0:
		emit_signal("boss_died", global_position, gold_reward)
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
					mat.albedo_color = Color.WHITE
	)

func heal(amount: float):
	hp += amount
	if hp > max_hp: hp = max_hp
