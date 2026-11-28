class_name VinePatch
extends Node3D

## Enredadera del Collar de la Madremonte (ItemEffects): enredadera DIBUJADA en el suelo (ToonFX objetos.png) que ralentiza a los
## enemigos que la pisan durante LIFETIME s. Pocas a la vez (ItemEffects.VINE_MAX, grupo "vine_patches").

const RADIUS := 2.2
const LIFETIME := 4.0
const TICK := 0.3
const SLOW := 0.45
const COLOR := Color(0.35, 0.75, 0.3)

var _t := 0.0
var _tick := 0.0
var _decal: Sprite3D
var _gone := false

static func spawn(parent: Node, at: Vector3) -> VinePatch:
	var v := VinePatch.new()
	parent.add_child(v)
	v.global_position = Vector3(at.x, at.y + 0.04, at.z)
	return v

func _ready() -> void:
	add_to_group("vine_patches")
	# Enredadera dibujada tumbada en el suelo (objetos.png), girada al azar; crece al salir
	_decal = ToonFX.item_decal(ToonFX.ITEM_FX_VINE_A + randi() % 2, RADIUS * 2.2)
	_decal.rotation.y = randf() * TAU
	_decal.scale = Vector3.ONE * 0.2
	add_child(_decal)
	var tw := _decal.create_tween()
	tw.tween_property(_decal, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var root := get_tree().current_scene
	if root:
		ToonFX.puff_burst(root, global_position + Vector3(0, 0.2, 0), COLOR, 5, 2.0, 0.4)

func _process(delta: float) -> void:
	_t += delta
	# Al final se encoge (un dibujo no se difumina)
	if not _gone and _t >= LIFETIME - 0.3:
		_gone = true
		var tw := _decal.create_tween()
		tw.tween_property(_decal, "scale", Vector3.ZERO, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tick += delta
	if _tick >= TICK:
		_tick = 0.0
		for e in EnemyRegistry.all():
			if not (e is EnemyData) or e.recycled:
				continue
			var off: Vector3 = e.global_position - global_position
			if absf(off.y) < 2.0 and Vector2(off.x, off.z).length() <= RADIUS:
				e.apply_slow(TICK + 0.2, SLOW)
	if _t >= LIFETIME:
		queue_free()
