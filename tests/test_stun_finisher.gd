extends Node

## Fase 1 del plan de mejora: colores de aviso por forma de evitarlo, barra de aturdimiento y
## remates (PlayerFinisherController). Carga la mazmorra real.

var _player: CharacterBody3D

func _ready() -> void:
	print("--- TEST: ATURDIMIENTO Y REMATES ---")
	GameData.game_mode = "dungeon"
	SaveManager.save_path = "user://test_save.json"   # no tocar la partida guardada real
	SaveManager.meta = {}
	var scene: Node = load("res://scenes/core/main_dungeon.tscn").instantiate()
	get_tree().root.add_child.call_deferred(scene)
	await get_tree().process_frame
	get_tree().current_scene = scene
	var enc: DungeonEncounter = null
	for i in 600:
		await get_tree().process_frame
		enc = scene.get_node_or_null("DungeonEncounter")
		if enc and enc.map and is_instance_valid(enc.player):
			break
	enc._pending.clear()
	_player = enc.player
	_player.health_comp.max_hp = 9999.0
	_player.health_comp.hp = 9999.0
	var c := enc.map.room_center(enc.map.arena_index)
	_player.global_position = c + Vector3(0, 0.3, 0)

	# 1. Cómo se evita cada ataque (y su color)
	assert(DungeonGoblin.guard_kind(DungeonGoblin.ATTACKS["slam"]) == "parry", "El porrazo del goblin se para")
	assert(DungeonGoblin.guard_kind(DungeonBrute.BRUTE_ATTACKS["stomp"]) == "dodge", "El pisotón del bruto solo se esquiva")
	assert(DungeonGoblin.guard_kind(DungeonMage.MAGE_ATTACKS["bolt"]) == "ranged", "El orbe del mago es un proyectil")
	assert(DungeonGoblin.guard_kind(DungeonNecromancer.NECRO_ATTACKS["eruption"]) == "dodge", "Las erupciones solo se esquivan")
	var g := enc.spawn_goblin()
	await get_tree().physics_frame
	g._atk = g.attacks["slam"]
	g._set_state(DungeonGoblin.State.WINDUP)
	var col: Vector3 = (g._telegraph.material_override as ShaderMaterial).get_shader_parameter("color")
	assert(col.is_equal_approx(Vector3(DungeonGoblin.GUARD_PARRY.r, DungeonGoblin.GUARD_PARRY.g, DungeonGoblin.GUARD_PARRY.b)),
		"El aviso de un ataque que se para es ámbar (%s)" % col)
	print("CHECK 1 PASSED: parry / esquiva / proyectil y aviso ámbar")

	# 2. La barra se llena: golpes flojos poco, pesados del todo; llena → STUNNED
	g._set_state(DungeonGoblin.State.APPROACH)
	g.take_damage(10.0, Vector3(0, 0, 3))
	assert(absf(g._stun - 5.0) < 0.01, "Un golpe de 10 llena 5 (%s)" % g._stun)
	assert(g.state != DungeonGoblin.State.STUNNED, "Un golpe flojo no lo deja indefenso")
	g.hp = g.max_hp
	g.take_damage(20.0, Vector3(0, 0, 3))   # pesado: aturde y llena 20
	g._set_state(DungeonGoblin.State.RECOVER)
	g.hp = g.max_hp
	g.take_damage(20.0, Vector3(0, 0, 3))   # castigo en la recuperación: 20 × 1,5 = 30 → 55 ≥ 36
	assert(g.state == DungeonGoblin.State.STUNNED, "Barra llena (%.0f / %.0f) → indefenso (estado %d)" % [g._stun, g.stun_max(), g.state])
	assert(g.can_be_finished(), "Indefenso se puede rematar")
	g.take_damage(5.0, Vector3.ZERO)
	assert(g.state == DungeonGoblin.State.STUNNED, "Los golpes no lo sacan de STUNNED")
	await get_tree().physics_frame
	assert(g._stun_bar.visible, "La barrita de aturdimiento se ve")
	assert(g._hp_bar.visible and g._hp_bar.position.y > g._stun_bar.position.y, "La barra de vida se ve encima de la de aguante")
	print("CHECK 2 PASSED: barra %.0f, 10 → 5, pesado y castigo → indefenso" % g.stun_max())

	# 3. Remate: el ataque lo lanza, el goblin muere y el jugador se cura
	var fin: PlayerFinisherController = _player.finisher_controller
	assert(fin != null, "En la mazmorra el jugador tiene remates")
	g.global_position = _player.global_position + Vector3(0, 0, -2.0)
	await get_tree().physics_frame
	await get_tree().process_frame
	assert(fin.candidate() == g, "El goblin indefenso a 2 m es candidato")
	assert(fin._prompt.visible, "Se ve el aviso REMATE")
	_player.health_comp.hp = 5000.0
	_player.attack()
	assert(fin.is_active() and _player.is_finishing(), "El ataque lanza el remate")
	assert(_player.health_comp.is_invincible(), "Invulnerable durante el remate")
	for i in 5000:   # con cámara lenta y hitstop, cada fotograma avanza muy poco tiempo de juego
		await get_tree().process_frame
		if not fin.is_active():
			break
	assert(g.is_dead(), "Un remate mata a un enemigo normal")
	assert(_player.health_comp.hp > 5000.0, "El remate cura (%.0f)" % _player.health_comp.hp)
	# El hitstop y la cámara lenta van en tiempo real
	await get_tree().create_timer(0.4, true, false, true).timeout
	await get_tree().process_frame
	assert(is_equal_approx(Engine.time_scale, 1.0), "La cámara lenta termina (%.2f)" % Engine.time_scale)
	print("CHECK 3 PASSED: remate mata, cura y termina la cámara lenta")

	# 4. Si no se le remata, se le pasa
	var g2 := enc.spawn_goblin()
	await get_tree().physics_frame
	g2._add_stun(g2.stun_max())
	assert(g2.state == DungeonGoblin.State.STUNNED, "Barra llena de golpe → indefenso")
	for i in int((g2.stunned_time + 0.3) * 60.0):
		await get_tree().physics_frame
	assert(g2.state != DungeonGoblin.State.STUNNED and g2._stun == 0.0, "Pasado el aturdimiento vuelve a pelear con la barra vacía")
	g2.take_damage(9999.0, Vector3.ZERO)
	print("CHECK 4 PASSED: el aturdimiento se pasa en %.1f s" % g2.stunned_time)

	# 5. Jefe: el remate quita un 12 % y sigue vivo; el parry llena su barra
	var n := enc.spawn_necromancer()
	await get_tree().physics_frame
	n._set_state(DungeonGoblin.State.APPROACH)
	n._on_parried()
	assert(absf(n._stun - n.stun_max() * n.stun_parry) < 0.01, "El parry llena el %d %% de la barra del jefe" % int(n.stun_parry * 100))
	n._add_stun(n.stun_max())
	var before := n.hp
	n.receive_finisher(Vector3(0, 0, 10))
	assert(absf(before - n.hp - n.max_hp * 0.12) < 0.5, "El remate le quita el 12 %% al jefe (%.0f)" % (before - n.hp))
	assert(not n.is_dead() and n.state == DungeonGoblin.State.STAGGER, "Sobrevive y cae de espaldas")
	print("CHECK 5 PASSED: remate al jefe = 12 % de vida")

	print("ALL STUN/FINISHER CHECKS PASSED")
	get_tree().quit(0)
