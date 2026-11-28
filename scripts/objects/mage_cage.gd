class_name MageCage
extends Node3D

## Jaula del mago en la Supervivencia (historia): el Nigromante raptó al mago en la intro y lo tiene enjaulado
## en el mapa. La hace aparecer RunEvents a los CAGE_TIME s mientras el mago siga sin rescatar
## (SaveManager.mago_rescatado). Quedarse HOLD s dentro del círculo (RADIUS) abre la jaula; fuera, el progreso
## baja despacio. Al entrar por primera vez emite `ambushed` (RunEvents manda un grupo). Al abrirla guarda el
## rescate (las mazmorras se abren en el salón) y emite `rescued`. Si el jugador muere antes, no se guarda nada
## y la jaula vuelve a salir en la siguiente partida.
## Mientras existe, una flecha en el borde de la pantalla señala hacia ella con la distancia.

signal ambushed
signal rescued

const RADIUS := 3.0
const HOLD := 8.0
const DECAY := 0.5                    ## fracción de HOLD que se pierde por segundo fuera del círculo
const COLOR := Color(0.45, 0.8, 1.0)
const BARS := 10
const BAR_R := 0.95
const BAR_H := 2.5
const MAGE_PATH := "res://assets/models/salon/mago.glb"
const THANKS := "¡Gracias, héroe! Te espero en el salón: abriré los portales de las mazmorras."
const LEAVE_AFTER := 4.0
const HUD_BOTTOM := 130.0             ## alto de la barra de armas de abajo: la flecha y la barra no la tapan

var player: Node3D
var progress := 0.0                   ## 0..1
var is_open := false
var _ambushed := false
var _bars: Node3D
var _ring_mat: StandardMaterial3D
var _label: Label3D
var _speech: Label3D
var _mage: Node3D
var _beam: MeshInstance3D
var _hud: CanvasLayer
var _arrow: Control

static func spawn(parent: Node, pos: Vector3, p_player: Node3D) -> MageCage:
	var c := MageCage.new()
	c.player = p_player
	parent.add_child(c)
	c.global_position = pos
	return c

func _ready() -> void:
	add_to_group("mage_cage")
	_build_ring()
	_build_cage()
	_build_mage()
	_label = _label3d("EL MAGO · QUÉDATE CERCA PARA LIBERARLO", 22)
	_label.position.y = BAR_H + 0.9
	add_child(_label)
	_speech = _label3d("", 20)
	_speech.position.y = BAR_H + 1.35
	_speech.visible = false
	add_child(_speech)
	var glow := OmniLight3D.new()
	glow.light_color = COLOR
	glow.light_energy = 1.4
	glow.omni_range = 5.0
	glow.position.y = 1.4
	add_child(glow)
	_build_beam()
	_build_hud()

# ───────────────────────────── piezas ─────────────────────────────

func _unshaded(col: Color, alpha: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(col, alpha)
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m

func _build_ring() -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = RADIUS - 0.25
	torus.outer_radius = RADIUS
	ring.mesh = torus
	ring.scale = Vector3(1.0, 0.2, 1.0)
	ring.position.y = 0.1
	_ring_mat = _unshaded(COLOR, 0.55)
	ring.material_override = _ring_mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)

func _build_cage() -> void:
	_bars = Node3D.new()
	add_child(_bars)
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.16, 0.15, 0.18)
	iron.roughness = 0.6
	iron.metallic = 0.5
	var bar_mesh := CylinderMesh.new()
	bar_mesh.top_radius = 0.045
	bar_mesh.bottom_radius = 0.045
	bar_mesh.height = BAR_H
	bar_mesh.radial_segments = 6
	for i in BARS:
		var a := TAU * float(i) / float(BARS)
		var b := MeshInstance3D.new()
		b.mesh = bar_mesh
		b.material_override = iron
		b.position = Vector3(cos(a) * BAR_R, BAR_H * 0.5, sin(a) * BAR_R)
		_bars.add_child(b)
	for y in [0.06, BAR_H]:
		var hoop := MeshInstance3D.new()
		var t := TorusMesh.new()
		t.inner_radius = BAR_R - 0.06
		t.outer_radius = BAR_R + 0.06
		t.rings = 16
		t.ring_segments = 6
		hoop.mesh = t
		hoop.material_override = iron
		hoop.position.y = y
		_bars.add_child(hoop)
	# tapa: disco de hierro con la runa del Nigromante (morada)
	var lid := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = BAR_R + 0.1
	cyl.bottom_radius = BAR_R + 0.1
	cyl.height = 0.08
	lid.mesh = cyl
	lid.material_override = iron
	lid.position.y = BAR_H + 0.04
	_bars.add_child(lid)
	var rune := MeshInstance3D.new()
	var rt := TorusMesh.new()
	rt.inner_radius = 0.35
	rt.outer_radius = 0.45
	rune.mesh = rt
	var rm := _unshaded(Color(0.75, 0.3, 1.0))
	rune.material_override = rm
	rune.scale = Vector3(1.0, 0.3, 1.0)
	rune.position.y = BAR_H + 0.1
	_bars.add_child(rune)

func _build_mage() -> void:
	if not ResourceLoader.exists(MAGE_PATH):
		return
	var ps := load(MAGE_PATH) as PackedScene
	_mage = ps.instantiate() as Node3D if ps else null
	if _mage == null:
		return
	add_child(_mage)
	CharacterLookApplier.apply_to(_mage, DungeonHub.mage_look())
	for mi in _mage.find_children("*", "MeshInstance3D", true, false):
		if String(mi.name).begins_with(CharacterLookApplier.BODY_NODE):
			continue
		var mesh := (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var src := mesh.surface_get_material(i)
			var m := DungeonHub.salon_material(src.resource_name if src else "", src) as StandardMaterial3D
			m.vertex_color_use_as_albedo = false
			(mi as MeshInstance3D).set_surface_override_material(i, m)
	_play("mago_idle", true)

## Columna de luz alta: se ve desde lejos por encima de las hordas.
func _build_beam() -> void:
	_beam = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.35
	cyl.bottom_radius = 0.6
	cyl.height = 30.0
	cyl.radial_segments = 8
	cyl.cap_top = false
	cyl.cap_bottom = false
	_beam.mesh = cyl
	var m := _unshaded(COLOR, 0.22)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_beam.material_override = m
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.position.y = BAR_H + 15.0   # sobre la tapa: no tapa al mago
	add_child(_beam)

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 35
	add_child(_hud)
	_arrow = Control.new()
	_arrow.set_anchors_preset(Control.PRESET_FULL_RECT)
	_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrow.draw.connect(_draw_hud)
	_hud.add_child(_arrow)

func _label3d(text: String, size: int) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.fixed_size = true
	l.pixel_size = 0.0011
	l.font_size = size
	l.outline_size = 8
	l.modulate = COLOR
	l.outline_modulate = Color(0.05, 0.02, 0.05)
	l.no_depth_test = true
	l.render_priority = 10
	return l

func _play(clip: String, loop: bool = false) -> void:
	if _mage == null:
		return
	var found := _mage.find_children("*", "AnimationPlayer", true, false)
	if found.is_empty():
		return
	var ap := found[0] as AnimationPlayer
	if not ap.has_animation(clip):
		return
	if loop:
		ap.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	ap.play(clip, 0.3)

# ───────────────────────────── juego ─────────────────────────────

func player_inside() -> bool:
	if not is_instance_valid(player):
		return false
	return Vector2(player.global_position.x - global_position.x, player.global_position.z - global_position.z).length() <= RADIUS

func _process(delta: float) -> void:
	if is_instance_valid(_arrow):
		_arrow.queue_redraw()
	if is_open:
		return
	step(delta, player_inside())

## Avanza el progreso (separado para las pruebas).
func step(delta: float, inside: bool) -> void:
	if is_open:
		return
	if inside and not _ambushed:
		_ambushed = true
		ambushed.emit()
	progress = clampf(progress + (delta / HOLD if inside else -delta * DECAY / HOLD), 0.0, 1.0)
	_ring_mat.albedo_color = Color(COLOR.lerp(Color.WHITE, progress), 0.55 + 0.45 * progress)
	_label.text = "LIBERANDO AL MAGO %d%%" % int(progress * 100.0) if progress > 0.0 else "EL MAGO · QUÉDATE CERCA PARA LIBERARLO"
	if progress >= 1.0:
		open()

## Abre la jaula: guarda el rescate y el mago da las gracias antes de irse al salón.
func open() -> void:
	if is_open:
		return
	is_open = true
	progress = 1.0
	SaveManager.set_mago_rescatado(true)
	_label.text = "¡MAGO LIBERADO!"
	_speech.text = THANKS
	_speech.visible = true
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_bars, "position:y", -BAR_H - 0.3, 0.9).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(_beam, "scale", Vector3(2.5, 1.0, 2.5), 0.6)
	if get_tree().current_scene:
		NecroVFX.shockwave(get_tree().current_scene, global_position, RADIUS * 2.0, COLOR)
	AudioManager.play("kill_burst", -4.0, 1.2)
	AudioManager.play("orb_cast", -2.0, 0.9)
	HitFeedback.shake(0.25)
	_play("mago_reverencia")
	rescued.emit()
	# Se teletransporta al salón: destello y desaparece
	get_tree().create_timer(LEAVE_AFTER).timeout.connect(func():
		if not is_instance_valid(self):
			return
		if get_tree().current_scene:
			NecroVFX.shockwave(get_tree().current_scene, global_position, 3.0, COLOR)
		AudioManager.play("impact_magic", -4.0, 1.2)
		var t2 := create_tween()
		t2.tween_property(self, "scale", Vector3(0.01, 0.01, 0.01), 0.35)
		t2.tween_callback(queue_free))

## Flecha en el borde de la pantalla (si la jaula no se ve) y barra de progreso abajo.
func _draw_hud() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var vp := _arrow.get_viewport_rect().size
	var at := global_position + Vector3(0, 1.5, 0)
	var dist := 0.0
	if is_instance_valid(player):
		dist = Vector2(player.global_position.x - global_position.x, player.global_position.z - global_position.z).length()
	var font: Font = RumbangStyle.FONT
	if progress > 0.0 and not is_open:
		var w := minf(360.0, vp.x * 0.5)
		var r := Rect2(Vector2((vp.x - w) * 0.5, vp.y - HUD_BOTTOM - 40.0), Vector2(w, 18.0))
		_arrow.draw_rect(r.grow(3.0), Color(0.03, 0.02, 0.05))
		_arrow.draw_rect(Rect2(r.position, Vector2(w * progress, r.size.y)), COLOR)
		_arrow.draw_string(font, r.position + Vector2(0, -8), "LIBERANDO AL MAGO", HORIZONTAL_ALIGNMENT_CENTER, w, 16, Color.WHITE)
	if is_open:
		return
	var on_screen := not cam.is_position_behind(at)
	var sp := cam.unproject_position(at) if on_screen else Vector2.ZERO
	var margin := 40.0
	var area := Rect2(Vector2(margin, margin), vp - Vector2(margin * 2.0, margin + HUD_BOTTOM))
	if on_screen and area.has_point(sp):
		return
	# Dirección en el plano de la cámara (si está detrás, se invierte)
	var center := area.get_center()
	var dir: Vector2
	if on_screen:
		dir = (sp - center).normalized()
	else:
		# Detrás de la cámara: la flecha apunta hacia abajo y hacia el lado donde está
		var local := cam.global_transform.affine_inverse() * at
		dir = Vector2(local.x, absf(local.z) * 0.5 + maxf(-local.y, 0.0)).normalized()
		if dir == Vector2.ZERO:
			dir = Vector2.DOWN
	var half := area.size * 0.5
	var k := minf(half.x / maxf(absf(dir.x), 0.001), half.y / maxf(absf(dir.y), 0.001))
	var p := center + dir * k
	var side := Vector2(-dir.y, dir.x)
	var tip := p + dir * 16.0
	var pts := PackedVector2Array([tip, p - dir * 8.0 + side * 13.0, p - dir * 8.0 - side * 13.0])
	var ink := PackedVector2Array([tip + dir * 3.0, p - dir * 10.0 + side * 16.0, p - dir * 10.0 - side * 16.0])
	_arrow.draw_colored_polygon(ink, Color(0.03, 0.02, 0.05))
	_arrow.draw_colored_polygon(pts, COLOR)
	var txt := "MAGO %d m" % int(dist)
	_arrow.draw_string_outline(font, p - dir * 40.0 - Vector2(80, -6), txt, HORIZONTAL_ALIGNMENT_CENTER, 160, 12, 6, Color(0.03, 0.02, 0.05))
	_arrow.draw_string(font, p - dir * 40.0 - Vector2(80, -6), txt, HORIZONTAL_ALIGNMENT_CENTER, 160, 12, COLOR)
