class_name StandAura
extends Node3D

## Aura de "Stand" (estilo JoJo) mientras el Komodo de Joel está fuera (solo mazmorra):
##  - destello y anillo en el pecho de Joel cuando el espíritu brota de él,
##  - llamas de aura que suben alrededor de Joel,
##  - los ゴゴゴ (onomatopeya de "amenaza") que aparecen flotando a su alrededor,
##  - al terminar, un último destello cuando el espíritu vuelve a entrar en él.
## Sigue al jugador (top_level) y se borra sola al acabar `duration`.

const TINT := Color(0.35, 1.0, 0.85)
const MENACE_COLOR := Color(0.75, 0.25, 1.0)
const MENACE_TEXT := "ゴ"
const MENACE_EVERY := 0.22        ## s entre ゴ
const CHEST := 1.05               ## m sobre los pies

static var _menace_font: Font = null

var player: Node3D
var duration := 1.6
var _t := 0.0
var _next_menace := 0.0
var _flames: CPUParticles3D
var _ending := false

static func spawn(p_player: Node3D, p_duration: float) -> StandAura:
	var a := StandAura.new()
	a.player = p_player
	a.duration = p_duration
	p_player.get_parent().add_child(a)
	a.global_position = p_player.global_position
	return a

func _ready() -> void:
	top_level = true
	_flames = _make_flames()
	_flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_flames.emission_ring_axis = Vector3.UP
	_flames.emission_ring_radius = 0.55
	_flames.emission_ring_inner_radius = 0.35
	_flames.emission_ring_height = 0.1
	add_child(_flames)
	_flames.emitting = true
	burst(1.0)
	AudioManager.play_at("impact_magic", global_position, -4.0, 0.55)

## Llamas de aura: manchas suaves aditivas turquesa que suben y se apagan.
func _make_flames() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = Quality.count(36)
	p.lifetime = 0.8
	p.direction = Vector3.UP
	p.spread = 12.0
	p.initial_velocity_min = 1.2
	p.initial_velocity_max = 2.4
	p.gravity = Vector3(0, 1.5, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	var q := QuadMesh.new()
	q.size = Vector2(0.32, 0.5)
	p.mesh = q
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	var tex := GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var tg := Gradient.new()
	tg.set_color(0, Color(1, 1, 1, 1))
	tg.set_color(1, Color(1, 1, 1, 0))
	tex.gradient = tg
	mat.albedo_texture = tex
	p.material_override = mat
	var g := Gradient.new()
	g.set_color(0, Color(TINT.r, TINT.g, TINT.b, 0.0))
	g.add_point(0.2, Color(TINT.r, TINT.g, TINT.b, 0.75))
	g.set_color(g.get_point_count() - 1, Color(0.3, 0.5, 1.0, 0.0))
	p.color_ramp = g
	return p

## Destello en el pecho (al salir y al volver el espíritu).
func burst(power: float) -> void:
	var at := global_position + Vector3(0, CHEST, 0)
	SpiritAnimal.spawn_vanish_burst(get_parent(), at, 0.6 * power)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.42
	torus.outer_radius = 0.5
	torus.rings = 24
	torus.ring_segments = 8
	ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(TINT.r, TINT.g, TINT.b, 0.9)
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(ring)
	ring.global_position = at
	# El anillo mira hacia donde apunta Joel (sale del pecho hacia delante)
	var fwd: Vector3 = -player.mesh.global_transform.basis.z if player and player.get("mesh") else Vector3.FORWARD
	ring.look_at(at + fwd, Vector3.UP)
	ring.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	ring.scale = Vector3.ONE * 0.3
	var tw := ring.create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector3.ONE * 2.2 * power, 0.35).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.35)
	tw.chain().tween_callback(ring.queue_free)

func _process(delta: float) -> void:
	_t += delta
	if is_instance_valid(player):
		global_position = player.global_position
	if not _ending:
		_next_menace -= delta
		if _next_menace <= 0.0:
			_next_menace = MENACE_EVERY
			_spawn_menace()
		if _t >= duration:
			_ending = true
			_flames.emitting = false
			burst(0.6)
			get_tree().create_timer(1.0).timeout.connect(queue_free)

## Un ゴ que aparece a un lado de Joel, crece de golpe, sube y se desvanece.
func _spawn_menace() -> void:
	var l := Label3D.new()
	l.text = MENACE_TEXT
	l.font = _get_menace_font()
	l.font_size = 96
	l.pixel_size = 0.006
	l.outline_size = 18
	l.modulate = MENACE_COLOR
	l.outline_modulate = Color(0.12, 0.0, 0.2, 1.0)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = false
	get_parent().add_child(l)
	var side := 1.0 if randf() < 0.5 else -1.0
	var right: Vector3 = player.mesh.global_transform.basis.x if player and player.get("mesh") else Vector3.RIGHT
	l.global_position = global_position + right * side * randf_range(0.8, 1.4) + Vector3(0, randf_range(0.6, 1.9), 0)
	l.rotation.z = randf_range(-0.35, 0.35)
	l.scale = Vector3.ONE * 0.2
	var big := randf_range(0.9, 1.4)
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector3.ONE * big, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "global_position:y", l.global_position.y + 0.5, 0.9)
	tw.tween_property(l, "modulate:a", 0.0, 0.35).set_delay(0.3)
	tw.parallel().tween_property(l, "outline_modulate:a", 0.0, 0.35)
	tw.tween_callback(l.queue_free)

static func _get_menace_font() -> Font:
	if _menace_font == null:
		# La fuente del juego (pixel art) no tiene katakana: se usa una del sistema que sí la tenga
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray(["Yu Gothic UI", "Yu Gothic", "Meiryo", "MS Gothic", "Noto Sans CJK JP", "Noto Sans JP", "Hiragino Sans", "Droid Sans Fallback"])
		sf.font_weight = 900
		_menace_font = sf
	return _menace_font
