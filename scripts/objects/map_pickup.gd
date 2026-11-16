class_name MapPickup
extends Node3D

## Objetos del mapa del modo supervivencia (estilo bullet heaven). Flotan y giran; al acercarte el
## jugador se aplican y desaparecen. Caen de élites y minijefe, rara vez de enemigos normales, y
## salen del cofre maldito (ChestRoulette).
##  magnet : atrae todas las gemas de XP del suelo
##  bomb   : mata a los enemigos normales cercanos (a los élites les quita el 25 % de su vida)
##  food   : cura el 35 % de la vida máxima
##  clock  : congela a todos los enemigos 5 s

const RADIUS := 1.7
const LIFETIME := 28.0
const BLINK_FROM := 22.0
const KILL_DROP_CHANCE := 0.004
const BOMB_RADIUS := 35.0
const BOMB_ELITE_FRACTION := 0.25
const FOOD_HEAL := 0.35
const CLOCK_SECONDS := 5.0
const MAGNET_SPEED := 30.0

const KINDS := {
	"magnet": {"label": "IMAN", "color": Color(0.35, 0.8, 1.0), "weight": 30.0, "msg": "¡IMAN! Todas las gemas vuelan hacia ti"},
	"bomb": {"label": "BOMBA", "color": Color(1.0, 0.45, 0.2), "weight": 25.0, "msg": "¡BOMBA!"},
	"food": {"label": "COMIDA", "color": Color(0.4, 1.0, 0.45), "weight": 30.0, "msg": "Vida recuperada"},
	"clock": {"label": "RELOJ", "color": Color(0.85, 0.85, 1.0), "weight": 15.0, "msg": "¡TIEMPO DETENIDO!"},
}

## Modelos cartoon con la tinta horneada (tools/blender_toon_pickups.py): assets/models/pickups/<archivo>.glb
## con su textura en assets/textures/toon/props/<archivo>.png (shader prop_toon, una lectura).
const MODEL_DIR := "res://assets/models/pickups/"
const MODELS := {"magnet": "pickup_magnet", "bomb": "pickup_bomb", "food": "pickup_food", "clock": "pickup_clock"}
static var _mesh_cache: Dictionary = {}

## Malla cartoon de un modelo de assets/models/pickups (null si no existe). Se fusiona en una superficie con
## la textura horneada; se carga una vez por archivo. La usa también FateDice (el dado).
static func toon_mesh(file: String) -> Mesh:
	if _mesh_cache.has(file):
		return _mesh_cache[file]
	var mesh: Mesh = null
	var path := MODEL_DIR + file + ".glb"
	var mat := ProceduralMap.toon_prop_material(file)
	if ResourceLoader.exists(path) and mat != null:
		var root := (load(path) as PackedScene).instantiate()
		for n in root.find_children("*", "MeshInstance3D", true, false):
			mesh = ProceduralMap.flatten_with((n as MeshInstance3D).mesh, mat)
			break
		root.free()
	_mesh_cache[file] = mesh
	return mesh

var kind := "magnet"
var player: Node3D
var _t := 0.0
var _holder: Node3D
var _done := false

static func roll_kind(rng: RandomNumberGenerator = null) -> String:
	var total := 0.0
	for k in KINDS:
		total += float(KINDS[k]["weight"])
	var roll := (rng.randf() if rng else randf()) * total
	for k in KINDS:
		roll -= float(KINDS[k]["weight"])
		if roll <= 0.0:
			return k
	return "food"

static func spawn(parent: Node, pos: Vector3, p_kind: String) -> MapPickup:
	var p := MapPickup.new()
	p.kind = p_kind
	p.player = parent.get_tree().get_first_node_in_group("player")
	parent.add_child(p)
	p.global_position = pos
	return p

## Mano de la suerte al morir un enemigo normal: casi nunca.
static func roll_kill_drop(parent: Node, pos: Vector3) -> void:
	if randf() < KILL_DROP_CHANCE:
		spawn(parent, pos, roll_kind())

func _ready() -> void:
	add_to_group("map_pickups")
	var col: Color = KINDS[kind]["color"]
	_holder = Node3D.new()
	_holder.position = Vector3(0, 1.1, 0)
	add_child(_holder)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 2.0
	var gem := MeshInstance3D.new()
	var toon := toon_mesh(String(MODELS.get(kind, "")))
	if toon != null:
		# Modelo cartoon: sus colores y su tinta van en la textura; debajo, un aro del color del objeto
		gem.mesh = toon
		gem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gem.scale = Vector3.ONE * 1.25
		gem.position.y = -0.5
		_holder.add_child(gem)
		_add_ring(col)
		return
	match kind:
		"bomb":
			var pm := PrismMesh.new()
			pm.size = Vector3(0.5, 0.5, 0.5)
			gem.mesh = pm
		"clock":
			var bm := BoxMesh.new()
			bm.size = Vector3(0.45, 0.45, 0.45)
			gem.mesh = bm
		_:
			var sm := SphereMesh.new()
			sm.radius = 0.28
			sm.height = 0.56
			sm.radial_segments = 8
			sm.rings = 4
			gem.mesh = sm
	gem.material_override = mat
	gem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_holder.add_child(gem)
	var label := Label3D.new()
	label.text = String(KINDS[kind]["label"])
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 36
	label.outline_size = 10
	label.modulate = col
	label.position = Vector3(0, 0.7, 0)
	_holder.add_child(label)

## Aro en el suelo del color del objeto (se ve de lejos entre la hierba).
func _add_ring(col: Color) -> void:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.55
	tm.outer_radius = 0.72
	tm.rings = 24
	tm.ring_segments = 4
	ring.mesh = tm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	ring.material_override = m
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.scale = Vector3(1.0, 0.15, 1.0)
	ring.position.y = 0.06
	add_child(ring)
	var ink := MeshInstance3D.new()
	var tm2 := TorusMesh.new()
	tm2.inner_radius = 0.5
	tm2.outer_radius = 0.77
	tm2.rings = 24
	tm2.ring_segments = 4
	ink.mesh = tm2
	var mi := StandardMaterial3D.new()
	mi.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.albedo_color = Color(0.03, 0.022, 0.05)
	ink.material_override = mi
	ink.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ink.scale = Vector3(1.0, 0.1, 1.0)
	ink.position.y = 0.04
	add_child(ink)

func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	_holder.rotation.y += delta * 2.0
	_holder.position.y = 1.1 + sin(_t * 3.0) * 0.12
	if _t > BLINK_FROM:
		_holder.visible = int(_t * 8.0) % 2 == 0
	if _t >= LIFETIME:
		queue_free()
		return
	if not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
		return
	var d := Vector2(player.global_position.x - global_position.x, player.global_position.z - global_position.z)
	if d.length() <= RADIUS:
		_done = true
		apply(kind, player, get_tree().current_scene)
		queue_free()

## Aplica el efecto del objeto (público para el cofre y las pruebas).
static func apply(p_kind: String, p_player: Node3D, root: Node) -> void:
	var col: Color = KINDS[p_kind]["color"]
	match p_kind:
		"magnet":
			for orb in p_player.get_tree().get_nodes_in_group("xp_orbs"):
				if orb.has_method("pull_to"):
					orb.pull_to(p_player, MAGNET_SPEED)
		"bomb":
			bomb_blast(p_player.global_position, BOMB_RADIUS)
		"food":
			if p_player.has_method("heal") and p_player.get("health_comp"):
				p_player.heal(p_player.health_comp.max_hp * FOOD_HEAL)
		"clock":
			for e in EnemyRegistry.all().duplicate():
				if e is EnemyData:
					e.apply_slow(CLOCK_SECONDS, 0.0)
	if root:
		NecroVFX.shockwave(root, p_player.global_position, 14.0 if p_kind == "bomb" else 8.0, col)
	AudioManager.play("kill_burst", -4.0, 1.2)
	if root and root.get("facade") and root.facade.wave_manager and root.facade.wave_manager.events:
		root.facade.wave_manager.events.announce(String(KINDS[p_kind]["msg"]), col, "")

## Bomba: los normales mueren; élites y minijefe pierden BOMB_ELITE_FRACTION de su vida máxima.
static func bomb_blast(center: Vector3, radius: float) -> int:
	var hit := 0
	for e in EnemyRegistry.all().duplicate():
		if not (e is EnemyData) or e.recycled:
			continue
		if Vector2(e.global_position.x - center.x, e.global_position.z - center.z).length() > radius:
			continue
		hit += 1
		if e.xp_reward >= XpCurve.XP_ELITE:
			e.take_damage(e.max_hp * BOMB_ELITE_FRACTION)
		else:
			e.take_damage(e.hp + 1.0)
	return hit
