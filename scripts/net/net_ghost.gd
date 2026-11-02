class_name NetGhost
extends Node

## Copia SOLO VISUAL de un proyectil o efecto de otro jugador (ver NetWorld). Se crea a partir de la misma
## escena que el original, sin colisiones ni lógica propia (el daño ya lo aplica el equipo de su dueño),
## y este nodo la mueve en línea recta con la velocidad medida hasta que el dueño avisa de que terminó.

const MAX_LIFETIME := 8.0

var dir := Vector3.ZERO
var speed := 0.0
var _age := 0.0

## Instancia `scene` como copia visual en `parent`. Devuelve el nodo (o null si no se pudo crear).
static func spawn(parent: Node, scene: PackedScene, pos: Vector3, rot: Quaternion, p_dir: Vector3, p_speed: float) -> Node3D:
	var node := scene.instantiate() as Node3D
	if node == null:
		return null
	node.set_meta("net_ghost", true)         # NetWorld no la vuelve a replicar
	_neutralize(node)
	parent.add_child(node)
	node.global_position = pos
	node.global_basis = Basis(rot)
	var g := NetGhost.new()
	g.dir = p_dir
	g.speed = p_speed
	node.add_child(g)
	return node

## Sin colisiones ni scripts propios en la raíz: solo se ve. (Los hijos con partículas siguen animándose.)
static func _neutralize(node: Node) -> void:
	if node is CollisionObject3D:
		(node as CollisionObject3D).collision_layer = 0
		(node as CollisionObject3D).collision_mask = 0
	if node is Area3D:
		(node as Area3D).monitoring = false
		(node as Area3D).monitorable = false
	for c in node.get_children():
		_neutralize(c)
	if node.get_parent() == null:
		node.set_physics_process(false)
		node.set_process(false)

func _physics_process(delta: float) -> void:
	_age += delta
	var p := get_parent() as Node3D
	if p == null:
		return
	p.global_position += dir * speed * delta
	if _age > MAX_LIFETIME:
		p.queue_free()
