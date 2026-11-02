extends Node

## Hacha de Garri en la mazmorra: lanzar, quedarse girando, recoger (giro potenciado) y giro 360.

var _player: CharacterBody3D

func _ready() -> void:
	print("--- TEST: HACHA DE GARRI ---")
	GameData.game_mode = "dungeon"
	for i in GameData.CHARACTERS.size():
		if GameData.CHARACTERS[i]["id"] == "garri":
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
	var c := enc.map.room_center(enc.map.arena_index)
	_player.global_position = c + Vector3(0, 0.3, 0)
	await _wait(0.3)
	var cc = _player.combat_controller
	var strat = cc._strategies[WeaponData.WeaponType.SPINNING_AXE]
	var anim = _player.animation_controller
	var lib: AnimationLibrary = anim.anim_player.get_animation_library("")

	# 1. Garri con el hacha en la mano y sus clips
	assert(_player.current_weapon() == WeaponData.WeaponType.SPINNING_AXE, "Garri empieza con el hacha")
	for n in ["axe_throw", "axe_spin", "axe_spin_power"]:
		assert(lib.has_animation(n), "Falta el clip %s" % n)
	var hand_axe: Node3D = _player.weapon_models[WeaponData.WeaponType.SPINNING_AXE]
	assert(hand_axe.has_meta("in_hand") and hand_axe.visible, "El hacha se ve en la mano")
	print("CHECK 1 PASSED: hacha en la mano y 3 clips")

	# 2. Lanzar: sale, vuela, se queda girando; sin hacha no se puede atacar ni girar
	var g := enc.spawn_goblin()
	await get_tree().physics_frame
	var fwd: Vector3 = -_player.mesh.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	g.global_position = _player.global_position + fwd * 5.0
	g.set_physics_process(false)
	var hp0: float = g.hp
	cc.attack_cooldown = 0.0
	strat._dungeon_throw()
	assert(cc.is_axe_thrown and anim._current_action_name == "axe_throw", "Lanza con su animación")
	await _wait(0.35)
	var axe: DungeonAxe = strat.thrown_axe()
	assert(axe != null, "El hacha sale de la mano")
	assert(not hand_axe.visible, "La mano queda vacía")
	await _wait(0.6)
	assert(g.hp < hp0, "El hacha daña al goblin que alcanza (%s → %s)" % [hp0, g.hp])
	assert(axe.phase != DungeonAxe.Phase.FLYING, "Al tocar al goblin se queda girando")
	print("CHECK 2 PASSED: lanzamiento, impacto (%.0f de daño) y giro en el sitio" % (hp0 - g.hp))
	var hp1: float = g.hp
	await _wait(1.0)
	assert(g.hp < hp1 or g.is_dead(), "Mientras gira en el sitio hace daño en área")
	cc.attack_cooldown = 0.0
	strat._dungeon_throw()
	assert(strat.thrown_axe() == axe, "Sin hacha no se lanza otra")
	assert(not strat.spin(false), "Sin hacha no hay giro")
	await _wait(1.5)
	assert(axe.is_resting(), "Tras 2 s sigue girando despacio, esperando")
	print("CHECK 3 PASSED: daño en área, sin ataques hasta recogerla, y luego espera")

	# 3. Recoger: vuelve a la mano y hace el giro potenciado (empuja más)
	var g2 := enc.spawn_goblin()
	await get_tree().physics_frame
	g2.set_physics_process(false)
	var at := axe.global_position
	_player.global_position = Vector3(at.x, _player.global_position.y, at.z) - fwd * 3.0
	g2.global_position = Vector3(at.x, _player.global_position.y, at.z) + fwd * 2.2
	var hp2: float = g2.hp
	_player.global_position = Vector3(at.x, _player.global_position.y, at.z)
	await _wait(0.1)
	assert(not cc.is_axe_thrown and not is_instance_valid(axe), "Al acercarse la recoge")
	assert(anim._current_action_name == "axe_spin_power", "Recogerla hace el giro potenciado (%s)" % anim._current_action_name)
	g2.set_physics_process(true)
	await _wait(0.6)
	var power_dmg: float = hp2 - g2.hp
	var power_knock: float = g2._knock.length()
	print("  giro potenciado: %.1f de daño, empuje %.1f" % [power_dmg, power_knock])
	var base_dmg: float = _player._weapon_damage(WeaponData.WeaponType.SPINNING_AXE)
	assert(power_dmg >= base_dmg * 2.0 - 0.01, "El giro potenciado hace el doble de daño (%.1f, base %.1f)" % [power_dmg, base_dmg])
	print("CHECK 4 PASSED: recogida con giro potenciado")

	# 4. Giro normal (click derecho): 360°, golpea delante y detrás
	await _wait(0.8)
	var front := enc.spawn_goblin()
	var back := enc.spawn_goblin()
	await get_tree().physics_frame
	for e in [front, back]:
		e.set_physics_process(false)
	front.global_position = _player.global_position + fwd * 1.8
	back.global_position = _player.global_position - fwd * 1.8
	var hf: float = front.hp
	var hb: float = back.hp
	strat._spin_ready_at = 0.0
	assert(_player.combat_controller.axe_spin(), "El click derecho hace el giro")
	assert(anim._current_action_name == "axe_spin", "Con su animación")
	await _wait(0.35)
	var spin_dmg: float = hf - front.hp
	print("  giro normal: %.1f de daño delante, %.1f detrás" % [spin_dmg, hb - back.hp])
	assert(spin_dmg > 0.0 and back.hp < hb, "El giro daña en 360° (delante y detrás)")
	assert(power_dmg > spin_dmg * 1.5, "El potenciado hace bastante más daño que el normal")
	assert(not _player.combat_controller.axe_spin(), "El giro tiene enfriamiento")
	print("CHECK 5 PASSED: giro 360 con enfriamiento")

	print("ALL AXE CHECKS PASSED")
	get_tree().quit(0)

func _wait(seconds: float) -> void:
	var acc := 0.0
	while acc < seconds:
		await get_tree().physics_frame
		acc += get_physics_process_delta_time()
