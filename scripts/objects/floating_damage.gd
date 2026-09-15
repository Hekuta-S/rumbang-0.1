extends Label3D

var velocity: Vector3 = Vector3.ZERO
var gravity: float = 6.0
var lifetime: float = 0.75
var time_alive: float = 0.0

static func spawn(parent: Node, world_pos: Vector3, amount: float, color: Color = Color(1.0, 0.9, 0.2), is_crit: bool = false, custom_text: String = "") -> Label3D:
	if not parent or not is_instance_valid(parent):
		return null
		
	var label = PoolManager.get_floating_damage()
	if not label:
		return null
	
	if custom_text != "":
		label.text = custom_text
	else:
		label.text = str(int(round(amount)))
		
	if is_crit and custom_text == "":
		label.text += "!"
		
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.render_priority = 100
	label.outline_render_priority = 99
	
	label.modulate = color
	label.outline_modulate = Color(0.02, 0.02, 0.04, 1.0)
	label.outline_size = 14 if is_crit else 10
	label.font_size = 46 if is_crit else 34
	
	# Slight random offset so numbers don't stack on top of each other
	var offset = Vector3(randf_range(-0.35, 0.35), randf_range(0.1, 0.4), randf_range(-0.35, 0.35))
	label.global_position = world_pos + offset
	
	var dmg_script = label as Object
	dmg_script.velocity = Vector3(
		randf_range(-1.2, 1.2),
		randf_range(4.0, 5.5) if is_crit else randf_range(2.8, 4.2),
		randf_range(-1.2, 1.2)
	)
	dmg_script.lifetime = 0.85 if is_crit else 0.7
	
	return label

func _ready() -> void:
	scale = Vector3(0.3, 0.3, 0.3)
	var tween = create_tween().set_parallel(true)
	tween.tween_property(self, "scale", Vector3(1.25, 1.25, 1.25), 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.chain().tween_property(self, "scale", Vector3(1.0, 1.0, 1.0), 0.12)

func _process(delta: float) -> void:
	time_alive += delta
	global_position += velocity * delta
	velocity.y -= gravity * delta
	
	var progress = time_alive / lifetime
	if progress > 0.4:
		var alpha = remap(progress, 0.4, 1.0, 1.0, 0.0)
		modulate.a = alpha
		outline_modulate.a = alpha
		
	if time_alive >= lifetime:
		PoolManager.return_floating_damage(self)
