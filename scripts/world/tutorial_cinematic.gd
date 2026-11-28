class_name TutorialCinematic
extends Node

## Invocación del patio (primer arranque): el rey y el mago llaman al héroe con un círculo de runas, un rayo de
## luz y un destello. Historia: justo después el Nigromante sale de un portal morado y se lleva al mago (por eso
## las mazmorras siguen cerradas hasta rescatarlo en la Supervivencia, ver MageCage). Una sola toma de cámara que
## acaba detrás del héroe. Se salta con skip(). Al terminar emite finished y TutorialPatio devuelve el control.

signal finished

const CIRCLE := Vector3(0.0, 0.0, 2.5)    ## círculo de invocación (donde aparece el héroe)
## Guion: [segundo, quién, texto]. Tono épico con humor (el héroe aparece en calzones) y el rapto al final.
const LINES := [
	[1.0, "rey", "¡Por la corona de Rumbang! Mago, ¡que se cumpla la profecía!"],
	[4.4, "mago", "Círculo antiguo, escucha mi voz... ¡Tráenos al héroe!"],
	[10.2, "rey", "¿...Este es el héroe? ¿En calzones?"],
	[12.4, "mago", "Ejem. La profecía no decía nada de la ropa, majestad."],
	[15.4, "necro", "Gracias por abrir el círculo, viejo. Tu magia ahora es mía."],
	[17.9, "mago", "¡Majestad! ¡Héroe, ayúdam...!"],
	[20.0, "rey", "¡El mago! Héroe, entrena en mi patio y tráelo de vuelta: el Nigromante acecha en la arena."],
]
const LENGTH := 24.2
const FLASH_AT := 8.4
## Rapto: el Nigromante aparece detrás del mago (NECRO_AT), lo atrapa (GRAB_AT) y se van los dos (VANISH_AT).
const NECRO_AT := 14.6
const GRAB_AT := 17.6
const VANISH_AT := 19.0
const NECRO_OFFSET := Vector3(-2.2, 0.0, -0.8)   ## respecto al mago
const NECRO_HEIGHT := 2.9
const NECRO_COLOR := Color(0.75, 0.3, 1.0)
const NECRO_IDLE := "res://assets/models/entities/enemigos/goblins/bosses/necromancer/ataque_idle_necroboss.fbx"
const NECRO_SUMMON := "res://assets/models/entities/enemigos/goblins/bosses/necromancer/invocar_zombies_necro.fbx"
const NECRO_TEX := "res://assets/textures/enemigos/textura_necro_boss.png"
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
var necro: Node3D                          ## el Nigromante (solo durante la intro)
var kidnapped := false                     ## el mago ya no está en el patio
var _necro_light: OmniLight3D
var _necro_portal: MeshInstance3D
var _necro_sparks: CPUParticles3D

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
	var mage_pos: Vector3 = patio.mage.position
	var necro_pos := mage_pos + NECRO_OFFSET
	_cam_move(Vector3(0.0, 4.2, 9.0), Vector3(0.0, 2.4, -9.0), 48.0, 4.0)        # avanza hacia el rey
	_cam_move(Vector3(-1.0, 1.75, 5.0), Vector3(-3.0, 1.45, 1.8), 40.0, 3.4)     # gira hacia el mago
	_cam_move(Vector3(2.3, 1.0, 4.6), Vector3(0.0, 0.9, 1.4), 46.0, 1.6)         # baja al círculo
	_cam_move(Vector3(1.6, 1.5, 4.4), Vector3(0.0, 1.15, 1.4), 44.0, 1.4)        # recibe al héroe
	_cam_move(Vector3(0.9, 1.75, 3.8), Vector3(0.2, 2.6, -10.0), 38.0, 2.0)      # tras el héroe, hacia el rey
	_cam_move(Vector3(-0.4, 1.7, 4.0), Vector3(-2.8, 1.45, 1.6), 40.0, 2.2)      # el mago se excusa
	_cam_move(Vector3(1.4, 2.3, 6.6), (mage_pos + necro_pos) * 0.5 + Vector3(0, 1.4, 0), 50.0, 1.6)  # ¡el Nigromante!
	_cam_tween.tween_interval(2.6)                                               # el rapto
	_cam_move(Vector3(0.4, 2.2, 2.6), Vector3(0.0, 2.7, -10.6), 36.0, 1.6)       # el rey, furioso
	_cam_tween.tween_interval(1.4)
	_cam_move(start_pos + Vector3(0, 3.0, 4.6), start_pos + Vector3(0, 1.0, -0.6), 50.0, 2.4)
	_cam_tween.finished.connect(_end)
	_timeline.clear()
	_at(0.3, func(): _ramp_runes(1.4, 4.0))
	for line in LINES:
		var ln: Array = line
		_at(float(ln[0]), func(): patio._say(String(ln[1]), String(ln[2])))
	_at(0.8, func(): patio._play(patio.king, "rey_invocar"))
	_at(4.2, func():
		_ramp_runes(3.2, 4.0)
		patio._play(patio.mage, "mago_conjurar"))
	_at(7.4, func():
		_beam.visible = true
		create_tween().tween_method(func(v: float): _beam_mat.set_shader_parameter("intensity", v), 0.0, 0.7, 1.0))
	_at(FLASH_AT, _flash_and_summon)
	_at(10.0, func(): patio._play(patio.king, "rey_sorpresa"))
	_at(10.4, func(): patio._play(patio.mage, "mago_sorpresa"))
	_at(12.6, func(): patio._play(patio.mage, "mago_reverencia"))
	_at(NECRO_AT, func(): _necro_appear(necro_pos, mage_pos))
	_at(GRAB_AT, _necro_grab)
	_at(VANISH_AT, _necro_vanish)
	_at(20.0, func(): patio._play(patio.king, "rey_hablar"))
	_at(LENGTH - 1.2, func(): patio._play(patio.king, "rey_idle"))

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

# ───────────────────────────── el rapto ─────────────────────────────

## Modelo del Nigromante (el jefe de la Supervivencia) a NECRO_HEIGHT de alto, con su textura.
func _make_necro() -> Node3D:
	if not ResourceLoader.exists(NECRO_IDLE):
		return null
	var ps := load(NECRO_IDLE) as PackedScene
	var root := Node3D.new()
	var m: Node3D = ps.instantiate() as Node3D if ps else null
	if m == null:
		return root
	root.add_child(m)
	var tex: Texture2D = load(NECRO_TEX) as Texture2D if ResourceLoader.exists(NECRO_TEX) else null
	var meshes := m.find_children("*", "MeshInstance3D", true, false)
	for mi in meshes:
		if tex:
			var mat := StandardMaterial3D.new()
			mat.albedo_texture = tex
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mat.roughness = 0.85
			(mi as MeshInstance3D).material_override = mat
	if not meshes.is_empty() and (meshes[0] as MeshInstance3D).mesh:
		var aabb: AABB = (meshes[0] as MeshInstance3D).mesh.get_aabb()
		var s := NECRO_HEIGHT / maxf(aabb.size.y, 0.001)
		m.scale = Vector3(s, s, s)   # sin girar: la raíz mira (+Z) al mago
		m.position.y = -aabb.position.y * s
	# Clip de invocar (brazos en alto) para el agarre, si el FBX existe
	var ap := m.find_children("*", "AnimationPlayer", true, false)
	if not ap.is_empty():
		var player := ap[0] as AnimationPlayer
		var list := player.get_animation_list()
		if not list.is_empty():
			player.get_animation(list[0]).loop_mode = Animation.LOOP_LINEAR
			player.play(list[0])
		if ResourceLoader.exists(NECRO_SUMMON):
			var sp := load(NECRO_SUMMON) as PackedScene
			var tmp: Node = sp.instantiate() if sp else null
			var tap: Array = tmp.find_children("*", "AnimationPlayer", true, false) if tmp else []
			if not tap.is_empty():
				var src := tap[0] as AnimationPlayer
				var names := src.get_animation_list()
				if not names.is_empty():
					if not player.has_animation_library(""):
						player.add_animation_library("", AnimationLibrary.new())
					player.get_animation_library("").add_animation("summon", src.get_animation(names[0]).duplicate())
			if tmp:
				tmp.free()
	return root

func _necro_appear(at: Vector3, mage_pos: Vector3) -> void:
	AudioManager.play("boss_sting", -2.0, 0.8)
	AudioManager.play("impact_magic", -2.0, 0.6)
	_shake = 0.35
	# La luz del patio se tiñe de morado
	var fade: ColorRect = patio._fade
	fade.color = Color(NECRO_COLOR.darkened(0.6), 0.0)
	create_tween().tween_property(fade, "color:a", 0.35, 0.6)
	_ramp_runes(0.3, 0.6)
	# Portal en el suelo y chispas moradas
	_necro_portal = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.5
	disc.bottom_radius = 1.5
	disc.height = 0.02
	_necro_portal.mesh = disc
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.albedo_color = Color(0.12, 0.02, 0.2, 0.9)
	_necro_portal.material_override = pm
	_necro_portal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_necro_portal.position = at + Vector3(0, 0.03, 0)
	_necro_portal.scale = Vector3(0.05, 1, 0.05)
	patio.add_child(_necro_portal)
	create_tween().tween_property(_necro_portal, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_necro_sparks = _make_sparks(NECRO_COLOR, 70, 1.4)
	_necro_sparks.position = at + Vector3(0, 0.05, 0)
	patio.add_child(_necro_sparks)
	_necro_sparks.emitting = true
	_necro_light = OmniLight3D.new()
	_necro_light.light_color = NECRO_COLOR
	_necro_light.light_energy = 0.0
	_necro_light.omni_range = 7.0
	_necro_light.position = at + Vector3(0, 1.6, 0)
	patio.add_child(_necro_light)
	create_tween().tween_property(_necro_light, "light_energy", 3.0, 0.6)
	# El Nigromante sube del portal mirando al mago
	necro = _make_necro()
	if necro:
		patio.add_child(necro)
		necro.position = at + Vector3(0, -NECRO_HEIGHT, 0)
		var d := mage_pos - at
		necro.rotation.y = atan2(d.x, d.z)
		create_tween().tween_property(necro, "position:y", at.y, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	patio._play(patio.mage, "mago_sorpresa")
	var md := at - mage_pos
	create_tween().tween_property(patio.mage, "rotation:y", atan2(md.x, md.z), 0.4)
	patio._play(patio.king, "rey_sorpresa")

func _necro_grab() -> void:
	if necro:
		var ap := necro.find_children("*", "AnimationPlayer", true, false)
		if not ap.is_empty() and (ap[0] as AnimationPlayer).has_animation("summon"):
			(ap[0] as AnimationPlayer).play("summon", 0.3)
	AudioManager.play("orb_cast", -2.0, 0.6)
	_shake = 0.25
	# El mago levita, atrapado en un aura morada, hacia el Nigromante
	var mage: Node3D = patio.mage
	var to: Vector3 = _necro_portal.position if _necro_portal else mage.position
	var target := mage.position.lerp(to, 0.6) + Vector3(0, 0.8, 0)
	create_tween().set_trans(Tween.TRANS_SINE).tween_property(mage, "position", target, 1.3)
	var aura := _make_sparks(NECRO_COLOR, 60, 0.6)
	aura.position = Vector3(0, 0.3, 0)
	mage.add_child(aura)
	aura.emitting = true

func _necro_vanish() -> void:
	AudioManager.play("slam_boom", -2.0, 0.7)
	AudioManager.play("impact_magic", 0.0, 0.5)
	_shake = 0.5
	var mage_node: Node3D = patio.mage
	var at: Vector3 = _necro_portal.position if _necro_portal else mage_node.position
	NecroVFX.shockwave(patio, at, 4.0, NECRO_COLOR)
	var fade: ColorRect = patio._fade
	fade.color = Color(NECRO_COLOR, 0.9)
	var tf := create_tween()
	tf.tween_property(fade, "color", Color(NECRO_COLOR.darkened(0.6), 0.0), 1.0)
	for n in [patio.mage, necro]:
		if n:
			var tw := create_tween()
			tw.tween_property(n, "scale", Vector3(0.02, 0.02, 0.02), 0.35)
	get_tree().create_timer(0.4).timeout.connect(apply_kidnap_end)
	_ramp_runes(1.6, 1.5)

## Estado tras el rapto (también al saltar la intro): sin mago ni Nigromante, sin portal.
func apply_kidnap_end() -> void:
	kidnapped = true
	if is_instance_valid(patio.mage):
		patio.mage.visible = false
	for n in [necro, _necro_portal, _necro_sparks]:
		if is_instance_valid(n):
			n.queue_free()
	necro = null
	_necro_portal = null
	_necro_sparks = null
	if is_instance_valid(_necro_light):
		var tw := create_tween()
		tw.tween_property(_necro_light, "light_energy", 0.0, 0.8)
		tw.tween_callback(_necro_light.queue_free)
	_necro_light = null

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
	patio._fade.color = Color(0, 0, 0, 0)
	apply_kidnap_end()
	var start_pos: Vector3 = patio.PLAYER_START
	_cam_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_cam_move(start_pos + Vector3(0, 3.0, 4.6), start_pos + Vector3(0, 1.0, -0.6), 50.0, 1.0)
	_cam_tween.finished.connect(_end)

func _end() -> void:
	if not running:
		return
	running = false
	_sparks.emitting = false
	if not kidnapped:
		apply_kidnap_end()
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
