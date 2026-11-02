class_name TreasureChest
extends Node3D

## Cofre de la cámara del tesoro. Al acercarse se abre (la tapa gira, sale un destello dorado)
## y emite `opened`; la mazmorra responde ofreciendo armas al azar.

signal opened(chest: TreasureChest)

const OPEN_RADIUS := 2.4
const WOOD := Color(0.36, 0.22, 0.11)
const WOOD_DARK := Color(0.24, 0.14, 0.07)
const GOLD := Color(1.0, 0.78, 0.25)

var player: Node3D
var is_open := false
var _lid: Node3D
var _light: OmniLight3D
var _t := 0.0

static func spawn(parent: Node, pos: Vector3, p_player: Node3D) -> TreasureChest:
	var c := TreasureChest.new()
	c.player = p_player
	parent.add_child(c)
	c.global_position = pos
	return c

func _ready() -> void:
	add_to_group("treasure_chests")
	_build()

func _mat(color: Color, emit: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emit
	return m

func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = pos
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

func _build() -> void:
	var wood := _mat(WOOD)
	var dark := _mat(WOOD_DARK)
	var gold := _mat(GOLD, 0.8)
	# Pedestal de piedra
	_box(self, Vector3(1.9, 0.25, 1.3), Vector3(0, 0.125, 0), _mat(Color(0.28, 0.26, 0.26)))
	# Cuerpo
	_box(self, Vector3(1.5, 0.7, 0.95), Vector3(0, 0.6, 0), wood)
	for x in [-0.62, 0.0, 0.62]:
		_box(self, Vector3(0.12, 0.72, 1.0), Vector3(x, 0.6, 0), gold)
	_box(self, Vector3(1.52, 0.1, 0.97), Vector3(0, 0.27, 0), dark)
	# Tapa (pivota en la bisagra trasera)
	_lid = Node3D.new()
	_lid.position = Vector3(0, 0.95, -0.47)
	add_child(_lid)
	_box(_lid, Vector3(1.5, 0.22, 0.95), Vector3(0, 0.11, 0.47), wood)
	_box(_lid, Vector3(1.3, 0.14, 0.8), Vector3(0, 0.27, 0.47), wood)
	for x in [-0.62, 0.0, 0.62]:
		_box(_lid, Vector3(0.12, 0.3, 0.97), Vector3(x, 0.17, 0.47), gold)
	# Cerradura
	_box(self, Vector3(0.22, 0.26, 0.06), Vector3(0, 0.88, 0.5), gold)
	_light = OmniLight3D.new()
	_light.light_color = GOLD
	_light.light_energy = 1.6
	_light.omni_range = 7.0
	_light.shadow_enabled = false
	_light.position = Vector3(0, 1.4, 0)
	add_child(_light)
	if Quality.level() != Quality.Level.LOW:
		var p := CPUParticles3D.new()
		p.name = "Sparkles"
		p.position = Vector3(0, 1.0, 0)
		p.amount = maxi(4, Quality.count(10))
		p.lifetime = 1.8
		p.direction = Vector3.UP
		p.spread = 30.0
		p.initial_velocity_min = 0.3
		p.initial_velocity_max = 0.9
		p.gravity = Vector3(0, 0.1, 0)
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 0.6
		var m := SphereMesh.new()
		m.radius = 0.04
		m.height = 0.08
		m.radial_segments = 4
		m.rings = 2
		var pm := StandardMaterial3D.new()
		pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		pm.albedo_color = GOLD
		m.material = pm
		p.mesh = m
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(p)

func _process(delta: float) -> void:
	_t += delta
	if is_open:
		return
	_light.light_energy = 1.4 + 0.4 * sin(_t * 3.0)
	if not is_instance_valid(player):
		return
	var d := Vector2(player.global_position.x - global_position.x, player.global_position.z - global_position.z)
	if d.length() <= OPEN_RADIUS:
		open()

func open() -> void:
	if is_open:
		return
	is_open = true
	AudioManager.play("level-up", -4.0, 1.2)
	var tw := create_tween()
	tw.tween_property(_lid, "rotation:x", -1.9, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_light, "light_energy", 4.0, 0.3)
	tw.tween_property(_light, "light_energy", 2.0, 0.6)
	tw.tween_callback(func(): opened.emit(self))
