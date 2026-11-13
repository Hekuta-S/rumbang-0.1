class_name HubPlayer
extends CharacterBody3D

## El héroe caminando por el Salón (DungeonHub): el modelo personalizable con su apariencia, idle /
## andar / correr y movimiento con WASD, el stick, el joystick táctil (VirtualInput) o clic/toque en el
## suelo (move_to). No hay gravedad: el salón es plano (la altura se fija en floor_y).

const WALK_SPEED := 2.4
const RUN_SPEED := 4.6
const MODEL_HEIGHT := 1.62
const ANIM_FILES := {"walk": "res://assets/models/riva/riva-caminar.fbx", "run": "res://assets/models/riva/riva-correr.fbx"}

var model: Node3D
var pivot: Node3D
var anim: AnimationPlayer
var locked := true                 ## sin control (intro, paneles, saliendo)
var floor_y := 0.0
var move_target: Variant = null    ## Vector3 al que ir andando (clic/toque) o null
var arrived_cb: Callable           ## se llama al llegar a move_target
var _idle := ""
var _state := ""

func setup(p_floor_y: float, look: CharacterLook) -> void:
	floor_y = p_floor_y
	collision_layer = 2
	collision_mask = 1
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.6
	cs.shape = cap
	cs.position.y = 0.8
	add_child(cs)
	pivot = Node3D.new()
	pivot.name = "Pivote"
	add_child(pivot)
	var path := GameData.get_idle_model_path(CharacterLook.CHAR_ID)
	if not ResourceLoader.exists(path):
		return
	model = (load(path) as PackedScene).instantiate() as Node3D
	pivot.add_child(model)
	var mi := CharacterLookApplier.body_mesh(model)
	if mi and mi.mesh:
		var aabb := mi.mesh.get_aabb()
		var s := MODEL_HEIGHT / maxf(aabb.size.y, 0.001)
		model.scale = Vector3.ONE * s
		model.position = Vector3(0, -aabb.position.y * s, 0)
	CharacterLookApplier.apply_to(model, look)
	_setup_anims()

func _setup_anims() -> void:
	var found := model.find_children("*", "AnimationPlayer", true, false)
	if found.is_empty():
		return
	anim = found[0] as AnimationPlayer
	# la biblioteca la comparte el recurso del modelo: se copia antes de añadirle clips
	var lib := anim.get_animation_library("").duplicate(true) as AnimationLibrary
	anim.remove_animation_library("")
	anim.add_animation_library("", lib)
	_idle = String(lib.get_animation_list()[0])
	lib.get_animation(_idle).loop_mode = Animation.LOOP_LINEAR
	var skel := model.find_children("*", "Skeleton3D", true, false)
	if skel.is_empty():
		return
	var skel_path := anim.get_node(anim.root_node).get_path_to(skel[0])
	for key in ANIM_FILES:
		var src := _first_animation(String(ANIM_FILES[key]))
		if src == null:
			continue
		var a := src.duplicate(true) as Animation
		# mismo criterio que PlayerAnimationController._retarget_tracks: del clip viejo solo giros y la
		# altura de la cadera (el cuerpo personalizable tiene otras articulaciones)
		for i in range(a.get_track_count() - 1, -1, -1):
			var bone := a.track_get_path(i).get_concatenated_subnames()
			if bone == "":
				continue
			if bone != "mixamorig_Hips" and a.track_get_type(i) in [Animation.TYPE_POSITION_3D, Animation.TYPE_SCALE_3D]:
				a.remove_track(i)
				continue
			a.track_set_path(i, NodePath(str(skel_path) + ":" + bone))
		a.loop_mode = Animation.LOOP_LINEAR
		lib.add_animation(key, a)
	_play("idle")

func _first_animation(path: String) -> Animation:
	if not ResourceLoader.exists(path):
		return null
	var n := (load(path) as PackedScene).instantiate()
	var aps := n.find_children("*", "AnimationPlayer", true, false)
	var out: Animation = null
	if not aps.is_empty():
		var ap := aps[0] as AnimationPlayer
		var names := ap.get_animation_list()
		if not names.is_empty():
			out = ap.get_animation(names[0])
	n.free()
	return out

func has_clip(n: String) -> bool:
	return anim != null and anim.has_animation(n)

func _play(state: String) -> void:
	if anim == null or state == _state:
		return
	_state = state
	var clip := _idle if state == "idle" else state
	if anim.has_animation(clip):
		anim.play(clip, 0.22)

## Gira al héroe para que mire hacia `p` (en el plano).
func face(p: Vector3) -> void:
	var d := p - global_position
	if Vector2(d.x, d.z).length() > 0.01:
		pivot.rotation.y = atan2(d.x, d.z)

func move_to(p: Vector3, on_arrive: Callable = Callable()) -> void:
	move_target = Vector3(p.x, floor_y, p.z)
	arrived_cb = on_arrive

func stop() -> void:
	move_target = null
	arrived_cb = Callable()
	velocity = Vector3.ZERO
	_play("idle")

func _physics_process(delta: float) -> void:
	var dir := Vector3.ZERO
	var speed := WALK_SPEED
	if not locked:
		var v := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
		if VirtualInput.movement_vector.length() > 0.1:
			v = VirtualInput.movement_vector
		if v.length() > 0.1:
			move_target = null
			arrived_cb = Callable()
			dir = Vector3(v.x, 0, v.y)
			if dir.length() > 1.0:
				dir = dir.normalized()
			if Input.is_key_pressed(KEY_SHIFT) or VirtualInput.is_running or v.length() > 0.95 and Input.get_connected_joypads().size() > 0:
				speed = RUN_SPEED
		elif move_target != null:
			var to: Vector3 = (move_target as Vector3) - global_position
			to.y = 0
			if to.length() < 0.12:
				var cb := arrived_cb
				stop()
				if cb.is_valid():
					cb.call()
			else:
				dir = to.normalized()
				speed = RUN_SPEED if to.length() > 3.0 else WALK_SPEED
	velocity = dir * speed
	move_and_slide()
	position.y = floor_y
	if dir.length() > 0.05:
		pivot.rotation.y = lerp_angle(pivot.rotation.y, atan2(dir.x, dir.z), minf(1.0, delta * 12.0))
		_play("run" if speed > WALK_SPEED + 0.1 else "walk")
		# atascado contra algo al ir a un punto: se da por llegado
		if move_target != null and get_real_velocity().length() < 0.2 and get_slide_collision_count() > 0:
			var cb := arrived_cb
			stop()
			if cb.is_valid():
				cb.call()
	else:
		_play("idle")
