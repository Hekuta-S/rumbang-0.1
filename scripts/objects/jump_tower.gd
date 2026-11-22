class_name JumpTower
extends Node3D

## Torre de saltos (supervivencia): plataformas flotantes en espiral que suben STEP_H m cada una (cabe en un
## salto normal: BASE_JUMP_VELOCITY^2 / 2g = 1.64 m). En lo alto hay un cofre dorado; abrirlo emite `claimed`.
## Premia saltar bien: el cofre solo se abre si el jugador está a su altura (no desde el suelo).

signal claimed(tower: JumpTower)

const RING_PLATFORMS := 4
const STEP_H := 1.3
const RING_RADIUS := 3.7
const RING_ARC_DEG := 62.0
const PLATFORM_SIZE := Vector3(3.0, 0.5, 3.0)
const TOP_SIZE := Vector3(3.2, 0.5, 3.2)
const STONE := Color(0.34, 0.32, 0.36)
const RIM := Color(1.0, 0.8, 0.3)

var player: Node3D
var chest: TreasureChest
var top_y := 0.0

static func spawn(parent: Node, pos: Vector3, p_player: Node3D) -> JumpTower:
	var t := JumpTower.new()
	t.player = p_player
	parent.add_child(t)
	t.global_position = pos
	return t

func _ready() -> void:
	add_to_group("jump_towers")
	var start_a := randf() * TAU
	for i in RING_PLATFORMS:
		var a := start_a + deg_to_rad(RING_ARC_DEG) * float(i)
		var h := STEP_H * float(i + 1)
		_platform(Vector3(cos(a) * RING_RADIUS, h - PLATFORM_SIZE.y * 0.5, sin(a) * RING_RADIUS), PLATFORM_SIZE, a)
	top_y = STEP_H * float(RING_PLATFORMS + 1)
	_platform(Vector3(0, top_y - TOP_SIZE.y * 0.5, 0), TOP_SIZE, 0.0)
	var label := Label3D.new()
	label.text = "COFRE DE ALTURA"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = true
	label.pixel_size = 0.0011
	label.font_size = 22
	label.outline_size = 8
	label.modulate = RIM
	label.outline_modulate = Color(0.05, 0.02, 0.05)
	label.no_depth_test = true
	label.position = Vector3(0, top_y + 2.3, 0)
	add_child(label)
	chest = TreasureChest.spawn(self, Vector3.ZERO, player)
	chest.position = Vector3(0, top_y, 0)
	chest.max_dy = 1.8
	chest.opened.connect(func(_c): claimed.emit(self))

func _platform(pos: Vector3, size: Vector3, yaw: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = pos
	body.rotation.y = yaw
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = STONE
	m.roughness = 0.9
	mi.material_override = m
	body.add_child(mi)
	# Borde dorado fino arriba para que se lea desde lejos
	var rim := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(size.x + 0.08, 0.06, size.z + 0.08)
	rim.mesh = rm
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = RIM
	rmat.emission_enabled = true
	rmat.emission = RIM
	rmat.emission_energy_multiplier = 0.7
	rim.material_override = rmat
	rim.position.y = size.y * 0.5
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(rim)
	add_child(body)
