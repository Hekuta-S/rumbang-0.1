extends Node
class_name AutoCombatController

@export var detection_radius: float = 15.0
@export var player: CharacterBody3D

var enemies_in_range: Array[Node3D] = []

@onready var scanner_area: Area3D = Area3D.new()
@onready var collision_shape: CollisionShape3D = CollisionShape3D.new()

func _ready():
	if not player:
		player = get_parent() as CharacterBody3D
		
	# Configurar el área de detección esférica
	var sphere = SphereShape3D.new()
	sphere.radius = detection_radius
	collision_shape.shape = sphere
	scanner_area.add_child(collision_shape)
	add_child(scanner_area)
	
	scanner_area.collision_layer = 0
	# Dependiendo de la configuración del proyecto, si los enemigos no están en una máscara específica,
	# detectamos todo lo que tenga el método take_damage o esté en el grupo "enemies".
	# Por defecto, escaneamos las máscaras típicas de físicas.
	scanner_area.collision_mask = 0xFFFFFFFF
	
	scanner_area.body_entered.connect(_on_body_entered)
	scanner_area.body_exited.connect(_on_body_exited)

func _process(delta):
	if not is_instance_valid(player):
		return

	# Mantener el área de escaneo de combate automático centrada en la posición global del jugador
	if is_instance_valid(scanner_area):
		scanner_area.global_position = player.global_position

	if enemies_in_range.is_empty():
		return
		
	# Limpiar enemigos que hayan sido destruidos
	enemies_in_range = enemies_in_range.filter(func(e): return is_instance_valid(e) and not e.is_queued_for_deletion())
	
	if enemies_in_range.is_empty():
		player.auto_combat_target = null
		return
		
	var target = get_closest_enemy()
	if target:
		player.auto_combat_target = target
		fire_available_weapons(target)

func get_closest_enemy() -> Node3D:
	var closest = null
	var min_dist = INF
	if not is_instance_valid(player): return null
	
	for enemy in enemies_in_range:
		var dist = player.global_position.distance_to(enemy.global_position)
		if dist < min_dist:
			min_dist = dist
			closest = enemy
	return closest

func fire_available_weapons(target: Node3D):
	if player.has_method("auto_attack"):
		player.auto_attack(target)
	
func _on_body_entered(body: Node3D):
	if body.is_in_group("enemies"):
		if not enemies_in_range.has(body):
			enemies_in_range.append(body)

func _on_body_exited(body: Node3D):
	if enemies_in_range.has(body):
		enemies_in_range.erase(body)
