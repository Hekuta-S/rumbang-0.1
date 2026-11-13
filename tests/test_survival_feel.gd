extends Node

## Fase 5 del plan de juice (docs/PLAN_JUICE.md): perfil "light" de supervivencia.

class FakeEnemy extends Node3D:
	var xp_reward := 1.0
	var kb := Vector3.ZERO
	func apply_knockback(v: Vector3) -> void:
		kb += v

func _ready() -> void:
	print("--- TEST: SUPERVIVENCIA LIGHT (FASE 5) ---")
	# 1. Perfiles
	GameData.game_mode = "dungeon"
	assert(HitFeedback.profile() == "full")
	GameData.game_mode = "survival"
	assert(HitFeedback.profile() == "light" and HitFeedback.enabled() and not HitFeedback.is_full())
	print("CHECK 1 PASSED: mazmorra full, supervivencia light")

	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	var hf := HitFeedback.new()
	add_child(hf)
	HitFeedback._inst = hf

	# 2. Sin hitstop en las hordas (parry, remates...) y temblor con tope
	HitFeedback.freeze(0.1)
	assert(Engine.time_scale == 1.0, "freeze no congela en supervivencia")
	var e := FakeEnemy.new()
	add_child(e)
	HitFeedback.weapon_tag = WeaponData.WeaponType.MACE
	for i in 30:
		hf._hit(e, 60.0, Vector3.RIGHT, false)
	assert(hf._trauma <= HitFeedback.LIGHT_TRAUMA_MAX + 0.001, "el temblor de los golpes tiene tope (%.2f)" % hf._trauma)
	assert(Engine.time_scale == 1.0, "golpes normales sin hitstop")
	assert(e.kb.length() > 0.0, "el empuje extra se mantiene")
	print("CHECK 2 PASSED: sin hitstop y temblor con tope")

	# 3. Presupuesto: 30 golpes en el mismo frame → solo LIGHT_FX_PER_FRAME con destello/partículas
	assert(hf._fx_count == HitFeedback.LIGHT_FX_PER_FRAME)
	await get_tree().process_frame
	await get_tree().process_frame
	hf._hit(e, 10.0, Vector3.RIGHT, false)
	assert(hf._fx_count == 1, "el presupuesto se renueva cada frame")
	print("CHECK 3 PASSED: presupuesto de efectos por frame")

	# 4. Bajas en masa: se agrupan y se resuelven una vez por frame
	assert(HitFeedback.batch_burst_count(HitFeedback.BATCH_BIG - 1) == 0)
	assert(HitFeedback.batch_burst_count(HitFeedback.BATCH_BIG) > 0)
	assert(HitFeedback.batch_burst_count(500) <= 60, "el estallido tiene tope")
	for i in 8:
		hf._hit(e, 60.0, Vector3.RIGHT, true)
	assert(hf._batch_n == 8)
	await get_tree().process_frame
	await get_tree().process_frame
	assert(hf._batch_n == 0, "las bajas del frame se resuelven en un solo estallido")
	print("CHECK 4 PASSED: bajas agrupadas en un estallido")

	# 5. Élite: su baja sí congela
	var elite := FakeEnemy.new()
	elite.xp_reward = XpCurve.XP_ELITE
	add_child(elite)
	assert(HitFeedback.is_elite(elite) and not HitFeedback.is_elite(e))
	hf._hit(elite, 200.0, Vector3.RIGHT, true)
	assert(Engine.time_scale < 1.0, "matar un élite congela un instante")
	await get_tree().create_timer(0.3, true, false, true).timeout
	assert(Engine.time_scale == 1.0)
	print("CHECK 5 PASSED: hitstop solo con élites")

	# 6. Gemas: salen con un salto, rebotan y se quedan a su altura
	var orb: XPOrb = load("res://scenes/objects/xp_orb.tscn").instantiate()
	orb.position = Vector3(0, 0.5, 0)
	add_child(orb)
	assert(orb._pop_vel.y > 0.0, "la gema sale hacia arriba")
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert(orb.global_position.y > 0.5, "sube al soltarse")
	await get_tree().create_timer(1.5).timeout
	assert(is_equal_approx(orb.global_position.y, 0.5), "y se asienta a su altura (%.3f)" % orb.global_position.y)
	print("CHECK 6 PASSED: gemas con salto y rebote")

	GameData.game_mode = "dungeon"
	print("ALL SURVIVAL FEEL CHECKS PASSED")
	get_tree().quit(0)
