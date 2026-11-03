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
##
## Color del aviso según cómo se evita (como los anillos de God of War, ver guard_kind):
##  ámbar = cuerpo a cuerpo, se para con un parry · rojo = área, solo se esquiva ·
##  azul = proyectil, la guardia reduce el daño.
## Barra de aturdimiento: se llena con golpes (más con los pesados, al castigar la recuperación
## y con los parry) y se vacía sola si se le deja en paz. Llena → STUNNED: queda indefenso unos
## segundos y se le puede rematar (PlayerFinisherController → receive_finisher).

signal died(goblin: DungeonGoblin)

## STUNNED va al final: el número de cada estado viaja en las instantáneas de red (NetWorld)
enum State { IDLE, APPROACH, WINDUP, ATTACK, RECOVER, HURT, STAGGER, DEAD, STUNNED }

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
		"damage": 4.0, "recover": 1.3, "wall_stun": 1.6},
}
const LEAP_CONTACT := 1.1             ## radio de contacto de la embestida (m)
const HURT_TIME := 0.35
const STAGGER_TIME := 1.3
const STAGGER_DAMAGE := 18.0          ## un golpe así (o empuje ≥ STAGGER_KNOCK) aturde
const STAGGER_KNOCK := 10.0
const ARMOR_DECAY := 6.0              ## daño acumulado contra la armadura que se olvida por segundo
const WINDUP_POISE := 12.0            ## daño acumulado que interrumpe la anticipación
const TURN_SPEED := 9.0
const WHISKER := 1.4                  ## alcance de los rayos que esquivan obstáculos (m)
const STUCK_TIME := 0.35              ## sin avanzar este tiempo → paso lateral para soltarse
const GRAVITY := 22.0

const GUARD_PARRY := Color(1.0, 0.72, 0.12)
const GUARD_DODGE := Color(1.0, 0.1, 0.05)
const GUARD_RANGED := Color(0.35, 0.65, 1.0)

# ── Aturdimiento y remate ──
const STUN_HIT_MULT := 0.5            ## un golpe normal llena la barra con la mitad de su daño
const STUN_HEAVY_MULT := 1.0          ## un golpe pesado (los que aturden), con todo su daño
const STUN_PUNISH_MULT := 1.5         ## × extra si está en RECOVER (castigar el ataque fallado)
const STUN_DECAY_DELAY := 2.5         ## s sin recibir golpes antes de que la barra se vacíe
const STUN_DECAY := 0.2               ## fracción de la barra que se vacía por segundo
const STUNNED_TIME := 3.2
const STUN_COLOR := Color(1.0, 0.85, 0.35)
const STUN_BAR_TINT := Color(1.0, 0.78, 0.25)
const HP_BAR_TINT := Color(0.9, 0.16, 0.12)
const STUN_BAR_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never;
instance uniform float fill = 0.0;
instance uniform float pulse = 0.0;
instance uniform vec3 tint = vec3(1.0, 0.78, 0.25);
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	float edge = step(UV.x, 0.025) + step(0.975, UV.x) + step(UV.y, 0.14) + step(0.86, UV.y);
	vec3 bar = mix(tint, vec3(1.0, 1.0, 0.85), pulse);
	vec3 c = UV.x < fill ? bar : vec3(0.08, 0.06, 0.04);
	ALBEDO = mix(c, vec3(0.0), clamp(edge, 0.0, 1.0));
	ALPHA = 0.9;
}
"""

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

# ── Configuración por tipo (las subclases, como DungeonBrute, la cambian en _init) ──
var attacks: Dictionary = ATTACKS
var clips: Dictionary = CLIPS
var clip_fallbacks: Dictionary = {}   ## clip -> ruta alternativa si el FBX propio aún no existe
var idle_model := IDLE_MODEL
var texture := TEXTURE                ## "" = sin textura: se quedan los materiales del FBX
var model_height := MODEL_HEIGHT
var enemy_type: int = EnemyData.EnemyType.NORMAL_GOBLIN
var hp_mult := HP_MULT
var speed_mult := 1.0
var hurt_time := HURT_TIME
var stagger_time := STAGGER_TIME
var stagger_damage := STAGGER_DAMAGE
var windup_poise := WINDUP_POISE
## Armadura: fuera de la anticipación, los golpes por debajo de este daño no lo interrumpen;
## se acumulan y, al llegar a `armor_break`, se aturde (0 = sin armadura)
var armor := 0.0
var armor_break := 0.0
var sfx_pitch := 1.0
var knock_scale := 1.0               ## cuánto le empujan los golpes (los pesados, menos)
var stagger_knock := STAGGER_KNOCK
var _armor_dmg := 0.0
var telegraph_color := Color(1.0, 0.12, 0.05)
var warn_sfx := "goblin_warn"         ## al empezar la anticipación
var swing_sfx := "goblin_swing"       ## al empezar el golpe
var hurt_sfx := "goblin_hurt"         ## al recibir un golpe
var die_sfx := "goblin_die"           ## al morir
var attack_rest := 0.0                ## pausa mínima entre ataques (s), además de la recuperación
var windup_scale := 1.0               ## multiplica todas las anticipaciones (el jefe las acorta por fases)
## Ritmo general de los ataques en la mazmorra: anticipación y recuperación más largas (más tiempo para leerlos).
const ATTACK_PACE := 1.25
const RECOVER_PACE := 1.2
const EXTRA_REST := 0.25              ## s de más entre un ataque y el siguiente
var face_player_dist := 4.0           ## en APPROACH mira al jugador (y no al camino) por debajo de esto
var stun_ratio := 0.45                ## tamaño de la barra de aturdimiento = vida máxima × esto
var show_hp_bar := true               ## barra de vida sobre la de aguante (los jefes ya tienen la suya en pantalla)
var stun_parry := 0.4                 ## fracción de la barra que llena un parry
var stunned_time := STUNNED_TIME
## Remate: fracción de la vida máxima que quita (0 = lo mata; los jefes solo pierden un trozo)
var finish_damage_frac := 0.0
var _guard_color := GUARD_PARRY
var _stun := 0.0
var _stun_idle := 0.0
var _stun_bar: MeshInstance3D
var _hp_bar: MeshInstance3D
static var _stun_shader: Shader
var _next_attack_at := 0.0
var _atk_target := Vector3.ZERO       ## posición del jugador fijada para los ataques "at_target"

var state: State = State.IDLE
var player: CharacterBody3D
var map: DungeonMap                   ## para navegar (campo de flujo); opcional
var _avoid_side := 1.0
var _stuck_t := 0.0                   # tiempo seguido avanzando casi nada en APPROACH
var _unstick_t := 0.0
var _last_pos := Vector3.ZERO
var _state_t := 0.0
var _hit_done := false
var _impact_done := false
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

# ── Red (ver NetWorld) ──
var puppet := false                   ## en los clientes: copia visual del enemigo del anfitrión (sin IA)
var net_id := 0
var _net_pos := Vector3.ZERO
var _net_yaw := 0.0
var _retarget_t := 0.0
var _puppet_init := false

func _ready() -> void:
	EnemyTypeFlyweightFactory.get_flyweight(enemy_type).apply_to(self)
	scale = Vector3.ONE           # el tamaño lo dan model_height y la cápsula, no la escala del cuerpo
	speed *= speed_mult
	max_hp *= hp_mult
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
	_build_stun_bar()
	EnemyRegistry.register(self)
	player = NetPlayers.nearest(global_position) as CharacterBody3D
	_facing = -global_transform.basis.z
	_set_state(State.IDLE)
	if Net.is_host() and not puppet:
		var nw := get_tree().current_scene.get_node_or_null("NetWorld")
		if nw:
			nw.register_enemy(self)

# ───────────────────────────── Modelo y animaciones ─────────────────────────────

## Nodo del modelo (para efectos como SpawnDissolve, que no deben tocar la telegrafía).
func get_model() -> Node3D:
	return _model

## Animaciones ya retargeteadas, compartidas por todos los enemigos del mismo modelo (antes cada
## aparición instanciaba el FBX de cada clip y duplicaba su animación: ~60 ms por goblin).
static var _clip_cache: Dictionary = {}
static var _flash_shader: Shader = null
static var _tex_mats: Dictionary = {}

## Todos los FBX que usan los enemigos de la mazmorra (modelo en reposo y clips), para cargarlos
## durante la pantalla de carga y no al aparecer el primer grupo.
static func asset_paths() -> Array:
	var out: Array = []
	for g in _all_kinds():
		out.append(g.idle_model)
		out.append_array(g.clips.values())
		out.append_array(g.clip_fallbacks.values())
		g.free()
	return out.filter(func(p): return String(p) != "" and ResourceLoader.exists(p))

static func _all_kinds() -> Array:
	return [DungeonGoblin.new(), DungeonBrute.new(), DungeonMage.new(), DungeonZombie.new(), DungeonNecromancer.new(),
		DungeonRat.new(), DungeonSlug.new(), DungeonRatKing.new(),
		DungeonBigRat.new(), DungeonBloater.new()]

## Un modelo montado de cada tipo (sin entrar en el árbol): calienta clips y sombreadores de piel.
## Quien lo llama coloca los modelos donde haga falta y los libera.
static func warm_models() -> Array:
	var models: Array = []
	for g in _all_kinds():
		EnemyTypeFlyweightFactory.get_flyweight(g.enemy_type).apply_to(g)
		g._build_model()
		g.remove_child(g._model)
		models.append(g._model)
		g.free()
	return models

func _build_model() -> void:
	_model = (load(idle_model) as PackedScene).instantiate() as Node3D
	add_child(_model)
	var mi := _model.find_children("*", "MeshInstance3D", true, false)
	for m in mi:
		_meshes.append(m as MeshInstance3D)
	_fit_model()
	var tex := load(texture) as Texture2D if texture != "" else null   # "": colores del propio FBX
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
	for clip in clips:
		var path: String = clips[clip]
		if not ResourceLoader.exists(path):
			path = clip_fallbacks.get(clip, "")
		if path == "":
			continue
		var key := "%s|%s|%s" % [path, skel_path, clip]
		var a: Animation = _clip_cache.get(key)
		if a == null:
			var scene := load(path) as PackedScene
			if scene == null:
				continue
			var inst := scene.instantiate()
			var ap := inst.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
			a = ap.get_animation(ap.get_animation_list()[0]).duplicate(true)
			inst.free()
			# Los FBX exportados desde Blender cuelgan el esqueleto de "<Armature>/Skeleton3D"
			for i in a.get_track_count():
				var bone := a.track_get_path(i).get_concatenated_subnames()
				if bone != "":
					a.track_set_path(i, NodePath(str(skel_path) + ":" + bone))
			a.loop_mode = Animation.LOOP_LINEAR if clip == "walk" else Animation.LOOP_NONE
			_clip_cache[key] = a
		lib.add_animation(clip, a)

func _fit_model() -> void:
	if _meshes.is_empty() or _meshes[0].mesh == null:
		return
	# Caja en el espacio del modelo: los FBX exportados desde Blender (ratas, babosas) cuelgan la
	# malla de un "<Armature>" girado -90° y escalado ×100; los de Mixamo no tienen nada en medio
	var xf := Transform3D.IDENTITY
	var n: Node = _meshes[0]
	while n != null and n != _model:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	var aabb := xf * _meshes[0].mesh.get_aabb()
	var s := model_height / maxf(aabb.size.y, 0.0001)
	_model.scale = Vector3.ONE * s
	_model.rotation.y = PI
	_model.position.y = -aabb.position.y * s

## Ajusta la forma del aviso en el suelo al ataque elegido.
func _shape_telegraph(a: Dictionary) -> void:
	var plane := _telegraph.mesh as PlaneMesh
	var mat := _telegraph.material_override as ShaderMaterial
	var reach: float = a.get("reach", 0.0)
	if a["shape"] == "none":
		return
	_telegraph.top_level = false
	_telegraph.rotation = Vector3.ZERO
	if a["shape"] == "circle":
		# Círculo de radio `radius` centrado `center` m por delante (0 = alrededor del propio enemigo),
		# o fijado en el suelo donde está el jugador ("at_target"; lo coloca _place_target_telegraph)
		var r := float(a["radius"])
		plane.size = Vector2(r * 2.0, r * 2.0)
		mat.set_shader_parameter("shape", 2)
		if a.get("at_target", false):
			_telegraph.top_level = true
			_place_target_telegraph()
		else:
			_telegraph.position = Vector3(0.0, 0.05, -float(a.get("center", 0.0)))
		mat.set_shader_parameter("progress", 0.0)
		return
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
func _choose_attack(dist: float, sees: bool = true) -> String:
	var options: Array = []
	var total := 0
	for n in attacks:
		var a: Dictionary = attacks[n]
		if dist < float(a["range"][0]) or dist > float(a["range"][1]):
			continue
		if (a["shape"] == "line" or a.get("needs_sight", false)) and not sees:
			continue
		if _clock < float(_atk_ready.get(n, 0.0)):
			continue
		options.append(n)
		total += int(a["weight"])
	if options.is_empty():
		return ""
	var roll := randi() % total
	for n in options:
		roll -= int(attacks[n]["weight"])
		if roll < 0:
			return n
	return options[0]

func _start_attack(n: String) -> void:
	_atk_name = n
	_atk = attacks[n]
	_atk_ready[n] = _clock + float(_atk["cooldown"])
	_next_attack_at = _clock + float(_atk["windup"]) * windup_scale * ATTACK_PACE + float(_atk["attack_time"]) + attack_rest + EXTRA_REST
	if is_instance_valid(player):
		_atk_target = player.global_position
	_set_state(State.WINDUP)

## Centro de la zona de golpe de un ataque en círculo: delante del enemigo o donde estaba el jugador.
func _attack_center() -> Vector3:
	if _atk.get("at_target", false):
		return _atk_target
	return global_position + _facing * float(_atk.get("center", 0.0))

func _place_target_telegraph() -> void:
	_telegraph.global_position = Vector3(_atk_target.x, _atk_target.y + 0.05, _atk_target.z)
	_telegraph.global_rotation = Vector3.ZERO

## Hacia dónde avanza en APPROACH cuando no ataca. Por defecto, hacia el jugador; los que
## atacan de lejos (DungeonMage) lo cambian para mantener la distancia.
func _approach_dir(to_p: Vector3, _dist: float, sees: bool) -> Vector3:
	return _nav_dir(to_p, sees)

func _play(clip: String, blend: float = 0.1) -> void:
	if _anim and _anim.has_animation(clip):
		_anim.play(clip, blend)

func _build_telegraph() -> void:
	_telegraph = MeshInstance3D.new()
	_telegraph.mesh = PlaneMesh.new()
	var m := ShaderMaterial.new()
	m.shader = TELEGRAPH_SHADER
	m.set_shader_parameter("color", Vector3(telegraph_color.r, telegraph_color.g, telegraph_color.b))
	_telegraph.material_override = m
	_telegraph.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_telegraph.visible = false
	add_child(_telegraph)

## Cómo se evita un ataque: "parry" (cuerpo a cuerpo), "dodge" (áreas: solo esquivar) o
## "ranged" (proyectiles: la guardia reduce el daño). Decide el color del aviso y si el parry vale.
static func guard_kind(a: Dictionary) -> String:
	if a.get("unblockable", false) or a["shape"] == "circle" or a.get("eruption", false) or a.get("burst", false):
		return "dodge"
	if a.get("ranged", false):
		return "ranged"
	return "parry"

static func guard_color(a: Dictionary) -> Color:
	match guard_kind(a):
		"dodge": return GUARD_DODGE
		"ranged": return GUARD_RANGED
	return GUARD_PARRY

## Barritas sobre la cabeza: vida (arriba, desde el primer golpe) y aguante acumulado (debajo,
## oculta mientras está vacía).
func _build_stun_bar() -> void:
	var k := clampf(model_height / MODEL_HEIGHT, 1.0, 1.8)
	_stun_bar = _make_head_bar(Vector2(0.9, 0.1) * k, model_height + 0.35, STUN_BAR_TINT)
	_hp_bar = _make_head_bar(Vector2(0.9, 0.12) * k, model_height + 0.35 + 0.14 * k, HP_BAR_TINT)

func _make_head_bar(size: Vector2, height: float, tint: Color) -> MeshInstance3D:
	if _stun_shader == null:
		_stun_shader = Shader.new()
		_stun_shader.code = STUN_BAR_SHADER
	var quad := QuadMesh.new()
	quad.size = size
	var mat := ShaderMaterial.new()
	mat.shader = _stun_shader
	mat.render_priority = 1
	quad.material = mat
	var bar := MeshInstance3D.new()
	bar.mesh = quad
	bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bar.position = Vector3(0, height, 0)
	bar.visible = false
	add_child(bar)
	bar.set_instance_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	return bar

func stun_max() -> float:
	return maxf(max_hp * stun_ratio, 1.0)

## 0..1 (lo envía NetWorld a las copias de los clientes).
func stun_fraction() -> float:
	return 1.0 if state == State.STUNNED else clampf(_stun / stun_max(), 0.0, 1.0)

func _update_stun_bar() -> void:
	var f := stun_fraction()
	_stun_bar.visible = f > 0.01 and state != State.DEAD
	_hp_bar.visible = show_hp_bar and state != State.DEAD and (hp < max_hp or _stun_bar.visible)
	if _hp_bar.visible:
		_hp_bar.set_instance_shader_parameter("fill", clampf(hp / max_hp, 0.0, 1.0))
	if _stun_bar.visible:
		_stun_bar.set_instance_shader_parameter("fill", f)
		_stun_bar.set_instance_shader_parameter("pulse", 0.5 + 0.5 * sin(_state_t * 12.0) if state == State.STUNNED else 0.0)

## Suma aturdimiento; true si la barra se llena y queda indefenso (STUNNED).
func _add_stun(amount: float) -> bool:
	if state == State.DEAD or state == State.STUNNED or amount <= 0.0:
		return false
	_stun_idle = 0.0
	_stun = minf(_stun + amount, stun_max())
	if _stun < stun_max():
		return false
	_set_state(State.STUNNED)
	_knock = -_facing * 3.0 * knock_scale
	AudioManager.play_at("impact_zap", global_position, -2.0, 0.55)
	HitFeedback.freeze(0.08)
	HitFeedback.shake(0.3)
	return true

## Se puede rematar ahora mismo (PlayerFinisherController).
func can_be_finished() -> bool:
	return state == State.STUNNED

## Lo que quita un remate: toda la vida, o un trozo a los jefes.
func finisher_damage() -> float:
	if finish_damage_frac > 0.0:
		return max_hp * finish_damage_frac
	return hp + max_hp

## Remate del jugador. En un cliente, el daño lo aplica el anfitrión (take_damage de la copia).
func receive_finisher(dir: Vector3) -> void:
	var dmg := finisher_damage()
	if puppet:
		take_damage(dmg, dir)
		return
	if not can_be_finished():
		return
	_stun = 0.0
	take_damage(dmg, dir)
	if state == State.STUNNED:
		# Sobrevive (jefe): cae de espaldas y se recupera enseguida
		_model.rotation.z = 0.0
		_set_state(State.STAGGER)
		_state_t = stagger_time - 1.0
		_knock = dir.normalized() * 6.0 * knock_scale

# ───────────────────────────── Estados ─────────────────────────────

func _set_state(s: State) -> void:
	state = s
	_state_t = 0.0
	_telegraph.visible = false
	# La anticipación dura ATTACK_PACE veces más: su clip va algo más lento para no quedarse congelado
	if _anim:
		_anim.speed_scale = 1.0 / ATTACK_PACE if s == State.WINDUP else 1.0
	match s:
		State.IDLE: _play("idle", 0.2)
		State.APPROACH: _play("walk", 0.15)
		State.WINDUP:
			_poise = 0.0
			_play(_atk["windup_clip"], 0.08)
			_shape_telegraph(_atk)
			_guard_color = guard_color(_atk)
			(_telegraph.material_override as ShaderMaterial).set_shader_parameter("color",
				Vector3(_guard_color.r, _guard_color.g, _guard_color.b))
			_telegraph.visible = _atk["shape"] != "none" and SettingsManager.show_attack_marks
			AudioManager.play_at(warn_sfx, global_position, 0.0, randf_range(0.9, 1.1) * sfx_pitch)
		State.ATTACK:
			_hit_done = false
			_impact_done = false
			_play(_atk["attack_clip"], 0.02)
			_knock += _facing * float(_atk["lunge"])
			AudioManager.play_at(swing_sfx, global_position, 0.0, randf_range(0.95, 1.05) * sfx_pitch)
		State.RECOVER: _play("recover", 0.05)
		State.HURT: _play("hurt", 0.03)
		State.STAGGER: _play("hurt", 0.03)
		State.STUNNED:
			_play("hurt", 0.03)
			if _anim:
				_anim.speed_scale = 0.5
		State.DEAD: _play("death", 0.05)

func _physics_process(delta: float) -> void:
	if puppet:
		_puppet_process(delta)
		return
	if Net.is_online():
		# Con varios jugadores va a por el más cercano (cada 0,4 s, no en cada tick)
		_retarget_t -= delta
		if _retarget_t <= 0.0:
			_retarget_t = 0.4
			player = NetPlayers.nearest(global_position) as CharacterBody3D
	_state_t += delta
	_clock += delta
	_armor_dmg = maxf(_armor_dmg - ARMOR_DECAY * delta, 0.0)
	_stun_idle += delta
	if _stun_idle > STUN_DECAY_DELAY and state != State.STUNNED:
		_stun = maxf(_stun - stun_max() * STUN_DECAY * delta, 0.0)
	_update_flash(delta)
	_update_stun_bar()
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
			# Ataques al alcance por distancia; los de línea (embestidas) piden línea de visión
			var pick := _choose_attack(dist, sees) if _clock >= _next_attack_at else ""
			if pick != "":
				_turn_towards(to_p, delta)
				_start_attack(pick)
			else:
				var dir := _approach_dir(to_p, dist, sees)
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
				_turn_towards(to_p if sees and dist < face_player_dist else dir, delta)
				move = dir * speed + EnemyRegistry.separation_push(self, 1.2) * 2.0
		State.WINDUP:
			var windup: float = float(_atk["windup"]) * windup_scale * ATTACK_PACE
			if _state_t <= float(_atk["track"]):
				_turn_towards(to_p, delta)
				# Los hechizos "at_target" siguen al jugador hasta que se fijan
				if _atk.get("at_target", false) and is_instance_valid(player):
					_atk_target = player.global_position
					_place_target_telegraph()
			var mat := _telegraph.material_override as ShaderMaterial
			mat.set_shader_parameter("progress", clampf(_state_t / windup, 0.0, 1.0))
			# Destello creciente del color del aviso: ¡va a pegar!
			_flash_color = _guard_color
			_flash = maxf(_flash, 0.15 + 0.45 * (_state_t / windup) * (0.6 + 0.4 * sin(_state_t * 30.0)))
			if _state_t >= windup:
				_set_state(State.ATTACK)
		State.ATTACK:
			var win: Vector2 = _atk["window"]
			var in_window := _state_t >= win.x and _state_t <= win.y
			if float(_atk["dash"]) > 0.0 and in_window:
				move = _facing * float(_atk["dash"])
			if not _impact_done and _state_t >= win.x:
				_impact_done = true
				_on_impact()
			if not _hit_done and in_window and not _atk.get("ranged", false):
				_try_hit_player()
			var wall_stun := float(_atk.get("wall_stun", 0.0))
			if wall_stun > 0.0 and in_window and _state_t > 0.05 and is_on_wall():
				# La embestida se estrella contra la pared: queda aturdido
				AudioManager.play_at("impact_blunt", global_position, 0.0, 0.6)
				_set_state(State.STAGGER)
				_state_t = stagger_time - wall_stun
			elif _state_t >= float(_atk["attack_time"]):
				_set_state(State.RECOVER)
		State.RECOVER:
			if _state_t >= float(_atk["recover"]) * RECOVER_PACE:
				_set_state(State.APPROACH)
		State.HURT:
			if _state_t >= hurt_time:
				_set_state(State.APPROACH)
		State.STAGGER:
			# Aturdido: tambaleo
			_model.rotation.z = sin(_state_t * 14.0) * 0.12 * clampf(1.0 - _state_t / stagger_time, 0.0, 1.0)
			if _state_t >= stagger_time:
				_model.rotation.z = 0.0
				_set_state(State.APPROACH)
		State.STUNNED:
			_stun_wobble()
			if _state_t >= stunned_time:
				_model.rotation.z = 0.0
				_stun = 0.0
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

## Indefenso esperando el remate: se tambalea y destella en dorado.
func _stun_wobble() -> void:
	_model.rotation.z = sin(_state_t * 6.0) * 0.1
	_flash_color = STUN_COLOR
	_flash = maxf(_flash, 0.25 + 0.2 * sin(_state_t * 10.0))

## El jugador ha parado este golpe con un parry: aturdimiento corto (corta también las embestidas).
func _on_parried() -> void:
	if _add_stun(stun_max() * stun_parry):
		_flash_color = PlayerParryController.COLOR
		_flash = 1.0
		return
	_set_state(State.STAGGER)
	_state_t = stagger_time - PlayerParryController.STUN
	_flash_color = PlayerParryController.COLOR
	_flash = 1.0
	_knock = -_facing * 4.0 * knock_scale

## Instante en que el golpe toca (inicio de la ventana): temblor y polvo para los ataques con "shake".
func _on_impact() -> void:
	var amount := float(_atk.get("shake", 0.0))
	if amount <= 0.0:
		return
	var at := _attack_center()
	if is_instance_valid(player):
		var d := Vector2(player.global_position.x - at.x, player.global_position.z - at.z).length()
		HitFeedback.shake(amount * clampf(1.0 - d / 12.0, 0.0, 1.0))
	AudioManager.play_at("impact_blunt", at, 0.0, 0.55)
	var root := get_tree().current_scene
	if root == null:
		return
	var dust := DustVFX.haze(18, 0.9, float(_atk.get("radius", 1.0)) * 0.7, 0.6, 1.4, Color(0.75, 0.65, 0.5), 0.3)
	dust.one_shot = true
	dust.explosiveness = 0.9
	dust.initial_velocity_min = 1.0
	dust.initial_velocity_max = 2.5
	root.add_child(dust)
	dust.global_position = at + Vector3(0, 0.2, 0)
	dust.emitting = true
	get_tree().create_timer(1.2).timeout.connect(dust.queue_free)

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
			AudioManager.play_at("goblin_swing", global_position, 0.0, randf_range(0.95, 1.05) * sfx_pitch)
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
	if _atk["shape"] == "circle":
		var center := _attack_center()
		var off := player.global_position - center
		if Vector2(off.x, off.z).length() > float(_atk["radius"]) + 0.45:
			return
	elif _atk["shape"] == "line":
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
	# Parry del jugador: el golpe no entra y este enemigo se lleva la reacción (las áreas no se paran)
	if guard_kind(_atk) == "parry" and player.has_method("try_parry_melee") and player.try_parry_melee(self):
		_on_parried()
		return
	var dmg: float = _atk["damage"]
	player.take_damage(dmg, to_p.normalized())
	AudioManager.play_at("impact_blunt", player.global_position, -2.0, 0.8)
	var root := get_tree().current_scene
	if root:
		FloatingDamage.spawn(root, player.global_position + Vector3(0, 2.0, 0), dmg, Color(1.0, 0.2, 0.2))

# ───────────────────────────── Recibir daño ─────────────────────────────

func take_damage(amount: float, knockback_dir: Vector3 = Vector3.ZERO) -> void:
	if puppet:
		_puppet_hit(amount, knockback_dir)
		return
	if state == State.DEAD:
		return
	hp -= amount
	_flash_color = Color(1, 1, 1)
	_flash = 1.0
	var root := get_tree().current_scene
	if root:
		FloatingDamage.spawn(root, global_position + Vector3(0, 1.8, 0), amount, Color(1.0, 0.88, 0.22), amount >= stagger_damage)
	var killed := hp <= 0.0
	var push := knockback_dir
	push.y = 0.0
	if push.length_squared() > 0.0001:
		_knock = push.normalized() * clampf(push.length(), 3.0, 20.0) * knock_scale
	HitFeedback.on_enemy_hit(self, amount, knockback_dir, killed)
	if killed:
		_die()
		return
	var now := Time.get_ticks_msec()
	if now - _last_hurt_sfx > 120:
		_last_hurt_sfx = now
		AudioManager.play_at(hurt_sfx, global_position, -4.0, randf_range(0.9, 1.15) * sfx_pitch)
	var heavy := amount >= stagger_damage or knockback_dir.length() >= stagger_knock
	var stun_gain := amount * (STUN_HEAVY_MULT if heavy else STUN_HIT_MULT)
	if state == State.RECOVER:
		stun_gain *= STUN_PUNISH_MULT
	if _add_stun(stun_gain):
		return
	match state:
		State.STUNNED:
			pass                                   # indefenso hasta el remate o hasta que se le pase
		State.ATTACK:
			pass                                   # el golpe ya salió: no se interrumpe
		State.WINDUP:
			_poise += amount
			if heavy:
				_set_state(State.STAGGER)
			elif _poise >= windup_poise:
				_set_state(State.HURT)
		_:
			if heavy:
				_armor_dmg = 0.0
				_set_state(State.STAGGER)
			elif armor > 0.0 and amount < armor:
				# Armadura: aguanta el golpe sin inmutarse hasta que se acumula bastante daño
				_armor_dmg += amount
				if armor_break > 0.0 and _armor_dmg >= armor_break:
					_armor_dmg = 0.0
					_set_state(State.STAGGER)
			else:
				_set_state(State.HURT)

func apply_knockback(v: Vector3) -> void:
	if state == State.DEAD:
		return
	v.y = 0.0
	_knock = (_knock + v * knock_scale).limit_length(24.0)

func _die() -> void:
	_set_state(State.DEAD)
	collision_layer = 0
	remove_from_group("enemies")
	EnemyRegistry.unregister(self)
	AudioManager.play_at(die_sfx, global_position, 0.0, randf_range(0.95, 1.05) * sfx_pitch)
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

# ───────────────────────────── Red: copia en los clientes ─────────────────────────────

## Datos para la instantánea (el anfitrión): ataque en curso y, si se fija en el suelo, su objetivo.
func attack_name() -> String:
	return _atk_name

func attack_target() -> Vector3:
	return _atk_target

## Estado recibido del anfitrión (cliente).
func net_apply(pos: Vector3, yaw: float, st: int, hp_value: float, atk: String, atk_target: Vector3) -> void:
	_net_pos = pos
	_net_yaw = yaw
	hp = hp_value
	_atk_target = atk_target
	if atk != _atk_name and attacks.has(atk):
		_atk_name = atk
		_atk = attacks[atk]
	if not _puppet_init:
		_puppet_init = true
		global_position = pos
		rotation.y = yaw
	if st != int(state) and state != State.DEAD:
		_set_state(st as State)

## Aturdimiento acumulado en el anfitrión (cliente), para la barrita.
func net_stun(fraction: float) -> void:
	_stun = fraction * stun_max()

func _puppet_process(delta: float) -> void:
	_state_t += delta
	_clock += delta
	_update_flash(delta)
	_update_stun_bar()
	if state == State.DEAD:
		return
	global_position = global_position.lerp(_net_pos, 1.0 - exp(-14.0 * delta))
	rotation.y = lerp_angle(rotation.y, _net_yaw, 1.0 - exp(-14.0 * delta))
	_facing = Vector3(-sin(rotation.y), 0.0, -cos(rotation.y))
	match state:
		State.WINDUP:
			var windup: float = float(_atk["windup"]) * windup_scale * ATTACK_PACE
			if _atk.get("at_target", false):
				_place_target_telegraph()
			var mat := _telegraph.material_override as ShaderMaterial
			mat.set_shader_parameter("progress", clampf(_state_t / windup, 0.0, 1.0))
			_flash_color = _guard_color
			_flash = maxf(_flash, 0.15 + 0.45 * (_state_t / windup) * (0.6 + 0.4 * sin(_state_t * 30.0)))
		State.STAGGER:
			_model.rotation.z = sin(_state_t * 14.0) * 0.12 * clampf(1.0 - _state_t / stagger_time, 0.0, 1.0)
		State.STUNNED:
			_stun_wobble()
		_:
			_model.rotation.z = 0.0

## Un golpe sobre la copia: efectos al instante y el daño real lo aplica el anfitrión.
func _puppet_hit(amount: float, knockback_dir: Vector3) -> void:
	if state == State.DEAD:
		return
	_flash_color = Color(1, 1, 1)
	_flash = 1.0
	var root := get_tree().current_scene
	if root:
		FloatingDamage.spawn(root, global_position + Vector3(0, 1.8, 0), amount, Color(1.0, 0.88, 0.22), amount >= stagger_damage)
	HitFeedback.on_enemy_hit(self, amount, knockback_dir, false)
	var nw := get_tree().current_scene.get_node_or_null("NetWorld") if get_tree().current_scene else null
	if nw:
		nw.send_enemy_hit(net_id, amount, knockback_dir)

## El anfitrión avisa de que murió (cliente).
func net_die() -> void:
	if state == State.DEAD and collision_layer == 0:
		return
	_set_state(State.DEAD)
	collision_layer = 0
	remove_from_group("enemies")
	EnemyRegistry.unregister(self)
	AudioManager.play_at(die_sfx, global_position, 0.0, randf_range(0.95, 1.05) * sfx_pitch)
	var tw := create_tween()
	tw.tween_interval(1.6)
	tw.tween_property(_model, "position:y", _model.position.y - 0.6, 0.8).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_model, "scale", _model.scale * 0.85, 0.8)
	tw.tween_callback(queue_free)
