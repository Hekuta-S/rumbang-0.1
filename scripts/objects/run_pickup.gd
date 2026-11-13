class_name RunPickup
extends Node3D

## Recogible de la estructura de partida (DungeonRun): pergaminos de enfoque y planos. Un pergamino
## flotante que gira; al acercarse el jugador emite `picked(player)` y desaparece.

signal picked(by: Node3D)

const RADIUS := 1.3

var text := ""
var color := Color.WHITE
var player: Node3D
var _t := 0.0
var _holder: Node3D
var _done := false

static func spawn(parent: Node, pos: Vector3, p_text: String, p_color: Color) -> RunPickup:
	var p := RunPickup.new()
	p.text = p_text
	p.color = p_color
	p.player = parent.get_tree().get_first_node_in_group("player") if parent.is_inside_tree() else null
	parent.add_child(p)
	p.global_position = Vector3(pos.x, 0.0, pos.z)
	return p

func _ready() -> void:
	add_to_group("run_pickups")
	_holder = Node3D.new()
	_holder.position = Vector3(0, 1.0, 0)
	add_child(_holder)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.88, 0.7)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.6
	var roll := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.09
	cyl.bottom_radius = 0.09
	cyl.height = 0.55
	roll.mesh = cyl
	roll.rotation.z = PI * 0.5
	roll.material_override = mat
	roll.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_holder.add_child(roll)
	var sheet := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.45, 0.4, 0.02)
	sheet.mesh = box
	sheet.position = Vector3(0, -0.2, 0)
	sheet.material_override = mat
	sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_holder.add_child(sheet)
	var label := Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 40
	label.outline_size = 10
	label.modulate = color
	label.position = Vector3(0, 0.75, 0)
	_holder.add_child(label)
	var light := Quality.new_light()
	light.light_color = color
	light.light_energy = 1.5
	light.omni_range = 4.0
	_holder.add_child(light)

func _process(delta: float) -> void:
	_t += delta
	if _holder:
		_holder.rotation.y += delta * 1.6
		_holder.position.y = 1.0 + 0.12 * sin(_t * 2.5)
	if _done or not is_instance_valid(player):
		return
	var d := Vector2(player.global_position.x - global_position.x, player.global_position.z - global_position.z).length()
	if d <= RADIUS:
		collect(player)

## Lo recoge `by` (también lo usan las pruebas).
func collect(by: Node3D) -> void:
	if _done:
		return
	_done = true
	AudioManager.play("level-up", -6.0, 1.4)
	picked.emit(by)
	queue_free()
