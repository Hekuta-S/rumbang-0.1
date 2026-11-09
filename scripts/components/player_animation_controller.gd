extends Node
class_name PlayerAnimationController

signal hit_window_opened(attack_id: int, anim_name: String)
signal hit_window_closed(attack_id: int)
## Red (NetWorld): cada acción de cuerpo entero y cada disparo del arma sujeta se avisa a los demás jugadores,
## que los reproducen en la copia de este personaje (RemotePlayer, que lleva su propio controlador).
signal net_action(anim_name: String, from_time: float, speed: float)
signal net_held_shot(speed: float)

const STATE_IDLE = "idle"
const STATE_WALK = "walk"
const STATE_RUN  = "run"
const STATE_JUMP = "jump"
const STATE_FAST = "fast" ## Estado de súper carrera (Riva: pies humeantes)
## Paso lateral (solo piernas): clip "strafe" hacia la izquierda; hacia la derecha se reproduce al revés.
const STRAFE_ANIM = "strafe_l"
const LEG_BONES := ["LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase", "LeftToe_End",
	"RightUpLeg", "RightLeg", "RightFoot", "RightToeBase", "RightToe_End"]
## Acciones de un disparo (OneShot sobre la máquina de estados): combo de 3 ataques y grito.
const ATTACKS := ["attack1", "attack2", "attack3", "attack4"]
## Combo ligero: estocada, tajos horizontales, slash giratorio y otra estocada. Tras los cuatro, el
## especial (click derecho) lanza el clavado con salto (attack3), que ya no forma parte de la cadena.
const LIGHT_COMBO := ["attack1", "attack2", "attack4", "attack1"]
const SLAM := "attack3"
## Combo de cada arma cuerpo a cuerpo (mazmorra) y su velocidad de reproducción. Las acciones son
## de WeaponAnimSets.ACTION_SETS; las ventanas de golpe/enlace y el lunge, de las tablas de abajo.
const COMBOS := {
	WeaponData.WeaponType.SPEAR_LANCE: {"combo": LIGHT_COMBO, "speed": 0.8},
	# Dagas: rápidas pero no frenéticas (antes 1.0 y se podía encadenar a 0,16 s del golpe anterior)
	WeaponData.WeaponType.DAGGERS: {"combo": ["dagger1", "dagger2", "dagger1", "dagger3"], "speed": 0.75},
	# Maza: barrido, golpe al suelo (se queda clavada) y levantarla para golpear en vertical. El helicóptero
	# (mace3) queda cargado pero fuera del combo.
	WeaponData.WeaponType.MACE: {"combo": ["mace2", "mace1", "mace4"], "speed": 0.85},
	# Espadón: los tres tajos del clip "Great Sword Slash" (cortado en los fotogramas 33 y 77)
	# Transición al segundo golpe (gs2) más lenta y pesada al levantar el arma
	WeaponData.WeaponType.GREATSWORD: {
		"combo": ["gs1", "gs2", "gs3"],
		"speed": 1.1,
		"speeds": {"gs1": 1.1, "gs2": 0.85, "gs3": 1.1, "gs_run": 1.1}
	},
	# Espada: ataque1, ataque2 y los dos golpes del clip "combo" (cortado en el fotograma 40)
	WeaponData.WeaponType.SWORD: {
		"combo": ["sw1", "sw2", "sw3", "sw4"],
		"speed": 1.15,
		"speeds": {"sw1": 1.2, "sw2": 1.2, "sw3": 1.1, "sw4": 1.1, "sw_run": 1.1}
	},
}
## Armas con carrera (espadón y espada): el clic mientras corren lanza este ataque, y los golpes siguientes
## continúan el combo desde el segundo.
const RUN_ATTACKS := {WeaponData.WeaponType.GREATSWORD: "gs_run", WeaponData.WeaponType.SWORD: "sw_run"}
## Espadón. Con él se anda despacio y se pasa a correr tras GS_RUN_DELAY s sin atacar, recibir daño ni rodar
## (PlayerMovementController); el clic mientras se corre lanza GS_RUN_ATTACK (ataque_si_va_corriendo) y los
## golpes siguientes continúan el combo desde el segundo.
const GS_RUN_ATTACK := "gs_run"
## Velocidad (m/s) a partir de la que se anima la carrera del espadón (andando va a ~2 m/s, corriendo a ~5,5).
const GS_WALK_TO_RUN := 3.6
## Velocidad (m/s) que representa cada clip del espadón a velocidad 1 en el personaje, ya con la zancada
## alargada (WeaponAnimSets.widen_stride): retroceso del pie apoyado, medido en juego con
## tools/measure_foot_slip.tscn. Volver a medir si cambian los clips o la zancada.
const GS_GAIT_SPEED := {"walk": 1.0, "run": 4.0, "strafe": 1.2}
## Lo mismo para cada arma con locomoción propia.
const WEAPON_GAIT_SPEED := {
	WeaponData.WeaponType.GREATSWORD: GS_GAIT_SPEED,
	WeaponData.WeaponType.SWORD: {"walk": 1.37, "run": 3.9, "strafe": 1.5},
}
## Tope de aceleración de los clips del arma. Antes llegaba a 1,7: 5-6 pasos/s al correr, se veía embalado.
## Con el tope, a la carrera del espadón le queda algo de deslizamiento (~10 %), menos visible que la cadencia.
const GS_GAIT_MAX_SCALE := {"walk": 1.5, "run": 1.25, "strafe": 1.5}
## Todas las acciones de golpe de combo (las que cuentan como "atacando").
const MELEE_ACTIONS := ["attack1", "attack2", "attack3", "attack4",
	"dagger1", "dagger2", "dagger3", "mace1", "mace2", "mace3", "mace4", "gs1", "gs2", "gs3", "gs_run",
	"sw1", "sw2", "sw3", "sw4", "sw_run"]
## Acciones especiales de las dagas y la maza (sin ventanas de golpe: el golpe lo pone la estrategia).
const DAGGER_DASH := "dagger_dash"
const MACE_SLAM := "mace_slam"
const ACTION_SHOUT = "shout"
const COMBO_RESET := 1.1   ## segundos sin atacar para volver al primer golpe
## Velocidad de reproducción de los golpes de la espalanza (1 = la del clip). Las ventanas de golpe
## y de enlace van en tiempo del clip, así que se estiran con ella y siguen sincronizadas.
const SPEAR_ATTACK_SPEED := 0.8
const ACTION_SCALE_PARAM := "parameters/action_scale/scale"
const ACTION_PARRY := "parry"
const ACTION_ROLL := "roll"
const SHOT_PARAM := "parameters/shot/request"
const SEEK_PARAM := "parameters/seek/seek_request"
## Ranuras de acción (ver setup_model) y fundido entre un golpe y el siguiente del combo (s, tiempo de acción).
const ACTION_SLOTS := ["a", "b"]
const SEEK_NODES := ["seek", "seek_b"]
const ACTION_SLOTS_PARAM := "parameters/action_slots/transition_request"
const ACTION_XFADE := 0.16
var _action_slots: Array[AnimationNodeAnimation] = []
var _action_slot := 0
var _action_started := ""   ## acción de cuerpo entero que suena ahora en la ranura activa
const ONE_SHOT_FADEOUT := 0.18
const ONE_SHOT_FADEIN := 0.08
const ACTION_CHARGE = "charge"
## Postura de carga: primeros CHARGE_POSE_T s de attack1 (la lanza atrás), sostenidos.
const CHARGE_POSE_T := 0.2
## Armas sujetas con las dos manos (solo mazmorra), las use quien las use: capa de torso
## sostener/disparar sobre la locomoción y explosión de cuerpo entero por el OneShot. Las animaciones
## son por ARMA (WeaponAnimSets) y se adaptan a este esqueleto al equiparla; el arma va en un ancla
## animada (WeaponAnchor) y las manos la agarran con IK (TwoBoneIK3D).
const HELD_HOLD := "w_hold_%d"
const HELD_FIRE := "w_fire_%d"
const HELD_BLAST := "w_blast_%d"
const UPPER_BONES := ["Spine", "Spine1", "Spine2", "Neck", "Head", "LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
	"RightShoulder", "RightArm", "RightForeArm", "RightHand"]
## Con un arma solo de transporte (CARRY: maza al hombro, dagas en guardia) la columna, el cuello y la cabeza
## salen del filtro de la capa de torso: siguen la locomoción (inclinación, giro y vaivén del paso, o la
## respiración del reposo) y los brazos van con el pecho en la postura del arma. Si el torso entero fuese la
## postura fija, las piernas correrían bajo un busto congelado (se veía robótico). Las armas sujetas que
## apuntan (lanzallamas...) sí necesitan la columna.
const SPINE_BONES := ["Spine", "Spine1", "Spine2", "Neck", "Head"]
## Peso de la postura de transporte en los brazos mientras se anda/corre, por arma (1 = brazos fijos en la
## postura). Las dagas son ligeras: al moverse los brazos siguen sobre todo el balanceo de la locomoción
## (con las hojas en las manos) y vuelven a la guardia al pararse. La maza al hombro no se suelta.
const CARRY_MOVING_WEIGHT := {WeaponData.WeaponType.DAGGERS: 0.25}
var _carry_move := 1.0
var _held_layer := false
var _held_hold := 0.0
var _held_fire := 0.0
## Lanzamientos de polvos de Tatan (solo mazmorra), de cuerpo entero por el OneShot.
## Los tres de polvo arcano se alternan. Valor: segundo en que el polvo sale de la mano.
const DUST_THROWS := ["dust1", "dust2", "dust3"]
const DUST_RELEASE := {"dust1": 0.30, "dust2": 0.37, "dust3": 0.30, "dust_heal": 0.37, "dust_speed": 0.27, "dust_face": 0.30}
var _dust_index := 0
## Gestos de invocación de Joel (solo mazmorra): uno por animación del Komodo (latigazo, torbellino, martillazo).
const GESTURES := ["gesture1", "gesture2", "gesture3"]
var held_weapon_type := -1    ## arma sujeta equipada ahora (WeaponData.WeaponType), -1 si ninguna
var held_equipped := false   ## set_held_weapon() lo pone según el arma activa
## La capa de torso solo pone la postura de transporte del arma (maza al hombro): sin IK de manos.
var carry_only := false
const HELD_CARRY := "w_carry_%d"
var _weapon_anchor: Node3D
var _hand_ik: HandIKModifier
var _held_built := {}         ## armas cuyas animaciones ya se adaptaron a este esqueleto
var held_fire_until := 0.0   ## la estrategia del arma lo renueva al disparar (s)
## Lunge de cada ataque: [segundos hasta el impulso, velocidad m/s]. Cortos: los pies quedan plantados
## (estilo God of War: el peso lo pone la animación, no el deslizamiento).
const ATTACK_DASH := {"attack1": [0.14, 6.0], "attack2": [0.15, 2.5], "attack3": [0.2, 7.0], "attack4": [0.2, 3.0],
	"dagger1": [0.08, 6.0], "dagger2": [0.08, 6.0], "dagger3": [0.13, 2.0],
	"mace1": [0.62, 5.0], "mace2": [0.58, 3.0], "mace3": [0.55, 1.5], "mace4": [0.62, 4.0]}   # (el espadón avanza con el clip: root motion)

## Ventanas activas de golpe por animación: [inicio_s, fin_s] o una lista de ellas.
## attack1 = estocada, attack2 = dos tajos horizontales (una ventana por tajo), attack3 = salto y clavado.
## Dagas: tajo derecho, revés izquierdo y torbellino. Maza (a dos manos): diagonal, barrido y helicóptero.
const ATTACK_WINDOWS := {
	"attack1": [0.20, 0.33],
	"attack2": [[0.17, 0.30], [0.47, 0.58]],
	"attack3": [0.45, 0.60],
	"attack4": [0.22, 0.55],
	"dagger1": [0.10, 0.20],
	"dagger2": [0.10, 0.20],
	"dagger3": [0.13, 0.42],
	# Maza pesada (2026-11-05): preparación larga, caída rápida, se clava y se recupera con esfuerzo
	"mace1": [0.63, 0.83],
	"mace2": [0.60, 0.83],
	"mace3": [0.57, 1.13],
	"mace4": [0.67, 0.83],
	# Espadón (tiempos de clip): bajada del tajo 1 (fotogramas 21-28), barrido del 2 (46-54 del clip entero),
	# martillazo vertical del 3 (92-101) y estocada del ataque corriendo (fotogramas 28-36)
	"gs1": [0.70, 0.93],
	"gs2": [0.43, 0.70],
	"gs3": [0.50, 0.80],
	"gs_run": [0.93, 1.20],
	# Espada (tiempos de clip, medidos por la velocidad de la mano: tools/measure_sword_clips.tscn). sw3 lleva dos
	# tajos antes del corte del fotograma 40; sw4 es la estocada final con avance.
	"sw1": [0.72, 0.98],
	"sw2": [0.70, 0.90],
	"sw3": [[0.50, 0.82], [1.00, 1.27]],
	"sw4": [0.85, 1.15],
	"sw_run": [0.27, 0.66],
}
## Ajustes de las ventanas de golpe hechos con el editor (tools/melee_grip_editor.tscn): {anim: [[ini_s, fin_s], ...]}.
## Lo que haya en el JSON sustituye a ATTACK_WINDOWS para esa animación.
const ATTACK_WINDOWS_CONFIG_PATH := "res://resources/attack_windows.json"
static var _windows_config: Dictionary = {}
static var _windows_config_loaded := false

static func attack_windows_config() -> Dictionary:
	if not _windows_config_loaded:
		_windows_config_loaded = true
		_windows_config = {}
		var txt := FileAccess.get_file_as_string(ATTACK_WINDOWS_CONFIG_PATH)
		if txt != "":
			var parsed: Variant = JSON.parse_string(txt)
			if parsed is Dictionary:
				_windows_config = parsed
	return _windows_config

static func reload_attack_windows_config() -> void:
	_windows_config_loaded = false
	_windows_config = {}

static func has_attack_windows(anim_name: String) -> bool:
	return not attack_windows(anim_name).is_empty()

## Ventanas activas de `anim_name` (segundos de clip), siempre como lista de [ini, fin]; el JSON manda sobre la tabla.
static func attack_windows(anim_name: String) -> Array:
	var raw: Variant = attack_windows_config().get(anim_name, ATTACK_WINDOWS.get(anim_name, []))
	return normalize_windows(raw)

static func normalize_windows(raw: Variant) -> Array:
	var out: Array = []
	if not (raw is Array) or (raw as Array).is_empty():
		return out
	var list: Array = raw if (raw as Array)[0] is Array else [raw]
	for w in list:
		if w is Array and (w as Array).size() >= 2:
			out.append([float(w[0]), float(w[1])])
	return out

## Ventanas de enlace [inicio_enlace_s, fin_enlace_s]
## Permiten encadenar el siguiente golpe durante la recuperación
const LINK_WINDOWS := {
	"attack1": [0.30, 0.68],
	"attack2": [0.66, 1.0],
	"attack3": [0.55, 0.95],
	"attack4": [0.45, 0.85],
	"dagger1": [0.26, 0.40],
	"dagger2": [0.26, 0.40],
	"dagger3": [0.48, 0.60],
	"mace1": [1.00, 1.60],
	"mace2": [0.95, 1.45],
	"mace3": [1.30, 1.75],
	"mace4": [1.05, 1.60],
	"gs1": [0.98, 1.40],
	"gs2": [0.95, 1.90],
	"gs_run": [1.20, 1.90],
	"sw1": [1.00, 1.60],
	"sw2": [0.92, 1.45],
	"sw3": [1.15, 1.40],
	"sw_run": [0.70, 1.25],
}

var current_attack_id: int = 0
var active_attack_name: String = ""
var _current_action_name: String = ""
var _action_elapsed: float = 0.0   ## en tiempo del clip (ya escalado por _action_speed)
var _action_speed: float = 1.0

var player: CharacterBody3D
var model: Node3D
var anim_player: AnimationPlayer
var anim_tree: AnimationTree
var playback: AnimationNodeStateMachinePlayback
var sm: AnimationNodeStateMachine
var _action_node: AnimationNodeAnimation
var _skel_path: NodePath
var _combo_index: int = 0
var light_hits: int = 0      ## golpes ligeros encadenados (el cuarto habilita el clavado)
var _combo_timer: float = 0.0
var _skip_next_attack := false
## La carga y el lanzamiento reutilizan attack1: no deben abrir su ventana de golpe melee ni su dash.
var _suppress_hit_window := false
var foot_ik: FootIKModifier

func _ready() -> void:
	player = get_parent() as CharacterBody3D
	setup_model()

## Mazmorra: el casco equipado se ve en la cabeza (EquipmentDB.helmet_of) y cambia con el equipo.
func _bind_equipment_helmet() -> void:
	var eq := player.get("equipment") as PlayerEquipment if player else null
	if eq == null:
		return
	if not eq.equipment_changed.is_connected(_refresh_helmet):
		eq.equipment_changed.connect(_refresh_helmet)
	_refresh_helmet()

func _refresh_helmet() -> void:
	var eq := player.get("equipment") as PlayerEquipment if player else null
	if eq and model:
		CharacterLookApplier.set_helmet_on(model, EquipmentDB.helmet_of(eq.get_item("casco")))
		CharacterLookApplier.set_armor_on(model, "pechera", EquipmentDB.armor_of(eq.get_item("pechera")))
		CharacterLookApplier.set_armor_on(model, "pantalones", EquipmentDB.armor_of(eq.get_item("pantalones")))

func setup_model() -> void:
	var char_id: String = _char_id()
	
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
	
	if char_id == CharacterLook.CHAR_ID:
		# Personaje personalizable: colores, accesorios y proporciones (local o de otro jugador de la red)
		var net_look: Variant = player.get("net_look")
		var look := CharacterLook.from_dict(net_look) if net_look is Dictionary else CharacterLook.current()
		CharacterLookApplier.apply_to(model, look)
		_bind_equipment_helmet()
	elif FileAccess.file_exists(tex_path) or FileAccess.file_exists(tex_path + ".import"):
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
	# La biblioteca viene del recurso de la escena, que COMPARTEN todas las instancias del mismo modelo (el
	# jugador local y la copia de un jugador remoto del mismo personaje): se copia para que cada controlador
	# modifique la suya (clips de arma, ventanas de golpe) sin pisar a los demás.
	_own_animation_library()
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

	if files.has("strafe"):
		var strafe_scene = load(base_path + files["strafe"]) as PackedScene
		if strafe_scene:
			_merge_first_animation_from_scene(strafe_scene, lib, STRAFE_ANIM)
			_keep_leg_tracks(lib.get_animation(STRAFE_ANIM))

	if files.has("jump"):
		var jump_scene = load(base_path + files["jump"]) as PackedScene
		if jump_scene: _merge_first_animation_from_scene(jump_scene, lib, STATE_JUMP)

	# Mazmorra: los golpes de la lanza son acciones del ARMA (WeaponAnimSets.ACTION_SETS), se cargan al
	# equiparla; aquí solo queda el grito (es del personaje)
	var own_actions: Array = [ACTION_SHOUT] if GameData.game_mode == "dungeon" else ATTACKS + [ACTION_SHOUT]
	for action_name in own_actions:
		if files.has(action_name):
			var action_scene = load(base_path + files[action_name]) as PackedScene
			if action_scene: _merge_first_animation_from_scene(action_scene, lib, action_name)
			if lib.has_animation(action_name):
				lib.get_animation(action_name).loop_mode = Animation.LOOP_NONE
				if has_attack_windows(action_name):
					_inject_hit_method_tracks(lib.get_animation(action_name), action_name)

	if GameData.game_mode == "dungeon":
		_held_layer = skel != null and (skel as Skeleton3D).find_bone("mixamorig_RightHand") >= 0
		if _held_layer:
			_setup_weapon_anchor(skel as Skeleton3D)

	if lib.has_animation(ATTACKS[0]):
		lib.add_animation(ACTION_CHARGE, _make_hold_pose(lib.get_animation(ATTACKS[0]), CHARGE_POSE_T))

	for looping_name in [STATE_IDLE, STATE_WALK, STATE_RUN, STATE_FAST]:
		if lib.has_animation(looping_name):
			lib.get_animation(looping_name).loop_mode = Animation.LOOP_LINEAR
			if WeaponAnimSets.STRIDE_WIDEN.has(looping_name):
				WeaponAnimSets.widen_stride(lib.get_animation(looping_name), WeaponAnimSets.STRIDE_WIDEN[looping_name])

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
	# Dos ranuras de acción (A/B) con fundido entre ellas: un golpe encadenado entra en la otra ranura y se
	# funde desde la pose del golpe anterior (antes se abortaba el OneShot y el golpe nuevo entraba desde la
	# locomoción: se veía un corte entre golpes del combo).
	_action_slots.clear()
	var slots := AnimationNodeTransition.new()
	slots.xfade_time = ACTION_XFADE
	slots.allow_transition_to_self = false
	for i in ACTION_SLOTS.size():
		var node := AnimationNodeAnimation.new()
		node.animation = STATE_IDLE
		_action_slots.append(node)
		var slot_name: String = ACTION_SLOTS[i]
		root.add_node("action" + ("" if i == 0 else "_" + slot_name), node, Vector2(0, 200 + 100 * i))
		root.add_node(SEEK_NODES[i], AnimationNodeTimeSeek.new(), Vector2(80, 200 + 100 * i))
		root.connect_node(SEEK_NODES[i], 0, "action" + ("" if i == 0 else "_" + slot_name))
		slots.add_input(slot_name)
		slots.set_input_reset(i, true)
	root.add_node("action_slots", slots, Vector2(140, 200))
	for i in ACTION_SLOTS.size():
		root.connect_node("action_slots", i, SEEK_NODES[i])
	_action_slot = 0
	_action_node = _action_slots[0]
	root.add_node("action_scale", AnimationNodeTimeScale.new(), Vector2(180, 200))
	root.connect_node("action_scale", 0, "action_slots")
	var shot := AnimationNodeOneShot.new()
	shot.fadein_time = ONE_SHOT_FADEIN
	shot.fadeout_time = ONE_SHOT_FADEOUT
	root.add_node("shot", shot, Vector2(250, 0))
	# Piernas del paso lateral sobre la locomoción (el torso sigue con andar/reposo)
	# Velocidad de los pasos ajustada a la velocidad real (sin patinar), ver _update_gait_scale
	root.add_node("loco_scale", AnimationNodeTimeScale.new(), Vector2(-60, 0))
	root.connect_node("loco_scale", 0, "sm")
	var loco := "loco_scale"
	if lib.has_animation(STRAFE_ANIM):
		lib.get_animation(STRAFE_ANIM).loop_mode = Animation.LOOP_LINEAR
		var sl := AnimationNodeAnimation.new()
		sl.animation = STRAFE_ANIM
		root.add_node("strafe_l", sl, Vector2(-200, -300))
		var sr := AnimationNodeAnimation.new()
		sr.animation = STRAFE_ANIM
		sr.play_mode = AnimationNodeAnimation.PLAY_MODE_BACKWARD
		root.add_node("strafe_r", sr, Vector2(-200, -200))
		root.add_node("strafe_lr", AnimationNodeBlend2.new(), Vector2(-80, -250))
		root.connect_node("strafe_lr", 0, "strafe_l")
		root.connect_node("strafe_lr", 1, "strafe_r")
		root.add_node("strafe_scale", AnimationNodeTimeScale.new(), Vector2(0, -250))
		root.connect_node("strafe_scale", 0, "strafe_lr")
		var legs := AnimationNodeBlend2.new()
		legs.filter_enabled = true
		for b in LEG_BONES:
			legs.set_filter_path(NodePath(str(_skel_path) + ":mixamorig_" + b), true)
		root.add_node("legs", legs, Vector2(60, -100))
		root.connect_node("legs", 0, "loco_scale")
		root.connect_node("legs", 1, "strafe_scale")
		loco = "legs"
		_has_strafe = true
	# Brazos más tranquilos al andar/correr: se mezclan con los del reposo (mismo ritmo que las piernas,
	# menos recorrido). El peso lo pone _update_gait_scale.
	var calm_idle := AnimationNodeAnimation.new()
	calm_idle.animation = STATE_IDLE
	root.add_node("calm_idle", calm_idle, Vector2(-200, 100))
	var calm := AnimationNodeBlend2.new()
	calm.filter_enabled = true
	for b in ARM_BONES:
		calm.set_filter_path(NodePath(str(_skel_path) + ":mixamorig_" + b), true)
	root.add_node("arms_calm", calm, Vector2(180, -60))
	root.connect_node("arms_calm", 0, loco)
	root.connect_node("arms_calm", 1, "calm_idle")
	loco = "arms_calm"
	if _held_layer:
		# Torso sujetando el lanzallamas (mezcla sostener/disparar) sobre las piernas de la locomoción
		var hold_node := AnimationNodeAnimation.new()
		hold_node.animation = STATE_IDLE      # se cambia al equipar un arma (set_held_weapon)
		root.add_node("w_hold", hold_node, Vector2(-200, 400))
		var fire_node := AnimationNodeAnimation.new()
		fire_node.animation = STATE_IDLE
		root.add_node("w_fire", fire_node, Vector2(-200, 500))
		root.add_node("w_fire_seek", AnimationNodeTimeSeek.new(), Vector2(-80, 500))
		root.connect_node("w_fire_seek", 0, "w_fire")
		root.add_node("w_fire_scale", AnimationNodeTimeScale.new(), Vector2(-40, 500))
		root.connect_node("w_fire_scale", 0, "w_fire_seek")
		root.add_node("w_mix", AnimationNodeBlend2.new(), Vector2(0, 450))
		root.connect_node("w_mix", 0, "w_hold")
		root.connect_node("w_mix", 1, "w_fire_scale")
		var upper := AnimationNodeBlend2.new()
		upper.filter_enabled = true
		for b in UPPER_BONES:
			upper.set_filter_path(NodePath(str(_skel_path) + ":mixamorig_" + b), true)
		for n in _anchor_paths():
			upper.set_filter_path(n, true)
		root.add_node("upper", upper, Vector2(120, 0))
		root.connect_node("upper", 0, loco)
		root.connect_node("upper", 1, "w_mix")
		root.connect_node("shot", 0, "upper")
	else:
		root.connect_node("shot", 0, loco)
	root.connect_node("shot", 1, "action_scale")
	root.connect_node("output", 0, "shot")
	anim_tree.tree_root = root
	playback = anim_tree.get("parameters/sm/playback") as AnimationNodeStateMachinePlayback
	if playback == null:
		push_error("AnimationTree playback not available.")
		return

	playback.start(STATE_IDLE)
	anim_tree.set(ACTION_SLOTS_PARAM, ACTION_SLOTS[0])
	if player.has_signal("weapon_attacked"):
		player.weapon_attacked.connect(_on_weapon_attacked)
	_setup_foot_ik()
	_ensure_common_actions()

## Guardia del parry y voltereta de la esquiva (solo mazmorra), adaptadas a este esqueleto.
func _ensure_common_actions() -> void:
	if GameData.game_mode != "dungeon" or not anim_player:
		return
	var skel := _find_first_node_of_type(model, "Skeleton3D") as Skeleton3D
	if skel == null:
		return
	var lib: AnimationLibrary = anim_player.get_animation_library("")
	var actions := WeaponAnimSets.build_common_actions(skel, _skel_path)
	for action_name in actions:
		if lib.has_animation(action_name):
			lib.remove_animation(action_name)
		lib.add_animation(action_name, actions[action_name])

## Acción de cuerpo entero de un arma (p. ej. los giros del hacha), sin ventanas de golpe melee.
func play_action(action_name: String) -> void:
	_fire_action(action_name)
	_suppress_hit_window = true

## Postura de guardia del parry (cuerpo entero, sin ventanas de golpe).
func play_parry() -> void:
	_fire_action(ACTION_PARRY)
	_suppress_hit_window = true

## Voltereta de la esquiva, ajustada para que dure `duration` segundos.
func play_roll(duration: float) -> void:
	var lib := anim_player.get_animation_library("") if anim_player else null
	if lib == null or not lib.has_animation(ACTION_ROLL):
		return
	_fire_action(ACTION_ROLL, -1.0, lib.get_animation(ACTION_ROLL).length / maxf(duration, 0.05))
	_suppress_hit_window = true

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
	_suppress_hit_window = true

## Lanzamiento: el estoque de attack1 desde la lanza ya atrás; sin lunge.
func play_throw() -> void:
	_skip_next_attack = true
	_fire_action(ATTACKS[0], CHARGE_POSE_T)
	_suppress_hit_window = true

## Combo del arma activa (o el de la espalanza si no tiene uno propio).
func _combo_cfg() -> Dictionary:
	var w: int = player.current_weapon() if player and player.has_method("current_weapon") else -1
	return COMBOS.get(w, COMBOS[WeaponData.WeaponType.SPEAR_LANCE])

func _combo_action_speed(anim_name: String) -> float:
	var cfg := _combo_cfg()
	if cfg.has("speeds") and (cfg["speeds"] as Dictionary).has(anim_name):
		return float(cfg["speeds"][anim_name])
	return float(cfg.get("speed", 1.0))

## Golpe del combo del arma (espalanza: 1 → 2 → 4 → 1); se reinicia tras COMBO_RESET sin atacar.
func play_attack() -> void:
	var cfg := _combo_cfg()
	var combo: Array = cfg["combo"]
	var lib := anim_player.get_animation_library("") if anim_player else null
	if lib == null or not lib.has_animation(combo[0]):
		return
	if _combo_timer <= 0.0 or _combo_index >= combo.size():
		_combo_index = 0
	# Espadón corriendo: embiste con el ataque de carrera, que cuenta como primer golpe del combo
	var run_name: String = RUN_ATTACKS.get(player.current_weapon(), "") if player and player.has_method("current_weapon") else ""
	var run_attack: bool = run_name != "" and lib.has_animation(run_name) and not is_attacking() and _gs_is_running()
	var anim_name: String = run_name if run_attack else str(combo[_combo_index])
	_combo_index = (1 if run_attack else _combo_index + 1) % combo.size()
	light_hits = mini(light_hits + 1, combo.size()) if _combo_timer > 0.0 else 1
	# El combo sigue vivo al menos hasta que se cierra la ventana de enlace (los golpes de maza son largos)
	var reset := COMBO_RESET
	if LINK_WINDOWS.has(anim_name):
		reset = maxf(reset, float(LINK_WINDOWS[anim_name][1]) + 0.25)
	_combo_timer = reset / _combo_action_speed(anim_name)
	_fire_action(anim_name)
	_schedule_dash(anim_name)

## ¿Se completaron los cuatro golpes ligeros y el combo sigue vivo? Entonces el especial es el clavado.
func can_slam() -> bool:
	if not is_instance_valid(anim_player) or not anim_player.get_animation_library("").has_animation(SLAM):
		return false
	return light_hits >= LIGHT_COMBO.size() and _combo_timer > 0.0

## Clavado con salto (mucho más fuerte que los golpes ligeros); reinicia el combo.
func play_slam() -> void:
	light_hits = 0
	_combo_index = 0
	_combo_timer = 0.0
	_fire_action(SLAM)
	_schedule_dash(SLAM)

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

## Vuelve a poner las ventanas de golpe de `anim_name` en su clip (tras cambiarlas con el editor o recargar el JSON).
func refresh_hit_windows(anim_name: String) -> void:
	if anim_player == null:
		return
	var lib := anim_player.get_animation_library("")
	if lib and lib.has_animation(anim_name):
		_inject_hit_method_tracks(lib.get_animation(anim_name), anim_name)

func _inject_hit_method_tracks(anim: Animation, anim_name: String) -> void:
	if anim_player == null:
		return
	var root_target = anim_player.get_node(anim_player.root_node)
	var my_path: NodePath = root_target.get_path_to(self)
	# Quita la pista de ventanas anterior (el editor las vuelve a inyectar al cambiarlas)
	for t in range(anim.get_track_count() - 1, -1, -1):
		if anim.track_get_type(t) == Animation.TYPE_METHOD and anim.track_get_path(t) == my_path:
			anim.remove_track(t)
	var windows := attack_windows(anim_name)
	if windows.is_empty():
		return
	var track_idx = anim.add_track(Animation.TYPE_METHOD)
	anim.track_set_path(track_idx, my_path)
	for window in windows:
		anim.track_insert_key(track_idx, float(window[0]), {"method": "_on_anim_hit_on", "args": [anim_name]})
		anim.track_insert_key(track_idx, float(window[1]), {"method": "_on_anim_hit_off", "args": [anim_name]})

func _on_anim_hit_on(anim_name: String) -> void:
	# (el golpe anterior del combo sigue sonando unos instantes en la otra ranura durante el fundido)
	if _suppress_hit_window or anim_name != _current_action_name:
		return
	current_attack_id += 1
	active_attack_name = anim_name
	if GameData.game_mode == "dungeon":
		_trigger_hit_dash(anim_name)
	hit_window_opened.emit(current_attack_id, anim_name)

func _on_anim_hit_off(anim_name: String) -> void:
	if active_attack_name != "" and anim_name == active_attack_name:
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

func is_attacking() -> bool:
	if _current_action_name in MELEE_ACTIONS:
		if is_instance_valid(anim_tree):
			return bool(anim_tree.get("parameters/shot/active"))
	return false

func is_in_link_window() -> bool:
	if not is_attacking():
		return false
	if not LINK_WINDOWS.has(_current_action_name):
		return false
	var lw: Array = LINK_WINDOWS[_current_action_name]
	return _action_elapsed >= float(lw[0]) and _action_elapsed <= float(lw[1])

func advance_combo() -> void:
	play_attack()

## La esquiva corta la recuperación de attack1/attack2, pero no el clavado (attack3) ni un golpe
## con la ventana de impacto abierta.
func can_cancel_for_dodge() -> bool:
	if active_attack_name != "":
		return false
	return not (is_attacking() and _current_action_name == ATTACKS[2])

## Corta la acción de cuerpo entero en curso (recuperación de un golpe, pose de carga...).
func cancel_action() -> void:
	if is_instance_valid(anim_tree) and bool(anim_tree.get("parameters/shot/active")):
		anim_tree.set(SHOT_PARAM, AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
	_on_anim_hit_off(_current_action_name)
	_current_action_name = ""
	_action_started = ""

func _fire_action(anim_name: String, from_time: float = -1.0, speed: float = -1.0) -> void:
	if not is_instance_valid(anim_tree) or _action_node == null:
		return
	if not anim_player.get_animation_library("").has_animation(anim_name):
		return
	net_action.emit(anim_name, from_time, speed)
	_current_action_name = anim_name
	if anim_name in MELEE_ACTIONS or anim_name == ACTION_ROLL or anim_name == ACTION_PARRY:
		_note_combat()
	# ¿Hay una acción en curso (aunque el OneShot ya esté desvaneciéndose hacia la locomoción)? Entonces la nueva
	# entra en la otra ranura y se funde desde ella: el OneShot sigue activo con el clip nuevo y no hay corte. Si
	# no, el OneShot arranca de nuevo desde la locomoción. (tools/measure_combo_pops.tscn mide los saltos.)
	var remaining := _action_remaining()
	var blend_from_current := remaining > 0.0
	# Ya desvaneciéndose: el OneShot terminaría al acabar el fundido aunque suene el clip nuevo; se relanza
	var refire := blend_from_current and remaining <= _shot_node().fadeout_time + 0.02
	if active_attack_name != "":
		_on_anim_hit_off(active_attack_name)   # el tajo anterior se sustituye: su ventana de golpe acaba aquí
	_action_elapsed = 0.0
	_action_speed = speed if speed > 0.0 else (_combo_action_speed(anim_name) if anim_name in MELEE_ACTIONS else 1.0)
	anim_tree.set(ACTION_SCALE_PARAM, _action_speed)
	_suppress_hit_window = false
	if blend_from_current:
		_action_slot = (_action_slot + 1) % ACTION_SLOTS.size()
		_action_node = _action_slots[_action_slot]
		_action_node.animation = anim_name
		anim_tree.set(ACTION_SLOTS_PARAM, ACTION_SLOTS[_action_slot])
		if refire:
			anim_tree.set(SHOT_PARAM, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	else:
		_action_node.animation = anim_name
		anim_tree.set(SHOT_PARAM, AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
		anim_tree.set(SHOT_PARAM, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	_action_started = anim_name
	_shot_node().fadeout_time = _fadeout_for(anim_name, _action_speed)
	if from_time >= 0.0:
		anim_tree.set("parameters/%s/seek_request" % SEEK_NODES[_action_slot], from_time)

func _shot_node() -> AnimationNodeOneShot:
	return (anim_tree.tree_root as AnimationNodeBlendTree).get_node("shot") as AnimationNodeOneShot

## Desvanecimiento hacia la locomoción al acabar `anim_name`. Si tiene ventana de enlace, el desvanecimiento no
## empieza antes de que se abra: así el golpe siguiente (que sale al abrirse, con el clic guardado) se funde
## desde este sin relanzar el OneShot.
func _fadeout_for(anim_name: String, speed: float) -> float:
	if not LINK_WINDOWS.has(anim_name):
		return ONE_SHOT_FADEOUT
	var lib := anim_player.get_animation_library("")
	if not lib.has_animation(anim_name):
		return ONE_SHOT_FADEOUT
	var after_link: float = (lib.get_animation(anim_name).length - float(LINK_WINDOWS[anim_name][0])) / maxf(speed, 0.01)
	return clampf(after_link - 0.03, 0.08, ONE_SHOT_FADEOUT)

## Segundos reales que le quedan a la acción de cuerpo entero en curso (0 si no hay ninguna activa).
func _action_remaining() -> float:
	if _action_started == "" or not bool(anim_tree.get("parameters/shot/active")):
		return 0.0
	var lib := anim_player.get_animation_library("")
	if not lib.has_animation(_action_started):
		return 0.0
	return (lib.get_animation(_action_started).length - _action_elapsed) / maxf(_action_speed, 0.01)

func _on_weapon_attacked(weapon_type) -> void:
	# Las animaciones de ataque (y su dash) son del modo mazmorra; en supervivencia, como antes
	if GameData.game_mode != "dungeon":
		return
	if COMBOS.has(weapon_type):
		if _skip_next_attack:
			_skip_next_attack = false
			return
		play_attack()

var _was_on_floor: bool = true

## Disparo secundario del arma sujeta (click derecho): cuerpo entero, sin ventanas de golpe.
func play_held_blast() -> void:
	var lib := anim_player.get_animation_library("") if anim_player else null
	if lib == null or not lib.has_animation(HELD_BLAST % held_weapon_type):
		return
	_fire_action(HELD_BLAST % held_weapon_type)
	_suppress_hit_window = true

## Arma activa (la llama Player al cambiar de arma). Si es un arma sujeta, adapta sus animaciones a
## este esqueleto (la primera vez), crea su modelo en el ancla y pone la capa de torso.
func set_held_weapon(weapon_type: int) -> void:
	_ensure_weapon_actions(weapon_type)
	_apply_weapon_loco(weapon_type)
	# Arma que se lleva con una postura de torso propia (la maza al hombro): misma capa, sin ancla ni IK
	if _held_layer and WeaponAnimSets.has_carry(weapon_type) and _ensure_carry(weapon_type):
		if held_weapon_type != weapon_type:
			held_weapon_type = weapon_type
			var croot := anim_tree.tree_root as AnimationNodeBlendTree
			(croot.get_node("w_hold") as AnimationNodeAnimation).animation = HELD_CARRY % weapon_type
			(croot.get_node("w_fire") as AnimationNodeAnimation).animation = HELD_CARRY % weapon_type
		held_equipped = true
		carry_only = true
		_set_spine_in_upper(false)
		return
	carry_only = false
	_set_spine_in_upper(true)
	if not _held_layer or not WeaponAnimSets.supports(weapon_type) or not _ensure_held_weapon(weapon_type):
		held_equipped = false
		return
	if held_weapon_type != weapon_type:
		held_weapon_type = weapon_type
		var root := anim_tree.tree_root as AnimationNodeBlendTree
		(root.get_node("w_hold") as AnimationNodeAnimation).animation = HELD_HOLD % weapon_type
		(root.get_node("w_fire") as AnimationNodeAnimation).animation = HELD_FIRE % weapon_type
	held_equipped = true

## Mete o saca la columna/cuello/cabeza del filtro de la capa de torso (ver SPINE_BONES).
func _set_spine_in_upper(on: bool) -> void:
	var root := anim_tree.tree_root as AnimationNodeBlendTree if is_instance_valid(anim_tree) else null
	if root == null or not root.has_node("upper"):
		return
	var upper := root.get_node("upper") as AnimationNodeBlend2
	for b in SPINE_BONES:
		upper.set_filter_path(NodePath(str(_skel_path) + ":mixamorig_" + b), on)

## ── Espadón: locomoción propia, root motion y carrera ──
const LOCO_ANIM := "loco_%s_%d"           ## clips de locomoción del arma en la biblioteca: loco_walk_17...
var _gs_loco := false                     ## ahora se anima con la locomoción del espadón
var _loco_weapon := -1
var _loco_built := {}

func held_weapon_type_is_greatsword() -> bool:
	return player != null and player.has_method("current_weapon") and player.current_weapon() == WeaponData.WeaponType.GREATSWORD

## ¿Corre ahora (no anda)? El jugador lo decide por su modo (PlayerMovementController); un jugador remoto, por la
## velocidad que llega por red.
func _gs_is_running() -> bool:
	var mc = player.get("movement_controller") if player else null
	if mc != null and mc.has_method("gs_running"):
		return mc.gs_running()
	return player != null and Vector2(player.velocity.x, player.velocity.z).length() > GS_WALK_TO_RUN

## Cualquier golpe, parada o rodada interrumpe la carrera del espadón (vuelve a andar).
func _note_combat() -> void:
	var mc = player.get("movement_controller") if player else null
	if mc != null and mc.has_method("note_combat"):
		mc.note_combat()

## Cambia reposo/andar/correr/paso lateral por los del arma (o los vuelve a poner si no tiene).
func _apply_weapon_loco(weapon_type: int) -> void:
	if not is_instance_valid(anim_tree) or anim_player == null or sm == null:
		return
	var want: bool = GameData.game_mode == "dungeon" and WeaponAnimSets.has_loco(weapon_type) and _ensure_loco(weapon_type)
	var which := weapon_type if want else -1
	if which == _loco_weapon:
		return
	_loco_weapon = which
	_gs_loco = want
	var root := anim_tree.tree_root as AnimationNodeBlendTree
	# El arma puede no traer reposo o paso lateral propios (la espada no tiene reposo): esos se quedan los del personaje
	var lib: AnimationLibrary = anim_player.get_animation_library("")
	var own_idle: bool = want and lib.has_animation(LOCO_ANIM % ["idle", weapon_type])
	var own_strafe: bool = want and lib.has_animation(LOCO_ANIM % ["strafe", weapon_type])
	for state in [STATE_IDLE, STATE_WALK, STATE_RUN]:
		if sm.has_node(state):
			var own: bool = want and (state != STATE_IDLE or own_idle)
			(sm.get_node(state) as AnimationNodeAnimation).animation = (LOCO_ANIM % [state, weapon_type]) if own else state
	if root.has_node("calm_idle"):
		(root.get_node("calm_idle") as AnimationNodeAnimation).animation = (LOCO_ANIM % ["idle", weapon_type]) if own_idle else STATE_IDLE
	if root.has_node("strafe_l"):
		var sl := root.get_node("strafe_l") as AnimationNodeAnimation
		var sr := root.get_node("strafe_r") as AnimationNodeAnimation
		sl.animation = (LOCO_ANIM % ["strafe", weapon_type]) if own_strafe else STRAFE_ANIM
		sr.animation = (LOCO_ANIM % ["strafe", weapon_type]) if own_strafe else STRAFE_ANIM
		# El clip del arma es el paso a la derecha: a la izquierda se reproduce al revés
		sl.play_mode = AnimationNodeAnimation.PLAY_MODE_BACKWARD if own_strafe else AnimationNodeAnimation.PLAY_MODE_FORWARD
		sr.play_mode = AnimationNodeAnimation.PLAY_MODE_FORWARD if own_strafe else AnimationNodeAnimation.PLAY_MODE_BACKWARD
	# Andar/correr hacia delante otra vez (si se retrocedía, _update_backpedal lo vuelve a poner al revés)
	for state in [STATE_WALK, STATE_RUN, STATE_FAST]:
		if sm.has_node(state):
			(sm.get_node(state) as AnimationNodeAnimation).play_mode = AnimationNodeAnimation.PLAY_MODE_FORWARD
	_backpedal = false

func _ensure_loco(weapon_type: int) -> bool:
	if _loco_built.has(weapon_type):
		return _loco_built[weapon_type]
	var lib: AnimationLibrary = anim_player.get_animation_library("")
	var skel := _find_first_node_of_type(model, "Skeleton3D") as Skeleton3D
	var clips: Dictionary = WeaponAnimSets.build_loco(weapon_type, skel, _skel_path) if skel else {}
	var ok := clips.has("walk") and clips.has("run")
	if ok:
		for clip in clips:
			var anim_name: String = LOCO_ANIM % [clip, weapon_type]
			if lib.has_animation(anim_name):
				lib.remove_animation(anim_name)
			lib.add_animation(anim_name, clips[clip])
	_loco_built[weapon_type] = ok
	return ok

## Root motion: el avance de la cadera del clip en curso (WeaponAnimSets.extract_root_motion) se convierte en
## velocidad del cuerpo, de modo que la animación y el personaje recorren lo mismo.
func _update_root_motion(delta: float) -> void:
	var mc = player.get("movement_controller") if player else null
	if mc == null or not ("root_motion_velocity" in mc):
		return
	mc.root_motion_velocity = Vector3.ZERO
	if _current_action_name == "" or delta <= 0.0 or not is_instance_valid(anim_tree):
		return
	if not bool(anim_tree.get("parameters/shot/active")):
		return
	var lib := anim_player.get_animation_library("") if anim_player else null
	if lib == null or not lib.has_animation(_current_action_name):
		return
	var anim := lib.get_animation(_current_action_name)
	if not anim.has_meta("root_motion"):
		return
	var rm: Dictionary = anim.get_meta("root_motion")
	var pts: PackedVector2Array = rm["pts"]
	var fps: float = float(rm["fps"])
	var t1 := clampf(_action_elapsed, 0.0, anim.length)
	var t0 := clampf(_action_elapsed - delta * _action_speed, 0.0, anim.length)
	var d := _root_at(pts, fps, t1) - _root_at(pts, fps, t0)
	var skel := _find_first_node_of_type(model, "Skeleton3D") as Skeleton3D
	if skel == null:
		return
	# Eje del esqueleto -> mundo (incluye el giro del modelo y su escala)
	var v: Vector3 = skel.global_transform.basis * Vector3(d.x, 0.0, d.y) / delta
	v.y = 0.0
	mc.root_motion_velocity = v

static func _root_at(pts: PackedVector2Array, fps: float, t: float) -> Vector2:
	if pts.is_empty():
		return Vector2.ZERO
	var f := t * fps
	var i := clampi(int(floor(f)), 0, pts.size() - 1)
	var j := mini(i + 1, pts.size() - 1)
	return pts[i].lerp(pts[j], clampf(f - float(i), 0.0, 1.0))

## Postura de transporte (WeaponAnimSets.CARRY) adaptada a este esqueleto, la primera vez.
func _ensure_carry(weapon_type: int) -> bool:
	var lib: AnimationLibrary = anim_player.get_animation_library("")
	var anim_name: String = HELD_CARRY % weapon_type
	if lib.has_animation(anim_name):
		return true
	var skel := _find_first_node_of_type(model, "Skeleton3D") as Skeleton3D
	var anim: Animation = WeaponAnimSets.build_carry(weapon_type, skel, _skel_path) if skel else null
	if anim == null:
		return false
	lib.add_animation(anim_name, anim)
	return true

## Acciones de cuerpo entero del arma (golpes de lanza, lanzamientos de polvos, poses de Joel),
## adaptadas a este esqueleto la primera vez que se equipa (solo mazmorra).
var _actions_built := {}
func _ensure_weapon_actions(weapon_type: int) -> void:
	if GameData.game_mode != "dungeon" or _actions_built.has(weapon_type) or not WeaponAnimSets.has_actions(weapon_type):
		return
	_actions_built[weapon_type] = true
	var skel := _find_first_node_of_type(model, "Skeleton3D") as Skeleton3D
	if skel == null or not anim_player:
		return
	var lib: AnimationLibrary = anim_player.get_animation_library("")
	var actions := WeaponAnimSets.build_actions(weapon_type, skel, _skel_path)
	for action_name in actions:
		if lib.has_animation(action_name):
			lib.remove_animation(action_name)
		var anim: Animation = actions[action_name]
		lib.add_animation(action_name, anim)
		if has_attack_windows(action_name):
			_inject_hit_method_tracks(anim, action_name)
	# Postura de carga del lanzamiento de la lanza: el principio de attack1, sostenido
	if actions.has(ATTACKS[0]):
		if lib.has_animation(ACTION_CHARGE):
			lib.remove_animation(ACTION_CHARGE)
		lib.add_animation(ACTION_CHARGE, _make_hold_pose(lib.get_animation(ATTACKS[0]), CHARGE_POSE_T))

func _ensure_held_weapon(weapon_type: int) -> bool:
	if _held_built.has(weapon_type):
		return _held_built[weapon_type]
	var lib: AnimationLibrary = anim_player.get_animation_library("")
	var skel := _weapon_anchor.get_parent().get_parent() as Skeleton3D
	var paths := _anchor_paths()
	var clips := WeaponAnimSets.build(weapon_type, skel, _skel_path, paths[0], paths[1], paths[2])
	var ok := clips.has("hold") and clips.has("fire")
	if ok:
		for clip in clips:
			if not clip in ["hold", "fire", "blast"]:
				continue
			var anim_name: String = {"hold": HELD_HOLD, "fire": HELD_FIRE, "blast": HELD_BLAST}[clip] % weapon_type
			if lib.has_animation(anim_name):
				lib.remove_animation(anim_name)
			lib.add_animation(anim_name, clips[clip])
		var vis = player.get("weapon_visuals")
		if vis and vis.has_method("attach_held_weapon"):
			vis.attach_held_weapon(player, _weapon_anchor, weapon_type, float(clips.get("weapon_scale", 1.0)))
	_held_built[weapon_type] = ok
	return ok

## Ancla del arma (hija del esqueleto) con los objetivos de las manos, y el IK de los dos brazos.
func _setup_weapon_anchor(skel: Skeleton3D) -> void:
	var pivot := Node3D.new()
	pivot.name = "WeaponPivot"        # HandIKModifier lo pone en el hombro derecho animado
	skel.add_child(pivot)
	_weapon_anchor = Node3D.new()
	_weapon_anchor.name = "WeaponAnchor"
	pivot.add_child(_weapon_anchor)
	var rh := Node3D.new()
	rh.name = "RHTarget"
	_weapon_anchor.add_child(rh)
	var lh := Node3D.new()
	lh.name = "LHTarget"
	_weapon_anchor.add_child(lh)
	# Polos de los codos: hacia fuera, abajo y atrás de cada hombro
	var frame := WeaponAnimSets._frame(skel)
	var h := WeaponAnimSets._height(skel)
	var poles := []
	for side in [1.0, -1.0]:
		var pole := Node3D.new()
		pole.name = "ElbowPole" + ("R" if side > 0.0 else "L")
		var shoulder := WeaponAnimSets._rest_pos(skel, "mixamorig_RightArm" if side > 0.0 else "mixamorig_LeftArm")
		pole.position = shoulder + frame.x * side * 0.45 * h - frame.y * 0.5 * h + frame.z * 0.3 * h
		skel.add_child(pole)
		poles.append(pole)
	var ik := HandIKModifier.new()
	ik.name = "HandIK"
	skel.add_child(ik)
	ik.setup(skel, rh, lh, poles[0], poles[1])
	ik.pivot = pivot
	ik.influence = 0.0
	_hand_ik = ik

## Rutas (desde la raíz de las animaciones) del ancla y de los objetivos de las manos.
func _anchor_paths() -> Array:
	if _weapon_anchor == null:
		return []
	var root_target := anim_player.get_node(anim_player.root_node)
	return [root_target.get_path_to(_weapon_anchor), root_target.get_path_to(_weapon_anchor.get_node("RHTarget")),
		root_target.get_path_to(_weapon_anchor.get_node("LHTarget"))]

## Lanzamiento de polvo según el modo (0 arcano, 1 velocidad, 2 sanador, 3 polvo a la cara). Devuelve
## {"release": s, "length": s} o {} si el personaje no tiene estas animaciones.
func play_dust_throw(mode: int) -> Dictionary:
	var lib := anim_player.get_animation_library("") if anim_player else null
	var anim_name := "dust_speed" if mode == 1 else ("dust_heal" if mode == 2 else ("dust_face" if mode == 3 else str(DUST_THROWS[_dust_index % DUST_THROWS.size()])))
	if lib == null or not lib.has_animation(anim_name):
		return {}
	if mode == 0:
		_dust_index += 1
	_fire_action(anim_name)
	_suppress_hit_window = true
	return {"release": float(DUST_RELEASE[anim_name]), "length": lib.get_animation(anim_name).length}

## Gesto de invocación `index` (0..2). Devuelve su duración en segundos, o 0 si no existe.
func play_gesture(index: int) -> float:
	var lib := anim_player.get_animation_library("") if anim_player else null
	var anim_name: String = GESTURES[clampi(index, 0, GESTURES.size() - 1)]
	if lib == null or not lib.has_animation(anim_name):
		return 0.0
	_fire_action(anim_name)
	_suppress_hit_window = true
	return lib.get_animation(anim_name).length

## Posición global de un hueso del modelo (p. ej. "mixamorig_RightHand").
func bone_global_position(bone: String) -> Vector3:
	var skel := _find_first_node_of_type(model, "Skeleton3D") as Skeleton3D
	if skel == null or skel.find_bone(bone) < 0:
		return player.global_position + Vector3(0, 1.0, 0)
	return skel.global_transform * skel.get_bone_global_pose(skel.find_bone(bone)).origin

## ¿Hay un arma sujeta equipada ahora mismo?
func has_held_layer() -> bool:
	return _held_layer and held_weapon_type >= 0 and not carry_only

## Disparo de arma de tiro a tiro (escopeta, bazuca): la animación de disparo empieza desde el
## principio y se mezcla durante toda su duración. `speed` la acelera (ráfagas).
func play_held_shot(speed: float = 1.0) -> void:
	if not has_held_layer() or not is_instance_valid(anim_tree):
		return
	net_held_shot.emit(speed)
	anim_tree.set("parameters/w_fire_scale/scale", speed)
	anim_tree.set("parameters/w_fire_seek/seek_request", 0.0)
	var lib := anim_player.get_animation_library("")
	held_fire_until = Time.get_ticks_msec() / 1000.0 + lib.get_animation(HELD_FIRE % held_weapon_type).length * 0.9 / maxf(speed, 0.1)

func _update_held_layer(delta: float) -> void:
	if not _held_layer or not is_instance_valid(anim_tree):
		return
	var k := 1.0 - exp(-12.0 * delta)
	_held_hold = lerpf(_held_hold, 1.0 if held_equipped else 0.0, k)
	_held_fire = lerpf(_held_fire, 1.0 if (held_equipped and Time.get_ticks_msec() / 1000.0 < held_fire_until) else 0.0, 1.0 - exp(-20.0 * delta))
	var move_w := 1.0
	if carry_only and player and Vector2(player.velocity.x, player.velocity.z).length() > 1.0:   # (también RemotePlayer)
		move_w = float(CARRY_MOVING_WEIGHT.get(held_weapon_type, 1.0))
	_carry_move = lerpf(_carry_move, move_w, 1.0 - exp(-8.0 * delta))
	anim_tree.set("parameters/upper/blend_amount", _held_hold * _carry_move)
	anim_tree.set("parameters/w_mix/blend_amount", _held_fire)
	# Las manos van al arma solo mientras está equipada (y no durante otras acciones de cuerpo entero)
	if _hand_ik:
		var shot_active := bool(anim_tree.get("parameters/shot/active"))
		var blasting := shot_active and _current_action_name == HELD_BLAST % held_weapon_type
		_hand_ik.influence = 0.0 if (carry_only or (shot_active and not blasting)) else _held_hold

func _process(delta: float) -> void:
	if not player or not is_instance_valid(playback): return
	_update_held_layer(delta)
	_action_elapsed += delta * _action_speed
	_update_root_motion(delta)
	_combo_timer = maxf(_combo_timer - delta, 0.0)
	if active_attack_name != "" and is_instance_valid(anim_tree):
		var shot_active = bool(anim_tree.get("parameters/shot/active"))
		if not shot_active:
			_on_anim_hit_off(active_attack_name)
	
	var is_on_floor: bool = bool(player.get("net_on_floor")) if player.get("net_on_floor") != null else player.is_on_floor()
	var just_jumped = _was_on_floor and not is_on_floor
	
	var horiz_velocity := Vector2(player.velocity.x, player.velocity.z).length()
	var moving := horiz_velocity > 1.0
	# Corre en cuanto va más rápido de lo que el clip de andar aguanta sin patinar
	var running: bool = horiz_velocity > (GS_WALK_TO_RUN if _gs_loco else WALK_TO_RUN)
	var current := playback.get_current_node()
	var fast_available: bool = sm.has_node(STATE_FAST)
	var is_fast: bool = fast_available and player.get("is_riva_fast") == true   # RemotePlayer no tiene la propiedad (bool(null) falla)
	if moving:
		_update_backpedal(Vector3(player.velocity.x, 0.0, player.velocity.z))
	_update_strafe(delta, Vector3(player.velocity.x, 0.0, player.velocity.z), moving and is_on_floor)
	_update_gait_scale(horiz_velocity, is_on_floor)

	if not is_on_floor:
		if (current != STATE_JUMP or just_jumped) and sm.has_node(STATE_JUMP):
			if just_jumped:
				playback.start(STATE_JUMP)
			else:
				playback.travel(STATE_JUMP)
				
			var char_id = _char_id()
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

## Velocidad (m/s) que representa cada clip del personaje a velocidad 1, con la zancada alargada
## (WeaponAnimSets.widen_stride): retroceso del pie apoyado, medido con tools/measure_foot_slip.tscn. La
## animación se acelera/frena para casar con la velocidad real, con un tope bajo: un ritmo de pasos alto se ve
## "embalado".
const GAIT_SPEED := {"walk": 1.64, "run": 4.5, "fast": 4.4, "strafe": 1.5}
const WALK_TO_RUN := 2.4
## Cuánto se calman los brazos (0 = los del clip, 1 = los del reposo) en cada estado de locomoción
const ARM_CALM := {"walk": 0.3, "run": 0.55, "fast": 0.55}
const ARM_BONES := ["LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand", "RightShoulder", "RightArm", "RightForeArm", "RightHand"]
var _arm_calm := 0.0
const GAIT_MAX_SCALE := 1.2

func _gait_scale(speed: float, clip: String) -> float:
	if _gs_loco:
		var gait: Dictionary = WEAPON_GAIT_SPEED.get(_loco_weapon, GS_GAIT_SPEED)
		return clampf(speed / float(gait.get(clip, GAIT_SPEED[clip])), 0.7, float(GS_GAIT_MAX_SCALE.get(clip, 1.5)))
	return clampf(speed / float(GAIT_SPEED[clip]), 0.7, GAIT_MAX_SCALE)

func _update_gait_scale(speed: float, on_floor: bool) -> void:
	var cur := String(playback.get_current_node())
	var s := 1.0
	if on_floor and GAIT_SPEED.has(cur) and (not _gs_loco or (WEAPON_GAIT_SPEED.get(_loco_weapon, GS_GAIT_SPEED) as Dictionary).has(cur)):
		s = _gait_scale(speed, cur)
	anim_tree.set("parameters/loco_scale/scale", s)
	# Los brazos del espadón van como en su clip (agarran la empuñadura): sin mezclar con el reposo
	var want: float = ARM_CALM.get(cur, 0.0) if (on_floor and not _gs_loco) else 0.0
	_arm_calm = lerpf(_arm_calm, want, 0.15)
	anim_tree.set("parameters/arms_calm/blend_amount", _arm_calm)

var _has_strafe := false
var _strafe_w := 0.0
var _strafe_side := 0.0

## Peso del paso lateral según cuánto del movimiento va de lado respecto a donde mira el cuerpo.
func _update_strafe(delta: float, vel: Vector3, active: bool) -> void:
	if not _has_strafe:
		return
	var want := 0.0
	var side := _strafe_side
	var mesh_node = player.get("mesh")
	if active and mesh_node is Node3D:
		var f: Vector3 = -(mesh_node as Node3D).global_transform.basis.z
		f.y = 0.0
		if f.length_squared() > 0.0001:
			f = f.normalized()
			var right := Vector3(-f.z, 0.0, f.x)
			var s := vel.normalized().dot(right)
			want = clampf((absf(s) - 0.35) / 0.45, 0.0, 1.0)
			if want > 0.0:
				side = 1.0 if s > 0.0 else 0.0
	var k := 1.0 - exp(-10.0 * delta)
	_strafe_w = lerpf(_strafe_w, want, k)
	_strafe_side = lerpf(_strafe_side, side, 1.0 - exp(-14.0 * delta))
	anim_tree.set("parameters/legs/blend_amount", _strafe_w)
	anim_tree.set("parameters/strafe_lr/blend_amount", _strafe_side)
	anim_tree.set("parameters/strafe_scale/scale", _gait_scale(vel.length(), "strafe"))

## Del clip de paso lateral solo se usan los giros de las piernas (los brazos del clip no gustan).
func _keep_leg_tracks(anim: Animation) -> void:
	if anim == null:
		return
	for i in range(anim.get_track_count() - 1, -1, -1):
		var bone := String(anim.track_get_path(i).get_concatenated_subnames())
		if not (bone.trim_prefix("mixamorig_") in LEG_BONES) or anim.track_get_type(i) != Animation.TYPE_ROTATION_3D:
			anim.remove_track(i)

## El cuerpo mira siempre a la mira (PlayerMovementController): al retroceder, los clips de andar/correr se
## reproducen al revés para que los pies no patinen hacia delante. Con histéresis para no parpadear al
## moverse de lado.
var _backpedal := false

func _update_backpedal(vel: Vector3) -> void:
	var mesh_node = player.get("mesh")
	if not (mesh_node is Node3D):
		return
	var facing: Vector3 = -(mesh_node as Node3D).global_transform.basis.z
	facing.y = 0.0
	if facing.length_squared() < 0.0001:
		return
	var d := vel.normalized().dot(facing.normalized())
	var want := d < -0.25 if not _backpedal else d < 0.05
	if want == _backpedal:
		return
	_backpedal = want
	var mode := AnimationNodeAnimation.PLAY_MODE_BACKWARD if want else AnimationNodeAnimation.PLAY_MODE_FORWARD
	for state in [STATE_WALK, STATE_RUN, STATE_FAST]:
		if sm.has_node(state):
			var n := sm.get_node(state) as AnimationNodeAnimation
			if n:
				n.play_mode = mode

func _add_transition(sm: AnimationNodeStateMachine, from: String, to: String, xfade: float) -> void:
	for i in range(sm.get_transition_count()):
		if sm.get_transition_from(i) == from and sm.get_transition_to(i) == to:
			return
	var trans := AnimationNodeStateMachineTransition.new()
	trans.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
	trans.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
	trans.xfade_time = xfade
	sm.add_transition(from, to, trans)

## Personaje de este controlador: el de la partida, o el de un jugador remoto (RemotePlayer.net_char_id).
func _char_id() -> String:
	var forced: Variant = player.get("net_char_id") if player else null
	if forced != null and str(forced) != "":
		return str(forced)
	return GameData.get_selected().get("id", "mikeura")

func _own_animation_library() -> void:
	var shared := anim_player.get_animation_library("")
	var own := AnimationLibrary.new()
	for n in shared.get_animation_list():
		own.add_animation(n, shared.get_animation(n).duplicate(true))
	anim_player.remove_animation_library("")
	anim_player.add_animation_library("", own)

func _fit_model() -> void:
	if not model: return
	var model_mesh = CharacterLookApplier.body_mesh(model)
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
	# El personaje personalizable usa el esqueleto de Riva con las articulaciones movidas a las del cuerpo
	# nuevo (tools/blender_riva_human.py): sus clips viejos solo aportan giros y la altura de la cadera; la
	# posición de los demás huesos sale del reposo del modelo.
	var keep_rest := _char_id() == CharacterLook.CHAR_ID
	for i in range(anim.get_track_count() - 1, -1, -1):
		var path := anim.track_get_path(i)
		var bone := path.get_concatenated_subnames()
		if bone == "":
			continue
		if keep_rest and bone != "mixamorig_Hips" and anim.track_get_type(i) in [Animation.TYPE_POSITION_3D, Animation.TYPE_SCALE_3D]:
			anim.remove_track(i)
			continue
		anim.track_set_path(i, NodePath(str(_skel_path) + ":" + bone))

func _apply_texture_to_meshes(node: Node, tex: Texture2D) -> void:
	if node is MeshInstance3D:
		var mat = StandardMaterial3D.new()
		mat.albedo_texture = tex
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		node.material_override = mat
	for child in node.get_children():
		_apply_texture_to_meshes(child, tex)
