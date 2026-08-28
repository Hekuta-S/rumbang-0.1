extends Area3D

@export var damage: float = 20.0
@export var delay: float = 1.0
@export var duration: float = 1.0

var timer: float = 0.0
var active: bool = false
var has_damaged: bool = false

@onready var visual: MeshInstance3D = $MeshInstance3D
var particles: CPUParticles3D

func _ready():
	if visual:
		visual.scale = Vector3(2.0, 0.1, 2.0)
		if visual.material_override:
			var mat = visual.material_override.duplicate()
			mat.albedo_color = Color(0.6, 0.1, 0.9, 0.5)
			visual.material_override = mat

	particles = CPUParticles3D.new()
	particles.emitting = false
	particles.one_shot = true
	particles.explosiveness = 0.85
	particles.amount = 45
	particles.lifetime = 0.8
	particles.mesh = QuadMesh.new()
	particles.mesh.size = Vector2(0.6, 0.6)
	particles.direction = Vector3(0, 1, 0)
	particles.spread = 20.0
	particles.gravity = Vector3(0, 2.0, 0)
	particles.initial_velocity_min = 4.0
	particles.initial_velocity_max = 7.0
	particles.scale_amount_min = 1.0
	particles.scale_amount_max = 2.5
	
	var p_mat = StandardMaterial3D.new()
	p_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	p_mat.albedo_color = Color(0.7, 0.1, 1.0, 0.8)
	p_mat.emission_enabled = true
	p_mat.emission = Color(0.6, 0.1, 0.9)
	p_mat.emission_energy_multiplier = 3.0
	p_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	particles.material_override = p_mat
	
	var p_curve = Curve.new()
	p_curve.add_point(Vector2(0, 0.2))
	p_curve.add_point(Vector2(0.2, 1.0))
	p_curve.add_point(Vector2(1, 0.0))
	particles.scale_amount_curve = p_curve
	
	add_child(particles)

func _physics_process(delta):
	timer += delta
	
	if not active:
		if timer >= delay:
			active = true
			timer = 0.0
			if visual:
				visual.visible = false
			
			if particles:
				particles.emitting = true
	else:
		if not has_damaged:
			for body in get_overlapping_bodies():
				if body.is_in_group("player") and body.has_method("take_damage"):
					body.take_damage(damage)
			has_damaged = true
			
		if timer >= duration:
			if not particles.emitting:
				queue_free()
