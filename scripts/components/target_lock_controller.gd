class_name TargetLockController
extends Node

## Fijar objetivo (solo mazmorra).
##  - Tab, clic central o pulsar el stick derecho: fija el enemigo más cercano al centro de la cámara
##    (o suelta el actual).
##  - Con un objetivo fijado, la cámara lo sigue sola y los golpes se orientan hacia él.
##    Un golpe rápido de ratón (o del stick derecho) hacia un lado cambia al enemigo de ese lado.
##  - Se suelta solo si el objetivo muere (pasa al siguiente cercano), se aleja o deja de verse.

signal target_changed(target: Node3D)

const MAX_RANGE := 22.0          ## m para fijar
const BREAK_RANGE := 28.0        ## m a los que se suelta
const AUTO_NEXT_RANGE := 12.0    ## al morir el objetivo, salta a otro dentro de este radio
const LOST_SIGHT_TIME := 1.5     ## s sin línea de visión antes de soltar
const FLICK_PIXELS := 90.0       ## desplazamiento de ratón acumulado que cambia de objetivo
const FLICK_DECAY := 6.0         ## lo acumulado se olvida rápido si el gesto no es brusco
const SWITCH_COOLDOWN := 0.3
const MARKER_HEIGHT := 1.3

var player: Node3D
var target: Node3D
var _flick := 0.0
var _switch_cd := 0.0
var _unseen := 0.0
var _joy_was_pressed := false
var _marker: MeshInstance3D
var _marker_mat: ShaderMaterial
var _t := 0.0

const MARKER_SHADER := """
shader_type spatial;
render_mode unshaded, depth_test_disabled, cull_disabled, shadows_disabled;
uniform vec4 col : source_color = vec4(1.0, 0.25, 0.15, 1.0);
uniform float pulse = 0.0;
void vertex() {
	// Billboard: siempre mirando a la cámara, conserva la escala del nodo
	vec3 s = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s.x, INV_VIEW_MATRIX[1] * s.y, INV_VIEW_MATRIX[2] * s.z, MODEL_MATRIX[3]);
}
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = abs(p.x) + abs(p.y);
	float r = 0.62 + pulse * 0.18;
	float ring = smoothstep(0.09, 0.02, abs(d - r));
	float dot_c = smoothstep(0.2, 0.13, d);
	ALBEDO = col.rgb * 1.6;
	ALPHA = max(ring, dot_c) * col.a;
}
"""

func _ready() -> void:
	_marker = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.8, 0.8)
	_marker.mesh = q
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sh := Shader.new()
	sh.code = MARKER_SHADER
	_marker_mat = ShaderMaterial.new()
	_marker_mat.shader = sh
	_marker.material_override = _marker_mat
	_marker.top_level = true
	_marker.visible = false
	add_child(_marker)

func has_target() -> bool:
	return target != null and is_instance_valid(target) and not _is_dead(target)

## Punto al que mira la cámara / se orienta el golpe.
func target_point() -> Vector3:
	return target.global_position + Vector3(0.0, MARKER_HEIGHT * 0.7, 0.0)

func toggle() -> void:
	if has_target():
		_set_target(null)
	else:
		_set_target(_best_candidate())

## El ratón/stick horizontal llega aquí mientras hay objetivo (en vez de girar la cámara).
func feed_flick(dx: float) -> void:
	if not has_target():
		return
	_flick += dx
	if absf(_flick) >= FLICK_PIXELS and _switch_cd <= 0.0:
		var next := _side_candidate(signf(_flick))
		if next:
			_set_target(next)
		_flick = 0.0
		_switch_cd = SWITCH_COOLDOWN

func _unhandled_input(event: InputEvent) -> void:
	var pressed := false
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		pressed = true
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_MIDDLE:
		pressed = true
	if pressed:
		toggle()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	_t += delta
	_switch_cd = maxf(_switch_cd - delta, 0.0)
	_flick = lerpf(_flick, 0.0, minf(FLICK_DECAY * delta, 1.0))

	var joy := Input.is_joy_button_pressed(0, JOY_BUTTON_RIGHT_STICK)
	if joy and not _joy_was_pressed:
		toggle()
	_joy_was_pressed = joy

	if target != null and not has_target():
		# Murió o desapareció: salta a otro cercano si lo hay
		var next := _best_candidate(AUTO_NEXT_RANGE)
		_set_target(next)
	if has_target():
		var d := _flat_dist(target)
		if d > BREAK_RANGE:
			_set_target(null)
		else:
			_unseen = 0.0 if _line_of_sight(target) else _unseen + delta
			if _unseen > LOST_SIGHT_TIME:
				_set_target(null)

	_marker.visible = has_target()
	if _marker.visible:
		_marker.global_position = target.global_position + Vector3(0.0, MARKER_HEIGHT + 0.05 * sin(_t * 5.0), 0.0)
		_marker_mat.set_shader_parameter("pulse", 0.5 + 0.5 * sin(_t * 6.0))

func _set_target(t: Node3D) -> void:
	if t == target:
		return
	target = t
	_unseen = 0.0
	_flick = 0.0
	if t:
		AudioManager.play("ui_click", -10.0, 1.4)
	target_changed.emit(t)

# ───────────────────────────── Selección ─────────────────────────────

func _candidates(max_range: float) -> Array:
	var out: Array = []
	for e in EnemyRegistry.all():
		if not is_instance_valid(e) or not (e is Node3D) or _is_dead(e):
			continue
		if _flat_dist(e) > max_range:
			continue
		if not _line_of_sight(e):
			continue
		out.append(e)
	return out

## El más centrado en la cámara, con un pequeño peso por distancia.
func _best_candidate(max_range: float = MAX_RANGE) -> Node3D:
	var cam_fwd := _camera_forward()
	var best: Node3D = null
	var best_score := INF
	for e in _candidates(max_range):
		var to_e: Vector3 = e.global_position - player.global_position
		to_e.y = 0.0
		var d := to_e.length()
		var ang := cam_fwd.angle_to(to_e / maxf(d, 0.001)) if d > 0.001 else 0.0
		var score := ang * 6.0 + d * 0.15
		if score < best_score:
			best_score = score
			best = e
	return best

## El vecino más cercano en pantalla hacia `side` (+1 derecha, -1 izquierda).
func _side_candidate(side: float) -> Node3D:
	var cam := player.get_viewport().get_camera_3d()
	if cam == null:
		return null
	var cur_x := cam.unproject_position(target_point()).x
	var best: Node3D = null
	var best_dx := INF
	for e in _candidates(MAX_RANGE):
		if e == target or cam.is_position_behind(e.global_position):
			continue
		var dx: float = (cam.unproject_position(e.global_position).x - cur_x) * side
		if dx > 4.0 and dx < best_dx:
			best_dx = dx
			best = e
	return best

func _camera_forward() -> Vector3:
	var cam := player.get_viewport().get_camera_3d()
	var f := -cam.global_transform.basis.z if cam else Vector3.FORWARD
	f.y = 0.0
	return f.normalized() if f.length_squared() > 0.0001 else Vector3.FORWARD

func _line_of_sight(e: Node3D) -> bool:
	var from := player.global_position + Vector3(0.0, 1.2, 0.0)
	var to := e.global_position + Vector3(0.0, 0.8, 0.0)
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	q.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	# Los props rompibles no tapan (se ven por encima y se rompen de un golpe)
	return hit.is_empty() or hit.collider == e or hit.collider is DestructibleProp

func _flat_dist(e: Node3D) -> float:
	return Vector2(e.global_position.x - player.global_position.x, e.global_position.z - player.global_position.z).length()

func _is_dead(e: Object) -> bool:
	return e.has_method("is_dead") and e.is_dead()
