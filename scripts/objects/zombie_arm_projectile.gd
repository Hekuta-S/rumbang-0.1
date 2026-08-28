extends Area3D

var damage: float = 25.0
var speed: float = 25.0
var max_range: float = 20.0
var player: Node3D = null

var direction: Vector3 = Vector3.ZERO
var start_pos: Vector3 = Vector3.ZERO
var returning: bool = false

var visual: MeshInstance3D

func _ready():
	collision_layer = 0
	collision_mask = 3
	body_entered.connect(_on_body_entered)

func setup(dir: Vector3, dmg: float, p: Node3D):
	direction = dir
	damage = dmg
	player = p
	start_pos = global_position
	
	visual = MeshInstance3D.new()
	var b_mesh = BoxMesh.new()
	b_mesh.size = Vector3(0.3, 0.3, 1.2)
	visual.mesh = b_mesh
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.7, 0.3)
	visual.material_override = mat
	add_child(visual)

func _physics_process(delta: float):
	if visual:
		visual.rotate_y(25.0 * delta)
		visual.rotate_x(15.0 * delta)

	if not returning:
		global_position += direction * speed * delta
		if global_position.distance_to(start_pos) >= max_range:
			returning = true
	else:
		if is_instance_valid(player):
			var to_player = (player.global_position + Vector3(0, 1.0, 0) - global_position).normalized()
			global_position += to_player * (speed * 1.3) * delta
			
			if global_position.distance_to(player.global_position + Vector3(0, 1.0, 0)) < 2.0:
				queue_free()
		else:
			queue_free()

func _on_body_entered(body: Node3D):
	if body.is_in_group("enemies") and body.has_method("take_damage"):
		body.take_damage(damage, direction)
