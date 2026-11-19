class_name EnemyRoutine
extends RefCounted

## Lo que hace un enemigo de mazmorra ANTES de ver al jugador (DungeonGoblin.routine; null = sin rutina).
## DungeonEncounter puebla la caverna cuando el jugador se acerca por el túnel (aún tras la niebla) y reparte
## rutinas con `plan`: al asomarse, la sala ya está habitada.
##   GATHER  reunidos en torno a la hoguera (o al centro), charlando
##   SLEEP   tumbado y roncando: casi no oye, tarda en levantarse y recibe más daño
##   PATROL  ronda entre varios puntos de la sala
##   GUARD   vigila una boca de túnel, barriendo con la mirada: ve de lejos
##   WANDER  da vueltas sin rumbo (ratas, babosas)
## Detección: cada rutina tiene su radio. Por la espalda oyen menos; si el jugador corre, más. Un ruido cercano
## (un golpe, una esquiva, fauna espantada) los pone SUSPICIOUS: miran hacia allí y afinan el oído unos segundos.
## Al notar al jugador pasan a REACT (un respingo con "!") y avisan al grupo con la señal `alerted` del enemigo;
## el encuentro despierta entonces a los demás, cada uno con su retardo.
## Emboscada: un golpe a quien aún no te ha visto hace AMBUSH_MULT de daño (SLEEP_MULT si duerme).

enum Kind { GATHER, SLEEP, PATROL, GUARD, WANDER }
enum Phase { CALM, SUSPICIOUS, REACT }

const NOTICE := {Kind.GATHER: 7.0, Kind.SLEEP: 2.2, Kind.PATROL: 9.0, Kind.GUARD: 11.5, Kind.WANDER: 6.5}   ## m
const REACT_TIME := {Kind.GATHER: 0.55, Kind.SLEEP: 1.5, Kind.PATROL: 0.4, Kind.GUARD: 0.3, Kind.WANDER: 0.5}  ## s
const FOV_DOT := 0.1                  ## por delante = dentro de un cono de ~170°
const BACK_FACTOR := 0.45             ## por la espalda solo oyen: radio × esto
const RUN_SPEED := 5.0                ## m/s del jugador a partir de los cuales hace ruido (andando no llega)
const RUN_FACTOR := 1.35
const SUSPICIOUS_FACTOR := 1.5
const SUSPICIOUS_TIME := 4.0
const AMBUSH_MULT := 1.75
const SLEEP_MULT := 2.5
const AMBUSH_GRACE := 0.5             ## s tras el respingo en los que el golpe aún cuenta como emboscada
const PATROL_SPEED := 0.35            ## fracción de su velocidad
const WANDER_SPEED := 0.28
const SLEEPERS := ["goblin", "brute", "rat_big", "zombie"]
const WANDERERS := ["rat", "slug", "slug_red", "slug_small"]
const GUARDS := ["goblin", "brute", "mage", "rat_big"]
const MARK_COLORS := {"!": Color(1.0, 0.36, 0.12), "?": Color(1.0, 0.86, 0.3), "Zzz": Color(0.72, 0.86, 1.0),
	"...": Color(0.92, 0.92, 0.86)}

var kind: int = Kind.GATHER
var phase: int = Phase.CALM
var room := -1
var anchor := Vector3.ZERO            ## dónde está (o en torno a qué se mueve)
var look := Vector3.FORWARD           ## hacia dónde mira en reposo
var points: Array[Vector3] = []       ## ronda (PATROL)
var silent := false                   ## sin ronquidos ni "Zzz" (el zombi tumbado es un cadáver)
var _point_i := 0
var _pause := 0.0
var _t := 0.0
var _voice_t := 0.0
var _react_left := 0.0
var _react_t := 0.0                   ## s desde que notó al jugador
var _suspect_at := Vector3.ZERO
var _mark: Label3D
var _model_xf := Transform3D.IDENTITY
var _posed := false
var _walking := false
var _announced := false
var _player_last := Vector3.INF
var _player_speed := 0.0

# ───────────────────────────── Reparto en la sala ─────────────────────────────

## Sitio y rutina de cada miembro del grupo: [{pos: Vector3, routine: EnemyRoutine}], en el orden de `kinds`.
static func plan(map: DungeonMap, room_i: int, kinds: Array) -> Array:
	var center := map.room_center(room_i)
	var reach := map.room_reach(room_i)
	var focus := _focus(map, room_i, center, reach)
	var mouths: Array = []
	for group in map.room_mouths(room_i):
		var m := Vector3.ZERO
		for q in group:
			m += q
		mouths.append(m / float((group as Array).size()))
	var n := kinds.size()
	var sleepers_left := 0 if n <= 1 else maxi(1, n / 4)
	var patrols_left := 0 if n < 3 else (2 if n >= 6 else 1)
	var guards_left := 0 if n < 4 or mouths.is_empty() else 1
	var out: Array = []
	var ring := 0
	for k in n:
		var kd: String = kinds[k]
		var r := EnemyRoutine.new()
		r.room = room_i
		var pos := center
		if WANDERERS.has(kd):
			r.kind = Kind.WANDER
			pos = _free(map, focus + _polar(randf() * TAU, randf_range(1.5, reach * 0.55)), center)
		elif guards_left > 0 and GUARDS.has(kd):
			guards_left -= 1
			r.kind = Kind.GUARD
			var mouth: Vector3 = mouths[randi() % mouths.size()]
			var inward := (center - mouth)
			inward.y = 0.0
			inward = inward.normalized()
			pos = _free(map, mouth + inward * 4.5, center)
			r.look = -inward
		elif patrols_left > 0 and kd != "mage":
			patrols_left -= 1
			r.kind = Kind.PATROL
			var a0 := randf() * TAU
			for j in 3:
				var p := _free(map, center + _polar(a0 + TAU * float(j) / 3.0, reach * randf_range(0.45, 0.62)), center)
				if r.points.is_empty() or _line_ok(map, r.points.back(), p):
					r.points.append(p)
			if r.points.size() < 2:
				r.kind = Kind.GATHER
			else:
				pos = r.points[0]
		elif sleepers_left > 0 and SLEEPERS.has(kd) and randf() < 0.6:
			sleepers_left -= 1
			r.kind = Kind.SLEEP
			r.silent = kd == "zombie"
			pos = _free(map, focus + _polar(randf() * TAU, randf_range(3.6, 4.8)), center)
			r.look = _polar(randf() * TAU, 1.0)
		if r.kind == Kind.GATHER:
			# Corro en torno al foco, mirando hacia él
			var a := TAU * float(ring) / float(maxi(n - 1, 3)) + randf_range(-0.2, 0.2)
			ring += 1
			pos = _free(map, focus + _polar(a, randf_range(2.3, 3.1)), center)
			r.look = (focus - pos).normalized() if pos.distance_to(focus) > 0.3 else Vector3.FORWARD
		r.anchor = pos
		out.append({"pos": pos, "routine": r})
	return out

## Foco de la sala: la hoguera (fuego a ras de suelo) más cercana al centro, o el propio centro.
static func _focus(map: DungeonMap, room_i: int, center: Vector3, reach: float) -> Vector3:
	var best := center
	var best_d := reach * 0.75
	for pt in (map.ambient_points.get("fire", PackedVector3Array()) as PackedVector3Array):
		if pt.y > 1.0 or not map.is_in_room(pt, room_i):
			continue
		var d := Vector2(pt.x - center.x, pt.z - center.z).length()
		if d < best_d:
			best_d = d
			best = Vector3(pt.x, 0.0, pt.z)
	return best

static func _polar(angle: float, dist: float) -> Vector3:
	return Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)

static func _cell_ok(map: DungeonMap, p: Vector3) -> bool:
	var c := map.world_to_cell(p)
	return map._cells.has(c) and not map._walls.has(c) and not map._blocked.has(c)

## Acerca `p` al centro hasta que cae en suelo libre.
static func _free(map: DungeonMap, p: Vector3, center: Vector3) -> Vector3:
	p.y = 0.0
	for t in 7:
		if _cell_ok(map, p):
			break
		p = p.lerp(Vector3(center.x, 0.0, center.z), 0.3)
	return p

static func _line_ok(map: DungeonMap, a: Vector3, b: Vector3) -> bool:
	var steps := maxi(2, int(a.distance_to(b)))
	for i in steps + 1:
		if not _cell_ok(map, a.lerp(b, float(i) / float(steps))):
			return false
	return true

# ───────────────────────────── Vida de la rutina ─────────────────────────────

## Al asignarla: coloca la pose de partida.
func begin(g: DungeonGoblin) -> void:
	_voice_t = randf_range(1.5, 6.0)
	_pause = randf_range(0.2, 1.0)
	if kind == Kind.PATROL:
		_point_i = 1                      # ya está en el primer punto de la ronda: sale hacia el segundo
	if look.length_squared() > 0.01:
		g._facing = look.normalized()
	if kind == Kind.SLEEP:
		_lie_down(g)
		if not silent:
			_set_mark(g, "Zzz")

## Un tick mientras el enemigo está en IDLE. Devuelve su velocidad horizontal.
func tick(g: DungeonGoblin, delta: float, to_p: Vector3, dist: float) -> Vector3:
	_t += delta
	_track_player(g, delta)
	if phase == Phase.REACT:
		_react_t += delta
		if kind != Kind.SLEEP or _react_left < 0.5:
			_stand_up(g)
		if to_p.length_squared() > 0.01:
			g._turn_towards(to_p, delta)
		_react_left -= delta
		if _react_left <= 0.0:
			finish(g)
			g._set_state(DungeonGoblin.State.APPROACH)
		return Vector3.ZERO
	if dist <= notice_radius(g, to_p) and g._sees_player():
		notice(g)
		return Vector3.ZERO
	if phase == Phase.SUSPICIOUS:
		var at := _suspect_at - g.global_position
		at.y = 0.0
		if at.length_squared() > 0.05:
			g._turn_towards(at, delta)
		_walk(g, false)
		_react_left -= delta
		if _react_left <= 0.0:
			phase = Phase.CALM
			_set_mark(g, "")
		return Vector3.ZERO
	match kind:
		Kind.SLEEP:
			_voice_t -= delta
			if _voice_t <= 0.0 and not silent:
				_voice_t = randf_range(3.2, 4.6)
				AudioManager.play_at("goblin_snore", g.global_position, -9.0, randf_range(0.85, 1.1) * g.sfx_pitch)
			if _mark:
				_mark.position.y = g.hit_height + 0.55 + 0.08 * sin(_t * 1.6)
		Kind.GATHER:
			g._turn_towards(look, delta)
			_voice_t -= delta
			if _voice_t <= 0.0:
				_voice_t = randf_range(5.0, 11.0)
				AudioManager.play_at("goblin_chatter", g.global_position, -11.0, randf_range(0.9, 1.2) * g.sfx_pitch)
				_pop(g, "...", 1.1)
		Kind.GUARD:
			# Barre con la mirada a los lados de la boca que vigila
			g._turn_towards(look.rotated(Vector3.UP, 0.6 * sin(_t * 0.7)), delta)
		Kind.PATROL:
			return _follow(g, delta, PATROL_SPEED)
		Kind.WANDER:
			if points.is_empty():
				points = [_wander_point(g)]
			return _follow(g, delta, WANDER_SPEED)
	_walk(g, false)
	return Vector3.ZERO

## Camina de punto en punto, con una pausa en cada uno.
func _follow(g: DungeonGoblin, delta: float, pace: float) -> Vector3:
	if _pause > 0.0:
		_pause -= delta
		_walk(g, false)
		return Vector3.ZERO
	var goal: Vector3 = points[_point_i % points.size()]
	var to := goal - g.global_position
	to.y = 0.0
	if to.length() < 0.5:
		_point_i += 1
		_pause = randf_range(1.0, 2.8)
		if kind == Kind.WANDER:
			points = [_wander_point(g)]
			_point_i = 0
		return Vector3.ZERO
	var dir := to.normalized()
	g._turn_towards(dir, delta)
	_walk(g, true)
	return dir * g.speed * pace

func _wander_point(g: DungeonGoblin) -> Vector3:
	for attempt in 6:
		var p := anchor + _polar(randf() * TAU, randf_range(1.2, 3.4))
		if g.map == null or (_cell_ok(g.map, p) and _line_ok(g.map, g.global_position, p)):
			return p
	return anchor

func _walk(g: DungeonGoblin, on: bool) -> void:
	if on == _walking:
		return
	_walking = on
	g._play("walk" if on else "idle", 0.25)

func _track_player(g: DungeonGoblin, delta: float) -> void:
	if not is_instance_valid(g.player):
		return
	var pp := g.player.global_position
	if _player_last != Vector3.INF:
		_player_speed = lerpf(_player_speed, Vector2(pp.x - _player_last.x, pp.z - _player_last.z).length() / maxf(delta, 0.0001), 0.25)
	_player_last = pp

## Distancia a la que ahora mismo nota al jugador (m).
func notice_radius(g: DungeonGoblin, to_p: Vector3) -> float:
	var r: float = NOTICE[kind]
	if _player_speed >= RUN_SPEED:
		r *= RUN_FACTOR
	if phase == Phase.SUSPICIOUS:
		r *= SUSPICIOUS_FACTOR
	if kind != Kind.SLEEP and to_p.length_squared() > 0.01 and g._facing.dot(to_p.normalized()) < FOV_DOT:
		r *= BACK_FACTOR
	return r

func is_unaware() -> bool:
	return phase != Phase.REACT

## ¿Un golpe ahora cuenta como emboscada? Sí mientras no te ha visto y en el instante del respingo: el propio
## tajo hace ruido, y quien se gira al oírlo sigue pillado por sorpresa.
func ambushable() -> bool:
	return phase != Phase.REACT or _react_t < AMBUSH_GRACE

## Ha oído algo en `at`: mira hacia allí y afina el oído un rato. Los dormidos no se enteran.
func suspect(g: DungeonGoblin, at: Vector3) -> void:
	if phase == Phase.REACT or kind == Kind.SLEEP:
		return
	phase = Phase.SUSPICIOUS
	_suspect_at = at
	_react_left = SUSPICIOUS_TIME
	_set_mark(g, "?")

## Ha visto al jugador (o le han avisado): respingo y, tras REACT_TIME + `delay`, a por él.
func notice(g: DungeonGoblin, delay: float = 0.0) -> void:
	if phase == Phase.REACT:
		return
	phase = Phase.REACT
	_react_left = float(REACT_TIME[kind]) + delay
	_walk(g, false)
	_set_mark(g, "")
	_pop(g, "!", 0.9, 1.5)
	AudioManager.play_at(g.warn_sfx, g.global_position, -4.0, randf_range(1.05, 1.25) * g.sfx_pitch)
	if not _announced:
		_announced = true
		g.alerted.emit(g)

## Un golpe mientras seguía en su rutina: devuelve el daño ya multiplicado y la termina.
func on_hit(g: DungeonGoblin, amount: float) -> float:
	var mult := 1.0
	if ambushable():
		mult = SLEEP_MULT if kind == Kind.SLEEP else AMBUSH_MULT
		_pop(g, "¡EMBOSCADA!", 1.2, 1.0, Color(1.0, 0.9, 0.25))
		AudioManager.play_at("alert_sting", g.global_position, -5.0)
	if not _announced:
		_announced = true
		g.alerted.emit(g)
	finish(g)
	# Un golpe flojo (rebota en la armadura) no lo deja herido: aun así ya sabe dónde está el jugador
	if g.state == DungeonGoblin.State.IDLE:
		g._set_state(DungeonGoblin.State.APPROACH)
	return amount * mult

## Deja al enemigo como si nunca hubiera tenido rutina.
func finish(g: DungeonGoblin) -> void:
	_stand_up(g)
	_set_mark(g, "")
	if g.routine == self:
		g.routine = null

# ───────────────────────────── Poses y marcas ─────────────────────────────

func _lie_down(g: DungeonGoblin) -> void:
	var m := g.get_model()
	if m == null or _posed:
		return
	_model_xf = m.transform
	_posed = true
	# Boca arriba: la cabeza hacia atrás y el cuerpo a ras de suelo
	m.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5) * _model_xf.basis,
		_model_xf.origin + Vector3(0.0, g.model_height * 0.18, -g.model_height * 0.45))
	if g._anim:
		g._anim.speed_scale = 0.35

func _stand_up(g: DungeonGoblin) -> void:
	if not _posed:
		return
	_posed = false
	var m := g.get_model()
	if m:
		m.transform = _model_xf
	if g._anim:
		g._anim.speed_scale = 1.0

static func _label(text: String, color: Color, size: int) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = false
	l.fixed_size = false
	l.pixel_size = 0.006
	l.font_size = size
	l.outline_size = int(size * 0.32)
	l.outline_modulate = Color(0.05, 0.04, 0.06)
	l.modulate = color
	return l

## Marca fija sobre la cabeza ("" la quita).
func _set_mark(g: DungeonGoblin, text: String) -> void:
	if _mark and is_instance_valid(_mark):
		_mark.queue_free()
	_mark = null
	if text == "":
		return
	_mark = _label(text, MARK_COLORS.get(text, Color.WHITE), 64)
	_mark.position = Vector3(0.0, g.hit_height + 0.55, 0.0)
	g.add_child(_mark)

## Marca que salta, sube y se va sola.
func _pop(g: DungeonGoblin, text: String, life: float, grow: float = 1.0, color: Color = Color.TRANSPARENT) -> void:
	var l := _label(text, MARK_COLORS.get(text, Color.WHITE) if color == Color.TRANSPARENT else color, 80)
	l.position = Vector3(0.0, g.hit_height + 0.6, 0.0)
	l.scale = Vector3.ONE * 0.3
	g.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector3.ONE * grow, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "position:y", l.position.y + 0.45, life)
	tw.tween_property(l, "modulate:a", 0.0, 0.25)
	tw.tween_callback(l.queue_free)
