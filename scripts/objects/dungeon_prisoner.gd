class_name DungeonPrisoner
extends Node3D

## Prisionero de la historia en la mazmorra (uno por mundo, WorldDefs "prisoner"): está enjaulado en una caverna
## normal. Lo coloca DungeonEncounter mientras SaveManager no lo tenga liberado y el mago ya esté rescatado.
## Al limpiar su caverna la jaula se abre (unlock); con la tecla de habilidad (E / RB / botón táctil, vía
## Player.interact_target) se le libera: cuenta su historia, se guarda (SaveManager.free_prisoner) y se va al
## salón, donde abre una estación (WorldDefs "prisoner".station; ver DungeonHub.station_locked).
## Si no se le libera en la partida, vuelve a salir en la siguiente.

signal freed(world: String)

const OPEN_DIST := 2.4
const HEIGHT := 1.75
const COLOR := Color(1.0, 0.85, 0.45)
const BARS := 10
const BAR_R := 0.85
const BAR_H := 2.3
const LINE_TIME := 3.2               ## s que se ve cada frase
const LEAVE_AFTER := 0.8             ## s tras la última frase

var world := ""
var def: Dictionary = {}
var player: Node3D
var is_open := false
var is_freed := false
var _near := false
var _bars: Node3D
var _model: Node3D
var _label: Label3D
var _prompt: Label3D
var _speech: Label3D

static func spawn(parent: Node, pos: Vector3, p_world: String, p_player: Node3D) -> DungeonPrisoner:
	var p := DungeonPrisoner.new()
	p.world = p_world
	p.def = WorldDefs.get_def(p_world).get("prisoner", {})
	p.player = p_player
	parent.add_child(p)
	p.global_position = pos
	return p

func _ready() -> void:
	add_to_group("dungeon_prisoner")
	_model = DungeonShop.make_npc(self, String(def.get("model", "tatan")), Vector3.ZERO, HEIGHT)
	_build_cage()
	_label = _label3d("PRESO: " + String(def.get("name", "PRISIONERO")), 24)
	_label.position.y = BAR_H + 0.7
	add_child(_label)
	_prompt = _label3d("E · LIBERAR", 20)
	_prompt.position.y = BAR_H + 0.4
	_prompt.visible = false
	add_child(_prompt)
	_speech = _label3d("", 20)
	_speech.position.y = BAR_H + 1.1
	_speech.visible = false
	add_child(_speech)
	var glow := OmniLight3D.new()
	glow.light_color = COLOR
	glow.light_energy = 0.9
	glow.omni_range = 4.0
	glow.position.y = 1.6
	add_child(glow)

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

## Su caverna está limpia: la jaula se abre y espera a que el jugador se acerque.
func unlock() -> void:
	if is_open:
		return
	is_open = true
	_label.text = "%s · ¡LA JAULA SE ABRIÓ!" % String(def.get("name", "PRISIONERO"))
	var tw := create_tween()
	tw.tween_property(_bars, "position:y", -BAR_H - 0.2, 0.9).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	AudioManager.play("coin", -2.0, 0.7)

func _exit_tree() -> void:
	_set_near(false)

func _process(delta: float) -> void:
	if _model and is_instance_valid(player) and not is_freed:
		var to := player.global_position - global_position
		if Vector2(to.x, to.z).length() > 0.1:
			_model.rotation.y = lerp_angle(_model.rotation.y, atan2(to.x, to.z), minf(1.0, delta * 4.0))
	if not is_open or is_freed or not is_instance_valid(player):
		_set_near(false)
		return
	var d := Vector2(player.global_position.x - global_position.x, player.global_position.z - global_position.z).length()
	_set_near(d <= OPEN_DIST)

func _set_near(on: bool) -> void:
	if on == _near:
		return
	_near = on
	if _prompt:
		_prompt.visible = on
	if not is_instance_valid(player) or not ("interact_target" in player):
		return
	if on:
		player.interact_target = self
	elif player.interact_target == self:
		player.interact_target = null

## Lo llama Player.activate_skill() cuando estás al lado.
func interact() -> void:
	if is_open and not is_freed:
		free_now()

## Liberar: se guarda ya, cuenta su historia y se va al salón.
func free_now() -> void:
	if is_freed:
		return
	is_freed = true
	_set_near(false)
	_label.text = "%s · LIBRE" % String(def.get("name", "PRISIONERO"))
	SaveManager.free_prisoner(world)
	AudioManager.play("level-up", -4.0, 1.0)
	freed.emit(world)
	var lines: Array = def.get("lines", [])
	var unlock_txt := String(def.get("unlock", ""))
	if unlock_txt != "":
		lines = lines + ["Desbloqueado en el salón: " + unlock_txt]
	_speech.visible = true
	_speech.text = String(lines[0]) if not lines.is_empty() else ""
	var tw := create_tween()
	for ln in lines:
		tw.tween_callback(func(): _speech.text = String(ln))
		tw.tween_interval(LINE_TIME)
	tw.tween_interval(LEAVE_AFTER)
	tw.tween_callback(_leave)

func _leave() -> void:
	if get_tree() and get_tree().current_scene:
		NecroVFX.shockwave(get_tree().current_scene, global_position, 2.5, COLOR)
	AudioManager.play("impact_magic", -6.0, 1.3)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3(0.01, 0.01, 0.01), 0.35)
	tw.tween_callback(queue_free)
