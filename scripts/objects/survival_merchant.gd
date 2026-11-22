class_name SurvivalMerchant
extends Node3D

## Tatan de paso en la supervivencia (lo hace aparecer RunEvents de vez en cuando).
## Vende tres cosas sorteadas al aparecer: un OBJETO (ItemDB), un TOMO (TomeDB) y una MEJORA de arma
## (UpgradeCards.build_choices). Se paga con el oro de la partida. Al comprarle una, se despide y
## desaparece; si nadie le compra, se va a los LIFETIME s (parpadea los últimos segundos).
## Se abre con la tecla de habilidad (E / RB / botón táctil) vía Player.interact_target, como la forja.

signal left(bought: bool)

const UpgradeCards := preload("res://scripts/ui/upgrade_choice_ui.gd")

const OPEN_DIST := 2.6
const LIFETIME := 60.0
const BLINK_FROM := 50.0
const HEIGHT := 1.75
const COLOR := Color(1.0, 0.55, 0.2)
## Precio base de cada oferta; sube PRICE_PER_MIN por minuto de partida
const PRICE := {"item": 60, "tome": 80, "upgrade": 70}
const PRICE_PER_MIN := 12
const ITEM_RARITY_COLOR := [Color(0.78, 0.8, 0.85), Color(0.4, 0.9, 0.45), Color(0.35, 0.65, 1.0), Color(0.72, 0.4, 1.0), Color(1.0, 0.78, 0.2)]

var player: Node3D
var offers: Array = []                ## [{kind, id, title, desc, icon, color, price, data}]
var _t := 0.0
var _near := false
var _done := false
var _ui: DungeonChoiceUI
var _prompt: Label3D
var _model: Node3D

static func spawn(parent: Node, pos: Vector3, p_player: Node3D, elapsed: float) -> SurvivalMerchant:
	var m := SurvivalMerchant.new()
	m.player = p_player
	m.offers = roll_offers(p_player, elapsed)
	parent.add_child(m)
	m.global_position = pos
	return m

## Sorteo de las ofertas (separado para las pruebas). Si no queda nada de un tipo, esa oferta no sale.
static func roll_offers(p: Node, elapsed: float) -> Array:
	var extra := PRICE_PER_MIN * int(elapsed / 60.0)
	var out: Array = []
	var inv = p.get("inventory") if p else null
	var items: Array = ItemDB.roll_choices(inv, 1)
	if not items.is_empty():
		var it: Dictionary = items[0]
		var r := int(it.get("rarity", 0))
		out.append({"kind": "item", "id": String(it["id"]), "title": String(it["name"]), "desc": String(it["description"]),
			"icon": "🎒", "color": ITEM_RARITY_COLOR[clampi(r, 0, ITEM_RARITY_COLOR.size() - 1)],
			"price": PRICE["item"] + 15 * r + extra})
	var tomes: Array = TomeDB.ids().filter(func(id): return TomeDB.can_take(id))
	if not tomes.is_empty():
		var id: String = tomes.pick_random()
		var sb = p.get("stat_block") if p else null
		var rar := TomeDB.roll_rarity(sb.luck() if sb != null else 0.0)
		out.append({"kind": "tome", "id": id, "rarity": rar, "title": "Tomo: " + TomeDB.tome_name(id),
			"desc": "%s · nivel %d → %d\n%s" % [TomeDB.RARITY_NAME[rar], TomeDB.level(id), TomeDB.level(id) + 1, TomeDB.describe(id, rar)],
			"icon": "📖", "color": TomeDB.RARITY_COLOR[rar], "price": PRICE["tome"] + 20 * rar + extra})
	var up := _roll_upgrade(p)
	if not up.is_empty():
		var inv_w = p.get("weapon_inventory")
		out.append({"kind": "upgrade", "id": UpgradeCards.choice_key(up), "choice": up,
			"title": "Mejora de arma", "desc": UpgradeCards.card_text(up, inv_w).replace("\n\n", "\n"),
			"icon": "⚔", "color": Color(1.0, 0.85, 0.35), "price": PRICE["upgrade"] + extra})
	return out

## Una mejora de un arma que ya llevas (o, si no queda ninguna, un arma nueva).
static func _roll_upgrade(p: Node) -> Dictionary:
	if p == null or p.get_node_or_null("PlayerCombatController") == null:
		return {}
	var all: Array = UpgradeCards.build_choices(p)
	var ups := all.filter(func(c): return c["type"] == "weapon_stat" or c["type"] == "upgrade")
	if ups.is_empty():
		ups = all.filter(func(c): return c["type"] == "new_weapon")
	return ups.pick_random() if not ups.is_empty() else {}

func _ready() -> void:
	add_to_group("survival_merchants")
	_model = DungeonShop.make_tatan(self, Vector3.ZERO, HEIGHT)
	var lbl := _label("TATAN · MERCADER", 24)
	lbl.position.y = HEIGHT + 0.75
	add_child(lbl)
	_prompt = _label("E · COMPRAR A TATÁN", 20)
	_prompt.position.y = HEIGHT + 0.45
	_prompt.visible = false
	add_child(_prompt)
	var glow := OmniLight3D.new()
	glow.light_color = COLOR
	glow.light_energy = 1.2
	glow.omni_range = 4.0
	glow.position.y = 1.2
	add_child(glow)

func _label(text: String, size: int) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.fixed_size = true
	l.pixel_size = 0.0011
	l.font_size = size
	l.outline_size = 8
	l.modulate = COLOR
	l.outline_modulate = Color(0.05, 0.02, 0.05)
	l.no_depth_test = true
	l.render_priority = 10
	return l

func _exit_tree() -> void:
	_set_near(false)

func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	if _t >= LIFETIME and not is_instance_valid(_ui):
		leave(false)
		return
	visible = _t < BLINK_FROM or fmod(_t, 0.4) < 0.25
	if not is_instance_valid(player):
		return
	if _model:
		var to := player.global_position - global_position
		if Vector2(to.x, to.z).length() > 0.1:
			_model.rotation.y = lerp_angle(_model.rotation.y, atan2(to.x, to.z), minf(1.0, delta * 4.0))
	var d := Vector2(player.global_position.x - global_position.x, player.global_position.z - global_position.z).length()
	_set_near(d <= OPEN_DIST and not is_instance_valid(_ui))

func _set_near(on: bool) -> void:
	if on == _near:
		return
	_near = on
	if _prompt:
		_prompt.visible = on
	if not is_instance_valid(player) or not ("interact_target" in player):
		return
	if on:
		player.interact_target = self
	elif player.interact_target == self:
		player.interact_target = null

## Lo llama Player.activate_skill() cuando estás al lado.
func interact() -> void:
	if not _done and not is_instance_valid(_ui):
		open()

func open() -> void:
	_ui = DungeonChoiceUI.present(get_tree().current_scene, "TATAN, MERCADER DE PASO", _gold_line(), options(), true)
	_ui.chosen.connect(buy)
	_set_near(false)

func _gold_line() -> String:
	return "Solo te vende UNA cosa y se va   —   TIENES %d ORO   (1-3 elige · Esc sale)" % GameState.get_instance().gold

func options() -> Array:
	var gold := GameState.get_instance().gold
	var out: Array = []
	for o in offers:
		var price := int(o["price"])
		out.append({"id": o["kind"], "icon": o["icon"], "title": o["title"], "desc": o["desc"], "color": o["color"],
			"price": price, "disabled": gold < price, "reason": "FALTAN %d ORO" % (price - gold) if gold < price else ""})
	return out

## Compra la oferta `kind` ("item" / "tome" / "upgrade"). Devuelve true si se compró (y Tatan se va).
func buy(kind: String) -> bool:
	if _done:
		return false
	var offer: Dictionary = {}
	for o in offers:
		if o["kind"] == kind:
			offer = o
	if offer.is_empty():
		return false
	var gs := GameState.get_instance()
	var price := int(offer["price"])
	if gs.gold < price or not _grant(offer):
		return false
	gs.gold -= price
	# El oro de la partida ya contaba para la tienda permanente: lo gastado sale también de ahí
	SaveManager.total_gold = maxi(0, SaveManager.total_gold - price)
	SaveManager.save()
	var scene := get_tree().current_scene
	if scene and scene.get("facade"):
		scene.facade.update_gold(gs.gold)
	AudioManager.play("level-up", -6.0, 1.3)
	if is_instance_valid(_ui):
		_ui._close()
	leave(true)
	return true

func _grant(offer: Dictionary) -> bool:
	if not is_instance_valid(player):
		return false
	match String(offer["kind"]):
		"item":
			var inv = player.get("inventory")
			if inv == null:
				return false
			inv.add_item(String(offer["id"]))
		"tome":
			var sb = player.get("stat_block")
			if sb == null or not TomeDB.can_take(String(offer["id"])):
				return false
			sb.add_tome(String(offer["id"]), int(offer["rarity"]))
		"upgrade":
			var c: Dictionary = offer["choice"]
			var w := int(c["weapon"])
			match String(c["type"]):
				"weapon_stat": player.weapon_inventory.upgrade_weapon_stat(w, String(c["upgrade_id"]))
				"upgrade": player.upgrade_weapon(w)
				"new_weapon": player.add_weapon(w)
				_: return false
			var scene := get_tree().current_scene
			if scene and scene.get("facade") and scene.facade.get("ui_manager"):
				scene.facade.ui_manager.refresh_weapon_ui()
		_:
			return false
	return true

## Se despide y desaparece (compra hecha o tiempo agotado).
func leave(bought: bool) -> void:
	if _done:
		return
	_done = true
	_set_near(false)
	left.emit(bought)
	var scene := get_tree().current_scene
	if scene:
		NecroVFX.shockwave(scene, global_position + Vector3(0, 0.1, 0), 3.0, COLOR)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3(0.01, 0.01, 0.01), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)
