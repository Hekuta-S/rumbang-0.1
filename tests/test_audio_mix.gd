extends Node

## Fase 6 del plan de juice (docs/PLAN_JUICE.md): buses, ducking, vida baja y variantes.

func _ready() -> void:
	print("--- TEST: MEZCLA DE AUDIO (FASE 6) ---")
	# El primer frame trae todo el tiempo de carga como delta: los tweens en tiempo real se lo comerían
	await get_tree().create_timer(0.3).timeout
	AudioManager.ensure_buses()

	# 1. Buses y efectos
	for pair in [["SFX", "Master"], ["Music", "Master"], ["UI", "Master"], ["Ambient", "SFX"]]:
		var idx := AudioServer.get_bus_index(pair[0])
		assert(idx >= 0, "falta el bus %s" % pair[0])
		assert(AudioServer.get_bus_send(idx) == StringName(pair[1]), "%s debe enviar a %s" % pair)
	assert(AudioManager._duck_fx != null and AudioManager._lp_music != null and AudioManager._lp_sfx != null)
	SettingsManager._apply_all()
	assert(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("UI")),
		AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX"))), "la UI sigue al volumen de efectos")
	print("CHECK 1 PASSED: buses SFX/Music/UI/Ambient con sus efectos")

	# 2. Ducking: baja casi al instante, se mantiene y vuelve; manda el más profundo
	AudioManager.duck(6.0, 0.2)
	AudioManager.duck(2.0, 0.0)   # más suave: no debe recortar el anterior
	await get_tree().create_timer(0.12).timeout
	assert(AudioManager.duck_level_db() < -5.5, "la música baja (%.1f dB)" % AudioManager.duck_level_db())
	await get_tree().create_timer(0.8).timeout
	assert(absf(AudioManager.duck_level_db()) < 0.05, "y vuelve a su nivel")
	print("CHECK 2 PASSED: ducking")

	# 3. Peligro por vida baja: curvas, filtro y latido
	assert(VitalsPanel.danger_for(1.0) == 0.0 and VitalsPanel.danger_for(0.3) == 0.0)
	assert(VitalsPanel.danger_for(0.15) > 0.0 and VitalsPanel.danger_for(0.05) == 1.0)
	assert(VitalsPanel.danger_for(0.0) == 0.0, "muerto: sin latido")
	assert(AudioManager.lowpass_for(0.0) == AudioManager.LOWPASS_OPEN)
	assert(AudioManager.lowpass_for(1.0) == AudioManager.LOWPASS_CLOSED)
	assert(AudioManager.beat_interval(0.0) == 0.0 and AudioManager.beat_interval(1.0) < AudioManager.beat_interval(0.3))
	AudioManager.set_danger(1.0)
	await get_tree().create_timer(0.6).timeout
	assert(AudioManager._lp_sfx.cutoff_hz < 2000.0, "el filtro se cierra (%.0f Hz)" % AudioManager._lp_sfx.cutoff_hz)
	assert(_lp_enabled("SFX") and _lp_enabled("Music"))
	assert(not _lp_enabled("UI"), "la interfaz y el latido no se filtran")
	AudioManager.set_danger(0.0)
	await get_tree().create_timer(0.6).timeout
	assert(not _lp_enabled("SFX"), "sin peligro el filtro se apaga (no gasta CPU)")
	print("CHECK 3 PASSED: filtro y latido con vida baja")

	# 4. Enrutado y variantes
	var before := AudioManager.get_child_count()
	AudioManager._last_play_ms.clear()
	AudioManager.play("ui_click")
	var last := AudioManager.get_child(AudioManager.get_child_count() - 1) as AudioStreamPlayer
	assert(AudioManager.get_child_count() == before + 1 and last.bus == &"UI", "ui_click va al bus UI")
	AudioManager.play("dodge")
	last = AudioManager.get_child(AudioManager.get_child_count() - 1) as AudioStreamPlayer
	assert(last.bus == &"SFX")
	for n in ["impact_slash", "goblin_hurt", "swing_light", "pickup", "coin", "heartbeat",
			# identidad por arma y por criatura (tools/generate_identity_sfx.py)
			"dagger_swing", "dagger_spin", "dagger_dash", "sword_swing", "sword_heavy", "great_swing", "great_heavy",
			"mace_swing", "mace_spin", "mace_ground", "spear_thrust",
			"impact_sword", "impact_great", "impact_dagger", "impact_mace", "player_hurt",
			"zombie_warn", "zombie_swing", "zombie_hurt", "zombie_die", "zombie_rise",
			"brute_warn", "brute_swing", "brute_hurt", "brute_die", "mage_warn", "mage_hurt", "mage_die",
			"necro_warn", "necro_hurt", "necro_die", "necro_summon"]:
		assert(AudioManager._exists(n), "falta %s" % n)
	AudioManager._pick_variant("impact_slash")
	assert(int(AudioManager._variant_count["impact_slash"]) == 3, "impact_slash con 3 variantes")
	print("CHECK 4 PASSED: enrutado por bus y variantes")

	print("ALL AUDIO MIX CHECKS PASSED")
	get_tree().quit(0)

func _lp_enabled(bus: String) -> bool:
	var idx := AudioServer.get_bus_index(bus)
	for i in AudioServer.get_bus_effect_count(idx):
		if AudioServer.get_bus_effect(idx, i) is AudioEffectLowPassFilter:
			return AudioServer.is_bus_effect_enabled(idx, i)
	return false
