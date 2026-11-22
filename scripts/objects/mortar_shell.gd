class_name MortarShell
extends Node3D

## Proyectil en parábola del mago de artillería. Al lanzarse fija el punto de impacto (donde está el
## jugador en ese instante) y vuela hasta allí en arco: no persigue al jugador, así que se esquiva
## moviéndose. Al caer daña al jugador si está dentro del radio de explosión.

const COLOR := Color(0.46, 0.51, 1.0)
const BLAST_RADIUS := 2.4
const MIN_FLIGHT_S := 1.1
const MAX_FLIGHT_S := 2.2
const FLIGHT_SPEED := 13.0     ## m/s horizontales: el tiempo de vuelo crece con la distancia
const ARC_BASE := 3.5
const ARC_PER_M := 0.14

var damage: float = 6.0
var _start: Vector3
var _end: Vector3
var _flight: float = 1.5
var _arc: float = 5.0
var _t: float = 0.0
var _marker: MeshInstance3D
var _sprite: Sprite3D

## Proyectiles libres: se reutilizan en vez de instanciar y liberar uno por disparo.
static var _pool: Array = []

## Marca del suelo: anillo entintado (ring.png) del radio de la explosión; el proyectil es una bola mágica
## dibujada (magia.png, fila arcana) que "hierve" alternando fotogramas. Todo 2D horneado.
static var _ring_mesh: PlaneMesh
static var _ring_mat: StandardMaterial3D
var _frame_t := 0.0

## Lanza un proyectil desde `from` hacia `target` (posición fija en el momento del disparo).
static func launch(parent: Node, from: Vector3, target: Vector3, dmg: float) -> void:
	var s: MortarShell = null
	while s == null and not _pool.is_empty():
		var c = _pool.pop_back()
		if is_instance_valid(c) and c.is_inside_tree():
			s = c
	if s == null:
		s = MortarShell.new()
		parent.add_child(s)
	s._setup(from, target, dmg)

static func _ensure_resources() -> void:
	if _ring_mesh != null:
		return
	_ring_mesh = PlaneMesh.new()
	_ring_mesh.size = Vector2(BLAST_RADIUS * 2.0, BLAST_RADIUS * 2.0)
	_ring_mat = ToonFX.ring_material()
	if _ring_mat == null:
		_ring_mat = StandardMaterial3D.new()
		_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.albedo_color = Color(COLOR.r, COLOR.g, COLOR.b, 0.75)

func _setup(from: Vector3, target: Vector3, dmg: float) -> void:
	_ensure_resources()
	damage = dmg
	_start = from
	_end = target
	var horizontal := Vector2(target.x - from.x, target.z - from.z).length()
	_flight = clampf(horizontal / FLIGHT_SPEED, MIN_FLIGHT_S, MAX_FLIGHT_S)
	_arc = ARC_BASE + horizontal * ARC_PER_M
	global_position = from
	top_level = true
	_t = 0.0
	visible = true
	set_process(true)

	if _sprite == null:
		_sprite = ToonFX.magic_sprite(ToonFX.MAGIC_ARCANE, 0.9)
		add_child(_sprite)

		# Marca en el suelo del punto de impacto, para poder esquivarlo
		_marker = MeshInstance3D.new()
		_marker.mesh = _ring_mesh
		_marker.material_override = _ring_mat
		_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_marker)
	_marker.global_position = Vector3(_end.x, _end.y + 0.08, _end.z)

func _process(delta: float) -> void:
	_t += delta
	_frame_t += delta
	if _frame_t >= 0.12:
		_frame_t = 0.0
		_sprite.frame = ToonFX.MAGIC_ARCANE * 2 + (_sprite.frame + 1) % 2
	var u := clampf(_t / _flight, 0.0, 1.0)
	# la marca late y se cierra al acercarse la caída
	_marker.scale = Vector3.ONE * lerpf(1.15, 1.0, u) * (1.0 + 0.04 * sin(_t * 18.0))
	var pos := _start.lerp(_end, u)
	pos.y += 4.0 * _arc * u * (1.0 - u)
	global_position = pos
	_marker.global_position = Vector3(_end.x, _end.y + 0.08, _end.z)
	if u >= 1.0:
		_explode()

func _explode() -> void:
	set_process(false)
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player != null:
		var d := Vector2(player.global_position.x - _end.x, player.global_position.z - _end.z).length()
		if d <= BLAST_RADIUS and player.has_method("take_damage"):
			player.take_damage(damage)
	var parent := get_parent()
	if parent != null:
		ToonFX.ring_burst(parent, _end, BLAST_RADIUS, COLOR, 0.32)
		ToonFX.impact_pop(parent, _end + Vector3(0, 0.6, 0), COLOR, 1.6)
		ToonFX.puff_burst(parent, _end + Vector3(0, 0.3, 0), COLOR, 8, 4.0, 0.6)
	visible = false
	_pool.append(self)
