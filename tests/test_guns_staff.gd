extends Node

## Pistola, fusil y bastón de fuego (mazmorra): se equipan con su modelo, la pistola y el fusil dañan con balas
## instantáneas y gastan balas (el fusil dispara solo mientras se mantiene), y la bola de fuego del bastón estalla en
## área, quema y gasta maná. El clic derecho no hace nada raro (no lanza la espalanza).

var _player: CharacterBody3D
var _enc: DungeonEncounter

func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _boot() -> void:
	GameData.game_mode = "dungeon"
	SaveManager.save_path = "user://test_save.json"
	for i in GameData.CHARACTERS.size():
		if GameData.CHARACTERS[i]["id"] == "mikeura":
			GameData.selected_index = i
	var scene: Node = load("res://scenes/core/main_dungeon.tscn").instantiate()
	get_tree().root.add_child.call_deferred(scene)
	await get_tree().process_frame
	get_tree().current_scene = scene
	for i in 600:
		await get_tree().process_frame
		_enc = scene.get_node_or_null("DungeonEncounter")
		if _enc and _enc.map and is_instance_valid(_enc.player):
			break
	_enc._pending.clear()
	_player = _enc.player
	_player.health_comp.max_hp = 9999.0
	_player.health_comp.hp = 9999.0
	await _wait(0.5)

func _home() -> void:
	_player.velocity = Vector3.ZERO
	_player.global_position = _enc.map.room_center(_enc.map.arena_index) + Vector3(0, 0.3, 0)
	await _wait(0.2)

func _fwd() -> Vector3:
	var f: Vector3 = -_player.mesh.global_transform.basis.z
	f.y = 0.0
	return f.normalized()

func _dummy(dist: float, side := 0.0) -> DungeonGoblin:
	var f := _fwd()
	var at: Vector3 = _player.global_position + f * dist + Vector3(-f.z, 0, f.x) * side
	var g := _enc._spawn_at(_enc.map.arena_index, at)
	g.global_position = at
	g.max_hp = 5000.0
	g.hp = 5000.0
	g.set_physics_process(false)
	return g

func _clear_enemies() -> void:
	var tl = _player.get("target_lock")
	if tl and tl.has_method("_set_target"):
		tl._set_target(null)
	for e in EnemyRegistry.all():
		if is_instance_valid(e) and e is Node:
			EnemyRegistry.unregister(e)
			e.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame

func _lock(g: Node3D) -> void:
	var tl = _player.get("target_lock")
	if tl:
		tl._set_target(g)

func _equip(w: int) -> void:
	if not _player.weapon_slots.has(w):
		var slots: Array = _player.weapon_inventory.weapon_slots
		var cur: int = _player.weapon_inventory.current_slot
		var free := slots.find(null)
		var idx := free if free >= 0 else (slots.size() - 1 if cur != slots.size() - 1 else 0)
		if free >= 0 or slots.size() >= PlayerCombatController.MAX_WEAPON_SLOTS:
			slots[idx] = w
		else:
			assert(_player.add_weapon(w), "Se añade el arma %d" % w)
		_player.combat_controller.weapon_slots = slots
	_player.select_slot(_player.weapon_slots.find(w))
	await _wait(0.4)
	assert(_player.current_weapon() == w)

func _ready() -> void:
	print("--- TEST: PISTOLA, FUSIL Y BASTÓN DE FUEGO ---")
	get_tree().create_timer(120.0).timeout.connect(func():
		print("TIMEOUT")
		get_tree().quit(1))
	await _boot()
	var W := WeaponData.WeaponType
	var cc = _player.combat_controller
	var res = _player.resources
	var ac = _player.animation_controller
	var vis = _player.weapon_visuals

	# 1. Se equipan con su modelo: la pistola y el fusil sujetos (capa de arma con ancla), el bastón en la mano
	for w in [W.PISTOL, W.RIFLE]:
		await _equip(w)
		assert(ac.has_held_layer() and ac.held_weapon_type == w, "Arma %d sujeta con las dos manos" % w)
		var rig: Node3D = _player.weapon_models.get(w)
		assert(rig is HeldWeaponRig and rig.is_visible_in_tree(), "Arma %d: modelo en la mano" % w)
	await _equip(W.FIRE_STAFF)
	assert(vis.staff_gem() != null and vis.staff_gem().is_visible_in_tree(), "Bastón visible en la mano")
	assert(ac.anim_player.has_animation("staff_cast"), "Bastón: animación de lanzamiento")
	print("CHECK 1 PASSED: pistola, fusil y bastón equipados con modelo")

	# 2. Pistola: cada disparo daña al instante y gasta una bala
	await _clear_enemies()
	await _equip(W.PISTOL)
	await _home()
	var g := _dummy(8.0)
	_lock(g)
	await _wait(0.3)
	var ammo0: int = res.ammo_of(W.PISTOL) if res.has_method("ammo_of") else int(res.ammo.get(W.PISTOL, 0))
	for i in 3:
		cc.attack_cooldown = 0.0
		cc.attack()
		await _wait(0.5)
	var ammo1: int = res.ammo_of(W.PISTOL) if res.has_method("ammo_of") else int(res.ammo.get(W.PISTOL, 0))
	print("  pistola: quitó %.1f, balas %d -> %d" % [5000.0 - g.hp, ammo0, ammo1])
	assert(g.hp < 5000.0 - 15.0, "Pistola: tres disparos dañan (%.1f)" % (5000.0 - g.hp))
	assert(ammo1 == ammo0 - 3, "Pistola: gasta una bala por disparo")

	# 3. Fusil: mantener el clic dispara en automático (el cooldown marca el ritmo)
	await _clear_enemies()
	await _equip(W.RIFLE)
	await _home()
	g = _dummy(8.0)
	_lock(g)
	await _wait(0.3)
	var hp0 := g.hp
	var t := 0.0
	while t < 1.0:
		cc.attack()          # lo que hace PlayerInputController cada fotograma con el clic mantenido
		await get_tree().process_frame
		t += get_process_delta_time()
	var shots: int = int(round((hp0 - g.hp) / maxf(_player._weapon_damage(W.RIFLE), 0.01)))
	print("  fusil: quitó %.1f en 1 s (~%d balas)" % [hp0 - g.hp, shots])
	assert(shots >= 4, "Fusil: ráfaga automática (%d impactos)" % shots)
	print("CHECK 2 PASSED: pistola y fusil disparan balas instantáneas")

	# 4. Bastón: la bola estalla en área (dos enemigos juntos), quema y gasta maná
	await _clear_enemies()
	await _equip(W.FIRE_STAFF)
	await _home()
	var a := _dummy(9.0, -0.6)
	var b := _dummy(9.0, 0.7)
	_lock(a)
	await _wait(0.3)
	var mana0: float = res.mana
	cc.attack_cooldown = 0.0
	cc.attack()
	assert(ac._current_action_name == "staff_cast", "Bastón: estocada de lanzamiento (%s)" % ac._current_action_name)
	await _wait(1.6)
	print("  bastón: a %.1f, b %.1f, maná %.0f -> %.0f" % [5000.0 - a.hp, 5000.0 - b.hp, mana0, res.mana])
	assert(a.hp < 5000.0 and b.hp < 5000.0, "Bastón: el estallido alcanza a los dos")
	var fx := StatusEffects.get_for(b)
	assert(fx != null and fx.has("burn"), "Bastón: quema")
	assert(res.mana < mana0, "Bastón: gasta maná")
	# Clic derecho: nada (no lanza la espalanza)
	_player._on_alt_attack_pressed()
	await _wait(0.1)
	assert(not cc.is_spear_thrown, "Clic derecho con el bastón no lanza nada")
	print("CHECK 3 PASSED: bola de fuego en área con quemadura")

	print("ALL GUNS STAFF CHECKS PASSED")
	get_tree().quit(0)
