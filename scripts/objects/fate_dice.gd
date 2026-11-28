class_name FateDice
extends Node3D

## DADO DEL DESTINO (supervivencia: 12 caras, ver OUTCOMES12; mazmorra: 6 caras, abajo): aparece al azar en el mapa; al acercarte se pregunta si lo
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
## Supervivencia: dado de 12 caras (dodecaedro). 1-4 malas, 5-12 buenas; 12 = premio gordo.
const OUTCOMES12 := {
	1: {"id": "catastrofe", "title": "¡CATÁSTROFE!", "desc": "Emboscada, un élite y maldición", "color": Color(0.9, 0.12, 0.15), "good": false},
	2: {"id": "emboscada", "title": "¡EMBOSCADA!", "desc": "Aparecen enemigos a tu alrededor", "color": Color(1.0, 0.3, 0.25), "good": false},
	3: {"id": "maldicion", "title": "¡MALDICIÓN!", "desc": "-25% daño y velocidad (20 s)", "color": Color(0.75, 0.35, 1.0), "good": false},
	4: {"id": "herida", "title": "¡HERIDA!", "desc": "Pierdes el 40% de tu vida actual", "color": Color(0.8, 0.2, 0.35), "good": false},
	5: {"id": "bolsa", "title": "BOLSA DE ORO", "desc": "Un puñado de oro", "color": Color(1.0, 0.85, 0.3), "good": true},
	6: {"id": "regalo", "title": "¡REGALO!", "desc": "Dos objetos del mapa", "color": Color(0.35, 0.85, 1.0), "good": true},
	7: {"id": "furia", "title": "¡FURIA!", "desc": "+50% daño y +20% velocidad (30 s)", "color": Color(1.0, 0.55, 0.15), "good": true},
	8: {"id": "cura", "title": "¡CURA!", "desc": "Vida completa", "color": Color(0.45, 1.0, 0.45), "good": true},
	9: {"id": "tesoro", "title": "¡TESORO!", "desc": "El botín de un cofre", "color": Color(1.0, 0.8, 0.25), "good": true},
	10: {"id": "lluvia_xp", "title": "¡LLUVIA DE XP!", "desc": "Una nube de experiencia", "color": Color(0.5, 0.9, 1.0), "good": true},
	11: {"id": "bendicion", "title": "¡BENDICIÓN!", "desc": "Vida completa y +100% daño, +40% velocidad (30 s)", "color": Color(1.0, 0.95, 0.6), "good": true},
	12: {"id": "jackpot", "title": "¡¡JACKPOT!!", "desc": "Vida completa, furia, oro y dos cofres de botín", "color": Color(1.0, 0.4, 0.9), "good": true},
}
const FACES_SURVIVAL := 12
const D12_RADIUS := 0.4
const BLESS_TIME := 30.0
const WOUND_FRACTION := 0.4
const WOUND_MIN_HP_FRACTION := 0.1       ## la herida nunca baja de esto de la vida máxima
const GOLD_JACKPOT := 150
const XP_RAIN_ORBS := 8
const XP_RAIN_EACH := 35.0
const CURSE_TIME := 20.0
const FURY_TIME := 30.0
const AMBUSH_SURVIVAL := 8
const AMBUSH_DUNGEON := 3
const GOLD_SURVIVAL := 60

var player: Node3D
var faces := 6                            ## 12 en supervivencia, 6 en la mazmorra
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
## Dado de 12: "arriba" de cada número en el espacio del dado (para que el resultado se lea derecho).
var _num_up := {}

# ───────────────────────────── aparición ─────────────────────────────

static func spawn(parent: Node, pos: Vector3, p_lifetime: float = 0.0) -> FateDice:
	var d := FateDice.new()
	d.lifetime = p_lifetime
	d.faces = FACES_SURVIVAL if GameData.game_mode != "dungeon" else 6
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
	var mesh := MapPickup.toon_mesh("pickup_dice") if faces == 6 else null
	if faces == 12:
		_build_d12()
	elif mesh != null:
		_die.mesh = mesh
	else:
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE * 0.5
		_die.mesh = bm
	_die.scale = Vector3.ONE * (1.45 if faces == 12 else 1.3)
	_die.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_holder.add_child(_die)
	if faces == 12:
		_add_d12_numbers()
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
	var table := _outcomes()
	for v in range(1, faces + 1):
		var label := String(table[v]["title"]).trim_prefix("¡").trim_suffix("!").trim_suffix("!")
		desc += "%d %s%s" % [v, label, "\n" if faces == 6 or v % 4 == 0 else " · "]
	var ui := DungeonChoiceUI.present(get_tree().current_scene, "DADO DEL DESTINO", "¿LO TIRAS? DEL 1 AL %d: PUEDE IR MUY BIEN… O MUY MAL" % faces, [
		{"id": "tirar", "icon": "🎲", "title": "Tirarlo", "color": GOLD_COLOR, "desc": desc.strip_edges()},
		{"id": "dejar", "icon": "✋", "title": "Dejarlo", "color": Color(0.7, 0.7, 0.7), "desc": "Puedes volver luego"},
	])
	ui.chosen.connect(func(id):
		_asking = false
		if id == "tirar" and is_instance_valid(self):
			roll()
		elif is_instance_valid(self):
			_label.text = "ALÉJATE Y VUELVE")

func _outcomes() -> Dictionary:
	return OUTCOMES12 if faces == 12 else OUTCOMES

## Tira el dado (`forced` 1..caras para las pruebas; 0 = al azar).
func roll(forced: int = 0) -> void:
	if _rolling or _done:
		return
	_value = forced if forced >= 1 and forced <= faces else randi_range(1, faces)
	_rolling = true
	_roll_t = 0.0
	_holder.visible = true
	_label.visible = false
	_spin_axis = Vector3(randf_range(-1, 1), randf_range(0.2, 1), randf_range(-1, 1)).normalized()
	# Orientación final: la cara del valor mirando arriba y un giro al azar alrededor de la vertical
	var up: Vector3 = face_up(faces, _value)
	var q := Quaternion(up, Vector3.UP) if up.dot(Vector3.DOWN) < 0.999 else Quaternion(Vector3.RIGHT, PI)
	_final = Basis(Vector3.UP, _final_yaw(Basis(q))) * Basis(q)
	AudioManager.play("dash", -6.0, 1.3)

## Giro final alrededor de la vertical: el número que queda arriba se lee derecho desde la cámara (su "arriba"
## apunta lejos de ella). Sin número o sin cámara, al azar.
func _final_yaw(face_basis: Basis) -> float:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if not _num_up.has(_value) or cam == null:
		return randf() * TAU
	var u: Vector3 = face_basis * (_num_up[_value] as Vector3)
	var away := global_position - cam.global_position
	u.y = 0.0
	away.y = 0.0
	if u.length_squared() < 0.0001 or away.length_squared() < 0.0001:
		return randf() * TAU
	return u.signed_angle_to(away, Vector3.UP)

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
	var o: Dictionary = _outcomes()[_value]
	var col: Color = o["color"]
	var good: bool = o.get("good", _value >= 3)
	HitFeedback.shake(0.25 if good else 0.4)
	AudioManager.play("level-up" if good else "boss_sting", -4.0, 1.0 + 0.04 * _value)
	NecroVFX.shockwave(get_tree().current_scene, global_position, 6.0, col)
	_label.visible = true
	_label.text = "%d · %s" % [_value, String(o["title"])]
	_label.modulate = col
	_label.font_size = 56
	announce(String(o["title"]), col, String(o["desc"]))
	if faces == 12:
		apply12(_value, player, get_tree().current_scene, global_position)
	else:
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
##
## ── PATRÓN STRATEGY: FateDice es el CONTEXT ──
## ANTES (ERROR 1 y 5): aquí había un `match v` de 6 ramas y un `if survival` dentro de cada una; todo el
## comportamiento de cada cara vivía en este método y había que editarlo para tocar un resultado.
## AHORA: el dado solo (1) arma el contexto, (2) busca la estrategia de esa cara y (3) la ejecuta.
## Qué hace cada cara está en scripts/patterns/strategy/fate_outcomes.gd (FateOutcomes.table).
static func apply(v: int, p: Node3D, scene: Node, at: Vector3) -> void:
	if p == null or scene == null:
		return
	var ctx := FateContext.make(p, scene, at, OUTCOMES[v]["color"])
	# CORRECCIÓN ERROR 5: el modo (supervivencia / mazmorra) elige la TABLA, ya no se bifurca dentro de cada rama.
	var outcome: FateOutcome = FateOutcomes.table(6, ctx.survival).get(v)
	if outcome != null:
		outcome.apply(ctx)

static func _floor(scene: Node, p: Vector3) -> Vector3:
	if scene and scene.has_method("get_floor_y"):
		return Vector3(p.x, scene.get_floor_y(p.x, p.z), p.z)
	return p

# CORRECCIÓN ERROR 5: aquí estaba _ambush(p, scene, enc, survival) con otro `if survival:` dentro. Se partió en dos
# estrategias: FateOutcomes.AmbushSurvivalOutcome y FateOutcomes.AmbushDungeonOutcome. Igual desaparecieron
# _heal_full() y _add_gold() (ERRORES 6 y 7): ahora son FateOutcomes.HealFullOutcome y FateOutcomes.GoldOutcome.

## Normal (hacia fuera) de la cara `v`: el cubo usa FACE_UP; el dodecaedro, las 12 direcciones de los vértices
## del icosaedro ordenadas de arriba abajo (la cara 1 queda en lo alto del modelo).
static func face_up(n_faces: int, v: int) -> Vector3:
	if n_faces == 6:
		return FACE_UP[v]
	return d12_normals()[v - 1]

static var _d12_normals: Array = []

static func d12_normals() -> Array:
	if _d12_normals.is_empty():
		var phi := (1.0 + sqrt(5.0)) * 0.5
		# Normales de las caras de ESTE dodecaedro (d12_vertices): (0, ±φ, ±1) y permutaciones cíclicas. Antes
		# eran (0, ±1, ±φ), las del dodecaedro girado: cada "cara" juntaba esquinas de caras vecinas y el dado
		# salía deforme y con agujeros.
		var raw: Array = [Vector3(0, phi, 1), Vector3(0, -phi, 1), Vector3(0, phi, -1), Vector3(0, -phi, -1),
			Vector3(phi, 1, 0), Vector3(-phi, 1, 0), Vector3(phi, -1, 0), Vector3(-phi, -1, 0),
			Vector3(1, 0, phi), Vector3(-1, 0, phi), Vector3(1, 0, -phi), Vector3(-1, 0, -phi)]
		raw.sort_custom(func(a: Vector3, b: Vector3): return a.normalized().y > b.normalized().y)
		for r: Vector3 in raw:
			_d12_normals.append(r.normalized())
	return _d12_normals

## Vértices del dodecaedro (radio 1).
static func d12_vertices() -> Array:
	var phi := (1.0 + sqrt(5.0)) * 0.5
	var ip := 1.0 / phi
	var vs: Array = []
	for x in [-1.0, 1.0]:
		for y in [-1.0, 1.0]:
			for z in [-1.0, 1.0]:
				vs.append(Vector3(x, y, z))
	for a in [-1.0, 1.0]:
		for b in [-1.0, 1.0]:
			vs.append(Vector3(0, a * ip, b * phi))
			vs.append(Vector3(a * ip, b * phi, 0))
			vs.append(Vector3(a * phi, 0, b * ip))
	return vs.map(func(v: Vector3): return v.normalized())

## Las 5 esquinas de la cara de normal `n`, ordenadas alrededor.
static func d12_face_corners(n: Vector3) -> Array:
	var vs := d12_vertices()
	vs.sort_custom(func(a: Vector3, b: Vector3): return a.dot(n) > b.dot(n))
	var corners: Array = vs.slice(0, 5)
	var center := Vector3.ZERO
	for c: Vector3 in corners:
		center += c
	center /= 5.0
	var ax: Vector3 = (corners[0] - center).normalized()
	var ay := n.cross(ax)
	corners.sort_custom(func(a: Vector3, b: Vector3): return atan2((a - center).dot(ay), (a - center).dot(ax)) < atan2((b - center).dot(ay), (b - center).dot(ax)))
	return corners

func _face_center(n: Vector3) -> Vector3:
	var center := Vector3.ZERO
	for c: Vector3 in d12_face_corners(n):
		center += c
	return center / 5.0 * D12_RADIUS

## Aspecto del dado de 12: cuerpo morado (dos tonos alternos para distinguir caras vecinas), cada cara con un
## bisel más oscuro alrededor (las aristas se leen aunque gire) y números dorados con contorno de tinta; las
## caras malas (1-4) llevan el número rojo. Antes: caras doradas/naranjas teñidas por cada resultado, con los
## colores de vértice tomados como lineales (se veía crema lavado) y números negros finos que parecían manchas.
const D12_FACE_A := Color(0.36, 0.17, 0.62)
const D12_FACE_B := Color(0.27, 0.12, 0.5)
const D12_BEVEL := Color(0.13, 0.05, 0.24)
const D12_INSET := 0.8                    ## tamaño de la cara plana frente al pentágono entero (el resto es bisel)
const D12_BEVEL_TILT := 0.45              ## cuánto se inclina la normal del bisel hacia la arista (aristas redondeadas)
const D12_NUM_GOOD := Color(1.0, 0.86, 0.35)
const D12_NUM_BAD := Color(1.0, 0.36, 0.3)
const D12_NUM_JACKPOT := Color(1.0, 0.55, 0.95)
const D12_INK := Color(0.04, 0.02, 0.06)

func _build_d12() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var normals := d12_normals()
	for i in normals.size():
		var n: Vector3 = normals[i]
		var corners := d12_face_corners(n)
		var col := D12_FACE_A if i % 2 == 0 else D12_FACE_B
		var center := _face_center(n)
		var inner: Array = []
		for c: Vector3 in corners:
			inner.append(center.lerp(c * D12_RADIUS, D12_INSET))
		for k in 5:
			var k2 := (k + 1) % 5
			var a: Vector3 = corners[k] * D12_RADIUS
			var b: Vector3 = corners[k2] * D12_RADIUS
			var ia: Vector3 = inner[k]
			var ib: Vector3 = inner[k2]
			# cara plana
			for v: Vector3 in [center, ib, ia]:
				st.set_color(col)
				st.set_normal(n)
				st.add_vertex(v)
			# bisel: la normal del borde exterior se abre hacia la arista
			var edge_n := (n + ((a + b) * 0.5 - center).normalized() * D12_BEVEL_TILT).normalized()
			for v: Vector3 in [ia, ib, b, ia, b, a]:
				var outer := v == a or v == b
				st.set_color(D12_BEVEL)
				st.set_normal(edge_n if outer else n)
				st.add_vertex(v)
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	mat.specular_mode = BaseMaterial3D.SPECULAR_TOON
	mat.roughness = 0.35
	# un poco de luz propia: de noche (DayNightCycle) sigue leyéndose
	mat.emission_enabled = true
	mat.emission = Color(0.1, 0.04, 0.18)
	mesh.surface_set_material(0, mat)
	_die.mesh = mesh
	# Borde de tinta: el mismo dado un poco mayor, visto solo por dentro
	var hull := MeshInstance3D.new()
	hull.mesh = mesh
	hull.scale = Vector3.ONE * 1.06
	var hm := StandardMaterial3D.new()
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.albedo_color = Color(0.04, 0.025, 0.05)
	hm.cull_mode = BaseMaterial3D.CULL_FRONT
	hull.material_override = hm
	hull.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_die.add_child(hull)

## Número de cada cara pegado sobre ella (hijos del dado: giran con él).
func _add_d12_numbers() -> void:
	var f := (load("res://scripts/objects/floating_damage.gd") as GDScript).comic_font() as Font
	var normals := d12_normals()
	for i in normals.size():
		var n: Vector3 = normals[i]
		var v := i + 1
		var l := Label3D.new()
		# 6 y 9 con punto, como en los dados de verdad (si no, no se sabe cuál es cuál)
		l.text = str(v) + ("." if v == 6 or v == 9 else "")
		l.pixel_size = 0.0026
		l.font_size = 72 if v < 10 else 60
		l.modulate = D12_NUM_JACKPOT if v == 12 else (D12_NUM_GOOD if OUTCOMES12[v].get("good", true) else D12_NUM_BAD)
		l.outline_size = 14
		l.outline_modulate = D12_INK
		l.double_sided = false
		l.shaded = false
		l.alpha_cut = Label3D.ALPHA_CUT_DISCARD
		if f:
			l.font = f
		var up_ref := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
		l.basis = Basis.looking_at(-n, up_ref)
		l.position = _face_center(n) + n * 0.006
		_die.add_child(l)
		_num_up[v] = l.basis.y

# ───────────────────────────── resultados del dado de 12 (supervivencia) ─────────────────────────────

## Aplica el resultado `v` (1..12) de la supervivencia. 1-4 malos, 5-12 buenos.
## CORRECCIÓN ERROR 2: antes era un segundo `match v` (12 ramas) casi clonado de apply(); ahora usa la MISMA
## mecánica de apply(): tabla de estrategias + execute. Las caras 1, 11 y 12 son combinaciones (CompositeOutcome)
## de estrategias que ya existían, en vez de copiar sus líneas (ERRORES 3, 4, 6, 7 y 8).
static func apply12(v: int, p: Node3D, scene: Node, at: Vector3) -> void:
	if p == null or scene == null:
		return
	var ctx := FateContext.make(p, scene, at, OUTCOMES12[v]["color"])
	var outcome: FateOutcome = FateOutcomes.table(12, true).get(v)
	if outcome != null:
		outcome.apply(ctx)

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
## RENDIMIENTO: el texto solo cambia una vez por segundo y el estilo solo cuando cambia el color. Antes se
## reaplicaban 8 overrides de tema en cada frame (la etiqueta se rehacía entera cada frame) y el texto llevaba
## el emoji 🎲, que PressStart2P no tiene: cada rehecho buscaba la fuente emoji del sistema → caída fuerte de FPS
## en el móvil durante FURIA (santuario o dado).
class FateStatus extends CanvasLayer:
	var _label: Label
	var _shown_text := ""
	var _shown_col := Color(0, 0, 0, 0)

	func _ready() -> void:
		layer = 55
		_label = Label.new()
		_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_label.offset_top = 96.0
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
		var txt := "  ·  ".join(parts)
		if txt != _shown_text:
			_shown_text = txt
			_label.text = txt
		if col != _shown_col:
			_shown_col = col
			RumbangStyle.style_title(_label, 14, col, col.darkened(0.4))
