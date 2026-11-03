class_name DungeonShop
extends Node3D

## Forja de la mazmorra (en la caverna inicial desde el nivel 2): al acercarse se abre la tienda
## (DungeonChoiceUI con keep_open). Se paga con el oro de la partida (GameState.gold), que sueltan
## los enemigos de la mazmorra. Vende poción, recarga y dos runas sorteadas al crearla.
## Para volver a abrirla hay que alejarse antes (REARM_DIST).

const OPEN_DIST := 2.4
const REARM_DIST := 4.0
const POTION_HEAL := 0.5
const COLOR := Color(1.0, 0.55, 0.2)

var player: Node3D
var level := 1
var _runes: Array = []
var _armed := true
var _ui: DungeonChoiceUI

static func spawn(parent: Node, pos: Vector3, p_player: Node3D, p_level: int) -> DungeonShop:
	var s := DungeonShop.new()
	s.player = p_player
	s.level = p_level
	s._runes = DungeonRunes.roll(2)
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
	lbl.text = "FORJA"
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.fixed_size = true
	lbl.pixel_size = 0.0011
	lbl.font_size = 24
	lbl.outline_size = 8
	lbl.modulate = COLOR
	lbl.position.y = 1.7
	add_child(lbl)

func prices() -> Dictionary:
	return {"potion": 25 + 5 * level, "refill": 15 + 3 * level, "rune": 50 + 15 * level}

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
	_ui = DungeonChoiceUI.present(get_tree().current_scene, "FORJA", _gold_line(), _options(), true)
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
	return out

func _buy(id: String) -> void:
	var gs := GameState.get_instance()
	var price: int = prices()["rune" if DungeonRunes.RUNES.has(id) else id]
	if gs.gold < price:
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
	gs.gold -= price
	var scene := get_tree().current_scene
	if scene and scene.get("facade"):
		scene.facade.update_gold(gs.gold)
	AudioManager.play("level-up", -6.0, 1.3)
	_ui.set_options(_options(), _gold_line())
