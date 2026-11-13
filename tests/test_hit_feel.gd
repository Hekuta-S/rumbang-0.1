extends Node

## Fase 1 del plan de juice (docs/PLAN_JUICE.md): racha de tono, marcas por arma, reacción de la
## víctima y cámara que vuelve a reposo tras el empujón.

class FakeEnemy extends Node3D:
	var model: Node3D
	var kb := Vector3.ZERO
	func get_model() -> Node3D:
		return model
	func apply_knockback(v: Vector3) -> void:
		kb += v

func _ready() -> void:
	print("--- TEST: HIT FEEL (FASE 1) ---")
	GameData.game_mode = "dungeon"

	# 1. Racha: +1 semitono por golpe, con tope
	assert(is_equal_approx(HitFeedback.chain_pitch(0), 1.0))
	assert(is_equal_approx(HitFeedback.chain_pitch(12), HitFeedback.chain_pitch(HitFeedback.CHAIN_MAX)))
	assert(HitFeedback.chain_pitch(3) > HitFeedback.chain_pitch(2))
	assert(absf(HitFeedback.chain_pitch(1) - 1.0595) < 0.001)
	print("CHECK 1 PASSED: chain_pitch sube un semitono por golpe y tiene tope")

	# 2. Marca según el sonido del arma
	assert(HitFeedback._mark_mode("impact_slash") == 0)
	assert(HitFeedback._mark_mode("impact_blunt") == 1)
	assert(HitFeedback._mark_mode("impact_pierce") == 2)
	assert(HitFeedback._mark_mode("impact_fire") == -1)
	print("CHECK 2 PASSED: cada tipo de impacto tiene su marca")

	# 3. Golpe completo sobre un enemigo falso: reacción + cámara + vuelta a reposo
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.fov = 64.0
	var enemy := FakeEnemy.new()
	enemy.model = Node3D.new()
	enemy.add_child(enemy.model)
	enemy.model.position = Vector3(0, 0.2, 0)
	enemy.model.scale = Vector3.ONE * 1.5
	add_child(enemy)
	enemy.global_position = Vector3(0, 0, -3)
	var hf := HitFeedback.new()
	add_child(hf)
	HitFeedback.weapon_tag = WeaponData.WeaponType.MACE
	hf._hit(enemy, 60.0, Vector3(1, 0, 0), false)
	hf._hit(enemy, 60.0, Vector3(1, 0, 0), true)   # segundo golpe encima: no debe mover la base
	assert(enemy.model.scale != Vector3.ONE * 1.5, "la víctima debe aplastarse al recibir")
	assert(enemy.kb.length() > 0.0)
	assert(cam.fov < 64.0, "golpe pesado: FOV punch")
	assert(Engine.time_scale < 1.0, "golpe pesado: hitstop")
	print("CHECK 3 PASSED: golpe pesado aplica squash, knockback, FOV punch y hitstop")

	await get_tree().create_timer(0.1, true, false, true).timeout
	assert(absf(cam.h_offset) + absf(cam.v_offset) + absf(cam.rotation.z) > 0.0, "la cámara debe moverse")
	print("CHECK 4 PASSED: la cámara recibe el empujón")

	await get_tree().create_timer(2.0, true, false, true).timeout
	assert(enemy.model.position.is_equal_approx(Vector3(0, 0.2, 0)), "la víctima vuelve a su posición")
	assert(enemy.model.scale.is_equal_approx(Vector3.ONE * 1.5), "la víctima vuelve a su escala")
	assert(not enemy.model.has_meta(&"_hf_base"))
	assert(Engine.time_scale == 1.0)
	assert(cam.h_offset == 0.0 and cam.v_offset == 0.0 and cam.rotation.z == 0.0, "la cámara vuelve a reposo")
	print("CHECK 5 PASSED: víctima, tiempo y cámara vuelven a reposo")

	print("ALL HIT FEEL CHECKS PASSED")
	get_tree().quit(0)
