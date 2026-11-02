class_name HealSoul
extends Area3D

## Alma verde que sueltan los tótems al romperse: sale disparada hacia arriba, flota un instante
## y luego vuela hacia el jugador para curarle un porcentaje de su vida máxima.

const HEAL_FRACTION := 0.06          ## de la vida máxima por alma
const MAGNET_RADIUS := 5.0
const SPEED := 12.0
const LIFETIME := 30.0
const COLOR := Color(0.35, 1.0, 0.5)

var _vel := Vector3.ZERO
var _age := 0.0
var _player: Node3D
var _magnet := false
var _mesh: MeshInstance3D

static var _shared_mesh: SphereMesh = null
static var _shared_mat: StandardMaterial3D = null

## Suelta `count` almas desde `pos`, repartidas en abanico.
static func burst(parent: Node, pos: Vector3, count: int) -> void:
	for k in count:
		var s := HealSoul.new()
		s.collision_layer = 0
		s.collision_mask = 2
		parent.add_child(s)
		s.global_position = pos
		var a := TAU * k / maxi(count, 1) + randf() * 0.6
		s._vel = Vector3(cos(a) * randf_range(1.5, 3.0), randf_range(4.0, 6.0), sin(a) * randf_range(1.5, 3.0))

static func _ensure_shared() -> void:
	if _shared_mesh != null:
		return
	_shared_mesh = SphereMesh.new()
	_shared_mesh.radius = 0.18
	_shared_mesh.height = 0.36
	_shared_mesh.radial_segments = 10
	_shared_mesh.rings = 5
	_shared_mat = StandardMaterial3D.new()
	_shared_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shared_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shared_mat.albedo_color = Color(COLOR.r, COLOR.g, COLOR.b, 0.85)
	_shared_mat.emission_enabled = true
	_shared_mat.emission = COLOR
	_shared_mat.emission_energy_multiplier = 3.0

func _ready() -> void:
	_ensure_shared()
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.7
	col.shape = shape
	add_child(col)
	_mesh = MeshInstance3D.new()
	_mesh.mesh = _shared_mesh
	_mesh.material_override = _shared_mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	var light := OmniLight3D.new()
	light.light_color = COLOR
	light.light_energy = 0.9
	light.omni_range = 3.5
	light.shadow_enabled = false
	add_child(light)
	if Quality.level() != Quality.Level.LOW:
		var p := CPUParticles3D.new()
		p.amount = maxi(3, Quality.count(6))
		p.lifetime = 0.9
		p.local_coords = false
		p.direction = Vector3.UP
		p.spread = 40.0
		p.initial_velocity_min = 0.2
		p.initial_velocity_max = 0.6
		p.gravity = Vector3(0, 0.6, 0)
		p.scale_amount_min = 0.08
		p.scale_amount_max = 0.2
		p.mesh = _shared_mesh
		p.material_override = _shared_mat
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(p)
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	_age += delta
	if _age > LIFETIME:
		queue_free()
		return
	_mesh.scale = Vector3.ONE * (1.0 + 0.15 * sin(_age * 7.0))
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if _player == null:
			return
	var to_p := _player.global_position + Vector3(0, 0.9, 0) - global_position
	# Primero sube y se frena; a los 0.8 s ya se deja atraer
	if _age < 0.8:
		_vel.y -= 9.0 * delta
		_vel *= 1.0 - 2.5 * delta
		global_position += _vel * delta
		return
	if not _magnet and to_p.length() < MAGNET_RADIUS:
		_magnet = true
	if _magnet:
		global_position += to_p.normalized() * SPEED * delta
		if to_p.length() < 0.7:
			_collect(_player)
	else:
		global_position.y += sin(_age * 3.0) * 0.2 * delta

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_collect(body)

func _collect(player: Node) -> void:
	var hc = player.get("health_comp")
	var max_hp: float = float(hc.max_hp) if hc != null else 100.0
	if player.has_method("heal"):
		player.heal(max_hp * HEAL_FRACTION)
	AudioManager.play("ui_click", -10.0, 1.9)
	set_physics_process(false)
	queue_free()
