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
}

var kind: String = "barrel"
var hp: float = 20.0
var _mesh: MeshInstance3D
var _base_basis: Basis
var _broken := false

## mesh/mesh_xf: malla del prop (la misma que usa ProceduralMap); shape_def: entrada de ProceduralMap.PROPS.
func setup(p_kind: String, mesh: Mesh, mesh_xf: Transform3D, shape_def: Dictionary, xf: Transform3D, p_hp: float = 20.0) -> void:
	kind = p_kind
	hp = p_hp
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

func take_damage(amount: float, dir: Vector3 = Vector3.ZERO) -> void:
	if _broken:
		return
	hp -= amount
	if hp <= 0.0:
		_break(dir)
		return
	# Tambaleo al recibir un golpe que no lo rompe
	AudioManager.play_at("impact_blunt", global_position, -6.0, randf_range(1.1, 1.3))
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

func _spawn_debris(pos: Vector3, dir: Vector3) -> void:
	var col: Color = DEBRIS_COLORS.get(kind, Color(0.45, 0.3, 0.18))
	var root := get_parent()
	# Astillas de madera
	var chips := CPUParticles3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.08, 0.04, 0.3)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 1.0
	box.material = mat
	chips.mesh = box
	chips.one_shot = true
	chips.explosiveness = 1.0
	chips.amount = Quality.count(18)
	chips.lifetime = 0.9
	chips.direction = (Vector3(dir.x, 0.0, dir.z).normalized() * 0.6 + Vector3.UP).normalized()
	chips.spread = 70.0
	chips.initial_velocity_min = 4.0
	chips.initial_velocity_max = 8.0
	chips.gravity = Vector3(0, -20, 0)
	chips.angular_velocity_min = -900.0
	chips.angular_velocity_max = 900.0
	chips.scale_amount_min = 0.6
	chips.scale_amount_max = 1.4
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
	dust.amount = Quality.count(8)
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
	for p in [chips, dust]:
		(p as CPUParticles3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(p)
		(p as CPUParticles3D).global_position = pos
		(p as CPUParticles3D).emitting = true
		get_tree().create_timer(1.2).timeout.connect((p as Node).queue_free)
