class_name HitFeedback
extends Node

## "Game feel" de cada golpe en el modo mazmorra (el combate es la clave):
##   1. Flash  — destello aditivo en el punto de impacto (+ el destello del shader del enemigo).
##   2. Sonido — impacto propio de cada tipo de arma (assets/sfx/impact_*.wav).
##   3. Partículas — color, forma y física distintas por arma.
##   4. Knockback — empuje extra según el arma (más en el golpe que mata).
##   5. Shake + freeze — temblor de cámara y hitstop (Engine.time_scale) breves.
##
## Quien golpea marca el arma antes de llamar a take_damage():
##     HitFeedback.weapon_tag = WeaponData.WeaponType.SPEAR_LANCE
## y EnemyData.take_damage() llama a on_enemy_hit(). En el modo supervivencia
## (hordas) no hace nada, para no saturar ni congelar la partida.

const W := WeaponData.WeaponType
const DEFAULT := {"color": Color(1.0, 0.85, 0.35), "kind": "spark", "count": 10, "speed": 7.0,
	"kb": 1.0, "shake": 0.18, "stop": 0.03, "sfx": "impact_blunt"}
## kind: spark (chispas alargadas), shard (esquirlas), ember (brasas que suben),
##       puff (nubes que se expanden), orb (motas mágicas que flotan)
const PROFILES := {
	W.SPEAR_LANCE:    {"color": Color(0.25, 1.0, 0.45), "kind": "shard", "count": 16, "speed": 9.0,  "kb": 1.7, "shake": 0.35, "stop": 0.06, "sfx": "impact_pierce"},
	W.ENERGY_SWORD:   {"color": Color(0.3, 0.9, 1.0),   "kind": "spark", "count": 14, "speed": 10.0, "kb": 1.3, "shake": 0.28, "stop": 0.05, "sfx": "impact_slash"},
	W.TRI_SHOTGUN:    {"color": Color(1.0, 0.6, 0.2),   "kind": "spark", "count": 8,  "speed": 12.0, "kb": 1.3, "shake": 0.22, "stop": 0.03, "sfx": "impact_blunt"},
	W.RAILGUN:        {"color": Color(0.6, 0.8, 1.0),   "kind": "spark", "count": 18, "speed": 14.0, "kb": 1.6, "shake": 0.4,  "stop": 0.06, "sfx": "impact_zap"},
	W.FLAME_THROWER:  {"color": Color(1.0, 0.45, 0.1),  "kind": "ember", "count": 6,  "speed": 3.0,  "kb": 0.5, "shake": 0.05, "stop": 0.0,  "sfx": "impact_fire"},
	W.SPORE_BAZOOKA:  {"color": Color(0.6, 1.0, 0.25),  "kind": "puff",  "count": 10, "speed": 4.0,  "kb": 1.3, "shake": 0.35, "stop": 0.04, "sfx": "impact_blunt"},
	W.DUSTS:          {"color": Color(0.75, 0.6, 0.4),  "kind": "puff",  "count": 8,  "speed": 3.5,  "kb": 1.0, "shake": 0.15, "stop": 0.02, "sfx": "impact_blunt"},
	W.SERPENTS:       {"color": Color(0.75, 0.35, 1.0), "kind": "orb",   "count": 10, "speed": 4.0,  "kb": 0.8, "shake": 0.12, "stop": 0.02, "sfx": "impact_magic"},
	W.SPINNING_AXE:   {"color": Color(1.0, 0.75, 0.3),  "kind": "shard", "count": 12, "speed": 8.0,  "kb": 1.5, "shake": 0.3,  "stop": 0.05, "sfx": "impact_slash"},
	W.ELEMENTS_CYCLE: {"color": Color(0.8, 0.95, 1.0),  "kind": "orb",   "count": 8,  "speed": 4.0,  "kb": 0.8, "shake": 0.1,  "stop": 0.02, "sfx": "impact_magic"},
	W.ZOMBIE_ARM:     {"color": Color(0.8, 0.12, 0.15), "kind": "shard", "count": 12, "speed": 7.0,  "kb": 1.4, "shake": 0.3,  "stop": 0.05, "sfx": "impact_blunt"},
}

const POOL_PER_KIND := 6
const FLASH_POOL := 8
const MAX_STOP := 0.12            ## hitstop máximo (s, tiempo real)
const STOP_SCALE := 0.04          ## velocidad del mundo durante el freeze
const SFX_GAP_MS := 45            ## evita que 8 impactos a la vez suenen como uno saturado

static var weapon_tag: int = -1
static var _inst: HitFeedback

var _particles: Dictionary = {}   # kind -> Array[CPUParticles3D]
var _particle_idx: Dictionary = {}
var _flashes: Array[MeshInstance3D] = []
var _flash_idx: int = 0
var _trauma: float = 0.0
var _stop_until_us: int = 0
var _last_sfx_ms: int = 0
var _last_us: int = 0

static func enabled() -> bool:
	return GameData.game_mode == "dungeon"

## Llamado por EnemyData.take_damage() en cada golpe directo (no en daño continuo).
static func on_enemy_hit(enemy, amount: float, knockback_dir: Vector3, killed: bool) -> void:
	if not enabled():
		return
	var root := EnemyManager.scene_root()
	if root == null:
		return
	if not is_instance_valid(_inst) or not _inst.is_inside_tree():
		_inst = HitFeedback.new()
		_inst.name = "HitFeedback"
		root.add_child(_inst)
	_inst._hit(enemy, amount, knockback_dir, killed)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_last_us = Time.get_ticks_usec()

func _exit_tree() -> void:
	Engine.time_scale = 1.0

func _hit(enemy, amount: float, kb_dir: Vector3, killed: bool) -> void:
	var p: Dictionary = PROFILES.get(weapon_tag, DEFAULT)
	var col: Color = p["color"]
	var pos: Vector3 = enemy.global_position + Vector3(0, 0.9 * enemy.scale.y, 0)
	var dir := kb_dir
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		var player := get_tree().get_first_node_in_group("player") as Node3D
		dir = (enemy.global_position - player.global_position) if player else Vector3.FORWARD
		dir.y = 0.0
	dir = dir.normalized()
	# Más daño = más impacto (0..1)
	var power := clampf(amount / 40.0, 0.25, 1.0) * (1.6 if killed else 1.0)

	# 1. Flash
	_flash(pos, col, 0.9 + 0.6 * power)
	# 2. Sonido
	var now := Time.get_ticks_msec()
	if now - _last_sfx_ms >= SFX_GAP_MS:
		_last_sfx_ms = now
		AudioManager.play_at(p["sfx"], pos, -2.0, randf_range(0.92, 1.08))
		if killed:
			AudioManager.play_at("kill_burst", pos, -4.0, randf_range(0.9, 1.05))
	# 3. Partículas
	_burst(p, pos, dir, int(float(p["count"]) * (1.8 if killed else 1.0)))
	# 4. Knockback extra (la base ya la aplica take_damage)
	if enemy.has_method("apply_knockback"):
		enemy.apply_knockback(dir * 3.5 * float(p["kb"]) * power)
	# 5. Shake + freeze
	_trauma = minf(_trauma + float(p["shake"]) * (0.6 + 0.4 * power) + (0.25 if killed else 0.0), 1.0)
	var stop := float(p["stop"]) * (0.6 + 0.4 * power) + (0.04 if killed else 0.0)
	if stop > 0.0:
		_freeze(stop)

# ───────────────────────────── Shake + freeze ─────────────────────────────

func _freeze(seconds: float) -> void:
	var now := Time.get_ticks_usec()
	var until := now + int(minf(seconds, MAX_STOP) * 1_000_000.0)
	# No se acumula: varios golpes en el mismo instante alargan hasta el más largo
	if until > _stop_until_us:
		_stop_until_us = until
	if not get_tree().paused:
		Engine.time_scale = STOP_SCALE

func _process(_delta: float) -> void:
	# Tiempo real (no afectado por time_scale)
	var now := Time.get_ticks_usec()
	var real_dt := float(now - _last_us) / 1_000_000.0
	_last_us = now
	if _stop_until_us > 0 and now >= _stop_until_us:
		_stop_until_us = 0
		Engine.time_scale = 1.0
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	if _trauma > 0.0:
		_trauma = maxf(_trauma - real_dt * 2.2, 0.0)
		var s := _trauma * _trauma * 0.25
		var t := float(now) / 1_000_000.0
		cam.h_offset = s * sin(t * 71.0)
		cam.v_offset = s * sin(t * 53.0 + 1.7)
	elif cam.h_offset != 0.0 or cam.v_offset != 0.0:
		cam.h_offset = 0.0
		cam.v_offset = 0.0

# ───────────────────────────── Flash ─────────────────────────────

const FLASH_SHADER_CODE := """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 tint : source_color = vec4(1.0);
uniform float alpha = 1.0;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}
void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float r = length(uv);
	float core = exp(-r * r * 18.0);
	float glow = exp(-r * r * 4.0) * 0.6;
	float rays = pow(max(1.0 - abs(uv.x * uv.y) * 14.0, 0.0), 3.0) * (1.0 - r) * 0.8;
	ALBEDO = (tint.rgb * (glow + rays) + vec3(core)) * alpha * 3.0;
}
"""

func _flash(pos: Vector3, col: Color, size: float) -> void:
	if _flashes.is_empty():
		var sh := Shader.new()
		sh.code = FLASH_SHADER_CODE
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE
		for i in FLASH_POOL:
			var mi := MeshInstance3D.new()
			mi.mesh = quad
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var m := ShaderMaterial.new()
			m.shader = sh
			mi.material_override = m
			mi.visible = false
			mi.top_level = true
			add_child(mi)
			_flashes.append(mi)
	var f := _flashes[_flash_idx]
	_flash_idx = (_flash_idx + 1) % FLASH_POOL
	var mat := f.material_override as ShaderMaterial
	mat.set_shader_parameter("tint", col)
	f.global_position = pos
	f.scale = Vector3.ONE * size * 0.4
	f.visible = true
	var tw := f.create_tween().set_ignore_time_scale(true)
	tw.set_parallel(true)
	tw.tween_property(f, "scale", Vector3.ONE * size * 1.3, 0.1).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(a: float): mat.set_shader_parameter("alpha", a), 1.0, 0.0, 0.12)
	tw.chain().tween_callback(func(): f.visible = false)

# ───────────────────────────── Partículas ─────────────────────────────

func _burst(p: Dictionary, pos: Vector3, dir: Vector3, count: int) -> void:
	var kind: String = p["kind"]
	if not _particles.has(kind):
		_particles[kind] = []
		_particle_idx[kind] = 0
		for i in POOL_PER_KIND:
			var cp := _make_emitter(kind)
			add_child(cp)
			(_particles[kind] as Array).append(cp)
	var arr: Array = _particles[kind]
	var cp: CPUParticles3D = arr[_particle_idx[kind]]
	_particle_idx[kind] = (int(_particle_idx[kind]) + 1) % arr.size()
	cp.global_position = pos
	# Salen hacia donde va el golpe (lado contrario al atacante)
	cp.direction = (dir + Vector3.UP * 0.35).normalized()
	cp.amount = maxi(Quality.count(count), 2)
	cp.initial_velocity_min = float(p["speed"]) * 0.5
	cp.initial_velocity_max = float(p["speed"])
	var col: Color = p["color"]
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1).lerp(col, 0.35))
	grad.set_color(1, Color(col.r, col.g, col.b, 0.0))
	cp.color_ramp = grad
	cp.restart()
	cp.emitting = true

func _make_emitter(kind: String) -> CPUParticles3D:
	var cp := CPUParticles3D.new()
	cp.one_shot = true
	cp.emitting = false
	cp.explosiveness = 0.95
	cp.local_coords = false
	cp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	match kind:
		"spark":
			var q := QuadMesh.new()
			q.size = Vector2(0.04, 0.28)
			cp.mesh = q
			mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
			cp.particle_flag_align_y = true
			cp.lifetime = 0.28
			cp.spread = 55.0
			cp.gravity = Vector3(0, -14, 0)
			cp.damping_min = 4.0
			cp.damping_max = 8.0
		"shard":
			var pr := PrismMesh.new()
			pr.size = Vector3(0.09, 0.16, 0.03)
			cp.mesh = pr
			cp.lifetime = 0.45
			cp.spread = 45.0
			cp.gravity = Vector3(0, -18, 0)
			cp.angular_velocity_min = -720.0
			cp.angular_velocity_max = 720.0
			cp.scale_amount_min = 0.6
			cp.scale_amount_max = 1.3
			cp.damping_min = 2.0
			cp.damping_max = 4.0
		"ember":
			var s := SphereMesh.new()
			s.radius = 0.04
			s.height = 0.08
			s.radial_segments = 4
			s.rings = 2
			cp.mesh = s
			cp.lifetime = 0.6
			cp.spread = 70.0
			cp.gravity = Vector3(0, 3.5, 0)
			cp.scale_amount_min = 0.5
			cp.scale_amount_max = 1.4
		"puff":
			var s2 := SphereMesh.new()
			s2.radius = 0.15
			s2.height = 0.3
			s2.radial_segments = 6
			s2.rings = 3
			cp.mesh = s2
			mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
			cp.lifetime = 0.55
			cp.spread = 80.0
			cp.gravity = Vector3(0, 0.6, 0)
			cp.damping_min = 5.0
			cp.damping_max = 8.0
			var curve := Curve.new()
			curve.add_point(Vector2(0, 0.4))
			curve.add_point(Vector2(1, 1.6))
			cp.scale_amount_curve = curve
		_:  # orb
			var s3 := SphereMesh.new()
			s3.radius = 0.05
			s3.height = 0.1
			s3.radial_segments = 6
			s3.rings = 3
			cp.mesh = s3
			cp.lifetime = 0.7
			cp.spread = 180.0
			cp.gravity = Vector3(0, 1.0, 0)
			cp.damping_min = 3.0
			cp.damping_max = 5.0
	(cp.mesh as PrimitiveMesh).material = mat
	return cp
