class_name DungeonBat
extends DungeonGoblin

## Murciélago gigante de las cavernas: VUELA. Comparte la máquina de estados (y la red, las fichas y el botín) de
## DungeonGoblin, pero no pisa el suelo: planea a `hover_h` m del suelo, sube y baja con el jugador y se dibuja como
## un sprite de tinta (atlas de la fauna ambiental) que mira siempre a la cámara, con su sombra en el suelo.
##
##  - bite (mordisco): pegado al jugador; anticipación corta y cono ancho → alejarse o parar con un parry.
##  - swoop (picado): de media distancia se encarama (sube y aletea rápido: ese es el aviso) y se lanza en línea
##    recta hacia el jugador, bajando hasta él → apartarse de lado.
## Frágil y rápido: la gracia es que está en el aire. Con el combate aéreo (saltar y golpear) se le alcanza igual, y
## aturdido cae al suelo aleteando, donde se le puede rematar. No se le puede lanzar (ya vuela): launch_mult = 0.
## DungeonCrow (supervivencia) lo hereda con otro dibujo del mismo atlas.

const ATLAS := "res://assets/textures/critters/critters_atlas.png"
const GRID := 4                       ## celdas por lado del atlas
const FRAME_PX := 96.0                ## píxeles de una celda
const BAT_ATTACKS := {
	"bite": {"range": [0.0, 1.7], "weight": 3, "cooldown": 0.0, "shape": "cone", "reach": 1.8, "half_angle": 75.0,
		"windup_clip": "bite_windup", "attack_clip": "bite", "windup": 0.32, "track": 0.25,
		"attack_time": 0.33, "window": Vector2(0.04, 0.16), "lunge": 3.5, "dash": 0.0,
		"damage": 1.5, "recover": 0.5},
	"swoop": {"range": [3.0, 8.0], "weight": 2, "cooldown": 3.5, "shape": "line", "reach": 6.0, "width": 1.0,
		"windup_clip": "swoop_windup", "attack_clip": "swoop", "windup": 0.7, "track": 0.55,
		"attack_time": 0.55, "window": Vector2(0.0, 0.45), "lunge": 0.0, "dash": 13.0, "dive": true,
		"damage": 2.0, "recover": 1.0},
}
const HOVER_RISE := 0.8               ## m extra que sube al encaramarse para el picado
const HOVER_BOB := 0.12               ## m de vaivén al planear
const CLIMB_GAIN := 5.0               ## 1/s: cuánto corrige su altura hacia la que quiere
const MAX_CLIMB := 7.0                ## m/s máximos de subida o bajada
const GROUND_RAY := 14.0
const GROUND_INTERVAL := 0.25
const FALL_REST := 0.06               ## m sobre el suelo al caer aturdido

const SHADOW_SHADER := """shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform float strength = 0.45;
void fragment() {
	float d = length(UV * 2.0 - 1.0);
	ALBEDO = vec3(0.0);
	ALPHA = strength * smoothstep(1.0, 0.3, d);
}
"""

## Dibujo (celdas del atlas: aleteo abierto y cerrado) y tamaño; DungeonCrow los cambia
var frames := Vector2i(4, 5)
var sprite_w := 1.1                   ## m de ancho del sprite
var faces_right := false              ## el dibujo mira a la derecha (cuervo): se voltea al ir hacia la izquierda
var hover_h := 0.95                   ## m sobre el suelo (sobre los pies del jugador) a los que planea

var _sprite: Sprite3D
var _shadow: MeshInstance3D
var _ground_y := 0.0
var _ground_at := -1.0
var _flap := 0.0
var _fade := 1.0                      ## opacidad (se desvanece al morir)
var _mod_sent := Color(0, 0, 0, -1)
static var _shadow_shader: Shader

func _init() -> void:
	attacks = BAT_ATTACKS
	clips = {}
	idle_model = ""
	texture = ""
	model_height = 0.9
	enemy_type = EnemyData.EnemyType.NORMAL_GOBLIN
	hp_mult = 0.45                    # 40 × 0,45 = 18 (× dureza global)
	speed_mult = 1.5
	hit_radius = 0.4
	hit_height = 0.8
	hurt_time = 0.25
	stagger_time = 1.0
	stagger_damage = 13.0
	armor = 0.0
	armor_break = 0.0
	windup_poise = 6.0
	knock_scale = 1.2
	launch_mult = 0.0                 # ya está en el aire
	uses_attack_token = false         # hostiga sin hacer cola con los de cuerpo a cuerpo
	warn_sfx = "bat_screech"
	swing_sfx = "wing_flap"
	hurt_sfx = "bat_screech"
	die_sfx = "bat_screech"
	sfx_pitch = 1.0
	attack_rest = 0.2
	face_player_dist = 8.0
	telegraph_color = Color(0.75, 0.35, 1.0)

func _ready() -> void:
	super()
	_ground_y = global_position.y
	_flap = randf() * 10.0
	_build_shadow()

# ───────────────────────────── Dibujo ─────────────────────────────

## Sin FBX: el "modelo" es un nodo con el sprite del atlas (siempre de cara a la cámara).
func _build_model() -> void:
	_model = Node3D.new()
	add_child(_model)
	_sprite = Sprite3D.new()
	_sprite.texture = load(ATLAS) as Texture2D
	_sprite.hframes = GRID
	_sprite.vframes = GRID
	_sprite.frame = frames.x
	_sprite.pixel_size = sprite_w / FRAME_PX
	_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sprite.shaded = false
	_sprite.double_sided = true
	_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sprite.position.y = hit_height * 0.5
	_model.add_child(_sprite)

## Sombra redonda en el suelo: sin ella no se lee a qué altura vuela.
func _build_shadow() -> void:
	if _shadow_shader == null:
		_shadow_shader = Shader.new()
		_shadow_shader.code = SHADOW_SHADER
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var mat := ShaderMaterial.new()
	mat.shader = _shadow_shader
	quad.material = mat
	_shadow = MeshInstance3D.new()
	_shadow.mesh = quad
	_shadow.top_level = true
	_shadow.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shadow)

func _update_shadow() -> void:
	if _shadow == null:
		return
	if state == State.DEAD:
		_shadow.visible = false
		return
	var h := maxf(global_position.y - _ground_y, 0.0)
	var k := clampf(1.0 - h * 0.18, 0.35, 1.0)
	_shadow.visible = true
	_shadow.global_position = Vector3(global_position.x, _ground_y + 0.04, global_position.z)
	_shadow.scale = Vector3.ONE * sprite_w * 0.8 * k
	(_shadow.mesh.material as ShaderMaterial).set_shader_parameter("strength", 0.5 * k)

## Destello de golpe y de aviso sobre el sprite (los FBX lo hacen con un material superpuesto).
func _update_flash(delta: float) -> void:
	_flash = move_toward(_flash, 0.0, delta * 5.0)
	if _sprite == null:
		return
	var k := clampf(_flash, 0.0, 1.0)
	var c := Color.WHITE.lerp(_flash_color, k * 0.7)
	var m := Color(c.r * (1.0 + k), c.g * (1.0 + k), c.b * (1.0 + k), _fade)
	if m != _mod_sent:
		_mod_sent = m
		_sprite.modulate = m

func _process(delta: float) -> void:
	if _sprite == null:
		return
	var hz := 7.0
	var folded := false
	match state:
		State.WINDUP, State.ATTACK:
			hz = 18.0
			folded = state == State.ATTACK and bool(_atk.get("dive", false))   # picando: alas pegadas
		State.STAGGER, State.STUNNED, State.DEAD:
			hz = 3.0
			folded = state == State.DEAD
	_flap += delta * hz
	_sprite.frame = frames.y if folded or fmod(_flap, 1.0) > 0.5 else frames.x
	# Mirando hacia donde va (el cuervo dibujado de perfil; el murciélago es simétrico)
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null and velocity.length_squared() > 1.0:
		var right := velocity.dot(cam.global_transform.basis.x) > 0.0
		_sprite.flip_h = (not right) if faces_right else right
	# El tambaleo del aturdimiento (gira el nodo del modelo) se ve como un temblor lateral del sprite
	_sprite.position.x = _model.rotation.z * 1.6
	_sprite.position.y = hit_height * 0.5

func _physics_process(delta: float) -> void:
	super(delta)
	_update_shadow()

# ───────────────────────────── Vuelo ─────────────────────────────

## Altura del suelo bajo el bicho (rayo hacia abajo cada GROUND_INTERVAL s).
func ground_y() -> float:
	return _ground_y

func _refresh_ground() -> void:
	if _clock < _ground_at:
		return
	_ground_at = _clock + GROUND_INTERVAL
	var from := global_position + Vector3(0.0, 0.5, 0.0)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0.0, -GROUND_RAY, 0.0), 1)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		_ground_y = float((hit["position"] as Vector3).y)
	elif is_instance_valid(player):
		_ground_y = player.global_position.y

## Altura (de los pies) a la que quiere estar según lo que hace.
func _want_y() -> float:
	var py := player.global_position.y if is_instance_valid(player) else _ground_y
	var base := maxf(py, _ground_y)
	match state:
		State.STAGGER, State.STUNNED:
			return _ground_y + FALL_REST                      # cae al suelo aleteando
		State.IDLE:
			return _ground_y + hover_h + sin(_clock * 2.0 + float(get_instance_id() % 7)) * HOVER_BOB
		State.WINDUP:
			if bool(_atk.get("dive", false)):
				return base + hover_h + HOVER_RISE            # se encarama antes de picar
		State.ATTACK:
			if bool(_atk.get("dive", false)) and is_instance_valid(player):
				return py + 0.3                               # baja hasta el jugador
	return base + hover_h + sin(_clock * 2.6 + float(get_instance_id() % 7)) * HOVER_BOB

func _apply_vertical(delta: float) -> void:
	if state == State.DEAD:
		super(delta)                                          # muerto: cae
		return
	_refresh_ground()
	var gain := CLIMB_GAIN * (1.6 if state == State.ATTACK else 1.0)
	var vy := clampf((_want_y() - global_position.y) * gain, -MAX_CLIMB, MAX_CLIMB)
	velocity.y = move_toward(velocity.y, vy, 40.0 * delta)

## En supervivencia no hay rejilla ni paredes cerca: lo ve siempre (los rayos de visión chocarían con el relieve).
func _sees_player() -> bool:
	if map == null:
		return true
	return super()

func _die() -> void:
	super()
	var tw := create_tween()
	tw.tween_interval(0.7)
	tw.tween_property(self, "_fade", 0.0, 0.8)
