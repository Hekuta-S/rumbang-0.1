class_name StatusEffects
extends Node

## Estados alterados (veneno, sangrado, quemadura) para enemigos y jugador.
## Se crea bajo demanda con StatusEffects.apply_to(host, ...); el host solo necesita
## take_damage(amount). Cada tick llama a take_damage en modo "daño continuo" (los
## enemigos agrupan números/destellos/sonido) y avisa a on_damage_dealt (robo de vida).
##
##   veneno   : acumula hasta 5 cargas; cada carga hace su dps.
##   sangrado : hasta 3 cargas; +50 % de daño mientras el objetivo se mueve.
##   quemadura: no acumula (gana el dps mayor); daño alto y corto.

signal effect_changed(effect_id: String)

const TICK := 0.5
const MOVING_SPEED := 0.6

const EFFECTS := {
	"poison": {"name": "Veneno", "icon": "☠", "color": Color(0.45, 1.0, 0.3), "max_stacks": 5, "stacks": true},
	"bleed": {"name": "Sangrado", "icon": "🩸", "color": Color(0.95, 0.12, 0.12), "max_stacks": 3, "stacks": true},
	"burn": {"name": "Quemadura", "icon": "🔥", "color": Color(1.0, 0.52, 0.12), "max_stacks": 1, "stacks": false},
}

var host = null   # Node (jugador) o EnemyData
## id -> {dps, time_left, stacks, source, weapon}
var active: Dictionary = {}
var _tick_acc: float = 0.0
var _vfx: Dictionary = {}

static var _soft_tex: GradientTexture2D = null
static var _quad: QuadMesh = null
static var _mats: Dictionary = {}

## Aplica (o refresca) un estado sobre cualquier nodo con take_damage().
## source = jugador que lo causó (robo de vida); source_weapon = tipo de arma o -1.
static func apply_to(target, effect_id: String, dps: float, duration: float,
		source: Node = null, source_weapon: int = -1, add_stacks: int = 1) -> void:
	if target == null or not is_instance_valid(target) or not EFFECTS.has(effect_id):
		return
	var comp := get_for(target)
	if comp == null:
		comp = StatusEffects.new()
		comp.name = "StatusEffects"
		comp.host = target
		if target is Node:
			target.add_child(comp)
		else:
			# Enemigo de datos: el componente vive bajo el EnemyManager y guarda su referencia en el enemigo
			if EnemyManager.instance == null:
				return
			comp.free()
			comp = _take_idle()
			if comp == null:
				comp = StatusEffects.new()
				comp.name = "StatusEffects"
				EnemyManager.instance.add_child(comp)
			comp.host = target
			target.status_fx = comp
	comp.apply(effect_id, dps, duration, source, source_weapon, add_stacks)

## Componentes libres de enemigos de datos: se reutilizan en vez de crear/liberar nodos.
static var _idle: Array = []

static func _take_idle() -> StatusEffects:
	while not _idle.is_empty():
		var c = _idle.pop_back()
		if is_instance_valid(c) and c.is_inside_tree():
			return c
	return null

## Devuelve el componente de un enemigo reciclado al pool (sin liberar el nodo).
static func release_to_pool(comp: StatusEffects) -> void:
	comp.clear_all()
	comp.host = null
	comp.set_process(false)
	_idle.append(comp)

static func get_for(target) -> StatusEffects:
	if target == null or not is_instance_valid(target):
		return null
	if target is Node:
		return target.get_node_or_null("StatusEffects") as StatusEffects
	var fx = target.get("status_fx")
	return fx as StatusEffects if fx != null and is_instance_valid(fx) else null

func _ready() -> void:
	if host == null:
		host = get_parent()
	set_process(false)

func apply(effect_id: String, dps: float, duration: float, source: Node = null,
		source_weapon: int = -1, add_stacks: int = 1) -> void:
	var cfg: Dictionary = EFFECTS[effect_id]
	var e: Dictionary = active.get(effect_id, {})
	if e.is_empty():
		e = {"dps": dps, "time_left": duration, "stacks": 0, "source": source, "weapon": source_weapon}
	var max_stacks: int = int(cfg["max_stacks"]) if cfg["stacks"] else 1
	e["stacks"] = mini(int(e["stacks"]) + maxi(add_stacks, 1), max_stacks)
	e["dps"] = maxf(float(e["dps"]), dps)
	e["time_left"] = maxf(float(e["time_left"]), duration)
	if source != null:
		e["source"] = source
		e["weapon"] = source_weapon
	active[effect_id] = e
	_ensure_vfx(effect_id)
	set_process(true)
	effect_changed.emit(effect_id)

func has(effect_id: String) -> bool:
	return active.has(effect_id)

func stacks_of(effect_id: String) -> int:
	return int(active.get(effect_id, {}).get("stacks", 0))

func time_left(effect_id: String) -> float:
	return float(active.get(effect_id, {}).get("time_left", 0.0))

func clear(effect_id: String) -> void:
	if not active.has(effect_id):
		return
	active.erase(effect_id)
	_remove_vfx(effect_id)
	if active.is_empty():
		set_process(false)
		_tick_acc = 0.0
	effect_changed.emit(effect_id)

func clear_all() -> void:
	for id in active.keys():
		clear(id)

## Daño que haría un tick de este estado ahora mismo (útil para tests/UI).
func tick_damage(effect_id: String) -> float:
	var e: Dictionary = active.get(effect_id, {})
	if e.is_empty():
		return 0.0
	var dmg: float = float(e["dps"]) * float(e["stacks"]) * TICK
	if effect_id == "bleed" and _host_is_moving():
		dmg *= 1.5
	return dmg

func _host_is_moving() -> bool:
	if host != null and "velocity" in host:
		var v: Vector3 = host.velocity
		return Vector2(v.x, v.z).length() > MOVING_SPEED
	return false

func _process(delta: float) -> void:
	if host == null or not is_instance_valid(host):
		return
	# Enemigo de datos: las partículas siguen a su dueño (no son hijas de ningún nodo suyo)
	if not (host is Node):
		for id in _vfx.keys():
			var vp = _vfx[id]
			if vp != null and is_instance_valid(vp):
				vp.global_position = host.global_position + Vector3(0, 1.0, 0)
	for id in active.keys():
		active[id]["time_left"] = float(active[id]["time_left"]) - delta
	_tick_acc += delta
	while _tick_acc >= TICK:
		_tick_acc -= TICK
		_do_tick()
		if host == null or not is_instance_valid(host) or host.is_queued_for_deletion():
			return
	for id in active.keys():
		if float(active[id]["time_left"]) <= 0.0:
			clear(id)

func _do_tick() -> void:
	for id in active.keys():
		if not active.has(id):
			continue
		var dmg: float = tick_damage(id)
		if dmg <= 0.0:
			continue
		var e: Dictionary = active[id]
		if "_force_dot" in host:
			host._force_dot = true
		host.take_damage(dmg, Vector3.ZERO)
		if not is_instance_valid(host):
			return
		if "_force_dot" in host:
			host._force_dot = false
		var src = e.get("source")
		var wpn: int = int(e.get("weapon", -1))
		if src != null and is_instance_valid(src) and wpn >= 0 and src.has_method("on_damage_dealt"):
			src.on_damage_dealt(dmg, wpn)
		if host.is_queued_for_deletion():
			return

# ── Visual barato: partículas billboard compartidas por tipo ─────────────────
static func _ensure_shared() -> void:
	if _soft_tex != null:
		return
	_soft_tex = GradientTexture2D.new()
	_soft_tex.width = 32
	_soft_tex.height = 32
	_soft_tex.fill = GradientTexture2D.FILL_RADIAL
	_soft_tex.fill_from = Vector2(0.5, 0.5)
	_soft_tex.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0)])
	g.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	_soft_tex.gradient = g
	_quad = QuadMesh.new()
	_quad.size = Vector2(1, 1)

static func _material_for(effect_id: String) -> StandardMaterial3D:
	_ensure_shared()
	if _mats.has(effect_id):
		return _mats[effect_id]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if effect_id != "bleed" else BaseMaterial3D.BLEND_MODE_MIX
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft_tex
	_mats[effect_id] = m
	return m

func _ensure_vfx(effect_id: String) -> void:
	if _vfx.has(effect_id) and is_instance_valid(_vfx[effect_id]):
		return
	if host == null:
		return
	var col: Color = EFFECTS[effect_id]["color"]
	var p := CPUParticles3D.new()
	p.name = "Vfx_" + effect_id
	p.amount = Quality.count(8)
	p.lifetime = 0.9
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.45
	p.direction = Vector3.UP if effect_id != "bleed" else Vector3.DOWN
	p.spread = 35.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.4
	p.gravity = Vector3(0, 0.4 if effect_id != "bleed" else -4.0, 0)
	p.scale_amount_min = 0.12
	p.scale_amount_max = 0.26
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([Color(col.r, col.g, col.b, 0.0), Color(col.r, col.g, col.b, 0.85), Color(col.r, col.g, col.b, 0.0)])
	ramp.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	p.color_ramp = ramp
	p.mesh = _quad
	p.material_override = _material_for(effect_id)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if host is Node:
		p.position = Vector3(0, 1.0, 0)
		host.add_child(p)
	else:
		add_child(p)
		p.global_position = host.global_position + Vector3(0, 1.0, 0)
	p.emitting = true
	_vfx[effect_id] = p

func _remove_vfx(effect_id: String) -> void:
	var p = _vfx.get(effect_id)
	_vfx.erase(effect_id)
	if p != null and is_instance_valid(p):
		p.emitting = false
		var t: SceneTree = p.get_tree()
		if t:
			t.create_timer(1.0).timeout.connect(p.queue_free)
		else:
			p.queue_free()

func _exit_tree() -> void:
	for id in _vfx.keys():
		var p = _vfx[id]
		if p != null and is_instance_valid(p):
			p.queue_free()
	_vfx.clear()
