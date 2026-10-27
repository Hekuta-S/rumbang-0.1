extends Node
class_name PlayerAnimationController

signal hit_window_opened(attack_id: int, anim_name: String)
signal hit_window_closed(attack_id: int)

const STATE_IDLE = "idle"
const STATE_WALK = "walk"
const STATE_RUN  = "run"
const STATE_JUMP = "jump"
const STATE_FAST = "fast" ## Estado de súper carrera (Riva: pies humeantes)
## Acciones de un disparo (OneShot sobre la máquina de estados): combo de 3 ataques y grito.
const ATTACKS := ["attack1", "attack2", "attack3"]
const ACTION_SHOUT = "shout"
const COMBO_RESET := 1.1   ## segundos sin atacar para volver al primer golpe
const SHOT_PARAM := "parameters/shot/request"
const SEEK_PARAM := "parameters/seek/seek_request"
const ACTION_CHARGE = "charge"
## Postura de carga: primeros CHARGE_POSE_T s de attack1 (la lanza atrás), sostenidos.
const CHARGE_POSE_T := 0.2
## Lunge de cada ataque: [segundos hasta el impulso, velocidad m/s]
const ATTACK_DASH := {"attack1": [0.14, 17.0], "attack2": [0.2, 7.0], "attack3": [0.2, 11.0]}

## Ventanas activas de golpe por animación [inicio_s, fin_s]
const ATTACK_WINDOWS := {
	"attack1": [0.20, 0.36],
	"attack2": [0.22, 0.55],
	"attack3": [0.45, 0.60]
}

var current_attack_id: int = 0
var active_attack_name: String = ""

var player: CharacterBody3D
var model: Node3D
var anim_player: AnimationPlayer
var anim_tree: AnimationTree
var playback: AnimationNodeStateMachinePlayback
var sm: AnimationNodeStateMachine
var _action_node: AnimationNodeAnimation
var _skel_path: NodePath
var _combo_index: int = 0
var _combo_timer: float = 0.0
var _skip_next_attack := false
var foot_ik: FootIKModifier

func _ready() -> void:
	player = get_parent() as CharacterBody3D
	setup_model()

func setup_model() -> void:
	var char_id: String = GameData.get_selected().get("id", "mikeura")
	
	var anim_files: Dictionary = GameData.ANIM_FILES
	
	if not anim_files.has(char_id):
		char_id = "mikeura"
		
	var files = anim_files[char_id]
	var base_path = "res://assets/models/" + char_id + "/"
	
	var idle_scene = load(base_path + files["idle"]) as PackedScene
	if idle_scene == null:
		push_error("Failed to load idle scene for " + char_id)
		return
		
	model = idle_scene.instantiate()
	model.name = "CharacterModel"
	player.mesh.add_child(model)
	_fit_model()

	# Apply character texture if it exists
	var base_tex_name = char_id
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
	var skel := _find_first_node_of_type(model, "Skeleton3D")
	if skel:
		_skel_path = anim_player.get_node(anim_player.root_node).get_path_to(skel)

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

	for action_name in ATTACKS + [ACTION_SHOUT]:
		if files.has(action_name):
			var action_scene = load(base_path + files[action_name]) as PackedScene
			if action_scene: _merge_first_animation_from_scene(action_scene, lib, action_name)
			if lib.has_animation(action_name):
				lib.get_animation(action_name).loop_mode = Animation.LOOP_NONE
				if ATTACK_WINDOWS.has(action_name):
					_inject_hit_method_tracks(lib.get_animation(action_name), action_name)

	if lib.has_animation(ATTACKS[0]):
		lib.add_animation(ACTION_CHARGE, _make_hold_pose(lib.get_animation(ATTACKS[0]), CHARGE_POSE_T))

	for looping_name in [STATE_IDLE, STATE_WALK, STATE_RUN, STATE_FAST]:
		if lib.has_animation(looping_name):
			lib.get_animation(looping_name).loop_mode = Animation.LOOP_LINEAR
			
	if lib.has_animation(STATE_JUMP):
		lib.get_animation(STATE_JUMP).loop_mode = Animation.LOOP_NONE

	anim_tree = AnimationTree.new()
	model.add_child(anim_tree)
	anim_tree.anim_player = anim_tree.get_path_to(anim_player)

	sm = AnimationNodeStateMachine.new()

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

	# Raíz: máquina de estados + OneShot para ataques/grito (cuerpo completo)
	var root := AnimationNodeBlendTree.new()
	root.add_node("sm", sm, Vector2(0, 0))
	_action_node = AnimationNodeAnimation.new()
	_action_node.animation = STATE_IDLE
	root.add_node("action", _action_node, Vector2(0, 200))
	root.add_node("seek", AnimationNodeTimeSeek.new(), Vector2(120, 200))
	root.connect_node("seek", 0, "action")
	var shot := AnimationNodeOneShot.new()
	shot.fadein_time = 0.08
	shot.fadeout_time = 0.18
	root.add_node("shot", shot, Vector2(250, 0))
	root.connect_node("shot", 0, "sm")
	root.connect_node("shot", 1, "seek")
	root.connect_node("output", 0, "shot")
	anim_tree.tree_root = root
	playback = anim_tree.get("parameters/sm/playback") as AnimationNodeStateMachinePlayback
	if playback == null:
		push_error("AnimationTree playback not available.")
		return

	playback.start(STATE_IDLE)
	if player.has_signal("weapon_attacked"):
		player.weapon_attacked.connect(_on_weapon_attacked)
	_setup_foot_ik()

## IK de pies (FootIKModifier) colgado del esqueleto del modelo.
func _setup_foot_ik() -> void:
	var skel := _find_first_node_of_type(model, "Skeleton3D") as Skeleton3D
	if skel == null:
		return
	foot_ik = FootIKModifier.new()
	foot_ik.name = "FootIK"
	skel.add_child(foot_ik)
	if not foot_ik.setup(player):
		foot_ik.queue_free()
		foot_ik = null

## Animación que mantiene la pose de `src` en el instante `t` (sin keys posteriores).
func _make_hold_pose(src: Animation, t: float) -> Animation:
	var a: Animation = src.duplicate(true)
	for i in a.get_track_count():
		for k in range(a.track_get_key_count(i) - 1, -1, -1):
			if a.track_get_key_time(i, k) > t:
				a.track_remove_key(i, k)
	a.length = 30.0
	a.loop_mode = Animation.LOOP_NONE
	return a

## Postura de carga del lanzamiento (se sostiene hasta soltar el click derecho).
func play_charge() -> void:
	_fire_action(ACTION_CHARGE)

## Lanzamiento: el estoque de attack1 desde la lanza ya atrás; sin lunge.
func play_throw() -> void:
	_skip_next_attack = true
	_fire_action(ATTACKS[0], CHARGE_POSE_T)

## Golpe del combo de espalanza (1 → 2 → 3); se reinicia tras COMBO_RESET sin atacar.
func play_attack() -> void:
	var lib := anim_player.get_animation_library("") if anim_player else null
	if lib == null or not lib.has_animation(ATTACKS[0]):
		return
	if _combo_timer <= 0.0:
		_combo_index = 0
	var anim_name: String = ATTACKS[_combo_index]
	_combo_index = (_combo_index + 1) % ATTACKS.size()
	_combo_timer = COMBO_RESET
	_fire_action(anim_name)
	_schedule_dash(anim_name)

## Impulso hacia delante sincronizado con el golpe de la animación.
func _schedule_dash(anim_name: String) -> void:
	if GameData.game_mode == "dungeon":
		return # En mazmorra se dispara exactamente con _on_anim_hit_on
	var mc = player.get("movement_controller")
	if not ATTACK_DASH.has(anim_name) or mc == null or not mc.has_method("add_dash"):
		return
	var d: Array = ATTACK_DASH[anim_name]
	get_tree().create_timer(d[0]).timeout.connect(func():
		if is_instance_valid(player) and is_instance_valid(mc):
			var fwd: Vector3 = -player.mesh.global_transform.basis.z
			mc.add_dash(fwd.normalized() * float(d[1])))

func _inject_hit_method_tracks(anim: Animation, anim_name: String) -> void:
	if not ATTACK_WINDOWS.has(anim_name) or anim_player == null:
		return
	var window: Array = ATTACK_WINDOWS[anim_name]
	var track_idx = anim.add_track(Animation.TYPE_METHOD)
	var root_target = anim_player.get_node(anim_player.root_node)
	anim.track_set_path(track_idx, root_target.get_path_to(self))
	anim.track_insert_key(track_idx, float(window[0]), {"method": "_on_anim_hit_on", "args": [anim_name]})
	anim.track_insert_key(track_idx, float(window[1]), {"method": "_on_anim_hit_off", "args": [anim_name]})

func _on_anim_hit_on(anim_name: String) -> void:
	current_attack_id += 1
	active_attack_name = anim_name
	if GameData.game_mode == "dungeon":
		_trigger_hit_dash(anim_name)
	hit_window_opened.emit(current_attack_id, anim_name)

func _on_anim_hit_off(_anim_name: String) -> void:
	if active_attack_name != "":
		hit_window_closed.emit(current_attack_id)
		active_attack_name = ""

func _trigger_hit_dash(anim_name: String) -> void:
	var mc = player.get("movement_controller")
	if not ATTACK_DASH.has(anim_name) or mc == null or not mc.has_method("add_dash"):
		return
	var d: Array = ATTACK_DASH[anim_name]
	var fwd: Vector3 = -player.mesh.global_transform.basis.z
	mc.add_dash(fwd.normalized() * float(d[1]))

## Grito de guerra (al activar Berserk).
func play_shout() -> void:
	_fire_action(ACTION_SHOUT)

func _fire_action(anim_name: String, from_time: float = -1.0) -> void:
	if not is_instance_valid(anim_tree) or _action_node == null:
		return
	if not anim_player.get_animation_library("").has_animation(anim_name):
		return
	_action_node.animation = anim_name
	anim_tree.set(SHOT_PARAM, AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
	anim_tree.set(SHOT_PARAM, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	if from_time >= 0.0:
		anim_tree.set(SEEK_PARAM, from_time)

func _on_weapon_attacked(weapon_type) -> void:
	if weapon_type == WeaponData.WeaponType.SPEAR_LANCE:
		if _skip_next_attack:
			_skip_next_attack = false
			return
		play_attack()

var _was_on_floor: bool = true

func _process(delta: float) -> void:
	if not player or not is_instance_valid(playback): return
	_combo_timer = maxf(_combo_timer - delta, 0.0)
	if active_attack_name != "" and is_instance_valid(anim_tree):
		var shot_active = bool(anim_tree.get("parameters/shot/active"))
		if not shot_active:
			_on_anim_hit_off(active_attack_name)
	
	var is_on_floor = player.is_on_floor()
	var just_jumped = _was_on_floor and not is_on_floor
	
	var horiz_velocity := Vector2(player.velocity.x, player.velocity.z).length()
	var moving := horiz_velocity > 1.0
	var running: bool = horiz_velocity > float(player.get("move_speed")) * PlayerMovementController.RUN_SPEED_RATIO
	var current := playback.get_current_node()
	var fast_available: bool = sm.has_node(STATE_FAST)
	var is_fast: bool = fast_available and bool(player.get("is_riva_fast"))

	if not is_on_floor:
		if (current != STATE_JUMP or just_jumped) and sm.has_node(STATE_JUMP):
			if just_jumped:
				playback.start(STATE_JUMP)
			else:
				playback.travel(STATE_JUMP)
				
			var char_id = GameData.get_selected().get("id", "mikeura")
			if char_id in ["mikeura", "vangry", "joel", "riva", "saimon"]:
				# 12 frames at standard 30 FPS = 0.4 seconds
				anim_tree.set("parameters/sm/jump/seek/seek_request", 12.0 / 30.0)
			elif char_id in ["bronch", "garri"]:
				# 32 frames at standard 30 FPS = ~1.066 seconds
				anim_tree.set("parameters/sm/jump/seek/seek_request", 32.0 / 30.0)
	else:
		if is_fast:
			if current != STATE_FAST:
				playback.travel(STATE_FAST)
		elif running and sm.has_node(STATE_RUN):
			if current != STATE_RUN:
				playback.travel(STATE_RUN)
		elif moving and sm.has_node(STATE_WALK):
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
	var trans := AnimationNodeStateMachineTransition.new()
	trans.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
	trans.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
	trans.xfade_time = xfade
	sm.add_transition(from, to, trans)

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
			var anim: Animation = ap.get_animation(names[0]).duplicate(true)
			_retarget_tracks(anim)
			lib.add_animation(new_name, anim)
	instance.queue_free()

## Los FBX exportados desde Blender cuelgan el esqueleto de "Armature/Skeleton3D";
## se reapuntan las pistas de huesos al esqueleto del modelo idle.
func _retarget_tracks(anim: Animation) -> void:
	if _skel_path.is_empty():
		return
	for i in anim.get_track_count():
		var path := anim.track_get_path(i)
		var bone := path.get_concatenated_subnames()
		if bone != "":
			anim.track_set_path(i, NodePath(str(_skel_path) + ":" + bone))

func _apply_texture_to_meshes(node: Node, tex: Texture2D) -> void:
	if node is MeshInstance3D:
		var mat = StandardMaterial3D.new()
		mat.albedo_texture = tex
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		node.material_override = mat
	for child in node.get_children():
		_apply_texture_to_meshes(child, tex)
