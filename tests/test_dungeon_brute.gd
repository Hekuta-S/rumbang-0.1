extends Node

## Bruto de mazmorra: contrato, armadura, repertorio y avisos. Carga la mazmorra real.

var _player: CharacterBody3D
var _hp_lost := 0.0

func _ready() -> void:
	print("--- TEST: DUNGEON BRUTE ---")
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
	enc._pending.clear()   # sin encuentros automáticos: solo el bruto de la prueba
	_player = enc.player
	var c := enc.map.room_center(enc.map.arena_index)
	_player.global_position = c + Vector3(0, 0.3, 0)

	# 1. Contrato y configuración
	var b := enc.spawn_brute()
	await get_tree().physics_frame
	assert(b is DungeonBrute, "spawn_brute debe crear un DungeonBrute")
	assert(EnemyRegistry.all().has(b), "El bruto debe estar en EnemyRegistry")
	assert(is_equal_approx(b.max_hp, 135.0), "Vida del bruto: 90 × 1,5 = 135 (es %s)" % b.max_hp)
	assert(b.scale.is_equal_approx(Vector3.ONE), "El cuerpo del bruto no debe ir escalado")
	assert(absf(b.speed - 3.2) < 0.01, "Velocidad del bruto 3,2 m/s (es %s)" % b.speed)
	for n in ["sweep", "smash", "stomp", "charge"]:
		assert(b.attacks.has(n), "Falta el ataque %s" % n)
		assert(b._anim.has_animation(b.attacks[n]["windup_clip"]) and b._anim.has_animation(b.attacks[n]["attack_clip"]),
			"Faltan clips (o su respaldo) de %s" % n)
	print("CHECK 1 PASSED: contrato, vida %d, velocidad %.1f, 4 ataques con clips" % [b.max_hp, b.speed])

	# 1b. Clips propios del bruto (no los del goblin normal) y poses legibles en su esqueleto
	for clip in DungeonBrute.BRUTE_CLIPS:
		assert(ResourceLoader.exists(DungeonBrute.BRUTE_CLIPS[clip]), "Falta el clip propio %s" % clip)
	assert(absf(b._anim.get_animation("smash_windup").length - 29.0 / 30.0) < 0.05, "smash_windup debe ser el clip del bruto (%.2f s)" % b._anim.get_animation("smash_windup").length)
	b.set_physics_process(false)
	var skel := b._model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var poses := {"smash_windup": "manos sobre la cabeza", "smash": "manos abajo", "death": "tumbado"}
	for clip in poses:
		b._anim.play(clip, 0.0)
		b._anim.seek(b._anim.get_animation(clip).length if clip != "smash" else 0.15, true)
		var head := skel.to_global(skel.get_bone_global_pose(skel.find_bone("mixamorig_Head")).origin)
		var hand := skel.to_global(skel.get_bone_global_pose(skel.find_bone("mixamorig_RightHand")).origin)
		var hips := skel.to_global(skel.get_bone_global_pose(skel.find_bone("mixamorig_Hips")).origin)
		print("  %s: cabeza %.2f m, mano %.2f m, cadera %.2f m" % [clip, head.y - b.global_position.y, hand.y - b.global_position.y, hips.y - b.global_position.y])
		match clip:
			"smash_windup": assert(hand.y > head.y, "En la anticipación del mazazo las manos deben quedar sobre la cabeza")
			"smash": assert(hand.y < head.y - 0.1 and hand.y < hips.y + 0.25, "En el impacto del mazazo las manos deben bajar a la altura de la cadera")
			"death": assert(head.y - b.global_position.y < 0.6, "Al morir debe acabar tumbado")
	b.set_physics_process(true)
	print("CHECK 1b PASSED: clips propios del bruto y poses correctas")

	# 2. Armadura: golpes flojos no le interrumpen; acumulados, lo aturden
	b._set_state(DungeonGoblin.State.APPROACH)
	b.take_damage(10.0, Vector3(0, 0, 3))
	assert(b.state == DungeonGoblin.State.APPROACH, "Un golpe de 10 no debe interrumpir al bruto")
	b.take_damage(12.0, Vector3(0, 0, 3))
	b.take_damage(12.0, Vector3(0, 0, 3))
	assert(b.state == DungeonGoblin.State.STAGGER, "34 de daño seguido deben aturdirle (estado %d)" % b.state)
	b._set_state(DungeonGoblin.State.APPROACH)
	b.take_damage(31.0, Vector3(0, 0, 3))
	assert(b.state == DungeonGoblin.State.STAGGER, "Un golpe de 31 debe aturdirle")
	b.hp = b.max_hp
	print("CHECK 2 PASSED: armadura (10 no interrumpe, 34 seguidos o 31 de golpe aturden)")

	# 3. Repertorio de cerca: jugador pegado; avisos en círculo para mazazo y pisotón
	b._set_state(DungeonGoblin.State.APPROACH)
	var seen := {}
	var circle_ok := true
	var prev_state := -1
	for i in 60 * 14:
		await get_tree().physics_frame
		_keep_player_alive()
		if not is_instance_valid(b) or b.is_dead():
			break
		# El jugador se queda a 1,2 m del bruto (lo vuelve a colocar si le empujan)
		var off := _player.global_position - b.global_position
		off.y = 0.0
		if off.length() > 1.8 or off.length() < 0.6:
			var dir := off.normalized() if off.length() > 0.1 else Vector3.FORWARD
			_player.global_position = b.global_position + dir * 1.2 + Vector3(0, 0.1, 0)
		if b.state == DungeonGoblin.State.WINDUP and prev_state != DungeonGoblin.State.WINDUP:
			seen[b._atk_name] = seen.get(b._atk_name, 0) + 1
			var mat := b._telegraph.material_override as ShaderMaterial
			var expected := 2 if b._atk["shape"] == "circle" else (1 if b._atk["shape"] == "line" else 0)
			if int(mat.get_shader_parameter("shape")) != expected:
				circle_ok = false
		prev_state = b.state
	print("Ataques de cerca en 14 s: ", seen, "  daño recibido: ", _hp_lost)
	# (Una carga suelta es válida: un golpe puede empujar al jugador a más de 4,5 m)
	assert(seen.has("sweep") and (seen.has("smash") or seen.has("stomp")), "De cerca debe alternar barrido con mazazo o pisotón")
	assert(int(seen.get("charge", 0)) <= 1, "La carga no debe ser lo habitual pegado al jugador")
	assert(circle_ok, "Cada ataque debe usar su forma de aviso")
	assert(_hp_lost > 0.0, "Los ataques del bruto deben dañar al jugador")
	print("CHECK 3 PASSED: repertorio de cerca variado, avisos correctos y daño")

	# 4. Carga de lejos con línea de visión
	_hp_lost = 0.0
	b._atk_ready.clear()
	var charged := false
	for i in 60 * 10:
		await get_tree().physics_frame
		_keep_player_alive()
		if b.state == DungeonGoblin.State.APPROACH or b.state == DungeonGoblin.State.IDLE:
			var off := _player.global_position - b.global_position
			off.y = 0.0
			if off.length() < 5.5:
				# Alejar al jugador a 7 m en una dirección libre
				for k in 8:
					var d := Vector3.FORWARD.rotated(Vector3.UP, k * PI / 4.0)
					var p := b.global_position + d * 7.0
					if b._clear_line(b.global_position + Vector3(0, 1, 0), p + Vector3(0, 1, 0)) and enc.map.segment_walkable(b.global_position, p, 1.0):
						_player.global_position = p + Vector3(0, 0.3, 0)
						break
		if b.state == DungeonGoblin.State.WINDUP and b._atk_name == "charge":
			charged = true
			break
	assert(charged, "De lejos y con línea de visión debe cargar")
	print("CHECK 4 PASSED: carga a distancia")

	# 5. Regresión: el goblin normal conserva su repertorio
	var g := enc.spawn_goblin()
	await get_tree().physics_frame
	assert(not (g is DungeonBrute), "spawn_goblin debe crear un goblin normal")
	assert(g.attacks.has("swipe") and g.attacks.has("leap") and not g.attacks.has("smash"), "El goblin normal mantiene sus ataques")
	assert(is_equal_approx(g.max_hp, 80.0), "Vida del goblin normal 80 (es %s)" % g.max_hp)
	print("CHECK 5 PASSED: goblin normal sin cambios")

	print("ALL BRUTE CHECKS PASSED")
	get_tree().quit(0)

func _keep_player_alive() -> void:
	var hc = _player.health_comp
	if hc.hp < hc.max_hp:
		_hp_lost += hc.max_hp - hc.hp
		hc.hp = hc.max_hp
