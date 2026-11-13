class_name EquipmentPickup
extends Area3D

## Pieza de equipo en el suelo de la mazmorra (ver EquipmentDB / PlayerEquipment). Brilla con el
## color de su rareza y lleva su nombre encima. Al acercarte vuela hacia ti: si su ranura está libre
## se equipa sola; si no, va a la mochila (se cambia en el menú de pausa, pestaña EQUIPO).
## Fuentes: cajas y barriles (PROP_CHANCE), enemigos (ENEMY_CHANCE, más en brutos y jefes),
## cofres del tesoro y la tienda de Tatan (DungeonShop).

const MAGNET_RADIUS := 2.5
const SPEED := 9.0
const LIFETIME := 90.0
const PROP_CHANCE := 0.11          ## cajas, barriles y bolsas (antes 0.08)
const ENEMY_CHANCE := 0.02         ## cualquier enemigo (antes 0.012)
const ELITE_CHANCE := 0.16         ## brutos (antes 0.12)
const BOSS_MIN_RARITY := 2         ## los jefes sueltan siempre una pieza, rara como mínimo

var item: Dictionary = {}
var _player: Node3D
var _magnet := false
var _age := 0.0
var _mesh: MeshInstance3D
var _collected := false
var beam: MeshInstance3D              ## columna de luz de las piezas raras o mejores
const BEAM_MIN_RARITY := 2

static func spawn(parent: Node, pos: Vector3, p_item: Dictionary) -> EquipmentPickup:
	RunLog.drop(p_item)
	var p := EquipmentPickup.new()
	p.item = p_item
	p.collision_layer = 0
	p.collision_mask = 2                  ## el jugador
	parent.add_child(p)
	p.global_position = pos + Vector3(0, 0.6, 0)
	return p

## Tira el dado de botín; devuelve la pieza soltada o null. Solo en la mazmorra y sin red.
static func try_drop(parent: Node, pos: Vector3, chance: float, min_rarity: int = 0) -> EquipmentPickup:
	if GameData.game_mode != "dungeon" or Net.is_online() or parent == null:
		return null
	if randf() >= chance * DungeonRun.drop_mult():
		return null
	var item := EquipmentDB.roll("", -1, null, maxi(maxi(min_rarity, DungeonRun.min_rarity()), DungeonRun.pity_min_rarity()))
	DungeonRun.note_drop(item)
	return spawn(parent, pos, item)

## Botín de un enemigo muerto según su tipo.
static func drop_for_enemy(parent: Node, dead: Node3D) -> EquipmentPickup:
	if not is_instance_valid(dead):
		return null
	if dead is DungeonNecromancer:
		# Jefes: botín propio (sus legendarias, EquipmentDB "boss") o una pieza rara o mejor
		if GameData.game_mode != "dungeon" or Net.is_online() or parent == null:
			return null
		var boss := "rat_king" if dead is DungeonRatKing else "necro"
		DungeonRun.maybe_blueprint(parent, dead.global_position + Vector3(-1.2, 0, 0), 1.0)
		return spawn(parent, dead.global_position, EquipmentDB.boss_drop(boss, BOSS_MIN_RARITY))
	# Garantía: tras DungeonRun.PITY_KILLS bajas sin pieza, la siguiente baja suelta una
	var forced := DungeonRun.note_kill_for_loot()
	if dead is DungeonBrute:
		return try_drop(parent, dead.global_position, 1.0 if forced else ELITE_CHANCE, 1)
	return try_drop(parent, dead.global_position, 1.0 if forced else ENEMY_CHANCE)

func _ready() -> void:
	add_to_group("equipment_pickups")
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.7
	col.shape = shape
	add_child(col)
	var color := EquipmentDB.rarity_color(item)
	_mesh = MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(0.36, 0.42, 0.36)
	_mesh.mesh = prism
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 3.0
	_mesh.material_override = mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 1.2
	light.omni_range = 2.5
	light.shadow_enabled = false
	add_child(light)
	var lbl := Label3D.new()
	lbl.text = "%s %s" % [EquipmentDB.KIND_ICONS.get(item.get("slot", ""), "✦"), item.get("name", "")]
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.fixed_size = true
	lbl.pixel_size = 0.0009
	lbl.font_size = 22
	lbl.outline_size = 8
	lbl.modulate = color
	lbl.no_depth_test = true
	lbl.position.y = 0.6
	add_child(lbl)
	if int(item.get("rarity", 0)) >= BEAM_MIN_RARITY:
		_add_beam(color)
		lbl.text += "\n%s%s" % [EquipmentDB.rarity_name(item).to_upper(), "  ★" if item.has("perk") else ""]
	body_entered.connect(_on_body_entered)
	_announce()

## Columna de luz (rara o mejor): se ve desde lejos. Más ancha y alta cuanto mejor la rareza.
func _add_beam(color: Color) -> void:
	var r := int(item.get("rarity", 0))
	beam = MeshInstance3D.new()
	beam.name = "Beam"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.05 + 0.03 * (r - BEAM_MIN_RARITY)
	cyl.bottom_radius = cyl.top_radius * 1.6
	cyl.height = 5.0 + 2.0 * (r - BEAM_MIN_RARITY)
	cyl.radial_segments = 8
	cyl.rings = 1
	beam.mesh = cyl
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(color.r, color.g, color.b, 0.28)
	beam.material_override = m
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.position.y = cyl.height * 0.5 - 0.4
	add_child(beam)

## Sonido y sacudida al aparecer una pieza buena (solo rara o mejor; las comunes son silenciosas).
func _announce() -> void:
	var r := int(item.get("rarity", 0))
	if r < BEAM_MIN_RARITY or not is_inside_tree():
		return
	AudioManager.play_at("level-up", global_position, -6.0 + 3.0 * (r - BEAM_MIN_RARITY), 1.15 - 0.12 * (r - BEAM_MIN_RARITY))
	if r >= 3:
		HitFeedback.shake(0.25 if r == 3 else 0.4)

func _physics_process(delta: float) -> void:
	_age += delta
	if _age > LIFETIME:
		queue_free()
		return
	_mesh.rotation.y += delta * 2.0
	_mesh.position.y = 0.1 * sin(_age * 3.0)
	if beam:
		(beam.material_override as StandardMaterial3D).albedo_color.a = 0.22 + 0.1 * sin(_age * 4.0)
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if _player == null:
			return
	var to_p := _player.global_position + Vector3(0, 0.9, 0) - global_position
	if not _magnet and to_p.length() < MAGNET_RADIUS:
		_magnet = true
	if _magnet:
		global_position += to_p.normalized() * SPEED * delta
		if to_p.length() < 0.7:
			collect(_player)

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		collect(body)

## Lo usa también el test. Con la mochila llena la pieza se queda en el suelo.
func collect(player: Node) -> String:
	if _collected:
		return ""
	var eq = player.get("equipment")
	if eq == null:
		return ""
	var result: String = eq.receive(item)
	if result == "full":
		_magnet = false
		global_position += Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * 1.5
		toast(self, "Mochila llena: %s" % item.get("name", ""), Color(1, 0.4, 0.35))
		return result
	_collected = true
	var text := "%s %s — %s" % ["EQUIPADO:" if result == "equipped" else "A LA MOCHILA:",
		item.get("name", ""), EquipmentDB.rarity_name(item)]
	if EquipmentDB.perk_text(item) != "":
		text += "\n★ " + EquipmentDB.perk_text(item)
	toast(self, text, EquipmentDB.rarity_color(item))
	if item.has("legendary"):
		HitFeedback.shake(0.35)
	AudioManager.play("level-up", -8.0, 1.5)
	queue_free()
	return result

## Aviso corto abajo en pantalla.
static func toast(from: Node, text: String, color: Color) -> void:
	if from == null or not from.is_inside_tree():
		return
	var tree := from.get_tree()
	var root := tree.current_scene if tree.current_scene else tree.root
	var layer := CanvasLayer.new()
	layer.layer = 72
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	var l := Label.new()
	l.text = text
	l.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	l.grow_vertical = Control.GROW_DIRECTION_BEGIN
	l.offset_bottom = -200.0
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.theme = RumbangStyle.get_theme()
	RumbangStyle.style_title(l, 16, color, RumbangStyle.NEON_CYAN)
	layer.add_child(l)
	root.add_child(layer)
	var tw := l.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	l.modulate.a = 0.0
	tw.tween_property(l, "modulate:a", 1.0, 0.2)
	tw.tween_interval(2.2)
	tw.tween_property(l, "modulate:a", 0.0, 0.5)
	tw.tween_callback(layer.queue_free)
