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

enum BossState { MOVING, IDLE_LIFESTEAL, SUMMONING, ERUPTING, VULNERABLE, PHASE_SHIFT }
var state: BossState = BossState.MOVING

## Fases según la vida: 0 = 100-66 %, 1 = 66-33 %, 2 = <33 % (enfurecido).
const PHASE_HP_THRESHOLDS: Array[float] = [0.66, 0.33]
const PHASE_SPEED_MULT: Array[float] = [1.0, 1.35, 1.7]
const PHASE_COOLDOWN_MULT: Array[float] = [1.0, 0.75, 0.5]
const PHASE_ZOMBIES: Array[int] = [3, 4, 5]
const PHASE_ERUPTIONS: Array[int] = [4, 6, 8]
const PHASE_LIFESTEAL_TIME: Array[float] = [3.0, 3.5, 4.5]
const PHASE_LIFESTEAL_RANGE: Array[float] = [15.0, 17.0, 20.0]
const PHASE_LIFESTEAL_DAMAGE: Array[float] = [2.0, 2.5, 3.0]
const PHASE_TINTS: Array[Color] = [Color.WHITE, Color(1.0, 0.8, 0.9), Color(1.0, 0.55, 0.55)]
## Tras cada habilidad el jefe queda quieto y vulnerable este tiempo (se acorta con las fases).
const VULNERABLE_TIME := 1.2
const PHASE_SHIFT_TIME := 1.3
var phase: int = 0
var _tint: Color = Color.WHITE
## Habilidades pendientes del sorteo actual: se baraja una bolsa para que no se repitan seguidas.
var _ability_bag: Array = []
var _last_ability: int = -1

# Efectos visuales (ver necromancer_vfx.gd)
var _aura: Dictionary = {}
var _beam: Node3D = null
var _sparks: CPUParticles3D = null
var _hit_fx: CPUParticles3D = null
var _bar: ProgressBar = null
var _bar_layer: CanvasLayer = null
var _heal_flash: float = 0.0
var _vfx_time: float = 0.0
var _dead: bool = false
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
	EnemyRegistry.register(self)
	add_to_group("boss")
	hp = max_hp
	player = get_tree().get_first_node_in_group("player")
	
	if not eruption_scene:
		eruption_scene = load("res://scenes/objects/eruption.tscn")
		
	_setup_model()
	_setup_vfx()

func _setup_vfx() -> void:
	_aura = NecroVFX.add_aura(self)
	_beam = NecroVFX.make_beam()
	add_child(_beam)
	_sparks = NecroVFX.make_sparks()
	add_child(_sparks)
	_hit_fx = NecroVFX.make_hit_fx()
	_hit_fx.position = Vector3(0, 2.5, 0)
	add_child(_hit_fx)
	_setup_health_bar()
	# Contorno de luz (rim) para destacar al jefe del resto
	for mi in mesh_instances:
		var mat := mi.material_override as StandardMaterial3D
		if mat:
			mat.rim_enabled = true
			mat.rim = 0.8
			mat.rim_tint = 0.4

## Barra de vida del jefe arriba al centro, con marcas en los cortes de fase (66 % y 33 %).
func _setup_health_bar() -> void:
	_bar_layer = CanvasLayer.new()
	_bar_layer.layer = 20
	add_child(_bar_layer)

	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.max_value = 100.0
	_bar.value = 100.0
	_bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_bar.offset_left = -260.0
	_bar.offset_right = 260.0
	_bar.offset_top = 46.0
	_bar.offset_bottom = 66.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.6, 0.15, 0.85)
	fill.set_corner_radius_all(3)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.05, 0.02, 0.1, 0.85)
	back.set_corner_radius_all(3)
	back.set_border_width_all(2)
	back.border_color = Color(0.85, 0.75, 1.0, 0.9)
	_bar.add_theme_stylebox_override("fill", fill)
	_bar.add_theme_stylebox_override("background", back)
	_bar_layer.add_child(_bar)

	for ratio in PHASE_HP_THRESHOLDS:
		var mark := ColorRect.new()
		mark.color = Color(1, 1, 1, 0.9)
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mark.anchor_left = ratio
		mark.anchor_right = ratio
		mark.anchor_bottom = 1.0
		mark.offset_right = 2.0
		_bar.add_child(mark)

	var title := Label.new()
	title.text = "NIGROMANTE"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 5)
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.offset_left = -100.0
	title.offset_right = 100.0
	title.offset_top = 20.0
	title.offset_bottom = 44.0
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bar_layer.add_child(title)

func _update_bar() -> void:
	if _bar:
		_bar.value = clampf(hp / max_hp, 0.0, 1.0) * 100.0

func _process(delta: float) -> void:
	_vfx_time += delta
	if _dead:
		return
	_heal_flash = maxf(_heal_flash - delta * 3.0, 0.0)
	var light: OmniLight3D = _aura.get("light")
	if is_instance_valid(light):
		light.light_energy = 1.3 + 0.5 * sin(_vfx_time * 2.2) + 2.5 * _heal_flash

## Oculta el haz y las chispas del robo de vida.
func _stop_drain() -> void:
	if is_instance_valid(_beam):
		_beam.visible = false
	if is_instance_valid(_sparks):
		_sparks.emitting = false

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
			velocity = to_player.normalized() * speed * PHASE_SPEED_MULT[phase]
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
			
			if is_instance_valid(_beam):
				var from := global_position + Vector3(0, 3.2, 0)
				var to := player.global_position + Vector3(0, 1.0, 0)
				_beam.visible = true
				NecroVFX.update_beam(_beam, from, to, NecroVFX.PHASE_COLORS[phase].lerp(Color(0.3, 1.0, 0.5), 0.6))
				_sparks.global_position = to
				_sparks.emitting = true

			if Engine.get_physics_frames() % 10 == 0:
				if global_position.distance_to(player.global_position) < PHASE_LIFESTEAL_RANGE[phase]:
					if player.has_method("take_damage"):
						player.take_damage(PHASE_LIFESTEAL_DAMAGE[phase])
						heal(PHASE_LIFESTEAL_DAMAGE[phase])
						_heal_flash = 1.0
			
			if state_timer <= 0:
				_stop_drain()
				_end_ability(2.0, 4.0)

		BossState.SUMMONING:
			state_timer -= delta
			velocity = Vector3.ZERO
			velocity.y = current_vy
			move_and_slide()
			play_animation("summon")
				
			if state_timer <= 0:
				spawn_zombies()
				_end_ability(4.0, 6.0)

		BossState.ERUPTING:
			state_timer -= delta
			velocity = Vector3.ZERO
			velocity.y = current_vy
			move_and_slide()
			play_animation("erupt")
				
			if state_timer <= 0:
				spawn_eruptions()
				_end_ability(3.0, 5.0)

		BossState.VULNERABLE:
			state_timer -= delta
			velocity = Vector3.ZERO
			velocity.y = current_vy
			move_and_slide()
			play_animation("idle")
			if state_timer <= 0:
				state = BossState.MOVING

		BossState.PHASE_SHIFT:
			state_timer -= delta
			velocity = Vector3.ZERO
			velocity.y = current_vy
			move_and_slide()
			play_animation("summon")
			if state_timer <= 0:
				state = BossState.MOVING
				ability_cooldown = 1.0

## Termina una habilidad: breve pausa vulnerable y cooldown (más corto en fases avanzadas).
func _end_ability(cd_min: float, cd_max: float) -> void:
	state = BossState.VULNERABLE
	state_timer = VULNERABLE_TIME / (1.0 + 0.5 * phase)
	ability_cooldown = randf_range(cd_min, cd_max) * PHASE_COOLDOWN_MULT[phase]

## Bolsa barajada de habilidades: no repite la última al rellenarse.
func _next_ability() -> int:
	if _ability_bag.is_empty():
		_ability_bag = [BossState.IDLE_LIFESTEAL, BossState.SUMMONING, BossState.ERUPTING]
		_ability_bag.shuffle()
		if _ability_bag[0] == _last_ability:
			_ability_bag.reverse()
	_last_ability = _ability_bag.pop_front()
	return _last_ability

func choose_next_ability():
	match _next_ability():
		BossState.IDLE_LIFESTEAL:
			state = BossState.IDLE_LIFESTEAL
			state_timer = PHASE_LIFESTEAL_TIME[phase]
		BossState.SUMMONING:
			state = BossState.SUMMONING
			state_timer = 1.5
		_:
			state = BossState.ERUPTING
			state_timer = 2.0

## Cambia de fase al cruzar un umbral de vida: interrumpe lo que hacía, ruge y se enfurece.
func _update_phase() -> void:
	var ratio := hp / max_hp
	var new_phase := 0
	for i in range(PHASE_HP_THRESHOLDS.size()):
		if ratio <= PHASE_HP_THRESHOLDS[i]:
			new_phase = i + 1
	if new_phase <= phase:
		return
	phase = new_phase
	_tint = PHASE_TINTS[phase]
	_stop_drain()
	NecroVFX.shockwave(get_parent(), global_position, 14.0, NecroVFX.PHASE_COLORS[phase])
	NecroVFX.set_aura_phase(_aura, phase)
	state = BossState.PHASE_SHIFT
	state_timer = PHASE_SHIFT_TIME
	_ability_bag.clear()
	_apply_tint()
	if player and is_instance_valid(player) and player.has_method("apply_camera_recoil"):
		player.apply_camera_recoil(0.05, 0.0, 0.3)

func spawn_zombies():
	var num_zombies: int = PHASE_ZOMBIES[phase]
	for i in range(num_zombies):
		var offset = Vector3(randf_range(-3.0, 3.0), 0, randf_range(-3.0, 3.0))
		var pos: Vector3 = global_position + offset
		pos.y = EnemyManager.floor_y(pos.x, pos.z)
		EnemyManager.spawn(EnemyData.EnemyType.ZOMBIE_GOBLIN, pos)
		NecroVFX.column(get_parent(), pos, NecroVFX.PHASE_COLORS[phase])
	NecroVFX.shockwave(get_parent(), global_position, 7.0, NecroVFX.PHASE_COLORS[phase])

func spawn_eruptions():
	if not eruption_scene or not player: return
	
	var e = eruption_scene.instantiate()
	get_parent().add_child(e)
	e.global_position = player.global_position
	
	var num_eruptions: int = PHASE_ERUPTIONS[phase]
	for i in range(num_eruptions):
		var er = eruption_scene.instantiate()
		get_parent().add_child(er)
		var offset = Vector3(randf_range(-6.0, 6.0), 0, randf_range(-6.0, 6.0))
		er.global_position = player.global_position + offset

func take_damage(amount: float, _knockback_dir: Vector3 = Vector3.ZERO) -> void:
	if _dead:
		return
	hp -= amount
	emit_signal("boss_hit")
	_update_bar()
	if hp > 0.0:
		_update_phase()
	if is_instance_valid(_hit_fx):
		_hit_fx.restart()
	
	_flash_hit()

	var FloatingDamage = load("res://scripts/objects/floating_damage.gd")
	if FloatingDamage:
		var is_crit = amount >= 24.0 or randf() < 0.2
		var col = Color(1.0, 0.25, 0.1) if is_crit else Color(1.0, 0.85, 0.2)
		FloatingDamage.spawn(get_parent(), global_position + Vector3(0, 2.2, 0), amount, col, is_crit)

	if hp <= 0:
		_die()

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
					mat.albedo_color = _tint
	)

func _apply_tint() -> void:
	for mi in mesh_instances:
		if is_instance_valid(mi) and mi.material_override:
			var mat := mi.material_override as StandardMaterial3D
			if mat:
				mat.albedo_color = _tint

func heal(amount: float):
	hp += amount
	if hp > max_hp: hp = max_hp
	_update_bar()

## Muerte: deja de ser un objetivo, se disuelve entre almas y solo entonces avisa (victoria, oro).
func _die() -> void:
	if _dead:
		return
	_dead = true
	remove_from_group("enemies")
	EnemyRegistry.unregister(self)
	remove_from_group("boss")
	collision_layer = 0
	collision_mask = 0
	set_physics_process(false)
	_stop_drain()
	for key in ["fog", "motes"]:
		if _aura.has(key):
			_aura[key].emitting = false
	if is_instance_valid(_bar_layer):
		_bar_layer.queue_free()
	NecroVFX.souls(get_parent(), global_position + Vector3(0, 2.0, 0))
	NecroVFX.shockwave(get_parent(), global_position, 10.0, NecroVFX.PHASE_COLORS[2])
	var tw := create_tween()
	tw.set_parallel(true)
	for mi in mesh_instances:
		var mat := mi.material_override as StandardMaterial3D if is_instance_valid(mi) else null
		if mat:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			tw.tween_property(mat, "albedo_color", Color(_tint.r, _tint.g, _tint.b, 0.0), 1.8)
	if model:
		tw.tween_property(model, "position:y", model.position.y + 1.2, 1.8)
	var light: OmniLight3D = _aura.get("light")
	if is_instance_valid(light):
		tw.tween_property(light, "light_energy", 0.0, 1.8)
	tw.chain().tween_callback(func():
		emit_signal("boss_died", global_position, gold_reward)
		queue_free()
	)
