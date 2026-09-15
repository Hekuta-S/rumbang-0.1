extends Node

const BULLET_POOL_SIZE = 50
const FLOATING_DAMAGE_POOL_SIZE = 50

var bullet_scene = preload("res://scenes/objects/bullet.tscn")
var floating_damage_script = preload("res://scripts/objects/floating_damage.gd")

var _bullet_pool: Array[Node3D] = []
var _bullet_index: int = 0

var _floating_damage_pool: Array[Label3D] = []
var _floating_damage_index: int = 0

func _ready() -> void:
	# Create pool parent to keep scene tree clean
	var pool_parent = Node.new()
	pool_parent.name = "ObjectPool"
	add_child(pool_parent)
	
	# Pre-instantiate bullets
	for i in range(BULLET_POOL_SIZE):
		var b = bullet_scene.instantiate()
		b.visible = false
		b.set_process(false)
		b.set_physics_process(false)
		b.set_deferred("monitoring", false)
		pool_parent.add_child(b)
		_bullet_pool.append(b)
		
	# Pre-instantiate floating damage numbers
	for i in range(FLOATING_DAMAGE_POOL_SIZE):
		var label = Label3D.new()
		label.script = floating_damage_script
		label.visible = false
		label.set_process(false)
		pool_parent.add_child(label)
		_floating_damage_pool.append(label)

func get_bullet() -> Node3D:
	if _bullet_pool.is_empty():
		return null
		
	var b = _bullet_pool[_bullet_index]
	_bullet_index = (_bullet_index + 1) % BULLET_POOL_SIZE
	
	# Wake up bullet
	b.visible = true
	b.set_process(true)
	b.set_physics_process(true)
	b.set_deferred("monitoring", true)
	b.lifetime = 0.0
	b.is_hit = false
	
	return b

func return_bullet(b: Node3D) -> void:
	b.visible = false
	b.set_process(false)
	b.set_physics_process(false)
	b.set_deferred("monitoring", false)
	b.is_hit = true
	# We don't remove it from tree, just hide it and disable physics

func get_floating_damage() -> Label3D:
	if _floating_damage_pool.is_empty():
		return null
		
	var label = _floating_damage_pool[_floating_damage_index]
	_floating_damage_index = (_floating_damage_index + 1) % FLOATING_DAMAGE_POOL_SIZE
	
	label.visible = true
	label.set_process(true)
	label.time_alive = 0.0
	
	return label

func return_floating_damage(label: Label3D) -> void:
	label.visible = false
	label.set_process(false)
