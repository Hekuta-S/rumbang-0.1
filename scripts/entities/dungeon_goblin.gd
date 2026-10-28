class_name DungeonGoblin
extends CharacterBody3D

## Goblin cuerpo a cuerpo del modo mazmorra (un nodo por enemigo, con animaciones reales).
##
## Estados: IDLE → APPROACH → WINDUP (telegrafía) → ATTACK (ventana de golpe) → RECOVER
## (vulnerable) y HURT / STAGGER al recibir golpes; DEAD al morir.
## Tres ataques (ATTACKS), elegidos por distancia, cada uno con su forma de evitarlo:
##  - swipe (zarpazo): pegado al jugador; anticipación corta y cono ancho y corto → alejarse.
##  - slam (porrazo a dos puños): media distancia; puños en alto y cuña larga → salir de la cuña.
##  - leap (embestida): de lejos; se agacha y se lanza en línea recta (franja en el suelo) →
##    apartarse de lado. Si choca contra una pared durante la embestida, se aturde.
## Todos son legibles y evitables: pose + destello rojo + aviso en el suelo que se rellena +
## gruñido. La orientación se fija antes de golpear y el daño solo se aplica dentro de la
## ventana del ataque, una vez, si el jugador está en la zona y sin pared en medio.
##  - Comparte el contrato de EnemyData: está en EnemyRegistry (lo encuentran MeleeHitbox,
##    EnemyQuery, el apuntado suave y la lanza lanzada), take_damage(amount, dir),
##    apply_knockback(v), hit_radius / hit_height, y avisa a HitFeedback.
## Los valores de combate son iniciales: se ajustan jugando (Fase D de AUDITORIA_COMBATE_MAZMORRAS.md).

signal died(goblin: DungeonGoblin)

enum State { IDLE, APPROACH, WINDUP, ATTACK, RECOVER, HURT, STAGGER, DEAD }

const MODEL_DIR := "res://assets/models/entities/enemigos/goblins/"
const CLIPS := {
	"walk": MODEL_DIR + "caminar_normal_goblin.fbx",
	"swipe_windup": MODEL_DIR + "dungeon/goblin_swipe_windup.fbx",
	"swipe": MODEL_DIR + "dungeon/goblin_swipe.fbx",
	"leap_windup": MODEL_DIR + "dungeon/goblin_leap_windup.fbx",
	"leap": MODEL_DIR + "dungeon/goblin_leap.fbx",
	"windup": MODEL_DIR + "dungeon/goblin_windup.fbx",
	"attack": MODEL_DIR + "dungeon/goblin_attack.fbx",
	"recover": MODEL_DIR + "dungeon/goblin_recover.fbx",
	"hurt": MODEL_DIR + "dungeon/goblin_hurt.fbx",
	"death": MODEL_DIR + "dungeon/goblin_death.fbx",
}
const IDLE_MODEL := MODEL_DIR + "idle_normal_goblin.fbx"
const TEXTURE := "res://assets/textures/enemigos/texture_normal_goblin.png"
const TELEGRAPH_SHADER: Shader = preload("res://assets/shaders/enemy_telegraph.gdshader")
const FloatingDamage = preload("res://scripts/objects/floating_damage.gd")
const MODEL_HEIGHT := 1.35

# ── Combate (valores iniciales) ──
const HP_MULT := 2.0                  ## vida = vida del goblin normal de las hordas × HP_MULT
const DETECT_RADIUS := 16.0
## Repertorio. Distancias en m, tiempos en s (ventana = segundos del clip de ataque).
##  range: [mín, máx] de distancia al jugador para elegirlo · shape: "cone" | "line"
##  reach / half_angle: zona de golpe (cono) · width: ancho de la franja (línea)
##  windup / track: anticipación y hasta cuándo sigue girando hacia el jugador
##  lunge: impulso al golpear · dash: velocidad sostenida durante la ventana (embestida)
const ATTACKS := {
	"swipe": {"range": [0.0, 1.6], "weight": 3, "cooldown": 0.0, "shape": "cone", "reach": 1.9, "half_angle": 70.0,
		"windup_clip": "swipe_windup", "attack_clip": "swipe", "windup": 0.4, "track": 0.28,
		"attack_time": 0.33, "window": Vector2(0.04, 0.16), "lunge": 4.0, "dash": 0.0,
		"damage": 2.0, "recover": 0.5},
	"slam": {"range": [0.0, 2.2], "weight": 2, "cooldown": 0.0, "shape": "cone", "reach": 2.6, "half_angle": 55.0,
		"windup_clip": "windup", "attack_clip": "attack", "windup": 0.75, "track": 0.5,
		"attack_time": 0.43, "window": Vector2(0.08, 0.22), "lunge": 8.0, "dash": 0.0,
		"damage": 3.0, "recover": 0.9},
	"leap": {"range": [4.0, 8.0], "weight": 1, "cooldown": 5.0, "shape": "line", "reach": 7.0, "width": 1.6,
		"windup_clip": "leap_windup", "attack_clip": "leap", "windup": 0.9, "track": 0.65,
		"attack_time": 0.5, "window": Vector2(0.0, 0.45), "lunge": 0.0, "dash": 14.0,
		"damage": 4.0, "recover": 1.3},
}
const LEAP_CONTACT := 1.1             ## radio de contacto de la embestida (m)
const LEAP_WALL_STUN := 1.6           ## aturdimiento si la embestida choca con una pared
const HURT_TIME := 0.35
const STAGGER_TIME := 1.3
const STAGGER_DAMAGE := 18.0          ## un golpe así (o empuje ≥ STAGGER_KNOCK) aturde
const STAGGER_KNOCK := 10.0
const WINDUP_POISE := 12.0            ## daño acumulado que interrumpe la anticipación
const TURN_SPEED := 9.0
const WHISKER := 1.4                  ## alcance de los rayos que esquivan obstáculos (m)
const STUCK_TIME := 0.35              ## sin avanzar este tiempo → paso lateral para soltarse
const GRAVITY := 22.0

var hit_radius := 0.5
var hit_height := 1.4
# Campos que rellena EnemyTypeFlyweight.apply_to (estado intrínseco compartido)
var max_hp := 40.0
var hp := 40.0
var speed := 4.5
var attack_range := 1.0
var damage := 0.5
var gold_reward := 8
var base_color := Color.WHITE

var state: State = State.IDLE
var player: CharacterBody3D
var map: DungeonMap                   ## para navegar (campo de flujo); opcional
var _avoid_side := 1.0
var _stuck_t := 0.0                   # tiempo seguido avanzando casi nada en APPROACH
var _unstick_t := 0.0
var _last_pos := Vector3.ZERO
var _state_t := 0.0
var _hit_done := false
var _atk_name := "slam"
var _atk: Dictionary = ATTACKS["slam"]
var _atk_ready := {}                  # nombre -> instante (s) en que vuelve a estar disponible
var _clock := 0.0
var _poise := 0.0
var _knock := Vector3.ZERO
var _facing := Vector3.FORWARD
var _model: Node3D
var _anim: AnimationPlayer
var _meshes: Array[MeshInstance3D] = []
var _flash_mat: ShaderMaterial
var _flash := 0.0
var _flash_color := Color.WHITE
var _telegraph: MeshInstance3D
var _last_hurt_sfx := 0

func _ready() -> void:
	EnemyTypeFlyweightFactory.get_flyweight(EnemyData.EnemyType.NORMAL_GOBLIN).apply_to(self)
	max_hp *= HP_MULT
	hp = max_hp
	collision_layer = 4          # capa de enemigos
	collision_mask = 1 | 2       # mundo (paredes, props, rompibles) y jugador
	add_to_group("enemies")
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = hit_radius
	cap.height = hit_height
	col.shape = cap
	col.position.y = hit_height * 0.5
	add_child(col)
	_build_model()
	_build_telegraph()
	EnemyRegistry.register(self)
	player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	_facing = -global_transform.basis.z
	_set_state(State.IDLE)

# ───────────────────────────── Modelo y animaciones ─────────────────────────────

## Nodo del modelo (para efectos como SpawnDissolve, que no deben tocar la telegrafía).
func get_model() -> Node3D:
	return _model

func _build_model() -> void:
	_model = (load(IDLE_MODEL) as PackedScene).instantiate() as Node3D
	add_child(_model)
	var mi := _model.find_children("*", "MeshInstance3D", true, false)
	for m in mi:
		_meshes.append(m as MeshInstance3D)
	_fit_model()
	var tex := load(TEXTURE) as Texture2D
	_flash_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = "shader_type spatial;\nrender_mode unshaded, blend_add, depth_draw_never;\nuniform vec4 flash_color : source_color = vec4(0.0);\nvoid fragment() { ALBEDO = flash_color.rgb * flash_color.a; }"
	_flash_mat.shader = sh
	for m in _meshes:
		if tex:
			var mat := StandardMaterial3D.new()
			mat.albedo_texture = tex
			m.material_override = mat
		m.material_overlay = _flash_mat
	_anim = _model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var lib := _anim.get_animation_library("")
	var first: String = lib.get_animation_list()[0]
	var idle := lib.get_animation(first)
	lib.remove_animation(first)
	idle.loop_mode = Animation.LOOP_LINEAR
	lib.add_animation("idle", idle)
	var skel := _model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var skel_path := _anim.get_node(_anim.root_node).get_path_to(skel)
	for clip in CLIPS:
		var scene := load(CLIPS[clip]) as PackedScene
		if scene == null:
			continue
		var inst := scene.instantiate()
		var ap := inst.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		var a: Animation = ap.get_animation(ap.get_animation_list()[0]).duplicate(true)
		inst.free()
		# Los FBX exportados desde Blender cuelgan el esqueleto de "<Armature>/Skeleton3D"
		for i in a.get_track_count():
			var bone := a.track_get_path(i).get_concatenated_subnames()
			if bone != "":
				a.track_set_path(i, NodePath(str(skel_path) + ":" + bone))
		a.loop_mode = Animation.LOOP_LINEAR if clip == "walk" else Animation.LOOP_NONE
		lib.add_animation(clip, a)

func _fit_model() -> void:
	if _meshes.is_empty() or _meshes[0].mesh == null:
		return
	var aabb := _meshes[0].mesh.get_aabb()
	var s := MODEL_HEIGHT / maxf(aabb.size.y, 0.0001)
	_model.scale = Vector3.ONE * s
	_model.rotation.y = PI
	_model.position.y = -aabb.position.y * s

## Ajusta la forma del aviso en el suelo al ataque elegido.
func _shape_telegraph(a: Dictionary) -> void:
	var plane := _telegraph.mesh as PlaneMesh
	var mat := _telegraph.material_override as ShaderMaterial
	var reach: float = a["reach"]
	if a["shape"] == "line":
		plane.size = Vector2(float(a["width"]), reach)
		mat.set_shader_parameter("shape", 1)
	else:
		var half := deg_to_rad(float(a["half_angle"]))
		plane.size = Vector2(sin(minf(half, PI * 0.5)) * reach * 2.0, reach)
		mat.set_shader_parameter("shape", 0)
		mat.set_shader_parameter("half_angle", half)
	_telegraph.position = Vector3(0.0, 0.05, -reach * 0.5)
	mat.set_shader_parameter("progress", 0.0)

## Ataque disponible para esta distancia (sorteo ponderado), o "" si ninguno.
func _choose_attack(dist: float) -> String:
	var options: Array = []
	var total := 0
	for n in ATTACKS:
		var a: Dictionary = ATTACKS[n]
		if dist < float(a["range"][0]) or dist > float(a["range"][1]):
			continue
		if _clock < float(_atk_ready.get(n, 0.0)):
			continue
		options.append(n)
		total += int(a["weight"])
	if options.is_empty():
		return ""
	var roll := randi() % total
	for n in options:
		roll -= int(ATTACKS[n]["weight"])
		if roll < 0:
			return n
	return options[0]

func _start_attack(n: String) -> void:
	_atk_name = n
	_atk = ATTACKS[n]
	_atk_ready[n] = _clock + float(_atk["cooldown"])
	_set_state(State.WINDUP)

func _play(clip: String, blend: float = 0.1) -> void:
	if _anim and _anim.has_animation(clip):
		_anim.play(clip, blend)

func _build_telegraph() -> void:
	_telegraph = MeshInstance3D.new()
	_telegraph.mesh = PlaneMesh.new()
	var m := ShaderMaterial.new()
	m.shader = TELEGRAPH_SHADER
	_telegraph.material_override = m
	_telegraph.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_telegraph.visible = false
	add_child(_telegraph)

# ───────────────────────────── Estados ─────────────────────────────

func _set_state(s: State) -> void:
	state = s
	_state_t = 0.0
	_telegraph.visible = false
	match s:
		State.IDLE: _play("idle", 0.2)
		State.APPROACH: _play("walk", 0.15)
		State.WINDUP:
			_poise = 0.0
			_play(_atk["windup_clip"], 0.08)
			_shape_telegraph(_atk)
			_telegraph.visible = true
			AudioManager.play_at("goblin_warn", global_position, 0.0, randf_range(0.9, 1.1))
		State.ATTACK:
			_hit_done = false
			_play(_atk["attack_clip"], 0.02)
			_knock += _facing * float(_atk["lunge"])
			AudioManager.play_at("goblin_swing", global_position, 0.0, randf_range(0.95, 1.05))
		State.RECOVER: _play("recover", 0.05)
		State.HURT: _play("hurt", 0.03)
		State.STAGGER: _play("hurt", 0.03)
		State.DEAD: _play("death", 0.05)

func _physics_process(delta: float) -> void:
	_state_t += delta
	_clock += delta
	_update_flash(delta)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = -1.0
	var move := Vector3.ZERO
	var to_p := Vector3.ZERO
	var dist := INF
	if is_instance_valid(player):
		to_p = player.global_position - global_position
		to_p.y = 0.0
		dist = to_p.length()

	match state:
		State.IDLE:
			if dist <= DETECT_RADIUS and _sees_player():
				_set_state(State.APPROACH)
		State.APPROACH:
			var sees := _sees_player()
			# De cerca elige entre zarpazo y porrazo; de lejos (con línea de visión), la embestida
			var pick := ""
			if dist <= 2.2 or (dist >= 4.0 and sees):
				pick = _choose_attack(dist)
			if pick != "":
				_turn_towards(to_p, delta)
				_start_attack(pick)
			else:
				var dir := _nav_dir(to_p, sees)
				# Atascado contra algo: paso lateral corto hacia el lado que rodeaba
				if _unstick_t > 0.0:
					_unstick_t -= delta
					dir = _avoid(_facing.cross(Vector3.UP) * _avoid_side)
				elif _stuck_t > STUCK_TIME:
					_stuck_t = 0.0
					# Trabado contra un barril o una caja: lo rompe de un manotazo
					if not _smash_blocking_prop():
						_unstick_t = 0.45
						_avoid_side = -_avoid_side
						# Que el camino deje de pasar por donde se atascó
						if map and not sees:
							var path := map.flow_path(global_position, player.global_position, 1)
							if not path.is_empty():
								map.penalize_cell(path[0])
				_turn_towards(to_p if sees and dist < 4.0 else dir, delta)
				move = dir * speed + EnemyRegistry.separation_push(self, 1.2) * 2.0
		State.WINDUP:
			var windup: float = _atk["windup"]
			if _state_t <= float(_atk["track"]):
				_turn_towards(to_p, delta)
			var mat := _telegraph.material_override as ShaderMaterial
			mat.set_shader_parameter("progress", clampf(_state_t / windup, 0.0, 1.0))
			# Destello rojo creciente: ¡va a pegar!
			_flash_color = Color(1.0, 0.1, 0.05)
			_flash = maxf(_flash, 0.15 + 0.45 * (_state_t / windup) * (0.6 + 0.4 * sin(_state_t * 30.0)))
			if _state_t >= windup:
				_set_state(State.ATTACK)
		State.ATTACK:
			var win: Vector2 = _atk["window"]
			var in_window := _state_t >= win.x and _state_t <= win.y
			if float(_atk["dash"]) > 0.0 and in_window:
				move = _facing * float(_atk["dash"])
			if not _hit_done and in_window:
				_try_hit_player()
			if _atk_name == "leap" and in_window and _state_t > 0.05 and is_on_wall():
				# La embestida se estrella contra la pared: queda aturdido
				AudioManager.play_at("impact_blunt", global_position, 0.0, 0.6)
				_set_state(State.STAGGER)
				_state_t = STAGGER_TIME - LEAP_WALL_STUN
			elif _state_t >= float(_atk["attack_time"]):
				_set_state(State.RECOVER)
		State.RECOVER:
			if _state_t >= float(_atk["recover"]):
				_set_state(State.APPROACH)
		State.HURT:
			if _state_t >= HURT_TIME:
				_set_state(State.APPROACH)
		State.STAGGER:
			# Aturdido: tambaleo
			_model.rotation.z = sin(_state_t * 14.0) * 0.12 * (1.0 - _state_t / STAGGER_TIME)
			if _state_t >= STAGGER_TIME:
				_model.rotation.z = 0.0
				_set_state(State.APPROACH)
		State.DEAD:
			pass

	_knock = _knock.move_toward(Vector3.ZERO, 30.0 * delta)
	velocity.x = move.x + _knock.x
	velocity.z = move.z + _knock.z
	move_and_slide()
	rotation.y = atan2(-_facing.x, -_facing.z)
	var moved := Vector2(global_position.x - _last_pos.x, global_position.z - _last_pos.z).length()
	_last_pos = global_position
	if state == State.APPROACH and move.length_squared() > 1.0 and moved < speed * delta * 0.25:
		_stuck_t += delta
	else:
		_stuck_t = 0.0

func _turn_towards(dir: Vector3, delta: float) -> void:
	if dir.length_squared() < 0.0001:
		return
	# Por ángulo (slerp no gira entre vectores opuestos: el goblin se quedaba de espaldas)
	var cur := atan2(_facing.x, _facing.z)
	var yaw := lerp_angle(cur, atan2(dir.x, dir.z), minf(TURN_SPEED * delta, 1.0))
	_facing = Vector3(sin(yaw), 0.0, cos(yaw))

## Dirección de avance: si ve al jugador, en línea recta con "bigotes" que esquivan props;
## si no, sigue el campo de flujo del mapa (rodea paredes, túneles y props).
func _nav_dir(to_p: Vector3, sees: bool) -> Vector3:
	# El rayo de visión puede colarse por una esquina o junta de pared: la línea recta
	# también tiene que ser transitable en la rejilla
	if map and (not sees or not map.segment_walkable(global_position, player.global_position, hit_radius)):
		return _path_dir()   # ya comprueba que el cuerpo cabe hasta el punto elegido
	return _avoid(to_p.normalized())

## Apunta al punto más lejano del camino por el que cabe el cuerpo en línea recta.
func _path_dir() -> Vector3:
	var path := map.flow_path(global_position, player.global_position)
	if path.is_empty():
		var d := player.global_position - global_position
		return Vector3(d.x, 0.0, d.z).normalized()
	for i in range(path.size() - 1, -1, -1):
		if _body_fits(path[i]):
			var d := path[i] - global_position
			return Vector3(d.x, 0.0, d.z).normalized()
	# Un prop tapa el camino (el campo de flujo solo conoce las paredes): rodearlo
	var d0 := path[0] - global_position
	return _avoid(Vector3(d0.x, 0.0, d0.z).normalized())

## true si el cuerpo va en línea recta hasta `p`: paredes con la rejilla del mapa (exacto) y
## props con un rayo central.
func _body_fits(p: Vector3) -> bool:
	if not map.segment_walkable(global_position, p, hit_radius + 0.1):
		return false
	var a := global_position + Vector3(0, 0.5, 0)
	return _clear_line(a, Vector3(p.x, a.y, p.z))

func _avoid(dir: Vector3) -> Vector3:
	var origin := global_position + Vector3(0, 0.5, 0)
	if _clear_line(origin, origin + dir * WHISKER):
		return dir
	# Prueba primero hacia el lado que ya rodeaba, para no oscilar
	for ang in [30.0, 60.0, 90.0, 120.0]:
		for side in [_avoid_side, -_avoid_side]:
			var d := dir.rotated(Vector3.UP, deg_to_rad(ang * side))
			if _clear_line(origin, origin + d * WHISKER):
				_avoid_side = side
				return d
	return dir

func _smash_blocking_prop() -> bool:
	for i in get_slide_collision_count():
		var prop := get_slide_collision(i).get_collider() as DestructibleProp
		if prop:
			var dir := prop.global_position - global_position
			prop.take_damage(999.0, Vector3(dir.x, 0.0, dir.z).normalized())
			AudioManager.play_at("goblin_swing", global_position, 0.0, randf_range(0.95, 1.05))
			return true
	return false

func _sees_player() -> bool:
	return _clear_line(global_position + Vector3(0, 1.0, 0), player.global_position + Vector3(0, 1.0, 0))

## true si no hay paredes ni props (capa 1) entre a y b.
func _clear_line(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b, 1)
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func _try_hit_player() -> void:
	if not is_instance_valid(player):
		return
	var to_p := player.global_position - global_position
	if absf(to_p.y) > 1.6:
		return
	to_p.y = 0.0
	if _atk["shape"] == "line":
		# Embestida: contacto con el cuerpo del goblin mientras vuela
		if to_p.length() > LEAP_CONTACT + 0.45:
			return
	else:
		var reach: float = float(_atk["reach"]) + 0.45  # + radio del jugador
		if to_p.length() > reach:
			return
		if to_p.length() > 0.3 and rad_to_deg(_facing.angle_to(to_p.normalized())) > float(_atk["half_angle"]):
			return
	if not _clear_line(global_position + Vector3(0, 0.8, 0), player.global_position + Vector3(0, 0.8, 0)):
		return
	_hit_done = true
	var dmg: float = _atk["damage"]
	player.take_damage(dmg, to_p.normalized())
	AudioManager.play_at("impact_blunt", player.global_position, -2.0, 0.8)
	var root := get_tree().current_scene
	if root:
		FloatingDamage.spawn(root, player.global_position + Vector3(0, 2.0, 0), dmg, Color(1.0, 0.2, 0.2))

# ───────────────────────────── Recibir daño ─────────────────────────────

func take_damage(amount: float, knockback_dir: Vector3 = Vector3.ZERO) -> void:
	if state == State.DEAD:
		return
	hp -= amount
	_flash_color = Color(1, 1, 1)
	_flash = 1.0
	var root := get_tree().current_scene
	if root:
		FloatingDamage.spawn(root, global_position + Vector3(0, 1.8, 0), amount, Color(1.0, 0.88, 0.22), amount >= STAGGER_DAMAGE)
	var killed := hp <= 0.0
	var push := knockback_dir
	push.y = 0.0
	if push.length_squared() > 0.0001:
		_knock = push.normalized() * clampf(push.length(), 3.0, 20.0)
	HitFeedback.on_enemy_hit(self, amount, knockback_dir, killed)
	if killed:
		_die()
		return
	var now := Time.get_ticks_msec()
	if now - _last_hurt_sfx > 120:
		_last_hurt_sfx = now
		AudioManager.play_at("goblin_hurt", global_position, -4.0, randf_range(0.9, 1.15))
	var heavy := amount >= STAGGER_DAMAGE or knockback_dir.length() >= STAGGER_KNOCK
	match state:
		State.ATTACK:
			pass                                   # el golpe ya salió: no se interrumpe
		State.WINDUP:
			_poise += amount
			if heavy:
				_set_state(State.STAGGER)
			elif _poise >= WINDUP_POISE:
				_set_state(State.HURT)
		_:
			_set_state(State.STAGGER if heavy else State.HURT)

func apply_knockback(v: Vector3) -> void:
	if state == State.DEAD:
		return
	v.y = 0.0
	_knock = (_knock + v).limit_length(24.0)

func _die() -> void:
	_set_state(State.DEAD)
	collision_layer = 0
	remove_from_group("enemies")
	EnemyRegistry.unregister(self)
	AudioManager.play_at("goblin_die", global_position, 0.0, randf_range(0.95, 1.05))
	died.emit(self)
	var tw := create_tween()
	tw.tween_interval(1.6)
	tw.tween_property(_model, "position:y", _model.position.y - 0.6, 0.8).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_model, "scale", _model.scale * 0.85, 0.8)
	tw.tween_callback(queue_free)

func _update_flash(delta: float) -> void:
	_flash = move_toward(_flash, 0.0, delta * 5.0)
	_flash_mat.set_shader_parameter("flash_color", Color(_flash_color.r, _flash_color.g, _flash_color.b, _flash))

func is_dead() -> bool:
	return state == State.DEAD
