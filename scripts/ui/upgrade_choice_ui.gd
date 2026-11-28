extends CanvasLayer

## Cartas al subir de nivel. Cada carta es una de:
##  - "evolution"   : el arma evoluciona (nivel y catalizador, ver WeaponSynergies); sale siempre primero
##  - "new_weapon"  : arma nueva (si queda hueco en los 4 slots)
##  - "weapon_stat" : mejora ESPECÍFICA de un arma equipada (WeaponUpgrades); id = "arma:mejora"
##  - "upgrade"     : mejora genérica para armas que aún no tienen mejoras propias
##  - "tome"        : tomo pasivo (TomeDB) con rareza propia (choice["rarity"]); 4 huecos de tomo
## Diseño: design/ux/level-up-cards.md. Cada carta lleva la IMAGEN de lo que da, insignias de etiqueta con
## icono y la fila "Potencia a": mini-iconos de tus armas/tomos que fortalece (WeaponSynergies.card_links).
## Debajo de las cartas, la tira "Tu equipo": tus armas y tomos y una barra por etiqueta (x/3). Al pasar el
## ratón o el foco por una carta, se iluminan en la tira las cosas tuyas que potencia.
## Debajo de cada carta: 🔒 bloquear (vuelve en la siguiente subida) · ✖ descartar (no vuelve en la
## partida); abajo, 🎲 volver a tirar. Los usos y lo bloqueado/descartado viven en GameState.

signal choice_made(choice_type, weapon_id)

const CARD_COUNT := 3
const MAX_PER_WEAPON := 2     ## como mucho 2 cartas del mismo arma para variar
const MAX_SLOTS := PlayerWeaponInventory.MAX_WEAPON_SLOTS
const EVOLUTION_COLOR := Color(1.0, 0.84, 0.3)
const LOCK_COLOR := Color(0.25, 0.95, 1.0)

const CARD_SIZE := Vector2(220, 300)
const CARD_IMAGE := 72           ## px de la imagen grande de la carta
const LINK_ICON := 26            ## px de los mini-iconos de "Potencia a"
const BADGE_ICON := 18           ## px del icono de una insignia de etiqueta
const STRIP_ICON := 40           ## px de armas y tomos en la tira "Tu equipo"
const DIM := 0.45                ## brillo de lo que NO potencia la carta señalada

@onready var container = $Control/Panel/MarginContainer/HBoxContainer

var _player: Node
var _choices: Array = []
var _strip: VBoxContainer
var _strip_nodes: Dictionary = {}      ## "w:<arma>" / "t:<tomo>" / "g:<etiqueta>" -> Control de la tira
var _reroll_btn: Button
static var _tex_cache: Dictionary = {}
const ACTION_BTN := Vector2(64, 44)      ## 🔒 / ✖: ~48 dp en un móvil (la UI base es 1280×720)
const HOLD_S := 0.4                     ## mantener la carta este tiempo muestra su detalle sin elegirla
const FLY_S := 0.35                     ## la imagen de la carta elegida vuela a su hueco de "Tu equipo"
var _detail: PanelContainer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	$Control.theme = preload("res://scripts/ui/rumbang_style.gd").get_theme()
	# Cartas arriba, "Tu equipo" debajo y volver a tirar al final
	var panel := $Control/Panel as Control
	panel.offset_top = -300.0
	panel.offset_bottom = 300.0
	panel.offset_left = -420.0
	panel.offset_right = 420.0
	var margin := $Control/Panel/MarginContainer
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	margin.remove_child(container)
	margin.add_child(vb)
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(container)
	_strip = VBoxContainer.new()
	_strip.add_theme_constant_override("separation", 6)
	vb.add_child(_strip)
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
			if not equipped.has(w) and MetaProgress.weapon_unlocked(w) \
					and GameData.weapon_available_in_mode(w) \
					and not banned.has(choice_key({"type": "new_weapon", "weapon": w})):
				fresh.append(w)
		fresh.shuffle()
		# Hasta 2 armas nuevas como candidatas (no inundar el sorteo)
		for w in fresh.slice(0, 2):
			candidates.append({"type": "new_weapon", "weapon": w})
		# La bloqueada puede ser un arma nueva que el sorteo no sacó
		if not locked.is_empty() and locked["type"] == "new_weapon" and not equipped.has(locked["weapon"]) \
				and GameData.weapon_available_in_mode(int(locked["weapon"])) \
				and not candidates.any(func(c): return choice_key(c) == choice_key(locked)):
			candidates.append(locked.duplicate())

	# Tomos: hasta 2 nuevos (si queda hueco) y los que ya tienes y no están al máximo
	var luck := 0.0
	var sb = player.get("stat_block")
	if sb != null:
		luck = sb.luck()
	var fresh_tomes: Array = []
	for id in TomeDB.ids():
		if not TomeDB.can_take(id):
			continue
		if TomeDB.level(id) > 0:
			candidates.append({"type": "tome", "weapon": -1, "upgrade_id": id, "rarity": TomeDB.roll_rarity(luck)})
		else:
			fresh_tomes.append(id)
	fresh_tomes.shuffle()
	for id in fresh_tomes.slice(0, 2):
		candidates.append({"type": "tome", "weapon": -1, "upgrade_id": id, "rarity": TomeDB.roll_rarity(luck)})
	# La bloqueada puede ser un tomo que el sorteo no sacó
	if not locked.is_empty() and locked["type"] == "tome" and TomeDB.can_take(String(locked["upgrade_id"])) 			and not candidates.any(func(c): return choice_key(c) == choice_key(locked)):
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
	if choice["type"] == "tome":
		var id: String = choice["upgrade_id"]
		var r: int = int(choice.get("rarity", 0))
		return "%s

%s
Nivel %d → %d / %d

%s" % [TomeDB.RARITY_NAME[r], TomeDB.tome_name(id), TomeDB.level(id), TomeDB.level(id) + 1, TomeDB.MAX_LEVEL, TomeDB.describe(id, r)]
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
	_hide_detail()
	for child in container.get_children():
		child.queue_free()
	var gs := GameState.get_instance()
	var inv = _player.get("weapon_inventory")
	var cols: Array = []
	for choice in _choices:
		var col := _make_column(choice, inv, gs)
		container.add_child(col)
		cols.append(col)
	UiJuice.deal_in(cols, 0.09)
	for b in container.find_children("*", "Button", true, false):
		if not (b as Button).disabled:
			(b as Button).grab_focus.call_deferred()
			break
	_build_strip(inv)
	_reroll_btn.text = "🎲 VOLVER A TIRAR (%d)" % gs.card_rerolls
	_reroll_btn.disabled = gs.card_rerolls <= 0

## Carta + botones de bloquear y descartar debajo.
func _make_column(choice: Dictionary, inv: Node, gs: GameState) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	var btn := _make_card(choice, inv)
	btn.pressed.connect(_on_card_released.bind(choice, btn))
	btn.gui_input.connect(_on_card_gui_input.bind(btn))
	# Señalar la carta ilumina en la tira lo tuyo que potencia
	var links: Array = btn.get_meta("links", [])
	btn.mouse_entered.connect(_highlight.bind(links))
	btn.focus_entered.connect(_highlight.bind(links))
	btn.mouse_exited.connect(_highlight.bind(null))
	btn.focus_exited.connect(_highlight.bind(null))
	col.add_child(btn)
	if choice["type"] == "evolution":
		return col                   # la evolución no se bloquea ni se descarta
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	var locked := not gs.locked_card.is_empty() and choice_key(gs.locked_card) == choice_key(choice)
	var lock := Button.new()
	lock.custom_minimum_size = ACTION_BTN      # cómodo para el dedo
	lock.text = "🔒 FIJADA" if locked else "🔒"
	lock.tooltip_text = "Bloquear: vuelve en la siguiente subida de nivel"
	if locked:
		lock.add_theme_color_override("font_color", LOCK_COLOR)
	lock.pressed.connect(_on_lock.bind(choice))
	row.add_child(lock)
	var ban := Button.new()
	ban.custom_minimum_size = ACTION_BTN
	ban.text = "✖ %d" % gs.card_banishes
	ban.tooltip_text = "Descartar: no vuelve a salir en la partida"
	ban.disabled = gs.card_banishes <= 0
	ban.pressed.connect(_on_banish.bind(choice))
	row.add_child(ban)
	col.add_child(row)
	return col

## Carta (design/ux/level-up-cards.md): tipo, IMAGEN grande, nombre y pips, insignias de etiqueta, fila
## "Potencia a" con los mini-iconos de tu equipo que fortalece y la descripción.
func _make_card(choice: Dictionary, inv: Node) -> Button:
	var Style := preload("res://scripts/ui/rumbang_style.gd")
	if choice["type"] == "tome":
		return _make_tome_card(choice, inv, Style)
	var w: int = choice["weapon"]
	var data := WeaponData.get_weapon_data(w)
	var btn := _card_button(choice, inv)
	var vb := _card_body(btn)
	var name_text := WeaponSynergies.weapon_name(inv, w)
	match choice["type"]:
		"evolution":
			for state in ["normal", "hover", "pressed"]:
				btn.add_theme_stylebox_override(state, Style.button_style(Color(0.16, 0.11, 0.03), EVOLUTION_COLOR, 3, 3))
			btn.add_theme_stylebox_override("focus", Style.focus_ring(EVOLUTION_COLOR))   # foco visible con mando
			vb.add_child(_card_label("¡EVOLUCIONA!", 13, EVOLUTION_COLOR))   # la fuente pixel no tiene "Ó"
			vb.add_child(_card_image(_weapon_icon(w), name_text, EVOLUTION_COLOR))
			vb.add_child(_card_label(String(WeaponSynergies.EVOLUTIONS[w]["name"]).to_upper(), 13, Style.TITLE))
		"weapon_stat":
			var d := WeaponUpgrades.get_def(w, choice["upgrade_id"])
			var lvl: int = inv.get_upgrade_level(w, choice["upgrade_id"])
			var max_lvl: int = int(d["max_level"])
			vb.add_child(_card_label("MEJORA · " + name_text.to_upper(), 10, Style.TEXT_DIM))
			vb.add_child(_card_image(_weapon_icon(w), name_text, Style.TITLE))
			vb.add_child(_card_label(String(d["name"]).to_upper(), 14, Style.TITLE))
			if max_lvl < WeaponUpgrades.UNLIMITED:
				vb.add_child(_card_pips(lvl, max_lvl, Style))
		"new_weapon":
			vb.add_child(_card_label("NUEVA ARMA", 12, Style.ACCENT))
			vb.add_child(_card_image(_weapon_icon(w), data.display_name, Style.TITLE))
			vb.add_child(_card_label(data.display_name.to_upper(), 14, Style.TITLE))
		_:
			vb.add_child(_card_label("MEJORAR ARMA", 12, Style.ACCENT))
			vb.add_child(_card_image(_weapon_icon(w), name_text, Style.TITLE))
			vb.add_child(_card_label(name_text.to_upper(), 14, Style.TITLE))
	vb.add_child(_tag_badges(WeaponSynergies.tags_of(w), Style))
	_add_links(vb, btn, choice, inv, Style)
	match choice["type"]:
		"evolution":
			vb.add_child(_card_label(String(WeaponSynergies.EVOLUTIONS[w]["desc"]), 10, Style.TEXT))
		"weapon_stat":
			var d2 := WeaponUpgrades.get_def(w, choice["upgrade_id"])
			vb.add_child(_card_label(String(d2["desc"]), 10, Style.TEXT))
		"upgrade":
			vb.add_child(_card_label("+ Daño / Área", 10, Style.TEXT))
	return btn

## Carta de tomo: borde y título del color de su rareza, imagen del tomo, pips, efecto y, en "Potencia a",
## tus armas que evoluciona.
func _make_tome_card(choice: Dictionary, inv: Node, Style) -> Button:
	var id: String = choice["upgrade_id"]
	var r: int = int(choice.get("rarity", 0))
	var col: Color = TomeDB.RARITY_COLOR[r]
	var def: Dictionary = TomeDB.TOMES[id]
	var btn := _card_button(choice, inv)
	for state in ["normal", "pressed"]:
		btn.add_theme_stylebox_override(state, Style.button_style(Color(col.r * 0.12, col.g * 0.12, col.b * 0.12), col, 3 if r > 0 else 2, 3))
	# Señalada (ratón o mando) brilla: fondo más claro y anillo con halo. Antes "focus" repetía el normal
	# y con mando no se sabía qué tomo estaba marcado.
	btn.add_theme_stylebox_override("hover", Style.button_style(Color(col.r * 0.24, col.g * 0.24, col.b * 0.24), col, 3, 3))
	btn.add_theme_stylebox_override("focus", Style.focus_ring(Style.NEON_CYAN))
	var vb := _card_body(btn)
	var title := String(def["name"]).replace("Tomo de ", "")
	vb.add_child(_card_label("TOMO · " + TomeDB.RARITY_NAME_ASCII[r], 11, col))
	vb.add_child(_card_image(_tex(TomeDB.icon_path(id)), title, col))
	vb.add_child(_card_label(title.to_upper(), 14, Style.TITLE))
	vb.add_child(_card_pips(TomeDB.level(id), TomeDB.MAX_LEVEL, Style))
	_add_links(vb, btn, choice, inv, Style)
	vb.add_child(_card_label(TomeDB.describe(id, r), 10, Style.TEXT))
	return btn

func _card_button(choice: Dictionary, inv: Node) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = CARD_SIZE
	btn.set_meta("choice", choice)
	var summary := card_text(choice, inv)
	var links := _links_for(choice, inv)
	if not links.is_empty():
		summary += "\n\nPotencia a: " + "; ".join(links.map(func(l): return String(l["text"])))
	btn.set_meta("text_summary", summary)   # para pruebas / accesibilidad
	btn.set_meta("links", links)
	btn.tooltip_text = summary
	return btn

func _card_body(btn: Button) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	btn.add_child(margin)
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 6)
	margin.add_child(vb)
	return vb

## Enlaces de una carta con tu equipo (WeaponSynergies.card_links con el estado del inventario).
func _links_for(choice: Dictionary, inv: Node) -> Array:
	if inv == null:
		return []
	var slots: Array = inv.weapon_slots
	var levels := {}
	var evolved: Array = []
	for s in slots:
		levels[s] = inv.get_weapon_level(s)
		if WeaponSynergies.is_evolved(inv, s):
			evolved.append(s)
	return WeaponSynergies.card_links(choice, slots, levels, TomeDB.owned().keys(), evolved)

## Fila "Potencia a": por enlace, los mini-iconos de tus cosas y el texto corto. Sin enlaces no aparece.
func _add_links(vb: VBoxContainer, btn: Button, _choice: Dictionary, _inv: Node, Style) -> void:
	var links: Array = btn.get_meta("links", [])
	if links.is_empty():
		return
	vb.add_child(_card_label("POTENCIA A", 9, EVOLUTION_COLOR))
	for l in links:
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 3)
		for w in l["weapons"]:
			row.add_child(_icon(_weapon_icon(w), LINK_ICON, WeaponData.weapon_names.get(w, "?")))
		for t in l["tomes"]:
			row.add_child(_icon(_tex(TomeDB.icon_path(t)), LINK_ICON, String(t)))
		for g in l["tags"]:
			row.add_child(_icon(_tex(WeaponSynergies.tag_icon_path(g)), LINK_ICON, String(g)))
		var txt := _card_label(String(l["text"]), 9, Style.TEXT)
		txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		txt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(txt)
		vb.add_child(row)

## Insignias de etiqueta: icono dibujado + nombre en el color de la etiqueta.
func _tag_badges(tags: Array, _Style) -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	for t in tags:
		var info: Dictionary = WeaponSynergies.TAG_INFO[t]
		var b := HBoxContainer.new()
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_theme_constant_override("separation", 3)
		b.add_child(_icon(_tex(WeaponSynergies.tag_icon_path(t)), BADGE_ICON, String(info["name"])))
		var l := _card_label(String(info["name"]), 10, info["color"])
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		b.add_child(l)
		row.add_child(b)
	return row

## Imagen grande centrada; sin textura, la inicial del nombre en un marco (nunca un emoji).
func _card_image(tex: Texture2D, label: String, color: Color) -> Control:
	var c := CenterContainer.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(_icon(tex, CARD_IMAGE, label, color))
	return c

func _icon(tex: Texture2D, px: int, label: String, color: Color = Color(0.85, 0.85, 0.85)) -> Control:
	if tex != null:
		var r := TextureRect.new()
		r.texture = tex
		r.custom_minimum_size = Vector2(px, px)
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return r
	push_warning("UpgradeChoiceUI: sin icono para '%s'" % label)
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(px, px)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := _card_label(label.substr(0, 1).to_upper(), int(px * 0.5), color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p

static func _tex(path: String) -> Texture2D:
	if path == "":
		return null
	if not _tex_cache.has(path):
		_tex_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _tex_cache[path]

static func _weapon_icon(w: int) -> Texture2D:
	return _tex(String(WeaponChoiceUI.ICONS.get(w, "")))

## Tira "Tu equipo": 4 huecos de arma, 4 de tomo y una barra por etiqueta que tengas (llena hasta 3: con 2
## armas se activa el primer bono, con 3 el segundo).
func _build_strip(inv: Node) -> void:
	var Style := preload("res://scripts/ui/rumbang_style.gd")
	for c in _strip.get_children():
		c.queue_free()
	_strip_nodes.clear()
	var slots: Array = inv.weapon_slots if inv else []
	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_theme_constant_override("separation", 6)
	var head := _card_label("TU EQUIPO", 10, Style.TEXT_DIM)
	head.autowrap_mode = TextServer.AUTOWRAP_OFF
	top.add_child(head)
	for i in range(MAX_SLOTS):
		if i < slots.size():
			var w: int = slots[i]
			var cell := _strip_cell(_weapon_icon(w), WeaponData.weapon_names.get(w, "?"), str(inv.get_weapon_level(w)), Style)
			_strip_nodes["w:%d" % w] = cell
			top.add_child(cell)
		else:
			top.add_child(_free_cell(0, Style))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(14, 0)
	top.add_child(gap)
	var owned: Array = TomeDB.owned().keys()
	for i in range(TomeDB.SLOTS):
		if i < owned.size():
			var id: String = owned[i]
			var cell := _strip_cell(_tex(TomeDB.icon_path(id)), String(TomeDB.TOMES[id]["name"]), str(TomeDB.level(id)), Style)
			_strip_nodes["t:%s" % id] = cell
			top.add_child(cell)
		else:
			top.add_child(_free_cell(1, Style))
	_strip.add_child(top)
	# Barras de etiqueta
	var bars := HBoxContainer.new()
	bars.alignment = BoxContainer.ALIGNMENT_CENTER
	bars.add_theme_constant_override("separation", 16)
	var counts := WeaponSynergies.tag_counts(slots)
	if counts.is_empty():
		bars.add_child(_card_label("Junta 2 armas con la misma etiqueta para activar su bono", 10, Style.TEXT_DIM))
	for t in WeaponSynergies.TAG_INFO:
		if not counts.has(t):
			continue
		var bar := _tag_bar(t, int(counts[t]))
		_strip_nodes["g:%s" % t] = bar
		bars.add_child(bar)
	_strip.add_child(bars)

## Hueco libre "+" de armas (group 0) o tomos (group 1): ahí aterriza una carta de arma o tomo nuevo.
func _free_cell(group: int, Style) -> Control:
	var c := _strip_cell(null, "+", "", Style)
	c.set_meta("free", true)
	c.set_meta("group", group)
	return c

func _strip_cell(tex: Texture2D, label: String, level: String, Style) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.tooltip_text = label
	if tex == null and label == "+":
		var empty := PanelContainer.new()
		empty.custom_minimum_size = Vector2(STRIP_ICON, STRIP_ICON)
		empty.modulate = Color(1, 1, 1, 0.35)
		var plus := _card_label("+", 16, Style.TEXT_DIM)
		plus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		plus.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.add_child(plus)
		v.add_child(empty)
		return v
	v.add_child(_icon(tex, STRIP_ICON, label))
	var lv := _card_label(level, 9, Style.ACCENT)
	lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(lv)
	return v

## Icono de la etiqueta + 3 segmentos; llenos tantos como armas (máx 3). El 2.º y 3.º marcan los bonos.
func _tag_bar(tag: String, count: int) -> Control:
	var info: Dictionary = WeaponSynergies.TAG_INFO[tag]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	row.tooltip_text = "%s %d/3: %s" % [info["name"], count, " · ".join(WeaponSynergies.SYNERGY_DESC[tag])]
	row.add_child(_icon(_tex(WeaponSynergies.tag_icon_path(tag)), 22, String(info["name"])))
	for k in range(3):
		var seg := ColorRect.new()
		seg.custom_minimum_size = Vector2(14, 12)
		seg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		seg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		seg.color = info["color"] if k < count else Color(0.2, 0.2, 0.24)
		row.add_child(seg)
	var lbl := _card_label("%s %d/3" % [info["name"], mini(count, 3)], 9, info["color"])
	lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(lbl)
	return row

## Ilumina en la tira lo que potencia la carta señalada y atenúa lo demás (null = todo normal).
func _highlight(links) -> void:
	var keys := {}
	if links != null:
		for l in links:
			for w in l["weapons"]:
				keys["w:%d" % int(w)] = true
			for t in l["tomes"]:
				keys["t:%s" % t] = true
			for g in l["tags"]:
				keys["g:%s" % g] = true
	for k in _strip_nodes:
		var node: Control = _strip_nodes[k]
		if not is_instance_valid(node):
			continue
		if links == null or keys.is_empty():
			node.modulate = Color.WHITE
		else:
			node.modulate = Color(1.25, 1.2, 0.8) if keys.has(k) else Color(DIM, DIM, DIM)

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

## Mantener la carta (dedo o ratón) HOLD_S muestra el detalle; soltar lo cierra SIN elegir. Un toque corto
## elige (el botón emite pressed al soltar). Así nadie elige por accidente al querer leer.
func _on_card_gui_input(ev: InputEvent, btn: Button) -> void:
	if not (ev is InputEventMouseButton) or (ev as InputEventMouseButton).button_index != MOUSE_BUTTON_LEFT:
		return
	if ev.pressed:
		btn.set_meta("down", true)
		btn.set_meta("held", false)
		get_tree().create_timer(HOLD_S, true).timeout.connect(_on_hold_timeout.bind(btn))
	else:
		btn.set_meta("down", false)
		_hide_detail()

func _on_hold_timeout(btn: Button) -> void:
	if is_instance_valid(btn) and btn.get_meta("down", false):
		btn.set_meta("held", true)
		_show_detail(btn)

func _on_card_released(choice: Dictionary, btn: Button) -> void:
	if btn.get_meta("held", false):
		btn.set_meta("held", false)
		return                                   # fue un "mantener para leer": no se elige
	_fly_to_strip(choice, btn)
	_on_card_pressed(choice)

## Globo con el texto completo de la carta (y su "Potencia a"), encima de ella.
func _show_detail(btn: Button) -> void:
	_hide_detail()
	var Style := preload("res://scripts/ui/rumbang_style.gd")
	_detail = PanelContainer.new()
	_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.05, 0.09, 0.96)
	sb.border_color = EVOLUTION_COLOR
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(10)
	_detail.add_theme_stylebox_override("panel", sb)
	var l := _card_label(String(btn.get_meta("text_summary", "")), 11, Style.TEXT)
	l.custom_minimum_size = Vector2(260, 0)
	_detail.add_child(l)
	$Control.add_child(_detail)
	var r := btn.get_global_rect()
	_detail.reset_size()
	_detail.global_position = Vector2(clampf(r.position.x + r.size.x * 0.5 - 140.0, 8.0, $Control.size.x - 290.0),
		maxf(8.0, r.position.y - _detail.size.y - 8.0))

func _hide_detail() -> void:
	if is_instance_valid(_detail):
		_detail.queue_free()
	_detail = null

## La imagen de la carta elegida vuela a su hueco de "Tu equipo" y se desvanece. Va en una capa propia
## para no retrasar la elección (el juego se reanuda al momento).
func _fly_to_strip(choice: Dictionary, btn: Button) -> void:
	var imgs := btn.find_children("*", "TextureRect", true, false)
	if imgs.is_empty():
		return
	var src := imgs[0] as TextureRect
	var target := _strip_target(choice)
	if target == null or src.texture == null:
		return
	var layer := CanvasLayer.new()
	layer.layer = 95
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	var ghost := TextureRect.new()
	ghost.texture = src.texture
	ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.size = src.size
	ghost.global_position = src.get_global_rect().position
	layer.add_child(ghost)
	get_tree().root.add_child(layer)
	var to := target.get_global_rect()
	var tw := ghost.create_tween().set_parallel(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(ghost, "global_position", to.position, FLY_S).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(ghost, "size", to.size, FLY_S).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(ghost, "modulate:a", 0.0, FLY_S * 0.5).set_delay(FLY_S * 0.6)
	tw.chain().tween_callback(layer.queue_free)

## Hueco de "Tu equipo" que recibe la carta: el arma o tomo que mejora, o el primer hueco libre.
func _strip_target(choice: Dictionary) -> Control:
	match choice["type"]:
		"tome":
			var key := "t:%s" % choice["upgrade_id"]
			if _strip_nodes.has(key):
				return _strip_nodes[key]
			return _first_free_slot(1)
		"new_weapon":
			return _first_free_slot(0)
		_:
			return _strip_nodes.get("w:%d" % int(choice["weapon"]), null)

## Primer hueco "+" de la fila de armas (0) o de tomos (1) de la tira.
func _first_free_slot(which: int) -> Control:
	if _strip.get_child_count() == 0:
		return null
	var top := _strip.get_child(0)
	var free: Array = top.get_children().filter(func(c): return c is VBoxContainer and c.get_meta("free", false))
	var half := free.filter(func(c): return int(c.get_meta("group", 0)) == which)
	return half[0] if not half.is_empty() else null

func _on_card_pressed(choice: Dictionary) -> void:
	_hide_detail()
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
		"tome":
			_on_choice_selected("tome", "%s:%d" % [choice["upgrade_id"], int(choice.get("rarity", 0))])
		_:
			_on_choice_selected("upgrade", str(choice["weapon"]))

func _on_choice_selected(c_type: String, c_id: String) -> void:
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	emit_signal("choice_made", c_type, c_id)
