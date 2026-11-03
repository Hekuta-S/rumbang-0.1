extends CanvasLayer

## Cartas al subir de nivel. Cada carta es una de:
##  - "evolution"   : el arma evoluciona (nivel y catalizador, ver WeaponSynergies); sale siempre primero
##  - "new_weapon"  : arma nueva (si queda hueco en los 4 slots)
##  - "weapon_stat" : mejora ESPECÍFICA de un arma equipada (WeaponUpgrades); id = "arma:mejora"
##  - "upgrade"     : mejora genérica para armas que aún no tienen mejoras propias
## Cada carta muestra las etiquetas del arma y, si es nueva, qué sinergia activaría. Debajo:
##  🎲 volver a tirar · 🔒 bloquear (la carta vuelve en la siguiente subida) · ✖ descartar (no vuelve
##  en la partida). Los usos y lo bloqueado/descartado viven en GameState (se reinician por partida).

signal choice_made(choice_type, weapon_id)

const CARD_COUNT := 3
const MAX_PER_WEAPON := 2     ## como mucho 2 cartas del mismo arma para variar
const MAX_SLOTS := 4
const EVOLUTION_COLOR := Color(1.0, 0.84, 0.3)
const LOCK_COLOR := Color(0.25, 0.95, 1.0)

@onready var container = $Control/Panel/MarginContainer/HBoxContainer

var _player: Node
var _choices: Array = []
var _synergy_lbl: Label
var _reroll_btn: Button

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	$Control.theme = preload("res://scripts/ui/rumbang_style.gd").get_theme()
	# Encima de las cartas, las sinergias activas; debajo, volver a tirar
	var panel := $Control/Panel as Control
	panel.offset_top = -215.0
	panel.offset_bottom = 215.0
	panel.offset_left = -380.0
	panel.offset_right = 380.0
	var margin := $Control/Panel/MarginContainer
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	margin.remove_child(container)
	margin.add_child(vb)
	_synergy_lbl = _card_label("", 10, preload("res://scripts/ui/rumbang_style.gd").TEXT_DIM)
	_synergy_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_synergy_lbl)
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(container)
	_reroll_btn = Button.new()
	_reroll_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_reroll_btn.pressed.connect(_on_reroll)
	vb.add_child(_reroll_btn)

## Clave única de una carta (para bloquear / descartar).
static func choice_key(c: Dictionary) -> String:
	return "%s:%d:%s" % [c["type"], int(c["weapon"]), c.get("upgrade_id", "")]

## Candidatos y sorteo (separado de la UI para poder probarlo).
## banned: claves descartadas · locked: carta bloqueada (sale si sigue siendo válida)
## Devuelve [{type, weapon, upgrade_id?}]
static func build_choices(player: Node, banned: Array = [], locked: Dictionary = {}) -> Array:
	var combat = player.get_node_or_null("PlayerCombatController")
	var inv = player.get("weapon_inventory")
	if combat == null:
		return []
	var equipped: Array = combat.weapon_slots
	var candidates: Array = []
	var picks: Array = []

	# Evoluciones listas: siempre primero
	for w in equipped:
		if WeaponSynergies.can_evolve(inv, player.get("inventory"), w):
			picks.append({"type": "evolution", "weapon": w})

	for w in equipped:
		if WeaponUpgrades.has_specific(w):
			for d in inv.get_available_upgrades(w):
				candidates.append({"type": "weapon_stat", "weapon": w, "upgrade_id": d["id"]})
		else:
			candidates.append({"type": "upgrade", "weapon": w})

	if equipped.size() < MAX_SLOTS:
		var fresh: Array = []
		for w in WeaponData.WeaponType.values():
			if not equipped.has(w) and not banned.has(choice_key({"type": "new_weapon", "weapon": w})):
				fresh.append(w)
		fresh.shuffle()
		# Hasta 2 armas nuevas como candidatas (no inundar el sorteo)
		for w in fresh.slice(0, 2):
			candidates.append({"type": "new_weapon", "weapon": w})
		# La bloqueada puede ser un arma nueva que el sorteo no sacó
		if not locked.is_empty() and locked["type"] == "new_weapon" and not equipped.has(locked["weapon"]) \
				and not candidates.any(func(c): return choice_key(c) == choice_key(locked)):
			candidates.append(locked.duplicate())

	candidates = candidates.filter(func(c): return not banned.has(choice_key(c)))
	candidates.shuffle()
	# La bloqueada, si sigue disponible, va delante
	if not locked.is_empty():
		for c in candidates:
			if choice_key(c) == choice_key(locked):
				candidates.erase(c)
				candidates.push_front(c)
				break
	var per_weapon: Dictionary = {}
	for c in candidates:
		if picks.size() >= CARD_COUNT:
			break
		var n: int = per_weapon.get(c["weapon"], 0)
		if n >= MAX_PER_WEAPON:
			continue
		per_weapon[c["weapon"]] = n + 1
		picks.append(c)
	# Si el límite por arma dejó huecos, completar con lo que quede
	for c in candidates:
		if picks.size() >= CARD_COUNT:
			break
		if not picks.has(c):
			picks.append(c)
	return picks

## Texto de una carta (público para pruebas/HUD).
static func card_text(choice: Dictionary, inv: Node) -> String:
	var w: int = choice["weapon"]
	var data := WeaponData.get_weapon_data(w)
	var head: String = "%s %s" % [data.icon, WeaponSynergies.weapon_name(inv, w)]
	match choice["type"]:
		"evolution":
			var e: Dictionary = WeaponSynergies.EVOLUTIONS[w]
			return "EVOLUCIÓN\n\n%s → %s\n\n%s" % [head, e["name"], e["desc"]]
		"new_weapon":
			return "NUEVA ARMA\n\n" + head
		"weapon_stat":
			var d := WeaponUpgrades.get_def(w, choice["upgrade_id"])
			var lvl: int = inv.get_upgrade_level(w, choice["upgrade_id"])
			var tope: String = "" if int(d["max_level"]) >= WeaponUpgrades.UNLIMITED else " / %d" % int(d["max_level"])
			return "%s\n\n%s\nNivel %d → %d%s\n\n%s" % [head, String(d["name"]).to_upper(), lvl, lvl + 1, tope, d["desc"]]
		_:
			return "MEJORAR ARMA\n\n" + head + "\n(+ Daño/Área)"

func present_choices(player: Node) -> void:
	_player = player
	get_tree().paused = true
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_deal()

## Reparte (o vuelve a repartir) la mano.
func _deal() -> void:
	var gs := GameState.get_instance()
	_choices = build_choices(_player, gs.banished_cards, gs.locked_card)
	_refresh()

func _refresh() -> void:
	for child in container.get_children():
		child.queue_free()
	var gs := GameState.get_instance()
	var inv = _player.get("weapon_inventory")
	for choice in _choices:
		container.add_child(_make_column(choice, inv, gs))
	var syn: Array = WeaponSynergies.active(inv.weapon_slots) if inv else []
	if syn.is_empty():
		_synergy_lbl.text = "Sinergias: junta 2 armas con la misma etiqueta"
	else:
		_synergy_lbl.text = "Sinergias: " + "   ".join(syn.map(func(s): return WeaponSynergies.describe(s)))
	_reroll_btn.text = "🎲 VOLVER A TIRAR (%d)" % gs.card_rerolls
	_reroll_btn.disabled = gs.card_rerolls <= 0

## Carta + botones de bloquear y descartar debajo.
func _make_column(choice: Dictionary, inv: Node, gs: GameState) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	var btn := _make_card(choice, inv)
	btn.pressed.connect(_on_card_pressed.bind(choice))
	col.add_child(btn)
	if choice["type"] == "evolution":
		return col                   # la evolución no se bloquea ni se descarta
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	var locked := not gs.locked_card.is_empty() and choice_key(gs.locked_card) == choice_key(choice)
	var lock := Button.new()
	lock.text = "🔒 FIJADA" if locked else "🔒"
	lock.tooltip_text = "Bloquear: vuelve en la siguiente subida de nivel"
	if locked:
		lock.add_theme_color_override("font_color", LOCK_COLOR)
	lock.pressed.connect(_on_lock.bind(choice))
	row.add_child(lock)
	var ban := Button.new()
	ban.text = "✖ %d" % gs.card_banishes
	ban.tooltip_text = "Descartar: no vuelve a salir en la partida"
	ban.disabled = gs.card_banishes <= 0
	ban.pressed.connect(_on_banish.bind(choice))
	row.add_child(ban)
	col.add_child(row)
	return col

## Carta con jerarquía visual: arma (tenue), mejora (título), pips de nivel, texto y etiquetas.
func _make_card(choice: Dictionary, inv: Node) -> Button:
	var Style := preload("res://scripts/ui/rumbang_style.gd")
	var w: int = choice["weapon"]
	var data := WeaponData.get_weapon_data(w)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(210, 250)
	btn.set_meta("choice", choice)
	btn.set_meta("text_summary", card_text(choice, inv))   # para pruebas / accesibilidad
	btn.tooltip_text = card_text(choice, inv)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	btn.add_child(margin)
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 9)
	margin.add_child(vb)

	vb.add_child(_card_label("%s %s" % [data.icon, WeaponSynergies.weapon_name(inv, w)], 11, Style.TEXT_DIM))

	match choice["type"]:
		"evolution":
			var e: Dictionary = WeaponSynergies.EVOLUTIONS[w]
			for state in ["normal", "hover", "pressed", "focus"]:
				var sb := Style.button_style(Color(0.16, 0.11, 0.03), EVOLUTION_COLOR, 3, 3)
				btn.add_theme_stylebox_override(state, sb)
			vb.add_child(_card_label("¡EVOLUCIONA!", 15, EVOLUTION_COLOR))   # la fuente pixel no tiene "Ó"
			vb.add_child(_card_label(String(e["name"]).to_upper(), 13, Style.TITLE))
			vb.add_child(_card_label(String(e["desc"]), 11, Style.TEXT))
		"weapon_stat":
			var d := WeaponUpgrades.get_def(w, choice["upgrade_id"])
			var lvl: int = inv.get_upgrade_level(w, choice["upgrade_id"])
			var max_lvl: int = int(d["max_level"])
			vb.add_child(_card_label(String(d["name"]).to_upper(), 15, Style.TITLE))
			if max_lvl < WeaponUpgrades.UNLIMITED:
				vb.add_child(_card_pips(lvl, max_lvl, Style))
			vb.add_child(_card_label("Nivel %s" % WeaponUpgrades.level_label(d, lvl + 1), 11, Style.ACCENT))
			vb.add_child(_card_label(String(d["desc"]), 12, Style.TEXT))
		"new_weapon":
			vb.add_child(_card_label("NUEVA ARMA", 15, Style.TITLE))
			vb.add_child(_card_label(data.display_name, 13, Style.TEXT))
			for line in WeaponSynergies.preview_new_weapon(inv.weapon_slots, w):
				vb.add_child(_card_label("⚡ " + line, 10, EVOLUTION_COLOR))
		_:
			vb.add_child(_card_label("MEJORAR ARMA", 15, Style.TITLE))
			vb.add_child(_card_label("+ Daño / Área", 12, Style.TEXT))
	vb.add_child(_card_label(WeaponSynergies.tags_label(w), 10, Style.TEXT_DIM))
	# Pista de evolución: el arma se acerca al nivel y aún le falta (o ya tiene) el catalizador
	if choice["type"] != "evolution" and WeaponSynergies.EVOLUTIONS.has(w) and not WeaponSynergies.is_evolved(inv, w) \
			and inv.get_weapon_level(w) >= WeaponSynergies.EVOLVE_LEVEL - 3:
		vb.add_child(_card_label("Evoluciona con: %s" % WeaponSynergies.catalyst_name(w), 9, Color(EVOLUTION_COLOR, 0.8)))
	return btn

func _card_label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l

func _card_pips(level: int, max_level: int, Style) -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 4)
	for i in range(max_level):
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(14, 14)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if i < level:
			pip.color = Style.ACCENT                        # ya obtenido
		elif i == level:
			pip.color = Color(Style.ACCENT, 0.45)           # el que se obtiene ahora
		else:
			pip.color = Style.BTN_BORDER
		row.add_child(pip)
	return row

func _on_reroll() -> void:
	var gs := GameState.get_instance()
	if gs.card_rerolls <= 0:
		return
	gs.card_rerolls -= 1
	AudioManager.play("melee_swing", -8.0, 1.3)
	_deal()

func _on_lock(choice: Dictionary) -> void:
	var gs := GameState.get_instance()
	if not gs.locked_card.is_empty() and choice_key(gs.locked_card) == choice_key(choice):
		gs.locked_card = {}
	else:
		gs.locked_card = choice.duplicate()
	_refresh()

func _on_banish(choice: Dictionary) -> void:
	var gs := GameState.get_instance()
	if gs.card_banishes <= 0:
		return
	gs.card_banishes -= 1
	gs.banished_cards.append(choice_key(choice))
	if not gs.locked_card.is_empty() and choice_key(gs.locked_card) == choice_key(choice):
		gs.locked_card = {}
	# Solo se cambia esa carta; las demás se quedan
	var others: Array = _choices.filter(func(c): return c != choice)
	var fresh := build_choices(_player, gs.banished_cards + others.map(func(c): return choice_key(c)), {})
	_choices = others
	for c in fresh:
		if _choices.size() >= CARD_COUNT:
			break
		if c["type"] != "evolution":
			_choices.append(c)
	_refresh()

func _on_card_pressed(choice: Dictionary) -> void:
	var gs := GameState.get_instance()
	if not gs.locked_card.is_empty() and choice_key(gs.locked_card) == choice_key(choice):
		gs.locked_card = {}
	match choice["type"]:
		"weapon_stat":
			_on_choice_selected("weapon_stat", "%d:%s" % [choice["weapon"], choice["upgrade_id"]])
		"new_weapon":
			_on_choice_selected("new_weapon", str(choice["weapon"]))
		"evolution":
			_on_choice_selected("evolution", str(choice["weapon"]))
		_:
			_on_choice_selected("upgrade", str(choice["weapon"]))

func _on_choice_selected(c_type: String, c_id: String) -> void:
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	emit_signal("choice_made", c_type, c_id)
