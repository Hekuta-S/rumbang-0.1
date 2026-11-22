class_name GroundBlast
extends Node3D

## Erupción en el suelo: durante `delay` segundos el suelo burbujea (vapores que suben y una luz
## que late cada vez más fuerte) y, al completarse, estalla en una columna de llamas con onda
## expansiva; daña una vez al jugador si sigue dentro. La usa el jefe necromántico (varias a la vez).
## El burbujeo y el estallido se ven siempre; el círculo del suelo es la marca de ataque y
## respeta la opción SettingsManager.show_attack_marks.

const TELEGRAPH_SHADER: Shader = preload("res://assets/shaders/enemy_telegraph.gdshader")

var radius := 1.6
var delay := 1.0
var damage := 3.0
var color := Color(0.3, 1.0, 0.6)
var _t := 0.0
var _mat: ShaderMaterial
var _light: OmniLight3D
var _done := false
var visual_only := false              ## copia en un cliente: solo se ve, el daño lo decide el anfitrión

static func spawn(parent: Node, at: Vector3, p_radius: float, p_delay: float, p_damage: float, p_color: Color) -> GroundBlast:
	var g := GroundBlast.new()
	g.radius = p_radius
	g.delay = p_delay
	g.damage = p_damage
	g.color = p_color
	parent.add_child(g)
	g.global_position = Vector3(at.x, at.y + 0.05, at.z)
	if Net.is_host():
		var nw := g.get_tree().current_scene.get_node_or_null("NetWorld")
		if nw:
			nw.fx_blast(at, p_radius, p_delay, p_damage, p_color)
	return g

func _ready() -> void:
	# Marca de ataque (opcional)
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(radius * 2.0, radius * 2.0)
	mi.mesh = plane
	_mat = ShaderMaterial.new()
	_mat.shader = TELEGRAPH_SHADER
	_mat.set_shader_parameter("shape", 2)
	_mat.set_shader_parameter("color", Vector3(color.r, color.g, color.b))
	_mat.set_shader_parameter("progress", 0.0)
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = SettingsManager.show_attack_marks
	add_child(mi)
	# Burbujeo (siempre): nubecitas dibujadas que suben por toda la zona (2D horneado, puff.png)
	var vapor := ToonFX.puff_rise(radius, color)
	add_child(vapor)
	vapor.emitting = true
	_light = Quality.new_light()
	_light.light_color = color
	_light.light_energy = 0.2
	_light.omni_range = radius * 2.2
	_light.position = Vector3(0, 0.4, 0)
	add_child(_light)

func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	var k := clampf(_t / delay, 0.0, 1.0)
	_mat.set_shader_parameter("progress", k)
	# La luz late cada vez más rápido y más fuerte
	_light.light_energy = (0.3 + 2.2 * k) * (0.6 + 0.4 * sin(_t * (6.0 + 22.0 * k)))
	if _t >= delay:
		_explode()

func _explode() -> void:
	_done = true
	if not visual_only:
		for target in NetPlayers.alive():
			var toff: Vector3 = (target as Node3D).global_position - global_position
			if absf(toff.y) < 1.6 and Vector2(toff.x, toff.z).length() <= radius + 0.45:
				target.take_damage(damage, Vector3(toff.x, 0.0, toff.z).normalized())
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if is_instance_valid(player):
		var off := player.global_position - global_position
		var d := Vector2(off.x, off.z).length()
		HitFeedback.shake(0.3 * clampf(1.0 - d / 14.0, 0.0, 1.0))
	AudioManager.play_at("impact_magic", global_position, -1.0, 0.55)
	var root := get_tree().current_scene
	if root:
		# Columna de llamas, onda y estrella de impacto dibujadas (cómic)
		ToonFX.flame_column(root, global_position, radius, color)
		ToonFX.ring_burst(root, global_position, radius * 1.6, color, 0.4)
		ToonFX.impact_pop(root, global_position + Vector3(0, 0.8, 0), color, 1.8)
		var flash := Quality.new_light()
		flash.light_color = color
		flash.light_energy = 6.0
		flash.omni_range = radius * 4.0
		root.add_child(flash)
		flash.global_position = global_position + Vector3(0, 1.0, 0)
		var tw := flash.create_tween()
		tw.tween_property(flash, "light_energy", 0.0, 0.45)
		tw.tween_callback(flash.queue_free)
	queue_free()
