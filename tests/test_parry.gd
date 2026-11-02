extends Node

## Parry (guardia + aura) y voltereta de la esquiva. Carga la mazmorra real.

var _player: CharacterBody3D
var _hp_lost := 0.0

func _ready() -> void:
	print("--- TEST: PARRY Y VOLTERETA ---")
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
	enc._pending.clear()
	_player = enc.player
	_player.health_comp.max_hp = 9999.0
	_player.health_comp.hp = 9999.0
	var c := enc.map.room_center(enc.map.arena_index)
	_player.global_position = c + Vector3(0, 0.3, 0)
	var parry: PlayerParryController = _player.parry_controller
	var anim = _player.animation_controller

	# 1. Clips de guardia y voltereta cargados (adaptados al esqueleto del personaje)
	var lib: AnimationLibrary = anim.anim_player.get_animation_library("")
	assert(lib.has_animation("parry") and lib.has_animation("roll"), "Faltan los clips parry/roll")
	var other: Node = load("res://assets/models/vangry/vangry-idle.fbx").instantiate()
	var vskel := other.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var vacts := WeaponAnimSets.build_common_actions(vskel, NodePath("Skeleton3D"))
	assert(vacts.has("parry") and vacts.has("roll") and (vacts["roll"] as Animation).get_track_count() > 20, "La guardia y la voltereta se adaptan a otro personaje (Vangry)")
	other.free()
	print("CHECK 1 PASSED: clips parry/roll (Mikeura y adaptados a Vangry)")

	# 2. Guardia: postura, aura y movimiento lento
	assert(parry.try_parry(), "El parry debe empezar")
	await get_tree().process_frame
	assert(parry.is_guarding() and anim._current_action_name == "parry", "Guardia con su animación")
	assert(parry._aura.visible, "El aura aparece")
	print("CHECK 2 PASSED: guardia, animación y aura")

	# 3. Parar un golpe cuerpo a cuerpo de frente: 0 de daño, goblin aturdido, bonificación
	var g := enc.spawn_goblin()
	await get_tree().physics_frame
	_face(g)
	_hp_lost = 0.0
	g._atk_name = "swipe"
	g._atk = g.attacks["swipe"]
	g._facing = (_player.global_position - g.global_position).normalized()
	g.global_position = _player.global_position - _forward() * -1.2
	g._facing = (_player.global_position - g.global_position)
	g._facing.y = 0.0
	g._facing = g._facing.normalized()
	g._hit_done = false
	g._try_hit_player()
	_keep_alive()
	assert(_hp_lost == 0.0, "Un golpe parado no hace daño (hizo %s)" % _hp_lost)
	assert(g.state == DungeonGoblin.State.STAGGER, "El atacante queda aturdido")
	var stun_left: float = g.stagger_time - g._state_t
	assert(absf(stun_left - PlayerParryController.STUN) < 0.05, "Aturdimiento de 1,5 s (es %.2f)" % stun_left)
	assert(parry.has_bonus(), "Tras el parry, el siguiente golpe tiene bonificación")
	assert(is_equal_approx(_player.parry_bonus_mult(), 1.5) and is_equal_approx(_player.parry_bonus_mult(), 1.0), "La bonificación es +50 % y solo una vez")
	await _wait(PlayerParryController.POSE_TIME)
	assert(not parry.is_active() and parry.cooldown_left() <= PlayerParryController.COOLDOWN_OK + 0.01, "Tras un parry con éxito, enfriamiento corto")
	print("CHECK 3 PASSED: golpe parado sin daño, goblin aturdido 1,5 s, +50 %% una vez")

	# 4. Golpe por la espalda: no se para
	await _wait(PlayerParryController.COOLDOWN_OK + 0.05)
	g._set_state(DungeonGoblin.State.APPROACH)
	assert(parry.try_parry(), "Nueva guardia")
	g.global_position = _player.global_position + _forward() * -1.2
	g._facing = (_player.global_position - g.global_position)
	g._facing.y = 0.0
	g._facing = g._facing.normalized()
	g._hit_done = false
	_hp_lost = 0.0
	_player.health_comp.invincibility_time = 0.0
	g._try_hit_player()
	_keep_alive()
	assert(_hp_lost > 0.0, "Un golpe por la espalda no se para")
	print("CHECK 4 PASSED: por la espalda no protege")

	# 5. Proyectil de frente: daño a la mitad. Área: daño completo.
	_player.health_comp.invincibility_time = 0.0
	_hp_lost = 0.0
	var dmg: float = _player.parry_projectile_damage(2.0, _player.global_position + _forward() * 2.0)
	assert(is_equal_approx(dmg, 1.0), "Un orbe de frente en guardia hace la mitad (%s)" % dmg)
	var blast := GroundBlast.spawn(get_tree().current_scene, _player.global_position, 1.6, 0.05, 3.0, Color.GREEN)
	await _wait(0.15)
	_keep_alive()
	assert(_hp_lost >= 3.0, "Las erupciones no se bloquean (daño %s)" % _hp_lost)
	print("CHECK 5 PASSED: orbe a la mitad, erupción completa")

	# 6. Guardia sin parar nada: enfriamiento largo
	await _wait(PlayerParryController.POSE_TIME)
	assert(parry.cooldown_left() > 2.0, "Si no para nada, enfriamiento de 2,5 s (%.2f)" % parry.cooldown_left())
	assert(not parry.try_parry(), "Durante el enfriamiento no se puede repetir")
	print("CHECK 6 PASSED: fallo con 2,5 s de enfriamiento")

	# 7. Jefe: el parry cuenta como daño contra su armadura
	var n := enc.spawn_necromancer()
	await get_tree().physics_frame
	parry._cooldown = 0.0
	assert(parry.try_parry(), "Guardia contra el jefe")
	n.global_position = _player.global_position + _forward() * 2.0
	n._atk_name = "scythe"
	n._atk = n.attacks["scythe"]
	n._facing = (_player.global_position - n.global_position)
	n._facing.y = 0.0
	n._facing = n._facing.normalized()
	n._set_state(DungeonGoblin.State.APPROACH)
	n._hit_done = false
	n._try_hit_player()
	assert(is_equal_approx(n._armor_dmg, PlayerParryController.BOSS_ARMOR), "El parry suma 60 a la armadura del jefe (%s)" % n._armor_dmg)
	assert(n.state != DungeonGoblin.State.STAGGER, "Un solo parry no aturde al jefe")
	n.queue_free()
	print("CHECK 7 PASSED: parry al jefe = 60 de armadura")

	# 8. Voltereta: la esquiva la reproduce y corta la guardia
	await _wait(PlayerParryController.POSE_TIME + 0.1)
	parry._cooldown = 0.0
	parry.try_parry()
	var mc = _player.movement_controller
	mc._dodge_cooldown_timer = 0.0
	mc.perform_dodge()
	await get_tree().process_frame
	assert(not parry.is_active(), "La esquiva corta la guardia")
	assert(anim._current_action_name == "roll", "La esquiva reproduce la voltereta (%s)" % anim._current_action_name)
	var roll_len: float = lib.get_animation("roll").length
	assert(absf(anim._action_speed - roll_len / mc.DODGE_DURATION) < 0.01, "La voltereta dura lo que la esquiva")
	print("CHECK 8 PASSED: voltereta de %.2f s ajustada a %.2f s; corta la guardia" % [roll_len, mc.DODGE_DURATION])

	print("ALL PARRY CHECKS PASSED")
	get_tree().quit(0)

func _forward() -> Vector3:
	var f: Vector3 = -_player.mesh.global_transform.basis.z
	f.y = 0.0
	return f.normalized()

func _face(n: Node3D) -> void:
	var d := n.global_position - _player.global_position
	_player.mesh.rotation.y = atan2(-d.x, -d.z)

func _wait(seconds: float) -> void:
	var acc := 0.0
	while acc < seconds:
		await get_tree().process_frame
		acc += get_process_delta_time()

func _keep_alive() -> void:
	var hc = _player.health_comp
	if hc.hp < hc.max_hp:
		_hp_lost += hc.max_hp - hc.hp
		hc.hp = hc.max_hp
