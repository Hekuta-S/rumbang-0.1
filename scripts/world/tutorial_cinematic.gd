class_name TutorialCinematic
extends Node

## Invocación del patio (la cinemática de siempre, ahora en el tutorial): el rey y el mago llaman al héroe con un
## círculo de runas, un rayo de luz y un destello, en una sola toma de cámara que acaba detrás del héroe.
## Se salta con skip(). Al terminar emite finished y TutorialPatio le devuelve el control al jugador.

signal finished

const CIRCLE := Vector3(0.0, 0.0, 2.5)    ## círculo de invocación (donde aparece el héroe)
## Guion: [segundo, quién, texto]. Tono épico con humor (el héroe aparece en calzones).
const LINES := [
	[1.2, "rey", "¡Por la corona de Rumbang! Mago, ¡que se cumpla la profecía!"],
	[5.2, "mago", "Círculo antiguo, escucha mi voz... ¡Tráenos al héroe de las mazmorras!"],
	[12.4, "rey", "¿...Este es el héroe? ¿En calzones?"],
	[15.4, "mago", "Ejem. La profecía no decía nada de la ropa, majestad."],
	[18.6, "rey", "¡Bah! Bienvenido, héroe. Antes de las mazmorras, demuestra lo que sabes en mi patio."],
]
const LENGTH := 24.2
const FLASH_AT := 9.6
const BEAM_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec4 color : source_color = vec4(0.45, 0.8, 1.0, 1.0);
uniform float intensity = 0.0;
void fragment() {
	float h = UV.y;
	float stripes = 0.55 + 0.45 * sin(UV.x * 37.7 + TIME * 3.0) * sin(UV.x * 12.6 - TIME * 1.7 + h * 6.0);
	float fade = smoothstep(0.0, 0.08, h) * (1.0 - smoothstep(0.35, 1.0, h));
	ALBEDO = color.rgb * 3.0;
	ALPHA = clamp(intensity * fade * stripes, 0.0, 1.0);
}
"""

var patio: Node3D                          ## TutorialPatio
var running := false
var time := 0.0
var camera: Camera3D
var _cam_pos := Vector3.ZERO
var _cam_target := Vector3.ZERO
var _cam_fov := 45.0
var _cam_tween: Tween
var _timeline: Array[Dictionary] = []
var _beam: MeshInstance3D
var _beam_mat: ShaderMaterial
var _sparks: CPUParticles3D
var _rune_mat: StandardMaterial3D
var _light: OmniLight3D
var _shake := 0.0

## Construye el círculo, la luz, el rayo y las chispas (siempre presentes en el patio).
func build(p: Node3D) -> void:
	patio = p
	_rune_mat = StandardMaterial3D.new()
	_rune_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_rune_mat.albedo_color = Color(0.55, 0.85, 1.0)
	_rune_mat.emission_enabled = true
	_rune_mat.emission = Color(0.45, 0.8, 1.0)
	_rune_mat.emission_energy_multiplier = 0.6
	for r in [[2.6, 0.06], [2.25, 0.035], [1.0, 0.05]]:
		var mi := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = float(r[0]) - float(r[1])
		tm.outer_radius = float(r[0]) + float(r[1])
		tm.rings = 48
		tm.ring_segments = 6
		mi.mesh = tm
		mi.scale = Vector3(1, 0.05, 1)
		mi.position = CIRCLE + Vector3(0, 0.05, 0)
		mi.material_override = _rune_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		patio.add_child(mi)
	for k in 6:   # estrella de seis puntas (tres líneas cruzadas) y rayos
		var bar := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(4.5, 0.02, 0.05)
		bar.mesh = bm
		bar.material_override = _rune_mat
		bar.position = CIRCLE + Vector3(0, 0.05, 0)
		bar.rotation.y = PI * k / 6.0
		bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		patio.add_child(bar)
	_light = OmniLight3D.new()
	_light.position = CIRCLE + Vector3(0, 0.7, 0)
	_light.light_color = Color(0.4, 0.75, 1.0)
	_light.light_energy = 0.6
	_light.omni_range = 7.0
	patio.add_child(_light)
	_beam = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.25
	cyl.bottom_radius = 1.25
	cyl.height = 7.0
	cyl.cap_top = false
	cyl.cap_bottom = false
	cyl.radial_segments = 48
	_beam.mesh = cyl
	var sh := Shader.new()
	sh.code = BEAM_SHADER
	_beam_mat = ShaderMaterial.new()
	_beam_mat.shader = sh
	_beam.material_override = _beam_mat
	_beam.position = CIRCLE + Vector3(0, 3.5, 0)
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.visible = false
	patio.add_child(_beam)
	_sparks = _make_sparks(Color(0.5, 0.85, 1.0), 90, 2.4)
	_sparks.position = CIRCLE + Vector3(0, 0.05, 0)
	patio.add_child(_sparks)

func _make_sparks(c: Color, amount: int, ring: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = 2.2
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_radius = ring
	p.emission_ring_inner_radius = ring * 0.15
	p.emission_ring_height = 0.02
	p.emission_ring_axis = Vector3.UP
	p.direction = Vector3.UP
	p.spread = 12.0
	p.gravity = Vector3(0, 0.6, 0)
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 1.1
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	var q := QuadMesh.new()
	q.size = Vector2(0.05, 0.05)
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	pm.albedo_color = c
	pm.vertex_color_use_as_albedo = true
	var dot := Gradient.new()
	dot.set_color(0, Color(1, 1, 1, 1))
	dot.set_color(1, Color(1, 1, 1, 0))
	var dt := GradientTexture2D.new()
	dt.gradient = dot
	dt.fill = GradientTexture2D.FILL_RADIAL
	dt.fill_from = Vector2(0.5, 0.5)
	dt.fill_to = Vector2(1.0, 0.5)
	dt.width = 32
	dt.height = 32
	pm.albedo_texture = dt
	q.material = pm
	p.mesh = q
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0))
	ramp.add_point(0.2, Color(1, 1, 1, 1))
	ramp.set_color(ramp.get_point_count() - 1, Color(1, 1, 1, 0))
	p.color_ramp = ramp
	p.emitting = false
	return p

# ───────────────────────────── guion ─────────────────────────────

func start() -> void:
	running = true
	time = 0.0
	var fade: ColorRect = patio._fade
	camera = Camera3D.new()
	patio.add_child(camera)
	camera.current = true
	_set_cam(Vector3(0.0, 5.2, 12.0), Vector3(0.0, 1.6, -6.0), 52.0)
	fade.color = Color(0, 0, 0, 1)
	create_tween().tween_property(fade, "color:a", 0.0, 1.6)
	patio._play(patio.king, "rey_invocar")
	patio._play(patio.mage, "mago_conjurar")
	_sparks.emitting = true
	var start_pos: Vector3 = patio.PLAYER_START
	_cam_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_cam_move(Vector3(0.0, 4.2, 9.0), Vector3(0.0, 2.4, -9.0), 48.0, 4.6)        # avanza hacia el rey
	_cam_move(Vector3(-1.0, 1.75, 5.0), Vector3(-3.0, 1.45, 1.8), 40.0, 4.2)     # gira hacia el mago
	_cam_move(Vector3(2.3, 1.0, 4.6), Vector3(0.0, 0.9, 1.4), 46.0, 2.4)         # baja al círculo
	_cam_move(Vector3(1.6, 1.5, 4.4), Vector3(0.0, 1.15, 1.4), 44.0, 1.6)        # recibe al héroe
	_cam_move(Vector3(0.9, 1.75, 3.8), Vector3(0.2, 2.6, -10.0), 38.0, 2.6)      # tras el héroe, hacia el rey
	_cam_move(Vector3(-0.4, 1.7, 4.0), Vector3(-2.8, 1.45, 1.6), 40.0, 3.2)      # el mago se excusa
	_cam_move(Vector3(0.4, 2.2, 2.6), Vector3(0.0, 2.7, -10.6), 34.0, 3.2)       # el rey da la bienvenida
	_cam_move(start_pos + Vector3(0, 3.0, 4.6), start_pos + Vector3(0, 1.0, -0.6), 50.0, 2.4)
	_cam_tween.finished.connect(_end)
	_timeline.clear()
	_at(0.3, func(): _ramp_runes(1.4, 4.0))
	for line in LINES:
		var ln: Array = line
		_at(float(ln[0]), func(): patio._say(String(ln[1]), String(ln[2])))
	_at(1.0, func(): patio._play(patio.king, "rey_invocar"))
	_at(5.0, func():
		_ramp_runes(3.2, 4.0)
		patio._play(patio.mage, "mago_conjurar"))
	_at(8.6, func():
		_beam.visible = true
		create_tween().tween_method(func(v: float): _beam_mat.set_shader_parameter("intensity", v), 0.0, 0.7, 1.0))
	_at(FLASH_AT, _flash_and_summon)
	_at(12.0, func(): patio._play(patio.king, "rey_sorpresa"))
	_at(12.5, func(): patio._play(patio.mage, "mago_sorpresa"))
	_at(15.2, func(): patio._play(patio.mage, "mago_reverencia"))
	_at(18.4, func(): patio._play(patio.king, "rey_hablar"))
	_at(LENGTH - 1.2, func():
		patio._play(patio.king, "rey_idle")
		patio._play(patio.mage, "mago_idle"))

func _cam_move(pos: Vector3, target: Vector3, fov: float, dur: float) -> void:
	_cam_tween.tween_property(self, "_cam_pos", pos, dur)
	_cam_tween.parallel().tween_property(self, "_cam_target", target, dur)
	_cam_tween.parallel().tween_property(self, "_cam_fov", fov, dur)

func _set_cam(pos: Vector3, target: Vector3, fov: float) -> void:
	_cam_pos = pos
	_cam_target = target
	_cam_fov = fov

func _at(t: float, fn: Callable) -> void:
	_timeline.append({"t": t, "fn": fn, "done": false})

func _ramp_runes(energy: float, dur: float) -> void:
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_rune_mat, "emission_energy_multiplier", energy, dur)
	tw.tween_property(_light, "light_energy", energy * 1.1, dur)

func _flash_and_summon() -> void:
	AudioManager.play("impact_magic", 2.0, 0.8)
	AudioManager.play("slam_boom", -2.0, 0.9)
	_shake = 0.5
	var fade: ColorRect = patio._fade
	fade.color = Color(0.85, 0.95, 1.0, 1.0)
	create_tween().tween_property(fade, "color:a", 0.0, 1.1).set_ease(Tween.EASE_OUT)
	_light.light_energy = 12.0
	create_tween().tween_property(_light, "light_energy", 1.6, 1.6)
	_rune_mat.emission_energy_multiplier = 8.0
	create_tween().tween_property(_rune_mat, "emission_energy_multiplier", 1.6, 2.5)
	var tp := create_tween()
	tp.tween_method(func(v: float): _beam_mat.set_shader_parameter("intensity", v), 1.4, 0.0, 1.8)
	tp.tween_callback(func(): _beam.visible = false)
	_appear_player(1.3)

func _appear_player(duration: float) -> void:
	var player: Node3D = patio.player
	player.visible = true
	var model: Node3D = player.animation_controller.model if player.animation_controller else null
	if model:
		model.visible = true
		SpawnDissolve.play(model, self, duration, Color(0.45, 0.85, 1.0), 1.62)

## Saltar la invocación: todo queda como al final y la cámara se va detrás del héroe.
func skip() -> void:
	if not running:
		return
	for e in _timeline:
		e["done"] = true
	if _cam_tween:
		_cam_tween.kill()
	patio._voice.stop()
	patio._sub_panel.visible = false
	_beam.visible = false
	patio._fade.color.a = 0.0
	if not patio.player.visible:
		_appear_player(0.8)
	_rune_mat.emission_energy_multiplier = 1.6
	_light.light_energy = 1.6
	patio._play(patio.king, "rey_idle")
	patio._play(patio.mage, "mago_idle")
	var start_pos: Vector3 = patio.PLAYER_START
	_cam_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_cam_move(start_pos + Vector3(0, 3.0, 4.6), start_pos + Vector3(0, 1.0, -0.6), 50.0, 1.0)
	_cam_tween.finished.connect(_end)

func _end() -> void:
	if not running:
		return
	running = false
	_sparks.emitting = false
	if is_instance_valid(camera):
		camera.queue_free()
	finished.emit()

func _process(delta: float) -> void:
	if not running:
		return
	time += delta
	for e in _timeline:
		if not e["done"] and time >= float(e["t"]):
			e["done"] = true
			(e["fn"] as Callable).call()
	_shake = maxf(_shake - delta, 0.0)
	var p := _cam_pos + Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * _shake * 0.08
	camera.fov = _cam_fov
	camera.look_at_from_position(p, _cam_target, Vector3.UP)
