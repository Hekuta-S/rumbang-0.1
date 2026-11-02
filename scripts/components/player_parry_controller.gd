class_name PlayerParryController
extends Node

## Parry al estilo Deadlock (solo mazmorra). F o el clic del stick izquierdo: el personaje adopta
## la guardia (POSE_TIME) y le rodea un aura. Los primeros WINDOW segundos protege de frente (180°):
##  - Golpe cuerpo a cuerpo: no hace daño y el atacante queda aturdido (lo decide el atacante con
##    try_block_melee(); el jefe lo cuenta como daño contra su armadura). Además, el siguiente golpe
##    del jugador en BONUS_TIME hace BONUS_MULT de daño. Se puede repetir enseguida (COOLDOWN_OK).
##  - Proyectil (orbes): solo reduce el daño (PROJECTILE_MULT); no aturde a nadie.
##  - Áreas (erupciones, nova, pisotón): no se bloquean; hay que esquivarlas.
## Si la guardia termina sin parar nada, no se puede repetir en COOLDOWN_FAIL.
## La esquiva corta la guardia.

signal parried(attacker: Node3D)

const WINDOW := 0.4
const POSE_TIME := 0.6
const COOLDOWN_OK := 0.5
const COOLDOWN_FAIL := 2.5
const STUN := 1.5                     ## aturdimiento del atacante (enemigos normales)
const BOSS_ARMOR := 60.0              ## daño contra la armadura del jefe
const PROJECTILE_MULT := 0.5
const BONUS_MULT := 1.5
const BONUS_TIME := 2.0
const MOVE_MULT := 0.4                ## velocidad durante la guardia
const COLOR := Color(0.45, 0.8, 1.0)
const SUCCESS_COLOR := Color(1.0, 0.92, 0.6)

const AURA_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled;
uniform vec4 col : source_color = vec4(0.45, 0.8, 1.0, 1.0);
uniform float strength = 1.0;
void fragment() {
	float rim = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.2);
	float bands = 0.5 + 0.5 * sin(UV.y * 48.0 - TIME * 7.0);
	ALBEDO = col.rgb * (rim * 1.8 + rim * bands * 0.7 + 0.04) * strength;
}
"""
static var _aura_shader: Shader

var player: CharacterBody3D
var _t := -1.0                        ## tiempo desde que empezó la guardia (< 0: sin guardia)
var _cooldown := 0.0
var _success := false
var _bonus_t := 0.0
var _flash := 0.0
var _aura: MeshInstance3D
var _aura_mat: ShaderMaterial

func _ready() -> void:
	player = get_parent() as CharacterBody3D
	if _aura_shader == null:
		_aura_shader = Shader.new()
		_aura_shader.code = AURA_SHADER
	_aura = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.85
	sphere.height = 2.3
	_aura.mesh = sphere
	_aura_mat = ShaderMaterial.new()
	_aura_mat.shader = _aura_shader
	_aura.material_override = _aura_mat
	_aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aura.position = Vector3(0, 1.0, 0)
	_aura.visible = false
	player.add_child.call_deferred(_aura)

## Empieza la guardia si se puede. Devuelve true si empezó.
func try_parry() -> bool:
	if GameData.game_mode != "dungeon" or is_active() or _cooldown > 0.0:
		return false
	var mc = player.get("movement_controller")
	if mc and mc.is_dodging():
		return false
	var anim = player.get("animation_controller")
	if anim and not anim.can_cancel_for_dodge():
		return false                  # en mitad de un golpe con la ventana abierta o del clavado
	var cc = player.get("combat_controller")
	if cc and cc.spear_charge >= 0.0:
		cc.spear_charge = -1.0
		cc._stop_charge_shake()
	_t = 0.0
	_success = false
	if anim:
		anim.cancel_action()
		anim.play_parry()
	AudioManager.play("melee_swing", -8.0, 0.75)
	_aura.visible = true
	_aura.scale = Vector3.ONE * 0.6
	_aura.create_tween().tween_property(_aura, "scale", Vector3.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return true

func is_active() -> bool:
	return _t >= 0.0

## Protegiendo ahora mismo (dentro de la ventana).
func is_guarding() -> bool:
	return _t >= 0.0 and _t <= WINDOW

func cooldown_left() -> float:
	return _cooldown

## Atacante delante del personaje (180°).
func faces(pos: Vector3) -> bool:
	var to := pos - player.global_position
	to.y = 0.0
	if to.length_squared() < 0.0001:
		return true
	var fwd: Vector3 = -player.mesh.global_transform.basis.z
	fwd.y = 0.0
	return fwd.normalized().dot(to.normalized()) >= 0.0

## Un golpe cuerpo a cuerpo de `attacker` va a entrar: true si lo para (no debe hacer daño).
func try_block_melee(attacker: Node3D) -> bool:
	if not is_guarding() or not is_instance_valid(attacker) or not faces(attacker.global_position):
		return false
	_success = true
	_bonus_t = BONUS_TIME
	_flash = 1.0
	AudioManager.play("impact_zap", -2.0, 0.7)
	AudioManager.play("impact_blunt", -4.0, 1.4)
	HitFeedback.freeze(0.09)
	HitFeedback.shake(0.35)
	var root := player.get_tree().current_scene
	if root:
		var at: Vector3 = player.global_position.lerp(attacker.global_position, 0.4) + Vector3(0, 1.1, 0)
		NecroVFX.shockwave(root, Vector3(player.global_position.x, player.global_position.y + 0.1, player.global_position.z), 2.4, COLOR)
		var s := DustVFX.sparkles(26, 0.45, 0.2, 0.08, 0.2, SUCCESS_COLOR)
		s.one_shot = true
		s.explosiveness = 1.0
		s.initial_velocity_min = 3.0
		s.initial_velocity_max = 6.0
		s.spread = 70.0
		root.add_child(s)
		s.global_position = at
		s.emitting = true
		root.get_tree().create_timer(0.8).timeout.connect(s.queue_free)
	parried.emit(attacker)
	return true

## Daño de un proyectil que llega desde `from_pos`: reducido si la guardia lo cubre.
func projectile_damage(amount: float, from_pos: Vector3) -> float:
	if not is_guarding() or not faces(from_pos):
		return amount
	_flash = maxf(_flash, 0.5)
	AudioManager.play("impact_magic", -6.0, 1.3)
	return amount * PROJECTILE_MULT

## Multiplicador del siguiente golpe tras un parry (lo consume: solo vale una vez).
func consume_bonus() -> float:
	if _bonus_t <= 0.0:
		return 1.0
	_bonus_t = 0.0
	return BONUS_MULT

func has_bonus() -> bool:
	return _bonus_t > 0.0

## Corta la guardia (la esquiva).
func cancel() -> void:
	if is_active():
		_end()

func _end() -> void:
	_cooldown = COOLDOWN_OK if _success else COOLDOWN_FAIL
	_t = -1.0
	var tw := _aura.create_tween()
	tw.tween_property(_aura, "scale", Vector3.ONE * 1.25, 0.15)
	tw.tween_callback(func(): _aura.visible = false)

func _process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	_bonus_t = maxf(_bonus_t - delta, 0.0)
	_flash = maxf(_flash - delta * 3.0, 0.0)
	if not is_active():
		return
	_t += delta
	if _t >= POSE_TIME:
		_end()
		return
	# Brillo: fuerte mientras protege, tenue después; destello dorado al parar un golpe
	var base := 1.3 if is_guarding() else 0.45
	_aura_mat.set_shader_parameter("strength", base + _flash * 2.5)
	_aura_mat.set_shader_parameter("col", COLOR.lerp(SUCCESS_COLOR, _flash))
