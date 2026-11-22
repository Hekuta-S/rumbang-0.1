extends Area3D

@export var damage: float = 20.0
@export var delay: float = 1.0
@export var duration: float = 1.0

var timer: float = 0.0
var active: bool = false
var has_damaged: bool = false

@onready var visual: MeshInstance3D = $MeshInstance3D
var _bubbles: CPUParticles3D
const ERUPTION_COLOR := Color(0.7, 0.3, 1.0)

func _ready():
	if visual:
		# Aviso en el suelo: anillo entintado (ring.png) del radio del estallido, en vez del disco translúcido
		var ring := ToonFX.ring_material()
		if ring:
			var plane := PlaneMesh.new()
			plane.size = Vector2(2.0, 2.0)
			visual.mesh = plane
			ring.albedo_color = Color(ERUPTION_COLOR.r, ERUPTION_COLOR.g, ERUPTION_COLOR.b, 0.5)
			visual.material_override = ring
			visual.scale = Vector3(2.0, 1.0, 2.0)
		else:
			visual.scale = Vector3(2.0, 0.1, 2.0)
			if visual.material_override:
				var mat = visual.material_override.duplicate()
				mat.albedo_color = Color(0.6, 0.1, 0.9, 0.5)
				visual.material_override = mat

	# Burbujeo dibujado mientras avisa (puff.png); el estallido es una columna de llamas dibujadas
	_bubbles = ToonFX.puff_rise(2.0, ERUPTION_COLOR)
	add_child(_bubbles)
	_bubbles.emitting = true

## Sacudida breve de cámara si el jugador está cerca del estallido.
func _shake_camera() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player and player.has_method("apply_camera_recoil") and global_position.distance_to(player.global_position) < 18.0:
		player.apply_camera_recoil(0.02, randf_range(-0.01, 0.01), 0.12)

func _physics_process(delta):
	timer += delta
	
	if not active:
		# Telegrafía: el disco se va llenando de color y late más rápido al acercarse el estallido
		if visual and visual.material_override is StandardMaterial3D:
			var t := clampf(timer / maxf(delay, 0.01), 0.0, 1.0)
			var pulse := 0.5 + 0.5 * sin(timer * (8.0 + 16.0 * t))
			(visual.material_override as StandardMaterial3D).albedo_color.a = lerpf(0.2, 0.6, t) + 0.15 * pulse * t
		if timer >= delay:
			active = true
			timer = 0.0
			if visual:
				visual.visible = false
			_bubbles.emitting = false
			ToonFX.flame_column(get_parent(), global_position, 2.0, ERUPTION_COLOR)
			ToonFX.ring_burst(get_parent(), global_position, 4.5, ERUPTION_COLOR, 0.4)
			ToonFX.impact_pop(get_parent(), global_position + Vector3(0, 1.0, 0), ERUPTION_COLOR, 2.0)
			_shake_camera()
	else:
		if not has_damaged:
			for body in get_overlapping_bodies():
				if body.is_in_group("player") and body.has_method("take_damage"):
					body.take_damage(damage)
			has_damaged = true
			
		if timer >= duration:
			queue_free()
