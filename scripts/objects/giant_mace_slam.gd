class_name GiantMaceSlam
extends Node3D

## Maza Gigante (supervivencia): una maza DIBUJADA (2D horneada, tools/make_weapon_sprites.py -> maza.png)
## aparece en el aire junto al punto de golpe, se echa atrás, baja girando sobre el agarre y pega fuerte en
## el suelo: daño en área con empuje hacia fuera, grieta dibujada, onda de tinta, polvo, estrella de impacto
## y temblor de cámara. La crea GiantMaceStrategy (una por maza; con mejoras salen varias seguidas).
##
## El dibujo es un recorte plano (no billboard) en un pivote que mira a la cámara en horizontal, así el golpe
## se ve de lado: la cabeza cae de arriba a la derecha de la pantalla hasta el suelo.

const W := WeaponData.WeaponType.GIANT_MACE
const CELL_PX := 256.0
const PIXEL := 0.017                  ## celda de 256 px ≈ 4,35 m: la maza dibujada mide ~3,9 m
const GRIP_BELOW_CENTER := 0.44       ## el agarre está 0,44 celdas por debajo del centro del dibujo
const HEAD_FROM_GRIP := 0.70          ## centro de la cabeza, a 0,70 celdas del agarre
const HEAD_RADIUS := 0.23             ## celdas (bola + pinchos): altura del agarre sobre el suelo al pegar
const APPEAR := 0.12                  ## aparece de golpe (crece con rebote)
const WINDUP := 0.2                   ## se echa atrás (anticipación)
const SWING := 0.13                   ## baja acelerando
const HOLD := 0.32                    ## clavada en el suelo
const VANISH := 0.14
const RAISED_DEG := -20.0             ## inclinación al aparecer (0 = de pie)
const WINDUP_DEG := -42.0
const IMPACT_DEG := 90.0              ## tumbada sobre el suelo
const CRACK_LIFE := 1.4
const COLOR := Color(1.0, 0.8, 0.32)
const DUST := Color(0.62, 0.5, 0.36)

var damage := 30.0
var radius := 3.2
var knockback := 9.0
var source_player: Node = null
var _pivot: Node3D
var _sprite: Sprite3D
var _target := Vector3.ZERO
var _scale := 1.0

## Crea una maza que pegará en `at` (posición en el suelo). `size` escala la maza y el área.
static func spawn(parent: Node, at: Vector3, p_damage: float, p_radius: float, size: float, p_source: Node) -> GiantMaceSlam:
	var g := GiantMaceSlam.new()
	g.damage = p_damage
	g.radius = p_radius
	g._scale = size
	g.source_player = p_source
	g._target = at
	parent.add_child(g)
	g.global_position = at
	g._build()
	return g

func _build() -> void:
	# Pivote en el agarre, mirando a la cámara en horizontal (+Z hacia la cámara, +X a su derecha)
	var cam := get_viewport().get_camera_3d()
	var to_cam := Vector3.BACK
	if cam:
		to_cam = cam.global_position - _target
		to_cam.y = 0.0
		to_cam = to_cam.normalized() if to_cam.length_squared() > 0.01 else Vector3.BACK
	var right := Vector3.UP.cross(to_cam).normalized()
	var cell_m := CELL_PX * PIXEL * _scale
	_pivot = Node3D.new()
	add_child(_pivot)
	_pivot.global_basis = Basis(right, Vector3.UP, to_cam)
	_pivot.global_position = _target - right * HEAD_FROM_GRIP * cell_m + Vector3.UP * HEAD_RADIUS * cell_m
	_sprite = ToonFX.sheet_sprite("maza.png", 2, 1, PIXEL * _scale, false)
	_sprite.position = Vector3(0.0, GRIP_BELOW_CENTER * cell_m, 0.0)
	_pivot.add_child(_sprite)
	_pivot.rotation.z = -deg_to_rad(RAISED_DEG)
	_pivot.scale = Vector3.ONE * 0.05

	var tw := create_tween()
	tw.tween_property(_pivot, "scale", Vector3.ONE, APPEAR).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_pivot, "rotation:z", -deg_to_rad(WINDUP_DEG), WINDUP).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func(): _sprite.frame = 1)
	tw.tween_property(_pivot, "rotation:z", -deg_to_rad(IMPACT_DEG), SWING).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(_impact)
	# aplastamiento del golpe y vuelta
	tw.tween_property(_sprite, "scale", Vector3(1.0, 0.82, 1.0), 0.05)
	tw.tween_property(_sprite, "scale", Vector3.ONE, 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(HOLD)
	tw.tween_property(_pivot, "scale", Vector3.ZERO, VANISH).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)
	AudioManager.play_at("melee_swing", _target, -6.0, 0.6)

func _impact() -> void:
	_sprite.frame = 0
	var hits := 0
	for e in EnemyRegistry.all().duplicate():   # copia: los que mueren se dan de baja durante el bucle
		if not is_instance_valid(e) or not e.has_method("take_damage"):
			continue
		var off: Vector3 = e.global_position - _target
		var hr = e.get("hit_radius")
		if absf(off.y) > 2.5 or Vector2(off.x, off.z).length() > radius + (float(hr) if hr != null else 0.5):
			continue
		var out := Vector3(off.x, 0.0, off.z)
		out = out.normalized() if out.length_squared() > 0.0001 else Vector3.FORWARD
		HitFeedback.weapon_tag = W
		e.take_damage(damage, out * knockback)
		hits += 1
		if is_instance_valid(source_player) and source_player.has_method("on_damage_dealt"):
			source_player.on_damage_dealt(damage, W)
	_effects(hits)

func _effects(hits: int) -> void:
	var root := get_tree().current_scene
	if root == null:
		return
	var ground := _target + Vector3(0, 0.02, 0)
	# grieta dibujada en el suelo (vista desde arriba), se apaga sola
	var crack := ToonFX.sheet_sprite("grieta.png", 1, 1, radius * 2.0 / CELL_PX, false)
	crack.rotation = Vector3(-PI * 0.5, randf() * TAU, 0.0)
	root.add_child(crack)
	crack.global_position = ground + Vector3(0, 0.04, 0)
	var ctw := crack.create_tween()
	ctw.tween_interval(CRACK_LIFE)
	ctw.tween_property(crack, "scale", Vector3.ZERO, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	ctw.tween_callback(crack.queue_free)
	ToonFX.ring_burst(root, ground, radius * 1.15, COLOR, 0.34)
	ToonFX.ring_burst(root, ground, radius * 0.7, Color(1, 1, 1), 0.22)
	FootDustVFX.land(root, ground, 1.0)
	ToonFX.puff_burst(root, ground + Vector3(0, 0.3, 0), DUST, 12, 6.0, 0.9 * _scale)
	ToonFX.impact_pop(root, ground + Vector3(0, HEAD_RADIUS * CELL_PX * PIXEL * _scale, 0), COLOR, 2.2 * _scale)
	AudioManager.play_at("impact_mace", ground, 0.0, 0.7)
	AudioManager.play_at("impact_blunt", ground, -3.0, 0.55)
	var player := source_player as Node3D
	var k := 1.0
	if is_instance_valid(player):
		k = clampf(1.0 - player.global_position.distance_to(_target) / 22.0, 0.25, 1.0)
	HitFeedback.shake(0.5 * k)
	if hits > 0:
		HitFeedback.freeze(0.045)
