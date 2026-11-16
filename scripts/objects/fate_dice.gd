class_name FateDice
extends Node3D

## DADO DEL DESTINO (supervivencia y mazmorra): aparece al azar en el mapa; al acercarte se pregunta si lo
## tiras. Si lo tiras salta, da vueltas y cae del 1 al 6:
##   1 EMBOSCADA  aparecen enemigos a tu alrededor
##   2 MALDICIÓN  -25 % de daño y de velocidad durante 20 s
##   3 BOLSA      oro
##   4 FURIA      +50 % de daño y +20 % de velocidad durante 30 s
##   5 REGALO     supervivencia: dos objetos del mapa (bomba, imán, comida, reloj); mazmorra: una pieza de equipo
##   6 FORTUNA    vida completa y botín grande (cofre de supervivencia sin maldición / equipo raro y oro)
## Si lo dejas, vuelve a preguntar cuando te alejes y regreses. En supervivencia desaparece a los 45 s.
## Las mejoras y castigos temporales suman a PlayerStatBlock._total mediante FateDice.stat_total (reloj de
## partida: se paran con la pausa). Modelo: tools/blender_toon_pickups.py (pickup_dice).

signal rolled(value: int)

const RADIUS := 2.0
const REARM_RADIUS := 4.0
const LIFETIME_SURVIVAL := 45.0
const BLINK_FROM := 38.0
const ROLL_TIME := 1.35
const JUMP_H := 2.4
const GOLD_COLOR := Color(1.0, 0.8, 0.3)
## Cara que queda arriba para cada valor (Godot, Y arriba; ver tools/blender_toon_pickups.py)
const FACE_UP := {1: Vector3.UP, 6: Vector3.DOWN, 2: Vector3.RIGHT, 5: Vector3.LEFT, 3: Vector3.FORWARD, 4: Vector3.BACK}
const OUTCOMES := {
	1: {"id": "emboscada", "title": "¡EMBOSCADA!", "desc": "Aparecen enemigos a tu alrededor", "color": Color(1.0, 0.3, 0.25)},
	2: {"id": "maldicion", "title": "¡MALDICIÓN!", "desc": "-25% daño y velocidad (20 s)", "color": Color(0.75, 0.35, 1.0)},
	3: {"id": "bolsa", "title": "BOLSA DE ORO", "desc": "Un puñado de oro", "color": Color(1.0, 0.85, 0.3)},
	4: {"id": "furia", "title": "¡FURIA!", "desc": "+50% daño y +20% velocidad (30 s)", "color": Color(1.0, 0.55, 0.15)},
	5: {"id": "regalo", "title": "¡REGALO!", "desc": "Un objeto para ti", "color": Color(0.35, 0.85, 1.0)},
	6: {"id": "fortuna", "title": "¡FORTUNA!", "desc": "Vida completa y gran botín", "color": Color(0.45, 1.0, 0.45)},
}
const CURSE_TIME := 20.0
const FURY_TIME := 30.0
const AMBUSH_SURVIVAL := 8
const AMBUSH_DUNGEON := 3
const GOLD_SURVIVAL := 60

var player: Node3D
var lifetime := 0.0                       ## 0 = no desaparece (mazmorra)
var _holder: Node3D
var _die: MeshInstance3D
var _label: Label3D
var _t := 0.0
var _armed := true
var _asking := false
var _rolling := false
var _roll_t := 0.0
var _value := 0
var _spin_axis := Vector3.ONE
var _final := Basis.IDENTITY
var _done := false

# ───────────────────────────── aparición ─────────────────────────────

static func spawn(parent: Node, pos: Vector3, p_lifetime: float = 0.0) -> FateDice:
	var d := FateDice.new()
	d.lifetime = p_lifetime
	d.player = parent.get_tree().get_first_node_in_group("player")
	parent.add_child(d)
	d.global_position = pos
	return d

func _ready() -> void:
	add_to_group("fate_dice")
	_holder = Node3D.new()
	_holder.position = Vector3(0, 1.0, 0)
	add_child(_holder)
	_die = MeshInstance3D.new()
	var mesh := MapPickup.toon_mesh("pickup_dice")
	if mesh != null:
		_die.mesh = mesh
	else:
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE * 0.5
		_die.mesh = bm
	_die.scale = Vector3.ONE * 1.3
	_die.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_holder.add_child(_die)
	_label = Label3D.new()
	_label.text = "¿TIRAR?"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.font_size = 40
	_label.modulate = GOLD_COLOR
	var f := (load("res://scripts/objects/floating_damage.gd") as GDScript).comic_font() as Font
	if f:
		_label.font = f
		_label.outline_size = 0
	else:
		_label.outline_size = 10
	_label.position = Vector3(0, 2.05, 0)
	add_child(_label)
	_add_ring()

func _add_ring() -> void:
	for pass_i in 2:
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.75 if pass_i == 1 else 0.7
		tm.outer_radius = 0.95 if pass_i == 1 else 1.02
		tm.rings = 28
		tm.ring_segments = 4
		ring.mesh = tm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = GOLD_COLOR if pass_i == 1 else Color(0.03, 0.022, 0.05)
		ring.material_override = m
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.scale = Vector3(1.0, 0.12, 1.0)
		ring.position.y = 0.06 if pass_i == 1 else 0.04
		add_child(ring)

# ───────────────────────────── bucle ─────────────────────────────

func _process(delta: float) -> void:
	_t += delta
	if _rolling:
		_update_roll(delta)
		return
	if _done:
		return
	_holder.rotation.y += delta * 1.4
	_holder.rotation.x = sin(_t * 1.3) * 0.3
	_holder.position.y = 1.0 + sin(_t * 2.6) * 0.12
	if lifetime > 0.0:
		if _t > BLINK_FROM:
			_holder.visible = int(_t * 8.0) % 2 == 0
		if _t >= lifetime:
			queue_free()
			return
	if not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
		return
	var d := Vector2(player.global_position.x - global_position.x, player.global_position.z - global_position.z).length()
	if not _armed and d > REARM_RADIUS:
		_armed = true
		_label.text = "¿TIRAR?"
	if _armed and not _asking and d <= RADIUS:
		ask()

## Pregunta si se tira (pausa el juego mientras se elige).
func ask() -> void:
	_asking = true
	_armed = false
	var desc := ""
	for v in range(1, 7):
		desc += "%d %s\n" % [v, String(OUTCOMES[v]["title"]).trim_prefix("¡").trim_suffix("!")]
	var ui := DungeonChoiceUI.present(get_tree().current_scene, "DADO DEL DESTINO", "¿LO TIRAS? DEL 1 AL 6: PUEDE IR MUY BIEN… O MUY MAL", [
		{"id": "tirar", "icon": "🎲", "title": "Tirarlo", "color": GOLD_COLOR, "desc": desc.strip_edges()},
		{"id": "dejar", "icon": "✋", "title": "Dejarlo", "color": Color(0.7, 0.7, 0.7), "desc": "Puedes volver luego"},
	])
	ui.chosen.connect(func(id):
		_asking = false
		if id == "tirar" and is_instance_valid(self):
			roll()
		elif is_instance_valid(self):
			_label.text = "ALÉJATE Y VUELVE")

## Tira el dado (`forced` 1..6 para las pruebas; 0 = al azar).
func roll(forced: int = 0) -> void:
	if _rolling or _done:
		return
	_value = forced if forced >= 1 and forced <= 6 else randi_range(1, 6)
	_rolling = true
	_roll_t = 0.0
	_holder.visible = true
	_label.visible = false
	_spin_axis = Vector3(randf_range(-1, 1), randf_range(0.2, 1), randf_range(-1, 1)).normalized()
	# Orientación final: la cara del valor mirando arriba y un giro al azar alrededor de la vertical
	var up: Vector3 = FACE_UP[_value]
	var q := Quaternion(up, Vector3.UP) if not up.is_equal_approx(Vector3.DOWN) else Quaternion(Vector3.RIGHT, PI)
	_final = Basis(Vector3.UP, randf() * TAU) * Basis(q)
	AudioManager.play("dash", -6.0, 1.3)

func _update_roll(delta: float) -> void:
	_roll_t += delta
	var k := clampf(_roll_t / ROLL_TIME, 0.0, 1.0)
	# salto con un rebote al final
	var h := JUMP_H * sin(PI * minf(k / 0.8, 1.0))
	if k > 0.8:
		h = 0.35 * sin(PI * (k - 0.8) / 0.2)
	_holder.position.y = 0.45 + h
	# vueltas rápidas que frenan; el último 35 % se asienta en la cara del resultado
	var spin := Basis(_spin_axis, (1.0 - pow(1.0 - k, 2.0)) * TAU * 3.5)
	_holder.rotation = Vector3.ZERO
	var w := smoothstep(0.65, 1.0, k)
	_holder.basis = Basis(Quaternion(spin.orthonormalized()).slerp(Quaternion(_final.orthonormalized()), w))
	if k >= 1.0:
		_rolling = false
		_done = true
		_resolve()

func _resolve() -> void:
	var o: Dictionary = OUTCOMES[_value]
	var col: Color = o["color"]
	HitFeedback.shake(0.25)
	AudioManager.play("level-up" if _value >= 3 else "boss_sting", -4.0, 1.0 + 0.05 * _value)
	NecroVFX.shockwave(get_tree().current_scene, global_position, 6.0, col)
	_label.visible = true
	_label.text = "%d · %s" % [_value, String(o["title"])]
	_label.modulate = col
	_label.font_size = 56
	announce(String(o["title"]), col, String(o["desc"]))
	apply(_value, player, get_tree().current_scene, global_position)
	rolled.emit(_value)
	var tw := create_tween()
	tw.tween_interval(2.2)
	tw.tween_property(_holder, "scale", Vector3.ONE * 0.01, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_label, "modulate:a", 0.0, 0.35)
	tw.tween_callback(queue_free)

# ───────────────────────────── resultados ─────────────────────────────

## Cartel grande: el de los eventos en supervivencia, el de la mazmorra en la mazmorra; si no, un aviso.
func announce(title: String, col: Color, sub: String) -> void:
	var scene := get_tree().current_scene
	var events = _events(scene)
	if events:
		events.announce(title, col, sub)
		return
	var enc := scene.get_node_or_null("DungeonEncounter") if scene else null
	if enc and enc.has_method("_show_banner"):
		enc._show_banner(title)
	EquipmentPickup.toast(self, sub, col)

static func _events(scene: Node):
	if scene and scene.get("facade") and scene.facade.wave_manager and scene.facade.wave_manager.get("events"):
		return scene.facade.wave_manager.events
	return null

## Aplica el resultado `v` (pública para las pruebas). `at` = dónde cayó el dado.
static func apply(v: int, p: Node3D, scene: Node, at: Vector3) -> void:
	if p == null or scene == null:
		return
	var survival := GameData.game_mode != "dungeon"
	var enc: Node = scene.get_node_or_null("DungeonEncounter")
	match v:
		1:
			_ambush(p, scene, enc, survival)
		2:
			add_mod("damage", -0.25, CURSE_TIME, "MALDICIÓN", OUTCOMES[2]["color"])
			add_mod("move_speed", -0.25, CURSE_TIME, "", OUTCOMES[2]["color"])
		3:
			if survival:
				var gs := GameState.get_instance()
				gs.add_gold(GOLD_SURVIVAL)
				if scene.get("facade"):
					scene.facade.update_gold(gs.gold)
			elif enc and enc.has_method("_add_gold"):
				enc._add_gold(30 + 15 * int(enc.get("level")))
		4:
			add_mod("damage", 0.5, FURY_TIME, "FURIA", OUTCOMES[4]["color"])
			add_mod("move_speed", 0.2, FURY_TIME, "", OUTCOMES[4]["color"])
		5:
			if survival:
				for k in 2:
					var a := TAU * k / 2.0 + randf()
					MapPickup.spawn(scene, _floor(scene, at + Vector3(cos(a), 0, sin(a)) * 1.6), MapPickup.roll_kind())
			else:
				EquipmentPickup.try_drop(scene, at + Vector3(0, 0, 1.2), 1.0, 1)
		6:
			if p.has_method("heal") and p.get("health_comp"):
				p.heal(p.health_comp.max_hp)
			if survival:
				var events = _events(scene)
				var sb = p.get("stat_block")
				if events:
					events._grant_rewards(at, ChestRoulette.roll(sb.luck() if sb != null else 0.0))
			else:
				EquipmentPickup.try_drop(scene, at + Vector3(0, 0, 1.2), 1.0, 2)
				if enc and enc.has_method("_add_gold"):
					enc._add_gold(20 * maxi(1, int(enc.get("level"))))

static func _floor(scene: Node, p: Vector3) -> Vector3:
	if scene and scene.has_method("get_floor_y"):
		return Vector3(p.x, scene.get_floor_y(p.x, p.z), p.z)
	return p

## Enemigos alrededor del jugador: anillo de normales en supervivencia; goblins (y un bruto desde el
## nivel 2) en la caverna donde estés en la mazmorra.
static func _ambush(p: Node3D, scene: Node, enc: Node, survival: bool) -> void:
	var c := p.global_position
	if survival:
		var events = _events(scene)
		var wm = scene.facade.wave_manager if scene.get("facade") else null
		if wm == null:
			return
		for k in AMBUSH_SURVIVAL:
			var a := TAU * k / float(AMBUSH_SURVIVAL)
			var pos := c + Vector3(cos(a), 0, sin(a)) * 9.0
			wm._spawn_single_enemy(events._ground(pos) if events else pos)
		return
	if enc == null:
		return
	var map: DungeonMap = enc.get("map")
	var room := int(map._owner.get(map.world_to_cell(c), 0)) if map else 0
	var level := int(enc.get("level"))
	for k in AMBUSH_DUNGEON + (1 if level >= 2 else 0):
		var a := TAU * k / float(AMBUSH_DUNGEON + 1) + randf()
		var kind := "brute" if k == AMBUSH_DUNGEON else "goblin"
		enc._spawn_at(room, c + Vector3(cos(a), 0, sin(a)) * 5.5, kind)

# ───────────────────────────── mejoras y castigos temporales ─────────────────────────────

## [{stat, value, until (s del reloj del dado), label, color}]
static var _mods: Array = []
static var _clock := 0.0
static var _status: FateStatus

## Suma `value` a `stat` (las mismas claves que PlayerStatBlock: damage, move_speed…) durante `seconds`.
static func add_mod(stat: String, value: float, seconds: float, label: String = "", color: Color = Color.WHITE) -> void:
	_ensure_status()
	_mods.append({"stat": stat, "value": value, "until": _clock + seconds, "label": label, "color": color})

static func stat_total(stat: String) -> float:
	if _mods.is_empty():
		return 0.0
	if not is_instance_valid(_status):          # partida nueva o escena cambiada: nada sigue activo
		_mods.clear()
		return 0.0
	var t := 0.0
	for m in _mods:
		if m["stat"] == stat and float(m["until"]) > _clock:
			t += float(m["value"])
	return t

static func clear_mods() -> void:
	_mods.clear()
	if is_instance_valid(_status):
		_status.queue_free()
	_status = null

static func _ensure_status() -> void:
	if is_instance_valid(_status):
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null:
		return
	_mods.clear()
	_clock = 0.0
	_status = FateStatus.new()
	tree.current_scene.add_child(_status)

## Indicador de lo que dure del dado (arriba en el centro) y reloj de las mejoras: avanza con el juego (se
## para en la pausa) y se quita solo cuando no queda nada activo.
class FateStatus extends CanvasLayer:
	var _label: Label

	func _ready() -> void:
		layer = 55
		_label = Label.new()
		_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_label.offset_top = 96.0
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.theme = RumbangStyle.get_theme()
		add_child(_label)

	func _process(delta: float) -> void:
		FateDice._clock += delta
		var parts: Array = []
		var col := Color.WHITE
		var keep := false
		for m in FateDice._mods:
			var left := float(m["until"]) - FateDice._clock
			if left <= 0.0:
				continue
			keep = true
			if String(m["label"]) != "":
				parts.append("%s %d s" % [m["label"], ceili(left)])
				col = m["color"]
		if not keep:
			FateDice._mods.clear()
			queue_free()
			return
		_label.text = "🎲 " + "  ·  ".join(parts)
		RumbangStyle.style_title(_label, 14, col, col.darkened(0.4))
