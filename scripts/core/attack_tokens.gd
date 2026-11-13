class_name AttackTokens
extends RefCounted

## Fichas de ataque (estilo God of War): solo unos pocos enemigos cuerpo a cuerpo pueden estar
## "comprometidos" con el jugador a la vez; el resto rodea a distancia (ver DungeonGoblin._wait_dir).
##
## Una ficha se RESERVA al acercarse a ENGAGE_DIST del jugador y se mantiene durante APPROACH/WINDUP/
## ATTACK. Se LIBERA al pasar a cualquier otro estado (RECOVER, HURT, STAGGER, STUNNED, DEAD...),
## al salir del árbol, al alejarse el jugador o por caducidad (RESERVE_MAX en APPROACH, HOLD_MAX en
## total): nunca hay fichas "perdidas" ni un enemigo que bloquee el combate.
##
## Qué consume ficha: goblins, brutos, ratas, zombis y babosas (cuerpo a cuerpo).
## NO consumen: los que atacan de lejos (DungeonMage) y los jefes (DungeonNecromancer, DungeonRatKing,
## y los jefes con script propio): siguen sus propias reglas (`uses_attack_token = false`).
## Solo corre en el anfitrión/offline: los puppets de los clientes no ejecutan IA.
## Las fichas son globales (no por jugador): en red se suma +1 por jugador extra (set_players).
##
## Coste: un Dictionary con <= MAX_CAP entradas; sin Arrays por frame.

## ── Valores a ajustar jugando ──
const BASE_TOKENS := 2                ## atacantes simultáneos al inicio
const LEVEL_STEP := 3                 ## +1 ficha cada tantos niveles de mazmorra
const CROWD_STEP := 8                 ## +1 ficha cada tantos enemigos vivos
const MAX_CAP := 5                    ## tope absoluto (sin contar jugadores extra)
const ENGAGE_DIST := 7.5              ## a menos de esto del jugador, un enemigo necesita ficha
const RESERVE_MAX := 3.5              ## s máx. con ficha acercándose sin llegar a atacar
const HOLD_MAX := 6.0                 ## s máx. con una ficha en total (red de seguridad)
const REST_AFTER_ATTACK := 0.9        ## s sin poder reservar tras atacar (si hay multitud), para rotar

static var level := 1                 ## nivel de la mazmorra (lo fija DungeonEncounter)
static var players := 1
## Enemigo -> {t: instante (s) de reserva}
static var _holders: Dictionary = {}

static func now() -> float:
	return Time.get_ticks_msec() * 0.001

static func set_level(l: int) -> void:
	level = maxi(l, 1)

static func set_players(n: int) -> void:
	players = maxi(n, 1)

## Máximo de atacantes simultáneos ahora mismo.
static func max_tokens() -> int:
	var m := BASE_TOKENS + (level - 1) / LEVEL_STEP + EnemyRegistry.count() / CROWD_STEP
	return mini(m, MAX_CAP) + (players - 1)

static func in_use() -> int:
	return _holders.size()

static func has(e: Object) -> bool:
	return _holders.has(e)

## Reserva (o conserva) una ficha para `e`. false si no queda ninguna.
static func try_acquire(e: Object) -> bool:
	var t := now()
	if _holders.has(e):
		return true
	if _holders.size() >= max_tokens():
		_purge(t)
		if _holders.size() >= max_tokens():
			return false
	_holders[e] = t
	return true

static func release(e: Object) -> void:
	_holders.erase(e)

## Segundos desde la reserva (0 si no tiene).
static func held_for(e: Object) -> float:
	if not _holders.has(e):
		return 0.0
	return now() - float(_holders[e])

## Quita fichas de enemigos liberados/muertos o que llevan demasiado.
static func _purge(t: float) -> void:
	for e in _holders.keys():
		if not is_instance_valid(e) or t - float(_holders[e]) > HOLD_MAX \
				or (e.has_method("is_dead") and e.is_dead()):
			_holders.erase(e)

static func clear() -> void:
	_holders.clear()
	level = 1
	players = 1
