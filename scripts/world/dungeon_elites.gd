class_name DungeonElites
extends RefCounted

## Élites de la mazmorra (al estilo de los "badass" de Borderlands / élites de Dead Cells): un enemigo
## normal con un MODIFICADOR que cambia cómo hay que pelear con él, no solo su vida.
##  - blindado: un escudo le quita el 65 % del daño hasta que lo aturdes (o lo paras) una vez
##  - vampirico: cada golpe que te da le cura un 20 % de su vida
##  - explosivo: al morir deja una carga que estalla en 1 s (apártate)
##  - veloz: más rápido y con anticipaciones más cortas
##  - protector: los aliados a menos de PROTECT_RADIUS m reciben la mitad de daño mientras viva
##  - furioso: por debajo de la mitad de vida se enfurece (más rápido y más daño)
## Todas: más vida, algo más de daño, triple de oro y una pieza de equipo garantizada (poco común o más).
## Solo sin red (DungeonEncounter.structure_enabled): las copias de los clientes no tienen la marca.

const MODS := {
	"blindado": {"label": "BLINDADO", "color": Color(0.55, 0.75, 1.0), "hp": 1.8, "desc": "Aturdelo para romper su escudo"},
	"vampirico": {"label": "VAMPIRICO", "color": Color(0.95, 0.15, 0.3), "hp": 2.0, "desc": "Se cura al golpearte"},
	"explosivo": {"label": "EXPLOSIVO", "color": Color(1.0, 0.55, 0.1), "hp": 1.8, "desc": "Estalla al morir"},
	"veloz": {"label": "VELOZ", "color": Color(1.0, 0.95, 0.3), "hp": 1.6, "desc": "Rapido y sin aviso"},
	"protector": {"label": "PROTECTOR", "color": Color(0.3, 1.0, 0.85), "hp": 2.0, "desc": "Protege a los suyos: matalo primero"},
	"furioso": {"label": "FURIOSO", "color": Color(1.0, 0.25, 0.15), "hp": 2.2, "desc": "Se enfurece a media vida"},
}
## Tipos que nunca son élite (jefes) o que van en enjambre (se reparten por WorldDefs "swarm").
const NEVER := ["necro", "rat_king"]

const DAMAGE_MULT := 1.25
const GOLD_MULT := 3
const MODEL_SCALE := 1.2
const DROP_MIN_RARITY := 1

const SHIELD_TAKEN := 0.35
const VAMP_HEAL := 0.2
const BLAST_DELAY := 1.0
const BLAST_RADIUS := 3.2
const BLAST_DAMAGE := 3.0
const VELOZ_SPEED := 1.45
const VELOZ_WINDUP := 0.7
const PROTECT_RADIUS := 6.0
const PROTECT_TAKEN := 0.5
const FURY_AT := 0.5
const FURY_SPEED := 1.4
const FURY_DAMAGE := 1.6
const FURY_WINDUP := 0.8

static var _protectors: Array = []

## Modificador al azar válido para el tipo `kind` ("" si ese tipo no puede ser élite).
static func roll_mod(kind: String) -> String:
	if NEVER.has(kind):
		return ""
	var ids: Array = MODS.keys()
	return ids[randi() % ids.size()]

## Convierte al enemigo en élite. Llamar después de añadirlo al árbol (su _ready ya fijó vida y velocidad).
static func make(e: DungeonGoblin, mod: String) -> void:
	if not is_instance_valid(e) or not MODS.has(mod) or e.elite != "":
		return
	var m: Dictionary = MODS[mod]
	e.elite = mod
	e.max_hp *= float(m["hp"])
	e.hp = e.max_hp
	e.damage_mult *= DAMAGE_MULT
	e.gold_reward *= GOLD_MULT
	var model := e.get_model()
	if model:
		model.scale *= MODEL_SCALE
	_add_marker(e, String(m["label"]), m["color"])
	var rc: Color = m["color"]
	e.set_rim(Color(rc.r, rc.g, rc.b, 0.8))      # contorno del color del modificador: se distingue de lejos
	match mod:
		"blindado":
			e.damage_taken_mult = SHIELD_TAKEN
			_add_shield(e)
		"veloz":
			e.speed *= VELOZ_SPEED
			e.windup_scale *= VELOZ_WINDUP
		"protector":
			_protectors.append(e)
			_add_ring(e, PROTECT_RADIUS, m["color"], "ProtectRing")
	e.died.connect(_on_died.bind(mod), CONNECT_ONE_SHOT)

## Multiplicador del daño que recibe `e` por las auras de los protectores cercanos (no la suya).
static func aura_mult(e: DungeonGoblin) -> float:
	if _protectors.is_empty():
		return 1.0
	for i in range(_protectors.size() - 1, -1, -1):
		var p = _protectors[i]
		if not is_instance_valid(p) or p.is_dead():
			_protectors.remove_at(i)
			continue
		if p != e and p.global_position.distance_to(e.global_position) <= PROTECT_RADIUS:
			return PROTECT_TAKEN
	return 1.0

## ¿Protege alguien a `e` ahora mismo? (para pruebas e interfaz)
static func is_protected(e: DungeonGoblin) -> bool:
	return aura_mult(e) < 1.0

## Golpe del élite al jugador.
static func on_hit_player(e: DungeonGoblin, dmg: float) -> void:
	if e.elite == "vampirico" and not e.is_dead():
		var heal := e.max_hp * VAMP_HEAL
		e.hp = minf(e.max_hp, e.hp + heal)
		var root := e.get_tree().current_scene if e.is_inside_tree() else null
		if root:
			DungeonGoblin.FloatingDamage.spawn(root, e.global_position + Vector3(0, 2.0, 0), heal, Color(0.3, 1.0, 0.4))

## El élite quedó aturdido.
static func on_stunned(e: DungeonGoblin) -> void:
	if e.elite == "blindado" and e.damage_taken_mult < 1.0:
		e.damage_taken_mult = 1.0
		var shield := e.get_node_or_null("EliteShield")
		if shield:
			shield.queue_free()
		AudioManager.play_at("impact_zap", e.global_position, 0.0, 0.7)
		_popup(e, "¡ESCUDO ROTO!", MODS["blindado"]["color"])

## Después de recibir daño (sigue vivo).
static func on_damaged(e: DungeonGoblin) -> void:
	if e.elite == "furioso" and not e.has_meta("fury") and e.hp <= e.max_hp * FURY_AT:
		e.set_meta("fury", true)
		e.speed *= FURY_SPEED
		e.damage_mult *= FURY_DAMAGE
		e.windup_scale *= FURY_WINDUP
		var model := e.get_model()
		if model:
			model.scale *= 1.1
		AudioManager.play_at("boss_sting", e.global_position, -6.0, 1.4)
		_popup(e, "¡FURIA!", MODS["furioso"]["color"])

static func _on_died(dead: DungeonGoblin, mod: String) -> void:
	if not is_instance_valid(dead) or not dead.is_inside_tree():
		return
	var parent := dead.get_parent()
	var pos := dead.global_position
	EquipmentPickup.try_drop(parent, pos + Vector3(0.6, 0, 0.6), 1.0, DROP_MIN_RARITY)
	for i in LootHits.extra_elite_drops(dead):
		EquipmentPickup.try_drop(parent, pos + Vector3(-0.6, 0, 0.6), 1.0, DROP_MIN_RARITY)
	DungeonRun.maybe_blueprint(parent, pos + Vector3(0, 0, -0.8), DungeonRun.BLUEPRINT_ELITE_CHANCE)
	if mod == "protector":
		_protectors.erase(dead)
	elif mod == "explosivo":
		_spawn_blast(parent, pos)

# ───────────────────────────── Explosión ─────────────────────────────

## Carga del explosivo: la erupción del jefe (GroundBlast) con su aviso en el suelo.
static func _spawn_blast(parent: Node, pos: Vector3) -> GroundBlast:
	return GroundBlast.spawn(parent, Vector3(pos.x, pos.y, pos.z), BLAST_RADIUS, BLAST_DELAY, BLAST_DAMAGE, MODS["explosivo"]["color"])

# ───────────────────────────── Marcas ─────────────────────────────

static func _add_marker(e: DungeonGoblin, text: String, col: Color) -> void:
	var lbl := Label3D.new()
	lbl.name = "EliteMarker"
	lbl.text = "★ " + text
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.font_size = 40
	lbl.outline_size = 10
	lbl.modulate = col
	lbl.pixel_size = 0.006
	lbl.position.y = e.model_height * MODEL_SCALE + 0.75
	e.add_child(lbl)
	_add_ring(e, 0.75, col, "EliteRing")

static func _add_ring(e: DungeonGoblin, radius: float, col: Color, node_name: String) -> void:
	var ring := MeshInstance3D.new()
	ring.name = node_name
	var torus := TorusMesh.new()
	torus.inner_radius = radius * 0.94
	torus.outer_radius = radius
	ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(col.r, col.g, col.b, 0.55 if radius < 2.0 else 0.3)
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.scale = Vector3(1.0, 0.15, 1.0)
	ring.position.y = 0.06
	e.add_child(ring)

static func _add_shield(e: DungeonGoblin) -> void:
	var s := MeshInstance3D.new()
	s.name = "EliteShield"
	var sphere := SphereMesh.new()
	var r := maxf(e.hit_radius * 2.2, 0.9)
	sphere.radius = r
	sphere.height = maxf(e.model_height * MODEL_SCALE * 1.15, r * 2.0)
	s.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var c: Color = MODS["blindado"]["color"]
	mat.albedo_color = Color(c.r, c.g, c.b, 0.18)
	s.material_override = mat
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.position.y = sphere.height * 0.5
	e.add_child(s)

static func _popup(e: DungeonGoblin, text: String, col: Color) -> void:
	if not e.is_inside_tree():
		return
	var lbl := Label3D.new()
	lbl.text = text
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.font_size = 48
	lbl.outline_size = 12
	lbl.modulate = col
	lbl.pixel_size = 0.006
	e.get_parent().add_child(lbl)
	lbl.global_position = e.global_position + Vector3(0, e.model_height * MODEL_SCALE + 1.3, 0)
	var tw := lbl.create_tween()
	tw.tween_property(lbl, "global_position:y", lbl.global_position.y + 0.8, 1.0)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 1.0).set_delay(0.4)
	tw.tween_callback(lbl.queue_free)
