class_name DestructibleProp
extends StaticBody3D

## Barril, caja u otro prop que se rompe a golpes (modo mazmorra).
## Bloquea el paso del jugador (capa 1) y está en el grupo "destructibles":
## MeleeHitbox y las balas del jugador le llaman take_damage().
## Al romperse: astillas, polvo, sonido, un pequeño shake y desaparece.

signal destroyed(prop: DestructibleProp)

const DEBRIS_COLORS := {
	"barrel": Color(0.4, 0.24, 0.12),
	"crate": Color(0.5, 0.36, 0.2),
	"hut": Color(0.38, 0.27, 0.16),
	"tent": Color(0.45, 0.32, 0.2),
	"palisade": Color(0.42, 0.3, 0.17),
	"skull_pole": Color(0.85, 0.82, 0.7),
	"totem": Color(0.3, 0.42, 0.28),
	"trash_bag": Color(0.08, 0.1, 0.08),
	"toxic_barrel": Color(0.55, 0.5, 0.12),
}
## Vida y tamaño de los trozos al romperse (las estructuras grandes aguantan más y sueltan más escombros).
const STRUCTURE := {
	"barrel": {"hp": 18.0, "chips": 18},
	"crate": {"hp": 25.0, "chips": 18},
	"skull_pole": {"hp": 16.0, "chips": 12, "chip_len": 0.2},
	"palisade": {"hp": 45.0, "chips": 26, "chip_len": 0.4},
	"tent": {"hp": 40.0, "chips": 24, "chip_len": 0.35},
	"hut": {"hp": 80.0, "chips": 40, "chip_len": 0.45},
	"totem": {"hp": 60.0, "chips": 30, "chip_len": 0.3},
	"trash_bag": {"hp": 8.0, "chips": 12},
	"toxic_barrel": {"hp": 14.0, "chips": 16},
}

static func hp_for(p_kind: String) -> float:
	return float((STRUCTURE.get(p_kind, {}) as Dictionary).get("hp", 20.0))

const MAX_PIECES := 140
static var _alive_pieces := 0

var kind: String = "barrel"
var hp: float = 20.0
var max_hp: float = 20.0
var _mesh: MeshInstance3D
var _base_basis: Basis
var _broken := false

## mesh/mesh_xf: malla del prop (la misma que usa ProceduralMap); shape_def: entrada de ProceduralMap.PROPS.
func setup(p_kind: String, mesh: Mesh, mesh_xf: Transform3D, shape_def: Dictionary, xf: Transform3D, p_hp: float = 20.0) -> void:
	kind = p_kind
	hp = p_hp
	max_hp = p_hp
	transform = xf
	collision_layer = 1
	collision_mask = 0
	add_to_group("destructibles")
	_mesh = MeshInstance3D.new()
	_mesh.mesh = mesh
	_mesh.transform = mesh_xf
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	_base_basis = _mesh.basis
	var size: Vector3 = shape_def["size"]
	var cs := CollisionShape3D.new()
	if shape_def["shape"] == "box":
		var bx := BoxShape3D.new()
		bx.size = size
		cs.shape = bx
	else:
		var cyl := CylinderShape3D.new()
		cyl.radius = size.x
		cyl.height = size.y
		cs.shape = cyl
	cs.position.y = size.y * 0.5
	add_child(cs)

func is_broken() -> bool:
	return _broken

func take_damage(amount: float, dir: Vector3 = Vector3.ZERO) -> void:
	if _broken:
		return
	hp -= amount
	if hp <= 0.0:
		_break(dir)
		return
	# Tambaleo al recibir un golpe que no lo rompe
	AudioManager.play_at("impact_blunt", global_position, -6.0, randf_range(1.1, 1.3))
	if max_hp > 30.0:
		_spawn_debris(global_position + Vector3(0, 0.8, 0), dir, 0.25)
	_darken(1.0 - hp / max_hp)
	var push := dir
	push.y = 0.0
	var axis := Vector3.UP.cross(push.normalized()) if push.length_squared() > 0.001 else Vector3.RIGHT
	var tw := create_tween()
	tw.tween_property(_mesh, "basis", _base_basis.rotated(axis, 0.25), 0.05)
	tw.tween_property(_mesh, "basis", _base_basis.rotated(axis, -0.12), 0.08)
	tw.tween_property(_mesh, "basis", _base_basis, 0.1)

func _break(dir: Vector3) -> void:
	_broken = true
	collision_layer = 0
	remove_from_group("destructibles")
	var pos := global_position + Vector3(0, 0.5, 0)
	AudioManager.play_at("impact_slash", pos, -2.0, randf_range(0.7, 0.85))
	AudioManager.play_at("impact_blunt", pos, -4.0, randf_range(0.8, 0.95))
	_spawn_debris(pos, dir)
	destroyed.emit(self)
	# El trozo de malla se encoge y desaparece mientras salen las astillas
	var tw := create_tween()
	tw.tween_property(_mesh, "scale", Vector3(1.25, 0.2, 1.25), 0.08)
	tw.tween_callback(queue_free)

## Las estructuras dañadas se oscurecen poco a poco (grietas/quemado) hasta romperse.
func _darken(t: float) -> void:
	if _mesh == null:
		return
	var v := 1.0 - 0.5 * clampf(t, 0.0, 1.0)
	_mesh.set_instance_shader_parameter("tint", Vector3(v, v * 0.94, v * 0.88))

func _spawn_debris(pos: Vector3, dir: Vector3, frac: float = 1.0) -> void:
	var col: Color = DEBRIS_COLORS.get(kind, Color(0.45, 0.3, 0.18))
	var cfg: Dictionary = STRUCTURE.get(kind, {})
	var root := get_parent()
	# Trozos de madera con física real: caen, rebotan en el suelo, ruedan y se quedan un rato.
	var n := maxi(3, Quality.count(int(float(cfg.get("chips", 18)) * frac)))
	n = mini(n, maxi(0, MAX_PIECES - _alive_pieces))
	var plank_len: float = float(cfg.get("chip_len", 0.3))
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 1.0
	var flat := Vector3(dir.x, 0.0, dir.z)
	var bias := flat.normalized() if flat.length_squared() > 0.001 else Vector3.ZERO
	for i in n:
		var piece := _make_piece(mat, plank_len)
		root.add_child(piece)
		piece.global_position = pos + Vector3(randf_range(-0.25, 0.25), randf_range(0.0, 0.4), randf_range(-0.25, 0.25))
		piece.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		var out := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized()
		piece.linear_velocity = (out * randf_range(1.5, 4.0) + bias * randf_range(1.5, 4.5) * frac) + Vector3.UP * randf_range(3.0, 7.0)
		piece.angular_velocity = Vector3(randf_range(-12.0, 12.0), randf_range(-12.0, 12.0), randf_range(-12.0, 12.0))
	# Polvo
	var dust := CPUParticles3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.25
	sph.height = 0.5
	sph.radial_segments = 6
	sph.rings = 3
	var dmat := StandardMaterial3D.new()
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dmat.vertex_color_use_as_albedo = true
	sph.material = dmat
	dust.mesh = sph
	dust.one_shot = true
	dust.explosiveness = 0.9
	dust.amount = maxi(2, Quality.count(int(8.0 * frac * (2.0 if max_hp > 30.0 else 1.0))))
	dust.lifetime = 0.7
	dust.spread = 180.0
	dust.initial_velocity_min = 1.0
	dust.initial_velocity_max = 2.5
	dust.gravity = Vector3(0, 0.5, 0)
	dust.damping_min = 3.0
	dust.damping_max = 5.0
	var grad := Gradient.new()
	grad.set_color(0, Color(0.55, 0.48, 0.4, 0.55))
	grad.set_color(1, Color(0.55, 0.48, 0.4, 0.0))
	dust.color_ramp = grad
	for p in [dust]:
		(p as CPUParticles3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(p)
		(p as CPUParticles3D).global_position = pos
		(p as CPUParticles3D).emitting = true
		get_tree().create_timer(1.2).timeout.connect((p as Node).queue_free)

## Un trozo suelto: tabla o taco de madera. Colisiona solo con el mundo (capa 32 -> máscara 1),
## así no estorba al jugador ni a los enemigos.
func _make_piece(mat: Material, plank_len: float) -> RigidBody3D:
	var sz: Vector3
	if randf() < 0.65:
		sz = Vector3(randf_range(0.07, 0.12), randf_range(0.04, 0.07), plank_len * randf_range(0.6, 1.3))
	else:
		var c := randf_range(0.08, 0.16)
		sz = Vector3(c, c * randf_range(0.6, 1.0), c * randf_range(0.8, 1.4))
	var rb := RigidBody3D.new()
	rb.collision_layer = 1 << 31
	rb.collision_mask = 1
	rb.mass = 0.3 + sz.x * sz.y * sz.z * 60.0
	rb.continuous_cd = true
	rb.linear_damp = 0.15
	rb.angular_damp = 0.8
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.35
	pm.friction = 0.8
	rb.physics_material_override = pm
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = sz
	cs.shape = bs
	rb.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	bm.material = mat
	mi.mesh = bm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rb.add_child(mi)
	_alive_pieces += 1
	rb.tree_exited.connect(func(): _alive_pieces -= 1)
	# Permanece en el suelo unos segundos y se encoge hasta desaparecer
	var life := randf_range(4.0, 6.0)
	var tw := rb.create_tween()
	tw.tween_interval(life)
	tw.tween_property(mi, "scale", Vector3.ZERO, 0.6)
	tw.tween_callback(rb.queue_free)
	return rb
