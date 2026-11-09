class_name DungeonShop
extends Node3D

## Forja de la mazmorra (en la caverna inicial desde el nivel 2): al acercarse se abre la tienda
## (DungeonChoiceUI con keep_open). Se paga con el oro de la partida (GameState.gold), que sueltan
## los enemigos de la mazmorra. Vende poción, recarga y dos runas sorteadas al crearla.
## Para volver a abrirla hay que alejarse antes (REARM_DIST).
## El tendero es Tatan (su modelo junto al yunque): además vende EQUIP_OFFERS piezas de equipo
## sorteadas (EquipmentDB), que van a PlayerEquipment como si las recogieras.

const OPEN_DIST := 2.4
const REARM_DIST := 4.0
const POTION_HEAL := 0.5
const COLOR := Color(1.0, 0.55, 0.2)
const EQUIP_OFFERS := 2
const TATAN_HEIGHT := 1.75
const TATAN_OFFSET := Vector3(1.4, 0.0, -0.3)

var player: Node3D
var level := 1
var _runes: Array = []
var _equip: Array = []                ## piezas a la venta
var tatan: Node3D
var _armed := true
var _ui: DungeonChoiceUI

static func spawn(parent: Node, pos: Vector3, p_player: Node3D, p_level: int) -> DungeonShop:
	var s := DungeonShop.new()
	s.player = p_player
	s.level = p_level
	s._runes = DungeonRunes.roll(2)
	for i in EQUIP_OFFERS:
		s._equip.append(EquipmentDB.roll("", -1, null, mini(int(p_level / 3.0), 2)))
	parent.add_child(s)
	s.global_position = pos
	return s

func _ready() -> void:
	add_to_group("dungeon_shops")
	var anvil := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.2, 0.7, 0.7)
	anvil.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.2, 0.22)
	mat.metallic = 0.6
	mat.roughness = 0.4
	anvil.material_override = mat
	anvil.position.y = 0.35
	add_child(anvil)
	var glow := OmniLight3D.new()
	glow.light_color = COLOR
	glow.light_energy = 1.6
	glow.omni_range = 4.0
	glow.position.y = 1.0
	add_child(glow)
	var lbl := Label3D.new()
	lbl.text = "FORJA DE TATAN"
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.fixed_size = true
	lbl.pixel_size = 0.0011
	lbl.font_size = 24
	lbl.outline_size = 8
	lbl.modulate = COLOR
	lbl.position.y = 1.7
	add_child(lbl)
	_spawn_tatan()

## Tatan, el tendero, de pie a la derecha del yunque y mirando hacia delante, en bucle de idle.
func _spawn_tatan() -> void:
	var path := GameData.get_idle_model_path("tatan")
	if path == "" or not ResourceLoader.exists(path):
		return
	var scene := load(path) as PackedScene
	if scene == null:
		return
	tatan = scene.instantiate() as Node3D
	tatan.name = "Tatan"
	add_child(tatan)
	tatan.position = TATAN_OFFSET
	tatan.rotation.y = -0.5
	# Mixamo: la malla va en cm bajo un esqueleto escalado, así que la altura se mide por los huesos
	var skels := tatan.find_children("*", "Skeleton3D", true, false)
	if not skels.is_empty():
		var sk := skels[0] as Skeleton3D
		var to_local := tatan.global_transform.affine_inverse() * sk.global_transform
		var lo := INF
		var hi := -INF
		for b in sk.get_bone_count():
			var y := (to_local * sk.get_bone_global_rest(b).origin).y
			lo = minf(lo, y)
			hi = maxf(hi, y)
		var h := (hi - lo) * 1.08          # la cabeza sobresale un poco del último hueso
		if h > 0.01:
			var k := TATAN_HEIGHT / h
			tatan.scale = Vector3(k, k, k)
			tatan.position.y = -lo * k
	var tex_path := GameData.get_texture_path("tatan")
	if tex_path != "" and ResourceLoader.exists(tex_path):
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = load(tex_path)
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		for m in tatan.find_children("*", "MeshInstance3D", true, false):
			(m as MeshInstance3D).material_override = mat
	var aps := tatan.find_children("*", "AnimationPlayer", true, false)
	if not aps.is_empty():
		var ap := aps[0] as AnimationPlayer
		var names := ap.get_animation_list()
		if not names.is_empty():
			ap.get_animation(names[0]).loop_mode = Animation.LOOP_LINEAR
			ap.play(names[0])

func prices() -> Dictionary:
	return {"potion": 25 + 5 * level, "refill": 15 + 3 * level, "rune": 50 + 15 * level}

func equip_price(item: Dictionary) -> int:
	return 40 + 35 * int(item.get("rarity", 0)) + 8 * level

func _process(_delta: float) -> void:
	if not is_instance_valid(player) or is_instance_valid(_ui):
		return
	var d := Vector2(player.global_position.x - global_position.x, player.global_position.z - global_position.z).length()
	if d > REARM_DIST:
		_armed = true
	elif _armed and d <= OPEN_DIST:
		_armed = false
		open()

func open() -> void:
	_ui = DungeonChoiceUI.present(get_tree().current_scene, "FORJA DE TATAN", _gold_line(), _options(), true)
	_ui.chosen.connect(_buy)

func _gold_line() -> String:
	return "TIENES %d ORO" % GameState.get_instance().gold

func _options() -> Array:
	var gold := GameState.get_instance().gold
	var p := prices()
	var out: Array = [
		{"id": "potion", "icon": "🧪", "title": "Poción", "desc": "Recupera el %d%% de la vida" % int(POTION_HEAL * 100.0),
			"price": p["potion"], "color": Color(1.0, 0.35, 0.35), "disabled": gold < p["potion"]},
		{"id": "refill", "icon": "🔋", "title": "Recarga", "desc": "Llena energía, maná y balas",
			"price": p["refill"], "color": Color(0.4, 0.8, 1.0), "disabled": gold < p["refill"]},
	]
	for r in _runes:
		var o := DungeonRunes.option(r, p["rune"])
		o["disabled"] = gold < p["rune"] or not DungeonRunes.can_add(r)
		out.append(o)
	var eq = player.get("equipment") if is_instance_valid(player) else null
	for it in _equip:
		var price := equip_price(it)
		var lines: Array = ["%s %s" % [EquipmentDB.KIND_NAMES.get(it["slot"], ""), EquipmentDB.rarity_name(it).to_lower()]]
		lines.append_array(EquipmentDB.describe_stats(it.get("stats", {})))
		lines.append_array(EquipmentDB.trait_lines(it))
		if EquipmentDB.SETS.has(String(it.get("set", ""))):
			lines.append("Set " + String(EquipmentDB.SETS[it["set"]]["name"]))
		out.append({"id": "equip:" + String(it["uid"]), "icon": EquipmentDB.KIND_ICONS.get(it["slot"], "✦"),
			"title": String(it["name"]), "desc": "
".join(lines), "price": price, "color": EquipmentDB.rarity_color(it),
			"disabled": gold < price or eq == null or eq.bag.size() >= PlayerEquipment.BAG_MAX})
	return out

func _equip_offer(id: String) -> Dictionary:
	for it in _equip:
		if "equip:" + String(it["uid"]) == id:
			return it
	return {}

func _buy(id: String) -> void:
	var gs := GameState.get_instance()
	var offer := _equip_offer(id)
	var price: int = equip_price(offer) if not offer.is_empty() else prices()["rune" if DungeonRunes.RUNES.has(id) else id]
	if gs.gold < price:
		return
	if not offer.is_empty():
		var eq = player.get("equipment")
		if eq == null or eq.receive(offer) == "full":
			return
		_equip.erase(offer)
		_charge(price)
		return
	match id:
		"potion":
			if player.has_method("heal") and player.get("health_comp"):
				player.heal(player.health_comp.max_hp * POTION_HEAL)
		"refill":
			if player.get("resources"):
				player.resources.refresh_for_new_level()
		_:
			if not DungeonRunes.can_add(id):
				return
			DungeonRunes.add(id)
			_runes.erase(id)
	_charge(price)

func _charge(price: int) -> void:
	var gs := GameState.get_instance()
	gs.gold -= price
	var scene := get_tree().current_scene
	if scene and scene.get("facade"):
		scene.facade.update_gold(gs.gold)
	AudioManager.play("level-up", -6.0, 1.3)
	if is_instance_valid(_ui):
		_ui.set_options(_options(), _gold_line())
