extends Node

## Energía, maná y balas en la mazmorra: costes, regeneración, bloqueo sin recurso y recogibles.

var _player: CharacterBody3D

func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _boot(char_id: String) -> DungeonEncounter:
	GameData.game_mode = "dungeon"
	for i in GameData.CHARACTERS.size():
		if GameData.CHARACTERS[i]["id"] == char_id:
			GameData.selected_index = i
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
	_player.global_position = enc.map.room_center(enc.map.arena_index) + Vector3(0, 0.3, 0)
	await _wait(0.4)
	return enc

func _ready() -> void:
	print("--- TEST: ENERGÍA / MANÁ / BALAS ---")
	var enc := await _boot("mikeura")
	var res: PlayerResources = _player.resources
	assert(res != null and res.active, "Hay recursos y están activos en mazmorra")
	assert(is_equal_approx(res.energy, PlayerResources.ENERGY_MAX), "Empieza con energía llena")

	# 1. Un golpe de espalanza gasta energía; sin pausa no se recupera de inmediato; luego sí
	var e0 := res.energy
	_player.combat_controller.attack_cooldown = 0.0
	_player.combat_controller.attack()
	assert(is_equal_approx(res.energy, e0 - res.cost_of(WeaponData.WeaponType.SPEAR_LANCE)), "El golpe cuesta su energía")
	var e1 := res.energy
	await _wait(PlayerResources.ENERGY_DELAY + 1.0)
	assert(res.energy > e1 + 10.0, "La energía se regenera tras la pausa (%.1f → %.1f)" % [e1, res.energy])
	print("CHECK 1 PASSED: golpe cuesta energía y se regenera")

	# 2. Rodar y saltar cuestan energía; sin energía no se puede
	var mc = _player.movement_controller
	mc._dodge_cooldown_timer = 0.0
	res.energy = PlayerResources.ENERGY_MAX
	mc.perform_dodge()
	assert(mc.is_dodging(), "Rueda con energía")
	assert(is_equal_approx(res.energy, PlayerResources.ENERGY_MAX - PlayerResources.DODGE_COST), "Rodar cuesta energía")
	await _wait(0.8)
	mc._dodge_cooldown_timer = 0.0
	res.energy = 1.0
	res._energy_wait = 10.0
	mc.perform_dodge()
	assert(not mc.is_dodging(), "Sin energía no rueda")
	assert(not res.spend_energy(PlayerResources.JUMP_COST), "Sin energía no salta")
	print("CHECK 2 PASSED: rodar y saltar cuestan energía y se bloquean sin ella")

	# 3. Sin energía el golpe no sale
	res.energy = 0.0
	res._energy_wait = 10.0
	_player.combat_controller.attack_cooldown = 0.0
	var fired := [false]
	_player.weapon_attacked.connect(func(_w): fired[0] = true)
	_player.combat_controller.attack()
	assert(not fired[0], "Sin energía no hay golpe")
	print("CHECK 3 PASSED: sin energía no se ataca")

	# 4. Maná: los polvos / espíritus gastan maná, no energía
	var W := WeaponData.WeaponType
	assert(res.kind_of(W.DUSTS) == PlayerResources.Kind.MANA and res.kind_of(W.SERPENTS) == PlayerResources.Kind.MANA, "Magia = maná")
	assert(res.kind_of(W.ELEMENTS_CYCLE) == PlayerResources.Kind.MANA, "Orbes elementales = maná")
	var m0 := res.mana
	assert(res.spend(W.DUSTS), "Polvos con maná suficiente")
	assert(is_equal_approx(res.mana, m0 - res.cost_of(W.DUSTS)), "Los polvos cuestan maná")
	res.mana = 1.0
	assert(not res.spend(W.SERPENTS), "Sin maná no hay magia")
	print("CHECK 4 PASSED: la magia gasta maná")

	# 5. Balas: escopeta, lanzallamas y bazuca gastan reserva; vacía bloquea; recogible repone
	for w in [W.TRI_SHOTGUN, W.FLAME_THROWER, W.SPORE_BAZOOKA]:
		assert(res.kind_of(w) == PlayerResources.Kind.AMMO and res.max_ammo_of(w) > 0, "Arma de fuego con reserva: %d" % w)
	var a0 := res.ammo_of(W.TRI_SHOTGUN)
	assert(res.spend(W.TRI_SHOTGUN), "Dispara con balas")
	assert(res.ammo_of(W.TRI_SHOTGUN) == a0 - 1, "Cada disparo gasta una bala")
	res.ammo[W.TRI_SHOTGUN] = 0
	assert(not res.spend(W.TRI_SHOTGUN), "Sin balas no dispara")
	var added := res.add_ammo_fraction(0.5, [W.TRI_SHOTGUN])
	assert(added > 0 and res.ammo_of(W.TRI_SHOTGUN) == added, "Las balas recogidas se suman")
	assert(res.ammo_of(W.SPEAR_LANCE) == -1, "La lanza no usa balas")
	print("CHECK 5 PASSED: balas por arma, bloqueo en vacío y recarga")

	# 6. Recogible de balas: la lanza no cuenta como arma de fuego; con escopeta sí
	var owned: Array = [W.SPEAR_LANCE]
	assert(not res.has_any_ammo_weapon(owned), "Sin arma de fuego no hay drop de balas")
	owned.append(W.TRI_SHOTGUN)
	assert(res.has_any_ammo_weapon(owned), "Con escopeta sí")
	res.ammo[W.TRI_SHOTGUN] = 0
	var pick := ResourcePickup.spawn(get_tree().current_scene, _player.global_position, ResourcePickup.Kind.MANA)
	res.mana = 0.0
	pick._collect(_player)
	assert(res.mana >= ResourcePickup.MANA_AMOUNT - 0.01, "El orbe de maná repone maná")
	res.refresh_for_new_level()
	assert(is_equal_approx(res.energy, PlayerResources.ENERGY_MAX) and res.ammo_of(W.TRI_SHOTGUN) > 0, "Al bajar de nivel se rellena")
	print("CHECK 6 PASSED: recogibles y relleno por nivel")

	var hud := get_tree().current_scene.find_children("ResourceBars", "", true, false)
	assert(not hud.is_empty(), "El HUD tiene las barras de recursos")
	print("CHECK 7 PASSED: barras en el HUD")
	print("ALL RESOURCE CHECKS PASSED")
	get_tree().quit(0)
