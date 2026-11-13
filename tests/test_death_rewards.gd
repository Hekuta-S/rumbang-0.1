extends Node

## Fase 2 del plan de juice (docs/PLAN_JUICE.md): muertes, overkill, multi-kill y recompensas.

func _ready() -> void:
	print("--- TEST: MUERTES Y RECOMPENSAS (FASE 2) ---")
	GameData.game_mode = "dungeon"

	# 1. Overkill y carteles
	assert(HitFeedback.is_overkill(-20.0, 30.0))
	assert(not HitFeedback.is_overkill(-5.0, 30.0))
	assert(not HitFeedback.is_overkill(-50.0, 0.0))
	assert(HitFeedback.multikill_label(1) == "")
	assert(HitFeedback.multikill_label(2) == "¡DOBLE!")
	assert(HitFeedback.multikill_label(3) == "¡TRIPLE!")
	assert(HitFeedback.multikill_label(5) == "¡MASACRE!")
	assert(HitFeedback.multikill_label(9) == "¡CARNICERÍA!")
	print("CHECK 1 PASSED: overkill y textos de multi-kill")

	# 2. Recompensas: escalera de tono, imán que acelera
	assert(is_equal_approx(RewardJuice.pitch_for(0), 1.0))
	assert(is_equal_approx(RewardJuice.pitch_for(40), RewardJuice.pitch_for(RewardJuice.CHAIN_MAX)))
	var p0 := RewardJuice.next_pitch(100000)
	var p1 := RewardJuice.next_pitch(100300)
	var p2 := RewardJuice.next_pitch(100600)
	var p_reset := RewardJuice.next_pitch(105000)
	assert(p1 > p0 and p2 > p1, "la racha sube de tono")
	assert(is_equal_approx(p_reset, 1.0), "tras una pausa la racha se reinicia")
	assert(RewardJuice.magnet_speed(10.0, 0.0) < RewardJuice.magnet_speed(10.0, 0.2))
	assert(RewardJuice.magnet_speed(10.0, 0.2) < RewardJuice.magnet_speed(10.0, 1.0))
	assert(is_equal_approx(RewardJuice.magnet_speed(10.0, 5.0), 10.0 * RewardJuice.MAGNET_MAX))
	print("CHECK 2 PASSED: escalera de tono y imán con aceleración")

	# 3. Disolución del cadáver: sustituye los materiales y devuelve su duración
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	var model := Node3D.new()
	add_child(model)
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.6, 0.3)
	mi.material_override = mat
	mi.material_overlay = StandardMaterial3D.new()
	model.add_child(mi)
	var hf := HitFeedback.new()
	add_child(hf)
	HitFeedback._inst = hf
	var t := HitFeedback.death_fx(model, [mi])
	assert(is_equal_approx(t, HitFeedback.DEATH_HOLD + HitFeedback.DEATH_DISSOLVE))
	var sm := mi.material_override as ShaderMaterial
	assert(sm != null and sm.shader == HitFeedback.DissolveShader)
	assert(mi.material_overlay == null, "sin contorno sobre los huecos")
	assert(sm.get_shader_parameter("albedo") == Color(0.2, 0.6, 0.3))
	# 3b. Muerte durante la materialización: la disolución toma su aspecto y SpawnDissolve no la pisa
	var model2 := Node3D.new()
	add_child(model2)
	var mi2 := MeshInstance3D.new()
	mi2.mesh = BoxMesh.new()
	var orig := StandardMaterial3D.new()
	orig.albedo_color = Color(0.7, 0.2, 0.2)
	mi2.material_override = orig
	model2.add_child(mi2)
	SpawnDissolve.play(model2, model2, 0.2)
	HitFeedback.death_fx(model2, [mi2])
	var sm2 := mi2.material_override as ShaderMaterial
	assert(sm2.shader == HitFeedback.DissolveShader)
	assert(sm2.get_shader_parameter("albedo") == Color(0.7, 0.2, 0.2), "toma el color del material original")
	await get_tree().create_timer(0.4).timeout
	assert(mi2.material_override == sm2, "al acabar la materialización no se restaura el material original")
	print("CHECK 3 PASSED: el cadáver pasa a material de disolución (también a medio aparecer)")

	# 4. Multi-kill: dos bajas seguidas muestran el cartel
	hf._register_kill(200000)
	assert(not is_instance_valid(hf._banner) or not hf._banner.visible)
	hf._register_kill(200200)
	assert(is_instance_valid(hf._banner) and hf._banner.visible and hf._banner.text == "¡DOBLE!")
	hf._register_kill(200400)
	assert(hf._banner.text == "¡TRIPLE!")
	print("CHECK 4 PASSED: cartel de multi-kill")

	# 5. Monedas y chispas no fallan y se limpian solas
	var player := Node3D.new()
	add_child(player)
	player.global_position = Vector3(3, 0, 0)
	RewardJuice.gold_burst(self, Vector3.ZERO, 20, player)
	RewardJuice.collect(self, Vector3.ZERO, Color.YELLOW)
	await get_tree().create_timer(1.0).timeout
	assert(sm.get_shader_parameter("dissolve") > 0.0, "la disolución avanza")
	for c in get_children():
		assert(not (c is MeshInstance3D and (c as MeshInstance3D).mesh is CylinderMesh), "las monedas llegan y se liberan")
	print("CHECK 5 PASSED: monedas vuelan al jugador y desaparecen")

	print("ALL DEATH/REWARD CHECKS PASSED")
	get_tree().quit(0)
