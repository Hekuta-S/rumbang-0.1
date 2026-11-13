class_name HiveMind
extends RefCounted

## Mente colmena de la horda: una vez por tick de física, ANTES de actualizar a ningún enemigo,
## calcula lo que comparte toda la multitud. Los enemigos solo LEEN de aquí (nunca escriben), así
## cada dato se calcula una vez por tick y no una vez por enemigo.
##
## Fase 1: datos de la multitud y de los jugadores.
## Fase 2: densidad por celda para la separación (separation_push).
## Pendiente (plan de mente colmena, supervivencia): escuadras lejanas y tokens de ataque.

## A partir de cuántos enemigos vivos se reparte la IA entre ticks (crowd_scale), y hasta cuánto.
const CROWD_REF := 120.0
const CROWD_MAX := 5.0
## Cada cuántos ticks se vuelve a buscar la lista de jugadores en el árbol (entran/salen poco).
const PLAYER_REFRESH_TICKS := 30

## Enemigos de datos vivos en este tick.
static var alive: int = 0
## >= 1: cuánto se espacian las actualizaciones de IA cuando la multitud es grande (ver EnemyData).
static var crowd_scale: float = 1.0
## Posición de cada jugador vivo en este tick (en LAN, todos los de "net_players"; si no, el local).
static var player_positions: PackedVector3Array = PackedVector3Array()

## El jugador al que persiguen los enemigos (EnemyManager.player_node) y su posición en este tick:
## se lee una vez aquí en vez de una o dos veces por enemigo (global_position de un nodo cuesta).
static var local_player: Node3D = null
static var local_player_pos: Vector3 = Vector3.ZERO

static var _players: Array = []
static var _players_age: int = PLAYER_REFRESH_TICKS

## Llamado por EnemyManager al empezar cada tick de física.
static func begin_tick(tree: SceneTree, alive_count: int) -> void:
	alive = alive_count
	crowd_scale = clampf(float(alive_count) / CROWD_REF, 1.0, CROWD_MAX)
	_refresh_players(tree)
	local_player = EnemyManager.player_node()
	if local_player != null:
		local_player_pos = local_player.global_position

static func _refresh_players(tree: SceneTree) -> void:
	_players_age += 1
	if _players_age >= PLAYER_REFRESH_TICKS and tree != null:
		_players_age = 0
		_players = tree.get_nodes_in_group("net_players")
		if _players.is_empty():
			_players = tree.get_nodes_in_group("player")
	player_positions.resize(0)
	var i := 0
	while i < _players.size():
		var p = _players[i]
		if p == null or not is_instance_valid(p) or not (p as Node).is_inside_tree():
			_players.remove_at(i)
			continue
		player_positions.append((p as Node3D).global_position)
		i += 1

## Posición del jugador más cercano a `pos` (en XZ). Devuelve `pos` si no hay jugadores.
static func nearest_player_pos(pos: Vector3) -> Vector3:
	var best := pos
	var best_d2 := INF
	for pp: Vector3 in player_positions:
		var dx := pp.x - pos.x
		var dz := pp.z - pos.z
		var d2 := dx * dx + dz * dz
		if d2 < best_d2:
			best_d2 = d2
			best = pp
	return best

# ───────────────────────────── Tokens de ataque (cuerpo a cuerpo) ─────────────────────────────
## Solo MELEE_TOKENS enemigos cuerpo a cuerpo pueden atacar al jugador a la vez; el resto espera en un
## anillo alrededor (ver EnemyBehavior.MeleeGoblinBehavior). Tras cada golpe el token se suelta y el
## que golpeó espera TOKEN_RETRY s antes de pedir otro, así los turnos rotan por la horda.
## RUMBANG_HIVE_TOKENS=0 los desactiva (todos atacan como antes).
const MELEE_TOKENS := 12
const TOKEN_RETRY := 1.0
static var use_tokens: bool = OS.get_environment("RUMBANG_HIVE_TOKENS") != "0"
static var tokens_used: int = 0

## Intenta darle un token a `e` (true si ya lo tenía o si quedaba alguno libre).
static func acquire_token(e) -> bool:
	if not use_tokens or e.has_token:
		return true
	if e.token_wait > 0.0 or tokens_used >= MELEE_TOKENS:
		return false
	tokens_used += 1
	e.has_token = true
	return true

## Devuelve el token de `e` (si lo tenía). `retry` = segundos antes de que pueda pedir otro.
static func release_token(e, retry: float = 0.0) -> void:
	if e.has_token:
		e.has_token = false
		tokens_used = maxi(tokens_used - 1, 0)
	e.token_wait = maxf(e.token_wait, retry)

# ───────────────────────────── Densidad de la horda (separación) ─────────────────────────────
## Rejilla fina centrada en el jugador: por celda, cuántos enemigos hay y la suma de sus posiciones
## (su centroide). La separación de cada enemigo lee solo las celdas vecinas (números, no objetos):
## sustituye a recorrer los enemigos de las celdas de 6 m de EnemyRegistry, que en una horda densa
## son decenas por consulta. Se construye como mucho una vez por tick, la primera vez que alguien pregunta.
const DENS_CELL := 1.0
const DENS_SIDE := 128                 ## 128 m de lado: fuera de la ventana se usa la separación exacta
## Igual que EnemyRegistry.SEP_MAX_NEIGHBORS: en un enjambre denso basta con los primeros vecinos.
const DENS_MAX_NEIGHBORS := 6
## RUMBANG_HIVE_SEP=0 vuelve a la separación exacta de EnemyRegistry (comparativas A/B del benchmark).
static var use_density: bool = OS.get_environment("RUMBANG_HIVE_SEP") != "0"
## La foto de densidad se rehace cada tantos ticks: cada enemigo recalcula su separación solo cada
## 0.2–1.5 s (EnemyData._logic_timer), así que una foto de ~67 ms de antigüedad no se nota.
const DENS_REBUILD_TICKS := 4

static var _dcount: PackedInt32Array = PackedInt32Array()
static var _dsx: PackedFloat32Array = PackedFloat32Array()
static var _dsz: PackedFloat32Array = PackedFloat32Array()
static var _dframe: int = -1           ## tick de física de la última foto
static var _dox: int = 0               ## celda (en coordenadas de mundo) de la esquina de la ventana
static var _doz: int = 0

static func _build_density() -> void:
	var n := DENS_SIDE * DENS_SIDE
	if _dcount.size() != n:
		_dcount.resize(n)
		_dsx.resize(n)
		_dsz.resize(n)
	_dcount.fill(0)
	_dsx.fill(0.0)
	_dsz.fill(0.0)
	var center := player_positions[0] if player_positions.size() > 0 else Vector3.ZERO
	var inv := 1.0 / DENS_CELL
	var half := DENS_SIDE / 2
	_dox = int(floor(center.x * inv)) - half
	_doz = int(floor(center.z * inv)) - half
	for e in EnemyRegistry.all():
		var p: Vector3 = e.global_position
		var ix := int(floor(p.x * inv)) - _dox
		var iz := int(floor(p.z * inv)) - _doz
		var is_data: bool = e is EnemyData
		if ix < 0 or iz < 0 or ix >= DENS_SIDE or iz >= DENS_SIDE:
			if is_data:
				e.hive_cell = -1
			continue
		var i := iz * DENS_SIDE + ix
		if is_data:
			e.hive_cell = i
		_dcount[i] += 1
		_dsx[i] += p.x
		_dsz[i] += p.z

## Empuje de separación horizontal sobre `me` a partir de la densidad de las celdas vecinas: cada celda
## empuja desde su centroide con (1 - d/radius) por enemigo (como EnemyRegistry.separation_push, pero
## tratando cada celda como un grupo). Fuera de la ventana se usa la separación exacta.
static func separation_push(me: Object, radius: float) -> Vector3:
	var frame := Engine.get_physics_frames()
	if _dframe < 0 or frame - _dframe >= DENS_REBUILD_TICKS or frame < _dframe:
		_dframe = frame
		_build_density()
	var p: Vector3 = me.global_position
	var inv := 1.0 / DENS_CELL
	var mx := int(floor(p.x * inv)) - _dox
	var mz := int(floor(p.z * inv)) - _doz
	if mx < 0 or mz < 0 or mx >= DENS_SIDE or mz >= DENS_SIDE:
		return EnemyRegistry.separation_push(me, radius)
	# Solo se descuenta a sí mismo de la celda donde lo contó la foto (si se movió desde entonces, no está)
	var self_cell: int = me.hive_cell if me is EnemyData else mz * DENS_SIDE + mx
	var span := int(ceil(radius * inv))
	var r2 := radius * radius
	var pushx := 0.0
	var pushz := 0.0
	var budget := DENS_MAX_NEIGHBORS
	for iz in range(maxi(mz - span, 0), mini(mz + span, DENS_SIDE - 1) + 1):
		for ix in range(maxi(mx - span, 0), mini(mx + span, DENS_SIDE - 1) + 1):
			var i := iz * DENS_SIDE + ix
			var m := _dcount[i]
			var sx := _dsx[i]
			var sz := _dsz[i]
			if i == self_cell:
				# Su celda en la foto: se descuenta a sí mismo del grupo (con la posición de la foto ≈ la actual)
				m -= 1
				sx -= p.x
				sz -= p.z
			if m <= 0:
				continue
			var ax := p.x - sx / float(m)
			var az := p.z - sz / float(m)
			var d2 := ax * ax + az * az
			if d2 > r2:
				continue
			if d2 < 0.0001:
				ax = randf() - 0.5
				az = randf() - 0.5
				d2 = 0.25
			var d := sqrt(d2)
			var k := mini(m, budget)
			var w := (1.0 - minf(d / radius, 1.0)) / d * float(k)
			pushx += ax * w
			pushz += az * w
			budget -= k
			if budget <= 0:
				return Vector3(pushx, 0.0, pushz)
	return Vector3(pushx, 0.0, pushz)

## Olvida todo (cambio de escena / reinicio).
static func reset() -> void:
	alive = 0
	crowd_scale = 1.0
	player_positions.resize(0)
	local_player = null
	local_player_pos = Vector3.ZERO
	_players = []
	_players_age = PLAYER_REFRESH_TICKS
	_dframe = -1
	tokens_used = 0
