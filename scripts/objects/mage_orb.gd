class_name MageOrb
extends Node3D

## Orbe arcano del mago de la mazmorra: viaja en línea recta a velocidad esquivable, se deshace al
## tocar una pared o un prop (capa 1) y daña al jugador una vez si le alcanza. La invulnerabilidad
## de la esquiva lo atraviesa (Player.take_damage ya la respeta).

const HIT_RADIUS := 0.55              ## + el radio del jugador, en horizontal
const LIFETIME := 2.4

var dir := Vector3.FORWARD
var speed := 11.0
var damage := 2.0
var color := Color(0.55, 0.35, 1.0)
var owner_rid: RID
var _t := 0.0
var _player: Node3D
var shooter: Node                     ## quién lo lanzó (RunLog: causa de la muerte)
var visual_only := false              ## copia en un cliente: solo se ve, el daño lo decide el anfitrión

static func spawn(parent: Node, from: Vector3, p_dir: Vector3, p_speed: float, p_damage: float, p_color: Color, p_owner: RID) -> MageOrb:
	var o := MageOrb.new()
	o.dir = Vector3(p_dir.x, 0.0, p_dir.z).normalized()
	o.speed = p_speed
	o.damage = p_damage
	o.color = p_color
	o.owner_rid = p_owner
	parent.add_child(o)
	o.global_position = from
	AudioManager.play_at("orb_cast", from, -6.0, randf_range(0.92, 1.08))
	if Net.is_host():
		var nw := o.get_tree().current_scene.get_node_or_null("NetWorld")
		if nw:
			nw.fx_orb(from, p_dir, p_speed, p_damage, p_color)
	return o

func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player") as Node3D
	var core := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.2
	sphere.height = 0.4
	core.mesh = sphere
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color.lightened(0.5)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 3.0
	core.material_override = m
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(core)
	var light := Quality.new_light()
	light.light_color = color
	light.light_energy = 1.6
	light.omni_range = 3.0
	add_child(light)
	var trail := DustVFX.sparkles(14, 0.35, 0.15, 0.05, 0.12, color)
	trail.local_coords = false
	add_child(trail)
	trail.emitting = true

func _physics_process(delta: float) -> void:
	_t += delta
	if _t > LIFETIME:
		_burst()
		return
	var step := dir * speed * delta
	var q := PhysicsRayQueryParameters3D.create(global_position, global_position + step, 1)
	q.exclude = [owner_rid]
	if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
		AudioManager.play_at("impact_magic", global_position, -8.0, randf_range(1.3, 1.5))
		_burst()
		return
	global_position += step
	if visual_only:
		return
	# Con varios jugadores, daña al primero al que alcance
	for target in NetPlayers.alive():
		var off: Vector3 = (target as Node3D).global_position - global_position
		if absf(off.y + 1.0) < 1.4 and Vector2(off.x, off.z).length() < HIT_RADIUS + 0.45:
			var dmg := damage
			if target.has_method("parry_projectile_damage"):
				dmg = target.parry_projectile_damage(damage, global_position)
			RunLog.hit_by(shooter)
			target.take_damage(dmg, dir)
			AudioManager.play_at("impact_magic", global_position, -2.0, 1.1)
			_burst()
			return

func _burst() -> void:
	set_physics_process(false)
	var root := get_tree().current_scene
	if root:
		var puff := DustVFX.sparkles(16, 0.4, 0.3, 0.06, 0.16, color)
		puff.one_shot = true
		puff.explosiveness = 1.0
		root.add_child(puff)
		puff.global_position = global_position
		puff.emitting = true
		get_tree().create_timer(0.8).timeout.connect(puff.queue_free)
	queue_free()
