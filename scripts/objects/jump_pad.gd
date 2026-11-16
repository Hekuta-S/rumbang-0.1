class_name JumpPad
extends Area3D

## Runa lanzadora del mapa de supervivencia (ProceduralMap la pone al pie de cada meseta y en el piso bajo
## de los zigurats). Al pisarla, el jugador sale despedido en parábola hasta `target` (la cima), atajo a la
## rampa. Desde arriba, saltar abajo hace el golpe de caída (PlayerMovementController.ground_slam).

const RADIUS := 1.25
const APEX_EXTRA := 2.5            ## m que sube por encima del destino
const COOLDOWN := 1.0
const COLOR := Color(0.45, 0.95, 1.0)
const GRAVITY := 22.0              ## = PlayerMovementController.gravity

var target := Vector3.ZERO
var _cool := 0.0
var _t := 0.0
var _glow: StandardMaterial3D
var _ring: MeshInstance3D

## Velocidad inicial para ir de `from` a `to` con gravedad `g`, subiendo `apex_extra` m sobre el más alto. Pura.
static func launch_velocity(from: Vector3, to: Vector3, g: float = GRAVITY, apex_extra: float = APEX_EXTRA) -> Vector3:
	var apex := maxf(from.y, to.y) + apex_extra
	var vy := sqrt(2.0 * g * (apex - from.y))
	var t := vy / g + sqrt(2.0 * (apex - to.y) / g)
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z) / t
	return Vector3(flat.x, vy, flat.z)

func _ready() -> void:
	add_to_group("jump_pads")
	collision_layer = 0
	collision_mask = 2                 # el jugador
	monitorable = false
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = RADIUS
	cyl.height = 1.6
	cs.shape = cyl
	cs.position.y = 0.6
	add_child(cs)
	# Losa de piedra con la runa encendida
	var slab := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = RADIUS
	sm.bottom_radius = RADIUS + 0.15
	sm.height = 0.25
	sm.radial_segments = 12
	sm.rings = 1
	slab.mesh = sm
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.22, 0.23, 0.27)
	stone.roughness = 0.95
	slab.material_override = stone
	slab.position.y = 0.05
	add_child(slab)
	_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = RADIUS * 0.55
	tm.outer_radius = RADIUS * 0.8
	tm.rings = 16
	tm.ring_segments = 4
	_ring.mesh = tm
	_ring.scale = Vector3(1.0, 0.25, 1.0)
	_ring.position.y = 0.2
	_glow = StandardMaterial3D.new()
	_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow.albedo_color = COLOR
	_ring.material_override = _glow
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	# Flecha hacia la cima
	var arrow := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(0.7, 0.6, 0.08)
	arrow.mesh = pm
	arrow.material_override = _glow
	arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	arrow.position.y = 0.22
	var flat := Vector3(target.x - global_position.x, 0.0, target.z - global_position.z) if is_inside_tree() else Vector3.FORWARD
	arrow.rotation = Vector3(-PI * 0.5, atan2(flat.x, flat.z) + PI, 0.0)
	add_child(arrow)
	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	_t += delta
	_cool = maxf(_cool - delta, 0.0)
	var k := 0.5 + 0.5 * sin(_t * 3.0)
	_glow.albedo_color = COLOR.lerp(Color.WHITE, 0.35 * k) if _cool <= 0.0 else COLOR.darkened(0.6)
	_ring.rotation.y = _t * 0.8

func _on_body_entered(body: Node) -> void:
	if _cool > 0.0 or not body.is_in_group("player"):
		return
	var mc = body.get("movement_controller")
	if mc == null or not mc.has_method("launch"):
		return
	_cool = COOLDOWN
	mc.launch(launch_velocity(body.global_position, target, float(mc.get("gravity")) if mc.get("gravity") != null else GRAVITY))
	AudioManager.play_at("level-up", global_position, -10.0, 1.5)
	HitFeedback.shake(0.08)
