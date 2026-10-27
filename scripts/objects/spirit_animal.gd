class_name SpiritAnimal
extends Node3D

## Espíritu animal invocado por Joel. Carga un modelo .glb (hecho en Blender), lo cubre con
## el shader espiritual compartido, hace fade-in, reproduce su animación de ataque y se
## desvanece. Las subclases implementan _on_strike() (el instante del golpe).

const SPIRIT_SHADER = preload("res://assets/shaders/spirit.gdshader")
static var _shared_mat: ShaderMaterial = null

var player: Node3D = null
var damage: float = 10.0
var scale_mult: float = 1.0
var source_weapon: int = -1
var model: Node3D = null
var anim_player: AnimationPlayer = null
var _meshes: Array[MeshInstance3D] = []

var attack_anim: String = "attack"
var strike_time: float = 0.4          ## s desde que empieza la animación hasta el golpe
var fade_in: float = 0.25
var fade_out: float = 0.5
var spirit_tint: Color = Color(0.35, 1.0, 0.85)
var struck: bool = false
var _elapsed: float = 0.0
var _total: float = 1.0
var _fade: float = 0.0
var _vanishing: bool = false

static func shared_material() -> ShaderMaterial:
	if _shared_mat == null:
		_shared_mat = ShaderMaterial.new()
		_shared_mat.shader = SPIRIT_SHADER
	return _shared_mat

## Instancia el modelo y lo coloca. `scene` es el PackedScene del .glb.
func build(scene: PackedScene) -> void:
	model = scene.instantiate()
	add_child(model)
	model.scale = Vector3.ONE * scale_mult
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		mi.material_override = shared_material()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.set_instance_shader_parameter("time_offset", randf() * 10.0)
		mi.set_instance_shader_parameter("fade", 0.0)
		mi.set_instance_shader_parameter("vanish", 0.0)
		_meshes.append(mi)
	var aps := model.find_children("*", "AnimationPlayer", true, false)
	if aps.size() > 0:
		anim_player = aps[0]
		if anim_player.has_animation(attack_anim):
			_total = anim_player.get_animation(attack_anim).length
			anim_player.play(attack_anim)

func _process(delta: float) -> void:
	_elapsed += delta
	_motion(delta)
	if not struck and _elapsed >= strike_time:
		struck = true
		_on_strike()
	# fade-in al aparecer; al terminar la animación se DISUELVE (vanish) con una ráfaga de motas
	var f := 1.0
	if _elapsed < fade_in:
		f = _elapsed / fade_in
	_fade = clampf(f, 0.0, 1.0)
	var out_start := maxf(_total, strike_time + 0.2)
	var v := 0.0
	if _elapsed > out_start:
		if not _vanishing:
			_vanishing = true
			_start_vanish()
		v = clampf((_elapsed - out_start) / fade_out, 0.0, 1.0)
	for mi in _meshes:
		mi.set_instance_shader_parameter("fade", _fade)
		mi.set_instance_shader_parameter("vanish", v)
	if _elapsed >= out_start + fade_out:
		queue_free()

func _start_vanish() -> void:
	spawn_vanish_burst(get_parent(), global_position + Vector3(0, 1.0 * scale_mult, 0), 0.9 * scale_mult)

## Ráfaga de motas luminosas que suben (un disparo, baratas y compartidas).
static func spawn_vanish_burst(parent: Node, at: Vector3, radius: float = 0.9) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var tint := Color(0.35, 1.0, 0.85)
	var grains := DustVFX.grains(36, 0.9, radius, 0.1, 0.22, tint, 1.6)
	grains.gravity = Vector3(0, 1.2, 0)          # las almas ascienden
	grains.one_shot = true
	grains.explosiveness = 0.85
	var sparks := DustVFX.sparkles(6, 0.8, radius * 0.8, 0.35, 0.6, tint)
	sparks.gravity = Vector3(0, 1.0, 0)
	sparks.one_shot = true
	sparks.explosiveness = 0.9
	for ps in [grains, sparks]:
		parent.add_child(ps)
		ps.global_position = at
		ps.emitting = true
		parent.get_tree().create_timer(1.6).timeout.connect(ps.queue_free)

func _on_strike() -> void:
	pass

## Movimiento por fotograma (los animales que se desplazan lo sobrescriben).
func _motion(_delta: float) -> void:
	pass

## Daña a un enemigo y aplica robo de vida; devuelve true si lo golpeó.
func hit_enemy(e, dmg: float, kb: Vector3) -> bool:
	if not is_instance_valid(e) or not e.has_method("take_damage"):
		return false
	HitFeedback.weapon_tag = source_weapon
	e.take_damage(dmg, kb)
	if is_instance_valid(player) and source_weapon >= 0 and player.has_method("on_damage_dealt"):
		player.on_damage_dealt(dmg, source_weapon)
	return true
