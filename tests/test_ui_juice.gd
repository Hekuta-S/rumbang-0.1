extends Node

## Fase 4 del plan de juice (docs/PLAN_JUICE.md): combo, cartas, botones, números y panel de vida.

func _ready() -> void:
	print("--- TEST: UI JUICE (FASE 4) ---")
	GameData.game_mode = "dungeon"

	# 1. Rangos del combo
	assert(ComboCounter.rank_for(0) == 0)
	assert(ComboCounter.rank_for(4) == 0)
	assert(ComboCounter.RANKS[ComboCounter.rank_for(5)][1] == "D")
	assert(ComboCounter.RANKS[ComboCounter.rank_for(23)][1] == "B")
	assert(ComboCounter.RANKS[ComboCounter.rank_for(999)][1] == "S")
	print("CHECK 1 PASSED: rangos D-C-B-A-S")

	# 2. Contador: aparece a los 3 golpes, sube de rango, se rompe al recibir daño y se reinicia
	var ui := Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(ui)
	var combo := ComboCounter.new()
	ui.add_child(combo)
	await get_tree().process_frame
	ComboCounter.register_hit(false)
	ComboCounter.register_hit(false)
	assert(not combo.visible, "con 2 golpes aún no se ve")
	ComboCounter.register_hit(true)   # matar suma 2
	assert(combo.visible and combo.count == 4)
	ComboCounter.register_hit(false)
	assert(combo._rank_lbl.text == "D", "a los 5 golpes, rango D")
	ComboCounter.break_combo()
	assert(combo._count_lbl.text == "ROTO")
	await get_tree().create_timer(1.2).timeout
	assert(not combo.visible and combo.count == 0, "tras romperse se oculta y se reinicia")
	for i in 3:
		ComboCounter.register_hit(false)
	combo._timer = 0.01
	await get_tree().create_timer(0.8).timeout
	assert(combo.count == 0, "sin golpear, el combo se cae solo")
	print("CHECK 2 PASSED: contador de combo (aparece, rango, roto, caída)")

	# 3. Cartas que entran escalonadas y botones con hover
	var row := HBoxContainer.new()
	ui.add_child(row)
	var cards: Array = []
	for i in 3:
		var b := Button.new()
		b.text = "Carta %d" % i
		b.custom_minimum_size = Vector2(120, 80)
		row.add_child(b)
		cards.append(b)
	await get_tree().process_frame
	UiJuice.deal_in(cards)
	assert((cards[2] as Control).modulate.a == 0.0 and (cards[2] as Control).scale.x < 1.0, "empiezan pequeñas e invisibles")
	assert((cards[0] as Button).has_meta(&"_uj_pop"), "las cartas reaccionan al ratón")
	await get_tree().create_timer(0.8).timeout
	for c in cards:
		assert((c as Control).scale.is_equal_approx(Vector2.ONE) and is_equal_approx((c as Control).modulate.a, 1.0))
	UiJuice._to_scale(cards[0], UiJuice.HOVER_SCALE)
	await get_tree().create_timer(0.3).timeout
	assert(is_equal_approx((cards[0] as Control).scale.x, UiJuice.HOVER_SCALE), "hover agranda")
	var styled := RumbangStyle.make_button("X")
	assert(styled.has_meta(&"_uj_pop"), "todos los botones con estilo Rumbang tienen hover")
	styled.free()
	print("CHECK 3 PASSED: cartas con entrada y botones con hover")

	# 4. Punch vuelve a su escala
	var lbl := Label.new()
	lbl.text = "x10"
	ui.add_child(lbl)
	UiJuice.punch(lbl, 1.5, 0.15)
	assert(lbl.scale.x > 1.4)
	await get_tree().create_timer(0.4).timeout
	assert(lbl.scale.is_equal_approx(Vector2.ONE))
	print("CHECK 4 PASSED: punch")

	# 5. Panel de vida: tiembla al recibir daño
	var vit := VitalsPanel.new()
	ui.add_child(vit)
	await get_tree().process_frame
	vit.set_values(20.0, 20.0)
	vit.set_values(12.0, 20.0)
	assert(vit._shake > 0.0, "el golpe hace temblar el panel")
	assert(vit.trail_ratio() > vit.hp_ratio(), "el rastro blanco marca el daño")
	await get_tree().create_timer(0.6).timeout
	assert(vit._shake == 0.0)
	print("CHECK 5 PASSED: panel de vida con temblor y rastro")

	print("ALL UI JUICE CHECKS PASSED")
	get_tree().quit(0)
