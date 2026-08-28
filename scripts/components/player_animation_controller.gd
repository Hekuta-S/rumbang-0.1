extends Node
class_name PlayerAnimationController

const STATE_IDLE = "idle"
const STATE_WALK = "walk"
const STATE_RUN  = "run"
const STATE_JUMP = "jump"
const STATE_FAST = "fast" ## Estado de súper carrera (Riva: pies humeantes)

var player: CharacterBody3D
var model: Node3D
var anim_player: AnimationPlayer
var anim_tree: AnimationTree
var playback: AnimationNodeStateMachinePlayback

func _ready() -> void:
	player = get_parent() as CharacterBody3D
	setup_model()

func setup_model() -> void:
	var char_id: String = GameData.get_selected().get("id", "mikeura")
	
	var anim_files = {
		"cray": { "idle": "cray-idle.fbx", "walk": "cray-caminar.fbx", "run": "cray-correr.fbx", "jump": "cray-saltar.fbx" },
		"joel": { "idle": "joel-idle.fbx", "walk": "joel-caminar.fbx", "run": "joel-corre.fbx", "jump": "joel-salto.fbx" },
		"riva": { "idle": "riva-idle.fbx", "walk": "riva-caminar.fbx", "run": "riva-correr.fbx", "jump": "riva-salto.fbx", "fast": "riva-correr-rapido.fbx" },
		"bronch": { "idle": "bronch-idle.fbx", "walk": "bronch-caminar.fbx", "run": "bronch-correr.fbx", "jump": "bronch-saltar.fbx" },
		"mikeura": { "idle": "mikeura_idle.fbx", "walk": "mikeura_caminar.fbx", "run": "mikeura-correr.fbx", "jump": "mikeura-saltar.fbx" },
		"tatan": { "idle": "idle.fbx", "walk": "caminar.fbx", "run": "tatan-correr.fbx" },
		"vangry": { "idle": "vangry-idle.fbx", "walk": "vangry-caminar.fbx", "run": "vangry-correr.fbx", "jump": "Jumping.fbx" },
		"kaionz": { "idle": "cray-idle.fbx", "walk": "cray-caminar.fbx", "run": "cray-correr.fbx", "jump": "cray-saltar.fbx" },
		"crane": { "idle": "cray-idle.fbx", "walk": "cray-caminar.fbx", "run": "cray-correr.fbx", "jump": "cray-saltar.fbx" },
		"garri": { "idle": "garri-idle.fbx", "walk": "garri-caminar.fbx", "run": "garri-correr.fbx", "jump": "garri-saltar.fbx" },
		"saimon": { "idle": "saimon-idle.fbx", "walk": "saimon-caminar.fbx", "run": "saimon-correr.fbx", "jump": "saimon-saltar.fbx" }
	}
	
	if not anim_files.has(char_id):
		char_id = "mikeura"
		
	var files = anim_files[char_id]
	var base_path = "res://assets/models/" + ("cray" if char_id in ["kaionz", "crane"] else char_id) + "/"
	
	var idle_scene = load(base_path + files["idle"]) as PackedScene
	if idle_scene == null:
		push_error("Failed to load idle scene for " + char_id)
		return
		
	model = idle_scene.instantiate()
	model.name = "CharacterModel"
	player.mesh.add_child(model)
	_fit_model()

	# Apply character texture if it exists
	var base_tex_name = "cray" if char_id in ["kaionz", "crane"] else char_id
	var tex_path = "res://assets/textures/entities/" + base_tex_name + "/texture_" + base_tex_name + ".png"
	
	if FileAccess.file_exists(tex_path) or FileAccess.file_exists(tex_path + ".import"):
		var tex = load(tex_path) as Texture2D
		if tex != null:
			_apply_texture_to_meshes(model, tex)



	# Hide placeholders from KnightMesh
	for child_name in ["BodyMesh", "Visor", "Sword"]:
		var ph: Node3D = player.mesh.get_node_or_null(child_name) as Node3D
		if ph != null:
			ph.visible = false

	anim_player = _find_first_node_of_type(model, "AnimationPlayer") as AnimationPlayer
	if anim_player == null:
		push_error("Model idle FBX has no AnimationPlayer; animation disabled.")
		return

	if not anim_player.has_animation_library(""):
		anim_player.add_animation_library("", AnimationLibrary.new())
	var lib: AnimationLibrary = anim_player.get_animation_library("")

	_rename_first_animation_in_library(lib, STATE_IDLE)

	if files.has("walk"):
		var walk_scene = load(base_path + files["walk"]) as PackedScene
		if walk_scene: _merge_first_animation_from_scene(walk_scene, lib, STATE_WALK)

	if files.has("run"):
		var run_scene = load(base_path + files["run"]) as PackedScene
		if run_scene: _merge_first_animation_from_scene(run_scene, lib, STATE_RUN)

	if files.has("fast"):
		var fast_scene = load(base_path + files["fast"]) as PackedScene
		if fast_scene: _merge_first_animation_from_scene(fast_scene, lib, STATE_FAST)

	if files.has("jump"):
		var jump_scene = load(base_path + files["jump"]) as PackedScene
		if jump_scene: _merge_first_animation_from_scene(jump_scene, lib, STATE_JUMP)

	for looping_name in [STATE_IDLE, STATE_WALK, STATE_RUN, STATE_FAST]:
		if lib.has_animation(looping_name):
			lib.get_animation(looping_name).loop_mode = Animation.LOOP_LINEAR
			
	if lib.has_animation(STATE_JUMP):
		lib.get_animation(STATE_JUMP).loop_mode = Animation.LOOP_NONE

	anim_tree = AnimationTree.new()
	model.add_child(anim_tree)
	anim_tree.anim_player = anim_tree.get_path_to(anim_player)

	var sm := AnimationNodeStateMachine.new()

	var idle_node := AnimationNodeAnimation.new()
	idle_node.animation = STATE_IDLE
	sm.add_node(STATE_IDLE, idle_node, Vector2(0, 0))

	if lib.has_animation(STATE_WALK):
		var walk_node := AnimationNodeAnimation.new()
		walk_node.animation = STATE_WALK
		sm.add_node(STATE_WALK, walk_node, Vector2(0, 3))
		
	if lib.has_animation(STATE_RUN):
		var run_node := AnimationNodeAnimation.new()
		run_node.animation = STATE_RUN
		sm.add_node(STATE_RUN, run_node, Vector2(0, 5))

	if lib.has_animation(STATE_FAST):
		var fast_node := AnimationNodeAnimation.new()
		fast_node.animation = STATE_FAST
		sm.add_node(STATE_FAST, fast_node, Vector2(0, 6))
		
	if lib.has_animation(STATE_JUMP):
		var jump_node := AnimationNodeAnimation.new()
		jump_node.animation = STATE_JUMP
		
		if char_id in ["mikeura", "vangry", "joel", "riva", "saimon", "bronch", "garri"]:
			var bt = AnimationNodeBlendTree.new()
			bt.add_node("anim", jump_node)
			var seek_node = AnimationNodeTimeSeek.new()
			bt.add_node("seek", seek_node)
			bt.connect_node("seek", 0, "anim")
			bt.connect_node("output", 0, "seek")
			sm.add_node(STATE_JUMP, bt, Vector2(-2, 0))
		else:
			sm.add_node(STATE_JUMP, jump_node, Vector2(-2, 0))

	if sm.has_node(STATE_WALK):
		_add_transition(sm, STATE_IDLE, STATE_WALK, 0.15)
		_add_transition(sm, STATE_WALK, STATE_IDLE, 0.15)
		
	if sm.has_node(STATE_RUN):
		for src_state in [STATE_IDLE, STATE_WALK, STATE_JUMP]:
			if sm.has_node(src_state):
				_add_transition(sm, src_state, STATE_RUN, 0.15)
				_add_transition(sm, STATE_RUN, src_state, 0.15)

	if sm.has_node(STATE_FAST):
		for src_state in [STATE_IDLE, STATE_WALK, STATE_RUN, STATE_JUMP]:
			if sm.has_node(src_state):
				_add_transition(sm, src_state, STATE_FAST, 0.15)
				_add_transition(sm, STATE_FAST, src_state, 0.15)

	if sm.has_node(STATE_JUMP):
		for src_state in [STATE_IDLE, STATE_WALK, STATE_RUN]:
			if sm.has_node(src_state):
				_add_transition(sm, src_state, STATE_JUMP, 0.1)
				_add_transition(sm, STATE_JUMP, src_state, 0.1)

	anim_tree.tree_root = sm
	playback = anim_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	if playback == null:
		push_error("AnimationTree playback not available.")
		return

	playback.start(STATE_IDLE)

var _was_on_floor: bool = true

func _process(_delta: float) -> void:
	if not player or not is_instance_valid(playback): return
	
	var is_on_floor = player.is_on_floor()
	var just_jumped = _was_on_floor and not is_on_floor
	
	var horiz_velocity := Vector2(player.velocity.x, player.velocity.z).length()
	var moving := horiz_velocity > 1.0
	var running: bool = horiz_velocity > player.get("move_speed") * 1.2
	var current := playback.get_current_node()
	var fast_available: bool = anim_tree.tree_root.has_node(STATE_FAST)
	var is_fast: bool = fast_available and bool(player.get("is_riva_fast"))

	if not is_on_floor:
		if (current != STATE_JUMP or just_jumped) and anim_tree.tree_root.has_node(STATE_JUMP):
			if just_jumped:
				playback.start(STATE_JUMP)
			else:
				playback.travel(STATE_JUMP)
				
			var char_id = GameData.get_selected().get("id", "mikeura")
			if char_id in ["mikeura", "vangry", "joel", "riva", "saimon"]:
				# 12 frames at standard 30 FPS = 0.4 seconds
				anim_tree.set("parameters/jump/seek/seek_request", 12.0 / 30.0)
			elif char_id in ["bronch", "garri"]:
				# 32 frames at standard 30 FPS = ~1.066 seconds
				anim_tree.set("parameters/jump/seek/seek_request", 32.0 / 30.0)
	else:
		if is_fast:
			if current != STATE_FAST:
				playback.travel(STATE_FAST)
		elif running and anim_tree.tree_root.has_node(STATE_RUN):
			if current != STATE_RUN:
				playback.travel(STATE_RUN)
		elif moving and anim_tree.tree_root.has_node(STATE_WALK):
			if current != STATE_WALK:
				playback.travel(STATE_WALK)
		else:
			if current != STATE_IDLE:
				playback.travel(STATE_IDLE)

	_was_on_floor = is_on_floor

func _add_transition(sm: AnimationNodeStateMachine, from: String, to: String, xfade: float) -> void:
	for i in range(sm.get_transition_count()):
		if sm.get_transition_from(i) == from and sm.get_transition_to(i) == to:
			return
	var tr := AnimationNodeStateMachineTransition.new()
	tr.switch_mode = 0
	tr.advance_mode = 1
	tr.xfade_time = xfade
	sm.add_transition(from, to, tr)

func _fit_model() -> void:
	if not model: return
	var model_mesh = _find_first_node_of_type(model, "MeshInstance3D") as MeshInstance3D
	if not model_mesh or not model_mesh.mesh: return
	
	var aabb: AABB = model_mesh.mesh.get_aabb()
	var model_height: float = maxf(aabb.size.y, 0.001)
	var s: float = 1.62 / model_height
	model.scale = Vector3(s, s, s)
	model.rotation.y = PI
	model.position.y = -aabb.position.y * s

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
	player.mesh.add_child(instance)
	var ap = _find_first_node_of_type(instance, "AnimationPlayer") as AnimationPlayer
	if ap and ap.has_animation_library(""):
		var src_lib = ap.get_animation_library("")
		var names = src_lib.get_animation_list()
		if not names.is_empty():
			lib.add_animation(new_name, ap.get_animation(names[0]).duplicate(true))
	instance.queue_free()

func _apply_texture_to_meshes(node: Node, tex: Texture2D) -> void:
	if node is MeshInstance3D:
		var mat = StandardMaterial3D.new()
		mat.albedo_texture = tex
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		node.material_override = mat
	for child in node.get_children():
		_apply_texture_to_meshes(child, tex)
