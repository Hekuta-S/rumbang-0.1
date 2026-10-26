extends CanvasLayer

## Cartas al subir de nivel. Cada carta es una de:
##  - "new_weapon"  : arma nueva (si queda hueco en los 4 slots)
##  - "weapon_stat" : mejora ESPECÍFICA de un arma equipada (WeaponUpgrades); id = "arma:mejora"
##  - "upgrade"     : mejora genérica para armas que aún no tienen mejoras propias

signal choice_made(choice_type, weapon_id)

const CARD_COUNT := 3
const MAX_PER_WEAPON := 2     ## como mucho 2 cartas del mismo arma para variar
const MAX_SLOTS := 4

@onready var container = $Control/Panel/MarginContainer/HBoxContainer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	$Control.theme = preload("res://scripts/ui/rumbang_style.gd").get_theme()

## Candidatos y sorteo (separado de la UI para poder probarlo).
## Devuelve [{type, weapon, upgrade_id?}]
static func build_choices(player: Node) -> Array:
	var combat = player.get_node_or_null("PlayerCombatController")
	var inv = player.get("weapon_inventory")
	if combat == null:
		return []
	var equipped: Array = combat.weapon_slots
	var candidates: Array = []

	for w in equipped:
		if WeaponUpgrades.has_specific(w):
			for d in inv.get_available_upgrades(w):
				candidates.append({"type": "weapon_stat", "weapon": w, "upgrade_id": d["id"]})
		else:
			candidates.append({"type": "upgrade", "weapon": w})

	if equipped.size() < MAX_SLOTS:
		var all_weapons: Array = WeaponData.WeaponType.values()
		var fresh: Array = []
		for w in all_weapons:
			if not equipped.has(w):
				fresh.append(w)
		fresh.shuffle()
		# Hasta 2 armas nuevas como candidatas (no inundar el sorteo)
		for w in fresh.slice(0, 2):
			candidates.append({"type": "new_weapon", "weapon": w})

	candidates.shuffle()
	var picks: Array = []
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
	var head: String = "%s %s" % [data.icon, data.display_name]
	match choice["type"]:
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
	for child in container.get_children():
		child.queue_free()

	get_tree().paused = true
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var inv = player.get("weapon_inventory")
	for choice in build_choices(player):
		var btn := _make_card(choice, inv)
		match choice["type"]:
			"weapon_stat":
				btn.pressed.connect(_on_choice_selected.bind("weapon_stat", "%d:%s" % [choice["weapon"], choice["upgrade_id"]]))
			"new_weapon":
				btn.pressed.connect(_on_choice_selected.bind("new_weapon", str(choice["weapon"])))
			_:
				btn.pressed.connect(_on_choice_selected.bind("upgrade", str(choice["weapon"])))
		container.add_child(btn)

## Carta con jerarquía visual: arma (tenue), mejora (título), pips de nivel, texto.
func _make_card(choice: Dictionary, inv: Node) -> Button:
	var Style := preload("res://scripts/ui/rumbang_style.gd")
	var w: int = choice["weapon"]
	var data := WeaponData.get_weapon_data(w)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(200, 240)
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
	vb.add_theme_constant_override("separation", 10)
	margin.add_child(vb)

	var weapon_lbl := _card_label("%s %s" % [data.icon, data.display_name], 11, Style.TEXT_DIM)
	vb.add_child(weapon_lbl)

	match choice["type"]:
		"weapon_stat":
			var d := WeaponUpgrades.get_def(w, choice["upgrade_id"])
			var lvl: int = inv.get_upgrade_level(w, choice["upgrade_id"])
			var max_lvl: int = int(d["max_level"])
			vb.add_child(_card_label(String(d["name"]).to_upper(), 15, Style.TITLE))
			vb.add_child(_card_pips(lvl, max_lvl, Style))
			vb.add_child(_card_label("Nivel %d → %d / %d" % [lvl, lvl + 1, max_lvl], 11, Style.ACCENT))
			vb.add_child(_card_label(String(d["desc"]), 12, Style.TEXT))
		"new_weapon":
			vb.add_child(_card_label("NUEVA ARMA", 15, Style.TITLE))
			vb.add_child(_card_label(data.display_name, 13, Style.TEXT))
		_:
			vb.add_child(_card_label("MEJORAR ARMA", 15, Style.TITLE))
			vb.add_child(_card_label("+ Daño / Área", 12, Style.TEXT))
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

func _on_choice_selected(c_type: String, c_id: String) -> void:
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	emit_signal("choice_made", c_type, c_id)
