extends Node

## Mente colmena (fase 1): datos compartidos de la multitud y de los jugadores.

func _ready() -> void:
	print("--- TEST: HIVE MIND (FASE 1) ---")
	HiveMind.reset()

	# 1. crowd_scale: igual a la fórmula anterior de EnemyManager (sin cambio de comportamiento)
	HiveMind.begin_tick(get_tree(), 0)
	assert(is_equal_approx(HiveMind.crowd_scale, 1.0), "Sin enemigos crowd_scale debe ser 1")
	HiveMind.begin_tick(get_tree(), 240)
	assert(is_equal_approx(HiveMind.crowd_scale, 2.0), "240 enemigos -> crowd_scale 2")
	HiveMind.begin_tick(get_tree(), 5000)
	assert(is_equal_approx(HiveMind.crowd_scale, HiveMind.CROWD_MAX), "crowd_scale topa en CROWD_MAX")
	assert(HiveMind.alive == 5000, "alive refleja el recuento del tick")
	print("CHECK 1 PASSED: crowd_scale y recuento de la multitud")

	# 2. Jugadores: posiciones por tick y jugador más cercano (LAN: net_players)
	var a := Node3D.new()
	var b := Node3D.new()
	add_child(a)
	add_child(b)
	a.global_position = Vector3(10, 0, 0)
	b.global_position = Vector3(-20, 0, 5)
	a.add_to_group("net_players")
	b.add_to_group("net_players")
	HiveMind.reset()
	HiveMind.begin_tick(get_tree(), 10)
	assert(HiveMind.player_positions.size() == 2, "Debe ver a los dos jugadores de red")
	assert(HiveMind.nearest_player_pos(Vector3(8, 0, 1)) == a.global_position, "Más cercano: a")
	assert(HiveMind.nearest_player_pos(Vector3(-15, 0, 0)) == b.global_position, "Más cercano: b")
	# Las posiciones se actualizan cada tick aunque la lista de jugadores esté en caché
	a.global_position = Vector3(11, 0, 0)
	HiveMind.begin_tick(get_tree(), 10)
	assert(HiveMind.player_positions[0].x == 11.0 or HiveMind.player_positions[1].x == 11.0, "Posición al día")
	print("CHECK 2 PASSED: posiciones de jugadores y jugador más cercano")

	# 3. Un jugador que sale del árbol desaparece sin esperar al refresco de la lista
	b.queue_free()
	await get_tree().process_frame
	HiveMind.begin_tick(get_tree(), 10)
	assert(HiveMind.player_positions.size() == 1, "El jugador liberado se descarta")
	assert(HiveMind.nearest_player_pos(Vector3(-15, 0, 0)) == a.global_position, "Queda solo a")
	print("CHECK 3 PASSED: jugadores liberados se descartan")

	# 4. Sin jugadores: devuelve la propia posición
	HiveMind.reset()
	a.remove_from_group("net_players")
	HiveMind.begin_tick(get_tree(), 0)
	assert(HiveMind.nearest_player_pos(Vector3(1, 2, 3)) == Vector3(1, 2, 3), "Sin jugadores, la propia posición")
	print("CHECK 4 PASSED: sin jugadores")

	a.queue_free()
	await get_tree().process_frame

	# 5. Separación por densidad (fase 2): misma dirección que la exacta en casos sencillos
	EnemyRegistry.clear()
	var e1 := _enemy(Vector3(0.2, 0, 0.5))
	var e2 := _enemy(Vector3(0.9, 0, 0.5))      # otra celda, a 0.7 m
	var lone := _enemy(Vector3(20, 0, 20))
	HiveMind.reset()
	HiveMind.begin_tick(get_tree(), 3)
	var p1 := HiveMind.separation_push(e1, 1.0)
	var p2 := HiveMind.separation_push(e2, 1.0)
	assert(p1.x < 0.0 and p2.x > 0.0, "Se empujan en sentidos opuestos")
	assert(p1.normalized().dot(EnemyRegistry.separation_push(e1, 1.0).normalized()) > 0.99, "Misma dirección que la exacta")
	assert(HiveMind.separation_push(lone, 1.0) == Vector3.ZERO, "Un enemigo aislado no recibe empuje")
	print("CHECK 5 PASSED: separación por densidad entre celdas")

	# 6. Varios en la misma celda: se descuenta a sí mismo y empuja lejos del centroide del resto
	var e3 := _enemy(Vector3(0.6, 0, 0.6))
	var e4 := _enemy(Vector3(0.4, 0, 0.4))      # misma celda que e3
	HiveMind.reset()
	HiveMind.begin_tick(get_tree(), 5)
	var p3 := HiveMind.separation_push(e3, 1.0)
	assert(p3.x > 0.0 and p3.z > 0.0, "e3 se aleja de e4 y e1 (hacia +x +z)")
	print("CHECK 6 PASSED: separación dentro de la misma celda")

	# 7. Fuera de la ventana de densidad se usa la separación exacta
	var far1 := _enemy(Vector3(500, 0, 0))
	var far2 := _enemy(Vector3(500.5, 0, 0))
	HiveMind.reset()
	HiveMind.begin_tick(get_tree(), 7)
	assert(HiveMind.separation_push(far1, 1.0) == EnemyRegistry.separation_push(far1, 1.0), "Fallback exacto fuera de la ventana")
	assert(far2 != null)
	print("CHECK 7 PASSED: fallback fuera de la ventana")

	EnemyRegistry.clear()

	# 8. Tokens de ataque: solo MELEE_TOKENS atacan a la vez; el resto rodea sin acercarse
	HiveMind.reset()
	HiveMind.use_tokens = true
	var target := Node3D.new()
	add_child(target)
	var melee: Array = []
	for k in 14:
		var m := EnemyData.new(EnemyData.EnemyType.NORMAL_GOBLIN)
		m.player = target
		m.orbit_sign = 1.0
		melee.append(m)
	var range_m: float = melee[0].attack_range
	var dist := range_m - 0.1                        # todos ya a distancia de golpe
	var to_p := Vector3(dist, 0, 0)                  # el jugador está en +x respecto al enemigo
	var waiting := 0
	for m in melee:
		var v: Vector3 = m.behavior.process_ai(0.016, to_p, dist, 3.0)
		if not m.has_token:
			waiting += 1
			assert(v.x <= 0.0, "Sin turno no se acerca al jugador (se aparta al anillo)")
			assert(absf(v.z) > 0.0, "Sin turno rodea al jugador")
	assert(HiveMind.tokens_used == HiveMind.MELEE_TOKENS, "Se reparten exactamente %d tokens" % HiveMind.MELEE_TOKENS)
	assert(waiting == 14 - HiveMind.MELEE_TOKENS, "El resto espera turno")
	print("CHECK 8 PASSED: %d atacan, %d esperan en el anillo" % [HiveMind.MELEE_TOKENS, waiting])

	# 9. Tras golpear se suelta el token (y espera TOKEN_RETRY); otro lo coge
	var holder: EnemyData = null
	for m in melee:
		if m.has_token:
			holder = m
			break
	holder.attack_cooldown = 0.0
	holder.attack_windup = 0.0
	holder.behavior.process_ai(0.5, to_p, dist, 3.0)        # windup >= 0.4: golpea
	assert(not holder.has_token and holder.token_wait > 0.0, "Tras golpear suelta el token y espera")
	assert(HiveMind.tokens_used == HiveMind.MELEE_TOKENS - 1, "Queda un token libre")
	holder.behavior.process_ai(0.016, to_p, dist, 3.0)
	assert(not holder.has_token, "Durante la espera no lo recupera")
	var taker: EnemyData = null
	for m in melee:
		if not m.has_token and m != holder:
			taker = m
			break
	taker.behavior.process_ai(0.016, to_p, dist, 3.0)
	assert(taker.has_token and HiveMind.tokens_used == HiveMind.MELEE_TOKENS, "Otro de la horda coge el turno")
	print("CHECK 9 PASSED: los turnos rotan tras cada golpe")

	# 10. Al alejarse el jugador o al volver al pool el token se devuelve
	var far_d := range_m + 1.3 + 3.5
	taker.behavior.process_ai(0.016, Vector3(far_d, 0, 0), far_d, 3.0)
	assert(not taker.has_token, "Si el jugador se aleja suelta el token")
	var pooled: EnemyData = null
	for m in melee:
		if m.has_token:
			pooled = m
			break
	var before := HiveMind.tokens_used
	EnemyManager.release(pooled)
	assert(not pooled.has_token and HiveMind.tokens_used == before - 1, "Al volver al pool devuelve el token")
	EnemyManager._free.clear()
	# Desactivados: todos atacan como antes
	HiveMind.reset()
	HiveMind.use_tokens = false
	for m in melee:
		m.has_token = false
		m.token_wait = 0.0
		assert(m.behavior.process_ai(0.016, to_p, dist, 3.0).x > 0.0, "Sin tokens todos se acercan")
	HiveMind.use_tokens = true
	print("CHECK 10 PASSED: devolución del token y modo desactivado")

	HiveMind.reset()
	print("ALL HIVE MIND CHECKS PASSED")
	get_tree().quit(0)

func _enemy(pos: Vector3) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	n.global_position = pos
	EnemyRegistry.register(n)
	return n
