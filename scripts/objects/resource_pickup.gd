class_name ResourcePickup
extends Area3D

## Recogible que sueltan los enemigos de la mazmorra: balas (para las armas de fuego que lleves) o maná.
## Se queda en el suelo; al acercarte vuela hacia ti y se recoge al tocarte.

enum Kind { AMMO, MANA }

const MAGNET_RADIUS := 4.5
const SPEED := 11.0
const AMMO_FRACTION := 0.3           ## de la capacidad de cada arma de fuego que llevas
const MANA_AMOUNT := 30.0
const LIFETIME := 25.0

var kind: int = Kind.AMMO
var _player: Node3D
var _magnet := false
var _magnet_t := 0.0
var _age := 0.0
var _mesh: MeshInstance3D
var _vel := Vector3.ZERO        ## salida en abanico al soltarse (RewardJuice)
var _rest_y := 0.0
const POP_TIME := 0.5           ## s de vuelo/rebote antes de que el imán pueda engancharlo

static func spawn(parent: Node, pos: Vector3, p_kind: int) -> ResourcePickup:
	var p := ResourcePickup.new()
	p.kind = p_kind
	p.collision_layer = 0
	p.collision_mask = 2                  ## el jugador
	parent.add_child(p)
	p.global_position = pos + Vector3(0, 0.5, 0)
	p._rest_y = p.global_position.y
	p._vel = RewardJuice.pop_velocity()
	return p

func _ready() -> void:
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.6
	col.shape = shape
	add_child(col)
	_mesh = MeshInstance3D.new()
	var color := Color(1.0, 0.75, 0.2) if kind == Kind.AMMO else Color(0.4, 0.55, 1.0)
	if kind == Kind.AMMO:
		var box := BoxMesh.new()
		box.size = Vector3(0.28, 0.2, 0.2)
		_mesh.mesh = box
	else:
		var sph := SphereMesh.new()
		sph.radius = 0.16
		sph.height = 0.32
		sph.radial_segments = 10
		sph.rings = 5
		_mesh.mesh = sph
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.5
	_mesh.material_override = mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	_age += delta
	if _age > LIFETIME:
		queue_free()
		return
	_mesh.rotation.y += delta * 2.5
	_mesh.position.y = 0.08 * sin(_age * 4.0)
	if _age < POP_TIME or not RewardJuice.settled(self, _vel, _rest_y):
		_vel = RewardJuice.bounce(self, _vel, _rest_y, delta)
		return
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if _player == null:
			return
	var to_p := _player.global_position + Vector3(0, 0.9, 0) - global_position
	if not _magnet and to_p.length() < MAGNET_RADIUS:
		_magnet = true
	if _magnet:
		_magnet_t += delta
		global_position += to_p.normalized() * minf(RewardJuice.magnet_speed(SPEED, _magnet_t) * delta, to_p.length())
		if to_p.length() < 0.7:
			_collect(_player)

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_collect(body)

func _collect(player: Node) -> void:
	var res = player.get("resources")
	if res == null:
		return
	if kind == Kind.AMMO:
		var owned: Array = player.weapon_inventory.weapon_slots if player.get("weapon_inventory") else []
		res.add_ammo_fraction(AMMO_FRACTION, owned)
	else:
		res.add_mana(MANA_AMOUNT)
	var color := Color(1.0, 0.75, 0.2) if kind == Kind.AMMO else Color(0.4, 0.55, 1.0)
	RewardJuice.collect(get_parent(), global_position, color, "ui_click", -12.0, 1.4)
	queue_free()
