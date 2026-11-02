extends Node

## Mago de mazmorra: contrato, distancia, hechizos, orbes e interrupción. Carga la mazmorra real.

var _player: CharacterBody3D
var _hp_lost := 0.0

func _ready() -> void:
	print("--- TEST: DUNGEON MAGE ---")
	GameData.game_mode = "dungeon"
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
	assert(enc != null, "La mazmorra debe crear DungeonEncounter")
	enc._pending.clear()
	_player = enc.player
	var c := enc.map.room_center(enc.map.arena_index)
	_player.global_position = c + Vector3(0, 0.3, 0)

	# 1. Contrato, clips propios y poses
	var m := enc.spawn_mage()
	await get_tree().physics_frame
	assert(m is DungeonMage, "spawn_mage debe crear un DungeonMage")
	assert(EnemyRegistry.all().has(m), "El mago debe estar en EnemyRegistry")
	assert(is_equal_approx(m.max_hp, 60.0), "Vida del mago 60 (es %s)" % m.max_hp)
	assert(absf(m.speed - 3.4) < 0.01, "Velocidad del mago 3,4 (es %s)" % m.speed)
	for clip in DungeonMage.MAGE_CLIPS:
		assert(ResourceLoader.exists(DungeonMage.MAGE_CLIPS[clip]), "Falta el clip %s" % clip)
		assert(m._anim.has_animation(clip), "El mago no cargó el clip %s" % clip)
	m.set_physics_process(false)
	var skel := m._model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	for clip in ["rune_windup", "cast"]:
		m._anim.play(clip, 0.0)
		m._anim.seek(m._anim.get_animation(clip).length if clip == "rune_windup" else 0.12, true)
		var head := skel.to_global(skel.get_bone_global_pose(skel.find_bone("mixamorig_Head")).origin)
		var hand := skel.to_global(skel.get_bone_global_pose(skel.find_bone("mixamorig_RightHand")).origin)
		var fwd := Vector2(hand.x - m.global_position.x, hand.z - m.global_position.z).dot(Vector2(m._facing.x, m._facing.z))
		print("  %s: cabeza %.2f m, mano %.2f m, mano adelantada %.2f m" % [clip, head.y - m.global_position.y, hand.y - m.global_position.y, fwd])
		if clip == "rune_windup":
			assert(hand.y > head.y, "Al preparar la runa las manos deben quedar sobre la cabeza")
		else:
			assert(fwd > 0.25, "Al lanzar el orbe la mano debe ir por delante")
	m.set_physics_process(true)
	print("CHECK 1 PASSED: contrato, 60 de vida, 3,4 m/s, 14 clips propios y poses")

	# 2. Mantiene la distancia: con el jugador a 2 m, se aleja (o usa nova/destello)
	m._atk_ready = {"nova": 999.0, "blink": 999.0}
	m._next_attack_at = 999.0
	m._set_state(DungeonGoblin.State.APPROACH)
	var dir_away := (m.global_position - _player.global_position)
	dir_away.y = 0.0
	_player.global_position = m.global_position - dir_away.normalized() * 2.0 + Vector3(0, 0.1, 0)
	var d0 := _flat(m.global_position - _player.global_position)
	for i in 60:
		await get_tree().physics_frame
	var d1 := _flat(m.global_position - _player.global_position)
	print("  distancia al jugador: %.1f m → %.1f m en 1 s" % [d0, d1])
	assert(d1 > d0 + 1.0, "Con el jugador encima, el mago debe alejarse")
	print("CHECK 2 PASSED: retrocede para mantener la distancia")

	# 3. Repertorio a distancia: orbes en vuelo, runa en el suelo del jugador y daño
	m._atk_ready.clear()
	m._next_attack_at = 0.0
	var seen := {}
	var orbs_seen := 0
	var rune_on_player := true
	var prev := -1
	for i in 60 * 16:
		await get_tree().physics_frame
		_keep_player_alive()
		if not is_instance_valid(m) or m.is_dead():
			break
		var d := _flat(m.global_position - _player.global_position)
		if d < 5.0 or d > 11.0:
			_place_player(m, enc, 8.0)
		if m.state == DungeonGoblin.State.WINDUP and prev != DungeonGoblin.State.WINDUP:
			seen[m._atk_name] = seen.get(m._atk_name, 0) + 1
		if m.state == DungeonGoblin.State.WINDUP and m._atk_name == "rune" and m._state_t < 0.5:
			var t := m._telegraph.global_position
			if _flat(t - _player.global_position) > 0.8:
				rune_on_player = false
		for o in get_tree().current_scene.get_children():
			if o is MageOrb:
				orbs_seen = maxi(orbs_seen, 1)
		prev = m.state
	print("  hechizos a distancia en 16 s: ", seen, "  daño recibido: ", _hp_lost)
	assert(seen.has("bolt"), "A distancia debe lanzar orbes")
	assert(seen.has("fan") or seen.has("rune"), "Debe variar con el abanico o la runa")
	assert(not seen.has("nova"), "La nova es solo de cerca")
	assert(orbs_seen > 0, "Los orbes deben aparecer en la escena")
	assert(rune_on_player, "El aviso de la runa debe seguir al jugador")
	assert(_hp_lost > 0.0, "Los hechizos deben dañar al jugador")
	print("CHECK 3 PASSED: orbes, abanico/runa, aviso sobre el jugador y daño")

	# 4. Orbe: una pared lo detiene y la esquiva (invulnerabilidad) lo atraviesa sin daño
	for o in get_tree().current_scene.get_children():
		if o is MageOrb:
			o.queue_free()
	m.set_physics_process(false)
	_hp_lost = 0.0
	var hc = _player.health_comp
	hc.invincibility_time = 0.0
	var orb := MageOrb.spawn(get_tree().current_scene, _player.global_position + Vector3(0, 1.0, 0) - Vector3(3, 0, 0), Vector3.RIGHT, 11.0, 2.0, DungeonMage.COLOR, RID())
	for i in 40:
		await get_tree().physics_frame
	_keep_player_alive()
	assert(not is_instance_valid(orb), "El orbe debe desaparecer al impactar")
	assert(_hp_lost >= 2.0, "Un orbe que alcanza al jugador hace 2 de daño (hizo %s)" % _hp_lost)
	_hp_lost = 0.0
	hc.set_invincibility(1.0)
	orb = MageOrb.spawn(get_tree().current_scene, _player.global_position + Vector3(0, 1.0, 0) - Vector3(3, 0, 0), Vector3.RIGHT, 11.0, 2.0, DungeonMage.COLOR, RID())
	for i in 40:
		await get_tree().physics_frame
	_keep_player_alive()
	assert(_hp_lost == 0.0, "Con invulnerabilidad el orbe no debe dañar")
	print("CHECK 4 PASSED: el orbe daña una vez y la esquiva lo evita")

	# 5. Interrupción: un golpe de 10 durante la anticipación corta el hechizo
	m.set_physics_process(true)
	m._start_attack("rune")
	await get_tree().physics_frame
	m.take_damage(10.0, Vector3(0, 0, 2))
	assert(m.state == DungeonGoblin.State.HURT or m.state == DungeonGoblin.State.STAGGER, "Un golpe de 10 debe interrumpir el hechizo")
	assert(not m._telegraph.visible, "Al interrumpirlo, el aviso desaparece")
	print("CHECK 5 PASSED: se le interrumpe al conjurar")

	# 6. Destello: reaparece lejos y en suelo libre
	m.hp = m.max_hp
	_player.global_position = m.global_position + Vector3(1.5, 0.1, 0)
	var before := m.global_position
	m._start_attack("blink")
	for i in 40:
		await get_tree().physics_frame
	var jumped := _flat(m.global_position - before)
	print("  destello: %.1f m, ahora a %.1f m del jugador" % [jumped, _flat(m.global_position - _player.global_position)])
	assert(jumped > 3.0, "El destello debe alejarlo")
	print("CHECK 6 PASSED: destello")

	# 7. Regresión: goblin normal y bruto conservan sus repertorios
	var g := enc.spawn_goblin()
	var b := enc.spawn_brute()
	await get_tree().physics_frame
	assert(g.attacks.has("swipe") and not g.attacks.has("bolt"), "El goblin normal mantiene sus ataques")
	assert(b.attacks.has("smash") and is_equal_approx(b.max_hp, 135.0), "El bruto se mantiene")
	print("CHECK 7 PASSED: goblin y bruto sin cambios")

	print("ALL MAGE CHECKS PASSED")
	get_tree().quit(0)

func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()

## Coloca al jugador a `dist` m del mago, en suelo libre y a la vista.
func _place_player(m: DungeonMage, enc: DungeonEncounter, dist: float) -> void:
	for k in 8:
		var d := Vector3.FORWARD.rotated(Vector3.UP, k * PI / 4.0)
		var p := m.global_position + d * dist
		if m._clear_line(m.global_position + Vector3(0, 1, 0), p + Vector3(0, 1, 0)) and enc.map.segment_walkable(m.global_position, p, 0.8):
			_player.global_position = p + Vector3(0, 0.3, 0)
			return

func _keep_player_alive() -> void:
	var hc = _player.health_comp
	if hc.hp < hc.max_hp:
		_hp_lost += hc.max_hp - hc.hp
		hc.hp = hc.max_hp
