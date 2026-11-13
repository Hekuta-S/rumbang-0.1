class_name HitFeedback
extends Node

## "Game feel" de cada golpe en el modo mazmorra (el combate es la clave):
##   1. Flash  — destello aditivo en el punto de impacto (+ el destello del shader del enemigo).
##   2. Sonido — impacto propio de cada tipo de arma (assets/sfx/impact_*.wav).
##   3. Partículas — color, forma y física distintas por arma.
##   4. Knockback — empuje extra según el arma (más en el golpe que mata).
##   5. Shake + freeze — temblor de cámara (ruido + empujón con muelle en la dirección del golpe y
##      alabeo) y hitstop (Engine.time_scale) breves.
##   6. Reacción — el modelo de la víctima tiembla durante el freeze y hace squash & stretch.
##   7. Marca de impacto — corte en arco, anillo o punzada según el arma, orientado al golpe.
##   8. Racha — el tono del impacto sube un semitono por golpe encadenado (CHAIN_WINDOW_MS).
##   9. Golpes pesados — capa grave de sonido, FOV punch y aberración cromática de pantalla.
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
	W.SPEAR_LANCE:    {"color": Color(0.25, 1.0, 0.45), "kind": "shard", "count": 16, "speed": 9.0,  "kb": 0.6, "shake": 0.35, "stop": 0.06, "sfx": "impact_pierce"},
	W.ENERGY_SWORD:   {"color": Color(0.3, 0.9, 1.0),   "kind": "spark", "count": 14, "speed": 10.0, "kb": 1.3, "shake": 0.28, "stop": 0.05, "sfx": "impact_slash"},
	W.TRI_SHOTGUN:    {"color": Color(1.0, 0.6, 0.2),   "kind": "spark", "count": 8,  "speed": 12.0, "kb": 1.3, "shake": 0.22, "stop": 0.03, "sfx": "impact_pierce"},
	W.RAILGUN:        {"color": Color(0.6, 0.8, 1.0),   "kind": "spark", "count": 18, "speed": 14.0, "kb": 1.6, "shake": 0.4,  "stop": 0.06, "sfx": "impact_zap"},
	W.FLAME_THROWER:  {"color": Color(1.0, 0.45, 0.1),  "kind": "ember", "count": 6,  "speed": 3.0,  "kb": 0.5, "shake": 0.05, "stop": 0.0,  "sfx": "impact_fire"},
	W.SPORE_BAZOOKA:  {"color": Color(0.6, 1.0, 0.25),  "kind": "puff",  "count": 10, "speed": 4.0,  "kb": 1.3, "shake": 0.35, "stop": 0.04, "sfx": "impact_blunt"},
	W.DUSTS:          {"color": Color(0.75, 0.6, 0.4),  "kind": "puff",  "count": 8,  "speed": 3.5,  "kb": 1.0, "shake": 0.15, "stop": 0.02, "sfx": "impact_blunt"},
	W.SERPENTS:       {"color": Color(0.75, 0.35, 1.0), "kind": "orb",   "count": 10, "speed": 4.0,  "kb": 0.8, "shake": 0.12, "stop": 0.02, "sfx": "impact_magic"},
	W.SPINNING_AXE:   {"color": Color(1.0, 0.75, 0.3),  "kind": "shard", "count": 12, "speed": 8.0,  "kb": 1.5, "shake": 0.3,  "stop": 0.05, "sfx": "impact_slash"},
	W.ELEMENTS_CYCLE: {"color": Color(0.8, 0.95, 1.0),  "kind": "orb",   "count": 8,  "speed": 4.0,  "kb": 0.8, "shake": 0.1,  "stop": 0.02, "sfx": "impact_magic"},
	W.ZOMBIE_ARM:     {"color": Color(0.8, 0.12, 0.15), "kind": "shard", "count": 12, "speed": 7.0,  "kb": 1.4, "shake": 0.3,  "stop": 0.05, "sfx": "impact_blunt"},
	W.DAGGERS:        {"color": Color(0.95, 0.2, 0.25), "kind": "spark", "count": 8,  "speed": 11.0, "kb": 0.5, "shake": 0.12, "stop": 0.02, "sfx": "impact_dagger"},
	W.MACE:           {"color": Color(0.3, 1.0, 0.55),  "kind": "shard", "count": 18, "speed": 7.0,  "kb": 1.8, "shake": 0.45, "stop": 0.07, "sfx": "impact_mace"},
	W.SWORD:          {"color": Color(1.0, 0.9, 0.6),   "kind": "spark", "count": 12, "speed": 9.5,  "kb": 1.2, "shake": 0.25, "stop": 0.045, "sfx": "impact_sword"},
	W.KATANA:         {"color": Color(1.0, 0.2, 0.12),  "kind": "spark", "count": 14, "speed": 10.0, "kb": 1.25, "shake": 0.28, "stop": 0.05, "sfx": "impact_sword"},
	W.GREATSWORD:     {"color": Color(1.0, 0.85, 0.55), "kind": "spark", "count": 14, "speed": 9.0,  "kb": 1.4, "shake": 0.35, "stop": 0.06, "sfx": "impact_great"},
	W.BOW:            {"color": Color(1.0, 0.9, 0.6),   "kind": "shard", "count": 8,  "speed": 8.0,  "kb": 0.7, "shake": 0.12, "stop": 0.03, "sfx": "impact_pierce"},
}

const POOL_PER_KIND := 6
const FLASH_POOL := 8
const MAX_STOP := 0.12            ## hitstop máximo (s, tiempo real)
const STOP_SCALE := 0.04          ## velocidad del mundo durante el freeze
const SFX_GAP_MS := 45            ## evita que 8 impactos a la vez suenen como uno saturado

static var weapon_tag: int = -1
## Último impacto a un enemigo (lo lee el crosshair para su marca de impacto).
static var last_hit_ms: int = -1
static var last_hit_killed := false
static var _inst: HitFeedback

var _particles: Dictionary = {}   # kind -> Array[CPUParticles3D]
var _particle_idx: Dictionary = {}
var _flashes: Array[MeshInstance3D] = []
var _flash_idx: int = 0
var _trauma: float = 0.0
var _stop_until_us: int = 0
var _slow_until_us: int = 0
var _slow_scale: float = 1.0
var _last_sfx_ms: int = 0
var _last_us: int = 0

## Perfil de "feel" según el modo:
##   "full"  — mazmorra: todo (hitstop, reacción, marcas, FOV, pantalla...).
##   "light" — supervivencia (hordas): presupuesto de efectos por frame, sin hitstop salvo al matar un élite,
##             temblor con tope bajo y las bajas de un mismo frame se agrupan en un solo estallido.
##   "off"   — servidor dedicado (no se ve ni se oye, y un hitstop congelaría la partida de todos) y el resto.
## Fuerza un perfil (bancos de pruebas y, en el futuro, los ajustes de la fase 0). "" = según el modo.
static var profile_override := ""

static func profile() -> String:
	if profile_override != "":
		return profile_override
	if Net.is_dedicated():
		return "off"
	if GameData.game_mode == "dungeon":
		return "full"
	if GameData.game_mode == "survival":
		return "light"
	return "off"

static func enabled() -> bool:
	return profile() != "off"

static func is_full() -> bool:
	return profile() == "full"

## Llamado por EnemyData.take_damage() en cada golpe directo (no en daño continuo).
static func on_enemy_hit(enemy, amount: float, knockback_dir: Vector3, killed: bool) -> void:
	if not enabled():
		return
	last_hit_ms = Time.get_ticks_msec()
	last_hit_killed = killed
	var inst := _instance()
	if inst:
		inst._hit(enemy, amount, knockback_dir, killed)

## Temblor de cámara suelto (explosiones, etc.). 0..1, se suma al actual.
static func shake(amount: float) -> void:
	if not enabled():
		return
	var inst := _instance()
	if inst:
		if is_full():
			inst._trauma = minf(inst._trauma + amount, 1.0)
		else:
			inst._trauma = minf(inst._trauma + amount * LIGHT_SHAKE_MULT, maxf(inst._trauma, LIGHT_TRAUMA_MAX))

## Congela el juego un instante (hitstop), p. ej. al hacer un parry. Solo en mazmorra.
static func freeze(seconds: float) -> void:
	if not is_full():   # en las hordas, ni parry ni remates congelan (solo la baja de un élite, en _hit_light)
		return
	var inst := _instance()
	if inst:
		inst._freeze(seconds)

## Cámara lenta durante `seconds` (tiempo real) a velocidad `world_scale` (los remates). Solo en mazmorra;
## un hitstop a la vez manda sobre ella.
static func slowmo(seconds: float, world_scale: float) -> void:
	if not enabled() or (not is_full() and Net.is_online()):
		return
	var inst := _instance()
	if inst:
		inst._slow_until_us = Time.get_ticks_usec() + int(seconds * 1_000_000.0)
		inst._slow_scale = world_scale
		if not inst.get_tree().paused and inst._stop_until_us == 0:
			Engine.time_scale = world_scale

## Llamado por Player.take_damage() cuando el golpe entra (no durante la invulnerabilidad).
static func on_player_hit(player: Node3D, amount: float, from_dir: Vector3) -> void:
	if not enabled():
		return
	var inst := _instance()
	if inst:
		inst._player_hit(player, amount, from_dir)

static func _instance() -> HitFeedback:
	if is_instance_valid(_inst) and _inst.is_inside_tree():
		return _inst
	var root := EnemyManager.scene_root()
	if root == null:
		return null
	if not is_instance_valid(_inst) or not _inst.is_inside_tree():
		_inst = HitFeedback.new()
		_inst.name = "HitFeedback"
		root.add_child(_inst)
	return _inst

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_last_us = Time.get_ticks_usec()

func _exit_tree() -> void:
	Engine.time_scale = 1.0
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	if cam:
		cam.h_offset = 0.0
		cam.v_offset = 0.0
		cam.rotation.z = 0.0

func _hit(enemy, amount: float, kb_dir: Vector3, killed: bool) -> void:
	if not is_full():
		_hit_light(enemy, amount, kb_dir, killed)
		return
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
	var stop := float(p["stop"]) * (0.6 + 0.4 * power) + (0.04 if killed else 0.0)
	var heavy := power >= HEAVY_POWER or stop >= HEAVY_STOP

	# 1. Flash + marca de impacto orientada (corte, punzada o anillo según el arma)
	_flash(pos, col, 0.9 + 0.6 * power)
	_mark(pos, col, dir, _mark_mode(String(p["sfx"])), 0.8 + 0.5 * power)
	# 2. Sonido: impacto con tono que sube en la racha + capa grave en golpes pesados/remates
	var now := Time.get_ticks_msec()
	if now - _last_sfx_ms >= SFX_GAP_MS:
		_chain = _chain + 1 if now - _last_sfx_ms <= CHAIN_WINDOW_MS else 0
		_last_sfx_ms = now
		AudioManager.play_at(p["sfx"], pos, -2.0, chain_pitch(_chain) * randf_range(0.97, 1.03))
		if heavy or killed:
			AudioManager.play_at("impact_blunt", pos, -7.0, randf_range(0.55, 0.62))
		if killed:
			AudioManager.play_at("kill_burst", pos, -4.0, randf_range(0.9, 1.05))
	# 3. Partículas
	_burst(p, pos, dir, int(float(p["count"]) * (1.8 if killed else 1.0)))
	# 4. Knockback extra (la base ya la aplica take_damage)
	if enemy.has_method("apply_knockback"):
		enemy.apply_knockback(dir * 3.5 * float(p["kb"]) * power)
	# 5. Shake (ruido + empujón en la dirección del golpe) + freeze
	_trauma = minf(_trauma + float(p["shake"]) * (0.6 + 0.4 * power) + (0.25 if killed else 0.0), 1.0)
	_kick(dir, float(p["shake"]) * (0.5 + 0.5 * power) + (0.2 if killed else 0.0))
	if stop > 0.0:
		_freeze(stop)
	# 6. La víctima tiembla durante el freeze y se aplasta al recibir
	if enemy.has_method("get_model"):
		_react(enemy.get_model(), dir, maxf(stop, 0.03), power)
	# 7. Golpes pesados: la cámara se cierra un instante y la pantalla se separa en color
	if heavy:
		AudioManager.duck(3.5 if not killed else 5.0, 0.06)   # la música se aparta un instante
		_fov_punch(FOV_PUNCH * clampf(power, 0.6, 1.3))
		_screen_pulse(clampf(0.35 + 0.5 * (power - HEAVY_POWER) + (0.25 if killed else 0.0), 0.3, 1.0))
	# 10. Contador de combo del HUD
	ComboCounter.register_hit(killed)
	if killed:
		last_kill_color = col
		# 8. Overkill: el golpe sobró de largo → esquirlas extra, temblor y un golpe grave
		var max_hp := float(enemy.get("max_hp")) if enemy.get("max_hp") != null else 0.0
		var left := float(enemy.get("hp")) if enemy.get("hp") != null else 0.0
		if is_overkill(left, max_hp):
			_burst(PROFILES.get(W.MACE, DEFAULT).merged({"color": col.lerp(Color(0.9, 0.1, 0.1), 0.4)}, true), pos, dir, 22)
			_trauma = minf(_trauma + 0.2, 1.0)
			AudioManager.play_at("slam_boom", pos, -9.0, randf_range(0.75, 0.85))
		# 9. Multi-kill: varias bajas casi a la vez → cartel
		_register_kill(now)

# ───────────────────────────── Muertes ─────────────────────────────

const OVERKILL_RATIO := 0.5       ## daño sobrante ≥ esto × vida máxima = overkill
const DEATH_HOLD := 0.75          ## s que el cadáver queda entero antes de deshacerse
const DEATH_DISSOLVE := 0.7       ## s que tarda en disolverse
const DissolveShader := preload("res://assets/shaders/enemy_dissolve.gdshader")

## Color del arma del último golpe que mató (borde de la disolución).
static var last_kill_color := Color(1.0, 0.55, 0.2)

## Pura: ¿la vida quedó muy por debajo de 0?
static func is_overkill(hp_left: float, max_hp: float) -> bool:
	return max_hp > 0.0 and -hp_left >= max_hp * OVERKILL_RATIO

## Cadáver: espera un instante y se disuelve con un borde del color del arma que lo mató.
## Devuelve los segundos que tarda (para liberar el nodo después) o -1 si no aplica (fuera de mazmorra:
## el enemigo usa su muerte de siempre).
static func death_fx(model: Node3D, meshes: Array) -> float:
	if not is_full() or not is_instance_valid(model):
		return -1.0
	var mats: Array[ShaderMaterial] = []
	var edge := last_kill_color
	for m in meshes:
		var mi := m as MeshInstance3D
		if not is_instance_valid(mi) or mi.mesh == null:
			continue
		mi.material_overlay = null   # el contorno se dibujaría sobre los huecos
		if mi.material_override != null:
			# Un material para toda la malla (textura del goblin, o la materialización si aún no acabó)
			var sm := _dissolve_from(mi.material_override, edge)
			mi.material_override = sm
			mats.append(sm)
			continue
		for s in mi.mesh.get_surface_count():
			var sm := _dissolve_from(mi.get_active_material(s), edge)
			mi.set_surface_override_material(s, sm)
			mats.append(sm)
	if mats.is_empty():
		return -1.0
	var tw := model.create_tween()
	tw.tween_interval(DEATH_HOLD)
	tw.tween_method(func(d: float): _set_dissolve(mats, d), 0.0, 1.0, DEATH_DISSOLVE).set_ease(Tween.EASE_IN)
	return DEATH_HOLD + DEATH_DISSOLVE

## Material de disolución con el aspecto de `src` (StandardMaterial3D o el de SpawnDissolve).
static func _dissolve_from(src: Material, edge: Color) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = DissolveShader
	sm.set_shader_parameter("edge_color", edge)
	if src is BaseMaterial3D:
		var b := src as BaseMaterial3D
		sm.set_shader_parameter("albedo", b.albedo_color)
		if b.albedo_texture:
			sm.set_shader_parameter("albedo_tex", b.albedo_texture)
			sm.set_shader_parameter("has_tex", true)
		sm.set_shader_parameter("self_lit", b.emission_energy_multiplier if b.emission_enabled else 0.0)
	elif src is ShaderMaterial and (src as ShaderMaterial).shader == SpawnDissolve.SHADER:
		var spawn := src as ShaderMaterial
		sm.set_shader_parameter("albedo", spawn.get_shader_parameter("base_color"))
		if spawn.get_shader_parameter("has_texture"):
			sm.set_shader_parameter("albedo_tex", spawn.get_shader_parameter("albedo_texture"))
			sm.set_shader_parameter("has_tex", true)
	return sm

static func _set_dissolve(mats: Array[ShaderMaterial], d: float) -> void:
	for sm in mats:
		sm.set_shader_parameter("dissolve", d)

## Último enemigo de la caverna: cámara lenta, la cámara se cierra y suena un cierre.
## En partidas en red no se toca el tiempo (lo compartiría el anfitrión con todos).
static func room_clear(pos: Vector3) -> void:
	if not enabled():
		return
	var inst := _instance()
	if inst == null:
		return
	if not Net.is_online():
		slowmo(ROOM_CLEAR_SLOWMO, ROOM_CLEAR_SCALE)
	AudioManager.duck(7.0, 0.45)
	inst._fov_punch(ROOM_CLEAR_FOV)
	inst._screen_pulse(0.5)
	inst._trauma = minf(inst._trauma + 0.3, 1.0)
	AudioManager.play_at("slam_boom", pos, -6.0, 0.7)
	AudioManager.play("level-up", -12.0, 1.25)

const ROOM_CLEAR_SLOWMO := 0.45
const ROOM_CLEAR_SCALE := 0.3
const ROOM_CLEAR_FOV := 7.0

# ───────────────────────────── Multi-kill ─────────────────────────────

const MULTIKILL_WINDOW_MS := 500  ## bajas a menos de esto de la anterior cuentan como la misma racha

var _kill_streak := 0
var _last_kill_ms := -100000
var _banner: Label

## Pura: texto del cartel para `n` bajas casi simultáneas ("" si no merece cartel).
static func multikill_label(n: int) -> String:
	if n >= 6:
		return "¡CARNICERÍA!"
	if n >= 4:
		return "¡MASACRE!"
	if n == 3:
		return "¡TRIPLE!"
	if n == 2:
		return "¡DOBLE!"
	return ""

func _register_kill(now_ms: int) -> void:
	_kill_streak = _kill_streak + 1 if now_ms - _last_kill_ms <= MULTIKILL_WINDOW_MS else 1
	_last_kill_ms = now_ms
	var text := multikill_label(_kill_streak)
	if text != "":
		_show_banner(text, _kill_streak)

func _show_banner(text: String, n: int) -> void:
	if not is_instance_valid(_banner):
		var layer := CanvasLayer.new()
		layer.layer = 51
		add_child(layer)
		_banner = Label.new()
		_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		# Franja a todo lo ancho a un 22 % de la altura: el texto queda centrado sea cual sea su tamaño
		_banner.anchor_left = 0.0
		_banner.anchor_right = 1.0
		_banner.anchor_top = 0.22
		_banner.anchor_bottom = 0.22
		_banner.offset_top = -40.0
		_banner.offset_bottom = 40.0
		_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_banner.add_theme_constant_override("outline_size", 10)
		_banner.add_theme_color_override("font_outline_color", Color(0.08, 0.02, 0.02))
		layer.add_child(_banner)
	var col := Color(1.0, 0.85, 0.3).lerp(Color(1.0, 0.25, 0.15), clampf(float(n - 2) / 4.0, 0.0, 1.0))
	_banner.text = text
	_banner.add_theme_font_size_override("font_size", 38 + mini(n, 8) * 4)
	_banner.add_theme_color_override("font_color", col)
	_banner.pivot_offset = Vector2(get_viewport().get_visible_rect().size.x * 0.5, 40.0)
	_banner.visible = true
	_banner.modulate.a = 1.0
	_banner.rotation = randf_range(-0.06, 0.06)
	_banner.scale = Vector2.ONE * 1.6
	var old = _banner.get_meta(&"tw") if _banner.has_meta(&"tw") else null
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	var tw := _banner.create_tween().set_ignore_time_scale(true)
	_banner.set_meta(&"tw", tw)
	tw.tween_property(_banner, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.7)
	tw.tween_property(_banner, "modulate:a", 0.0, 0.3)
	tw.tween_callback(func(): _banner.visible = false)
	AudioManager.play("kill_burst", -8.0, 0.9 + 0.08 * float(mini(n, 6)))

# ───────────────────────────── Racha de sonido ─────────────────────────────

const CHAIN_WINDOW_MS := 600      ## golpes a menos de esto siguen la racha (el tono sigue subiendo)
const CHAIN_MAX := 7              ## tope de semitonos
const HEAVY_POWER := 0.75         ## a partir de aquí el golpe es "pesado" (FOV + pantalla)
const HEAVY_STOP := 0.06
const FOV_PUNCH := 3.5            ## grados que se cierra la cámara en un golpe pesado

var _chain: int = 0

## Tono del impacto según la racha: +1 semitono por golpe encadenado, con tope. Pura (para las pruebas).
static func chain_pitch(chain: int) -> float:
	return pow(2.0, float(clampi(chain, 0, CHAIN_MAX)) / 12.0)

## Qué marca deja cada sonido de impacto: 0 corte, 1 anillo (contundente), 2 punzada. Pura.
static func _mark_mode(sfx: String) -> int:
	match sfx:
		"impact_slash", "impact_sword", "impact_great", "impact_dagger": return 0
		"impact_pierce", "impact_zap": return 2
		"impact_blunt", "impact_mace": return 1
	return -1   # fuego/magia: ya tienen sus partículas, sin marca

# ───────────────────────────── Reacción de la víctima ─────────────────────────────

const REACT_JITTER := 0.06        ## m de temblor del modelo durante el freeze
const REACT_SQUASH := 0.16        ## cuánto se aplasta (proporción)
const REACT_RECOVER := 0.16       ## s que tarda en recuperar la forma

## Tiembla (tiempo real, también durante el hitstop) y hace squash & stretch. Guarda la pose base
## en metadatos para que varios golpes seguidos no la vayan desplazando.
func _react(model: Node3D, dir: Vector3, hold: float, power: float) -> void:
	if not is_instance_valid(model):
		return
	if not model.has_meta(&"_hf_base"):
		model.set_meta(&"_hf_base", [model.position, model.scale])
	var base: Array = model.get_meta(&"_hf_base")
	var base_pos: Vector3 = base[0]
	var base_scale: Vector3 = base[1]
	var old = model.get_meta(&"_hf_tween") if model.has_meta(&"_hf_tween") else null
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	var parent := model.get_parent_node_3d()
	var local_dir := (parent.global_basis.orthonormalized().inverse() * dir) if parent else dir
	local_dir.y = 0.0
	local_dir = local_dir.normalized()
	var amp := REACT_JITTER * (0.6 + 0.6 * power)
	var sq := REACT_SQUASH * (0.6 + 0.5 * power)
	var tw := model.create_tween().set_ignore_time_scale(true)
	model.set_meta(&"_hf_tween", tw)
	# Golpe: empujado en la dirección del impacto y aplastado (ancho, bajo)
	model.position = base_pos + local_dir * amp
	model.scale = base_scale * Vector3(1.0 + sq * 0.6, 1.0 - sq, 1.0 + sq * 0.6)
	# Temblor mientras dura el freeze
	var steps := maxi(int(hold / 0.025), 1)
	for i in steps:
		var off := Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1)) * amp * (1.0 - float(i) / float(steps))
		tw.tween_property(model, "position", base_pos + off, hold / float(steps))
	# Recupera la forma con un pequeño estirón (overshoot)
	tw.tween_property(model, "position", base_pos, REACT_RECOVER * 0.5)
	tw.parallel().tween_property(model, "scale", base_scale, REACT_RECOVER) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func():
		if is_instance_valid(model):
			model.position = base_pos
			model.scale = base_scale
			model.remove_meta(&"_hf_base")
			model.remove_meta(&"_hf_tween"))

# ───────────────────────────── Cámara: empujón, FOV, pantalla ─────────────────────────────

const KICK_STIFF := 520.0         ## muelle del empujón (más = vuelve antes)
const KICK_DAMP := 30.0           ## amortiguación (subamortiguado: un rebote leve)
const KICK_POWER := 1.6           ## m/s de impulso por unidad de "shake"
const KICK_ROLL := 0.09           ## rad/s de alabeo por unidad de "shake"
const NOISE_ROLL := 0.045         ## alabeo máximo (rad) del temblor con trauma 1

var _kick_pos := Vector2.ZERO     # desplazamiento en pantalla (h, v) del muelle
var _kick_vel := Vector2.ZERO
var _roll := 0.0
var _roll_vel := 0.0
var _noise: FastNoiseLite

## Empujón de cámara en la dirección del golpe (proyectada a la pantalla) + alabeo hacia ese lado.
func _kick(world_dir: Vector3, amount: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or amount <= 0.0:
		return
	var b := cam.global_basis
	var d := Vector2(world_dir.dot(b.x), world_dir.dot(b.y) - 0.35)   # un poco hacia abajo: "pesa"
	if d.length_squared() < 0.0001:
		d = Vector2(0, -1)
	d = d.normalized()
	_kick_vel += d * KICK_POWER * amount
	_roll_vel += -d.x * KICK_ROLL * amount * 10.0

func _fov_punch(deg: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam:
		# CameraController lo devuelve a su FOV base con su lerp (escala con el tiempo: aguanta el freeze)
		cam.fov = maxf(cam.fov - deg, 40.0)

const SCREEN_SHADER_CODE := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float amount = 0.0;
uniform vec3 tint = vec3(1.0);
void fragment() {
	vec2 c = SCREEN_UV - 0.5;
	float edge = dot(c, c) * 4.0;               // más separación en los bordes
	vec2 off = c * amount * 0.018 * (0.3 + edge);
	vec3 col;
	col.r = texture(screen_tex, SCREEN_UV + off).r;
	col.g = texture(screen_tex, SCREEN_UV).g;
	col.b = texture(screen_tex, SCREEN_UV - off).b;
	col += tint * amount * 0.12;                 // destello suave (blanco; azul en la esquiva perfecta)
	COLOR = vec4(col, 1.0);
}
"""
const SCREEN_FADE := 7.0          ## 1/s

var _screen: ColorRect
var _screen_amount := 0.0

## Aberración cromática + destello de pantalla unos frames (golpes pesados; azul en la esquiva perfecta).
func _screen_pulse(amount: float, tint: Color = Color.WHITE) -> void:
	if not is_instance_valid(_screen):
		var layer := CanvasLayer.new()
		layer.layer = 49   # debajo de la viñeta (50) y del HUD que vaya encima
		add_child(layer)
		_screen = ColorRect.new()
		_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
		_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sh := Shader.new()
		sh.code = SCREEN_SHADER_CODE
		var mat := ShaderMaterial.new()
		mat.shader = sh
		_screen.material = mat
		_screen.visible = false
		layer.add_child(_screen)
	_screen_amount = maxf(_screen_amount, amount)
	(_screen.material as ShaderMaterial).set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))

func _update_camera_fx(cam: Camera3D, real_dt: float, now_us: int) -> void:
	# Pantalla
	if is_instance_valid(_screen):
		_screen_amount = maxf(_screen_amount - real_dt * SCREEN_FADE, 0.0)
		_screen.visible = _screen_amount > 0.0
		if _screen.visible:
			(_screen.material as ShaderMaterial).set_shader_parameter("amount", _screen_amount)
	if cam == null:
		return
	# Muelle del empujón (integración semi-implícita, en tiempo real; pasos pequeños para que sea estable)
	var dt := minf(real_dt, 0.05)
	var sub := maxi(int(ceil(dt / 0.008)), 1)
	var h := dt / float(sub)
	for i in sub:
		_kick_vel += (-KICK_STIFF * _kick_pos - KICK_DAMP * _kick_vel) * h
		_kick_pos += _kick_vel * h
		_roll_vel += (-KICK_STIFF * _roll - KICK_DAMP * _roll_vel) * h
		_roll += _roll_vel * h
	# Temblor por trauma: ruido suave (no senos fijos), también en alabeo
	var nx := 0.0
	var ny := 0.0
	var nr := 0.0
	if _trauma > 0.0:
		_trauma = maxf(_trauma - real_dt * 2.2, 0.0)
		if _noise == null:
			_noise = FastNoiseLite.new()
			_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
			_noise.frequency = 1.0
		var s := _trauma * _trauma
		var t := float(now_us) / 1_000_000.0 * 32.0
		nx = s * 0.32 * _noise.get_noise_2d(t, 0.0)
		ny = s * 0.32 * _noise.get_noise_2d(0.0, t + 91.0)
		nr = s * NOISE_ROLL * _noise.get_noise_2d(t + 37.0, t)
	var settled := _trauma <= 0.0 and _kick_pos.length_squared() < 1e-7 and _kick_vel.length_squared() < 1e-6 \
		and absf(_roll) < 1e-5 and absf(_roll_vel) < 1e-4
	if settled:
		_kick_pos = Vector2.ZERO
		_kick_vel = Vector2.ZERO
		_roll = 0.0
		_roll_vel = 0.0
		if cam.h_offset != 0.0 or cam.v_offset != 0.0 or cam.rotation.z != 0.0:
			cam.h_offset = 0.0
			cam.v_offset = 0.0
			cam.rotation.z = 0.0
		return
	cam.h_offset = nx + _kick_pos.x
	cam.v_offset = ny + _kick_pos.y
	cam.rotation.z = nr + _roll

# ───────────────────────────── Daño recibido ─────────────────────────────

const PLAYER_KNOCK := 7.0         ## empuje (m/s) al recibir un golpe
const PLAYER_STOP := 0.07         ## hitstop al recibir un golpe
const VIGNETTE_FADE := 2.2        ## velocidad a la que se apaga la viñeta (1/s)
const VIGNETTE_SHADER_CODE := """
shader_type canvas_item;
uniform float strength = 0.0;
void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float d = length(uv * vec2(1.0, 0.8));
	float v = smoothstep(0.3, 1.15, d) * 0.85 + 0.12;   // bordes fuertes + leve tinte general
	COLOR = vec4(0.8, 0.02, 0.02, v * strength);
}
"""
const PLAYER_FLASH_SHADER_CODE := """
shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled;
uniform float amount = 0.0;
void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 1.5);
	ALBEDO = vec3(1.0, 0.08, 0.05) * amount * (0.9 + rim * 2.5);
}
"""

var _vignette: ColorRect
var _vignette_strength: float = 0.0
var _player_flash_mat: ShaderMaterial

func _player_hit(player: Node3D, amount: float, from_dir: Vector3) -> void:
	var power := clampf(amount / 4.0, 0.4, 1.0)
	ComboCounter.break_combo()
	if not is_full():
		# Hordas: viñeta, destello y un temblor moderado; sin congelar ni empujar (te rodean)
		_ensure_vignette()
		_vignette_strength = minf(_vignette_strength + 0.4 + 0.3 * power, 0.85)
		_trauma = minf(_trauma + 0.25, maxf(_trauma, LIGHT_TRAUMA_MAX))
		AudioManager.play("player_hurt", -5.0)
		_flash_player(player)
		return
	# Viñeta roja + temblor fuerte + freeze corto
	_ensure_vignette()
	_vignette_strength = minf(_vignette_strength + 0.55 + 0.45 * power, 1.0)
	_trauma = minf(_trauma + 0.45 + 0.35 * power, 1.0)
	_kick(from_dir, 0.5 + 0.3 * power)
	_freeze(PLAYER_STOP * (0.6 + 0.4 * power))
	AudioManager.duck(4.0, 0.1)
	AudioManager.play("player_hurt", -2.0)
	# Mikeura destella en rojo
	_flash_player(player)
	# Empuje lejos del golpe
	var dir := from_dir
	dir.y = 0.0
	if dir.length_squared() > 0.0001 and player.get("movement_controller"):
		player.movement_controller.add_dash(dir.normalized() * PLAYER_KNOCK * (0.7 + 0.3 * power))

func _ensure_vignette() -> void:
	if is_instance_valid(_vignette):
		return
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	_vignette = ColorRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = VIGNETTE_SHADER_CODE
	var mat := ShaderMaterial.new()
	mat.shader = sh
	_vignette.material = mat
	layer.add_child(_vignette)

func _update_vignette(real_dt: float) -> void:
	if not is_instance_valid(_vignette):
		return
	_vignette_strength = maxf(_vignette_strength - real_dt * VIGNETTE_FADE, 0.0)
	_vignette.visible = _vignette_strength > 0.0
	(_vignette.material as ShaderMaterial).set_shader_parameter("strength", _vignette_strength)

func _flash_player(player: Node3D) -> void:
	var mesh_root = player.get("mesh")
	if not (mesh_root is Node3D):
		return
	if _player_flash_mat == null:
		var sh := Shader.new()
		sh.code = PLAYER_FLASH_SHADER_CODE
		_player_flash_mat = ShaderMaterial.new()
		_player_flash_mat.shader = sh
	var meshes: Array[GeometryInstance3D] = []
	for n in (mesh_root as Node3D).find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.visible and mi.material_overlay == null:
			mi.material_overlay = _player_flash_mat
			meshes.append(mi)
	var tw := create_tween().set_ignore_time_scale(true)
	tw.tween_method(func(a: float): _player_flash_mat.set_shader_parameter("amount", a), 1.0, 0.0, 0.22)
	tw.tween_callback(func():
		for mi in meshes:
			if is_instance_valid(mi) and mi.material_overlay == _player_flash_mat:
				mi.material_overlay = null)

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
	# Pausar durante el freeze no debe dejar el mundo a cámara lenta
	if get_tree().paused:
		_stop_until_us = 0
		_slow_until_us = 0
		if Engine.time_scale != 1.0:
			Engine.time_scale = 1.0
	elif _stop_until_us > 0 and now >= _stop_until_us:
		_stop_until_us = 0
		Engine.time_scale = _slow_scale if now < _slow_until_us else 1.0
	elif _slow_until_us > 0 and now >= _slow_until_us:
		_slow_until_us = 0
		if _stop_until_us == 0:
			Engine.time_scale = 1.0
	_update_vignette(real_dt)
	_flush_kills()
	_update_camera_fx(get_viewport().get_camera_3d(), real_dt, now)

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

# ───────────────────────────── Marca de impacto ─────────────────────────────

## Quad de cara a la cámara que gira en su plano: corte en arco (0), anillo de golpe seco (1) o
## punzada alargada en la dirección del golpe (2). `progress` 0→1 la anima.
const MARK_SHADER := preload("res://assets/shaders/hit_mark.gdshader")
const MARK_POOL := 8
const MARK_TIME := 0.16

var _marks: Array[MeshInstance3D] = []
var _mark_idx := 0

func _mark(pos: Vector3, col: Color, dir: Vector3, mode: int, size: float) -> void:
	if mode < 0:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	if _marks.is_empty():
		var sh := MARK_SHADER
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE
		for i in MARK_POOL:
			var mi := MeshInstance3D.new()
			mi.mesh = quad
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var m := ShaderMaterial.new()
			m.shader = sh
			mi.material_override = m
			mi.visible = false
			mi.top_level = true
			add_child(mi)
			_marks.append(mi)
	var f := _marks[_mark_idx]
	_mark_idx = (_mark_idx + 1) % MARK_POOL
	var mat := f.material_override as ShaderMaterial
	# Ángulo en pantalla de la dirección del golpe; el corte va perpendicular (cruza al enemigo)
	var b := cam.global_basis
	var screen_ang := atan2(dir.dot(b.y), dir.dot(b.x))
	var ang := screen_ang if mode == 2 else screen_ang + PI * 0.5 + randf_range(-0.45, 0.45)
	mat.set_shader_parameter("tint", col)
	mat.set_shader_parameter("mode", mode)
	mat.set_shader_parameter("angle", ang)
	mat.set_shader_parameter("alpha", 1.0)
	mat.set_shader_parameter("progress", 0.0)
	# Un poco hacia la cámara para que no se esconda dentro del modelo
	f.global_position = pos + (cam.global_position - pos).normalized() * 0.35
	f.scale = Vector3.ONE * size * (1.4 if mode == 0 else 1.0)
	f.visible = true
	var tw := f.create_tween().set_ignore_time_scale(true)
	tw.tween_method(_mark_step.bind(mat), 0.0, 1.0, MARK_TIME)
	tw.tween_callback(func(): f.visible = false)

func _mark_step(t: float, mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("progress", t)
	mat.set_shader_parameter("alpha", 1.0 if t < 0.45 else 1.0 - (t - 0.45) / 0.55)

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

# ───────────────────────────── Movimiento (fase 3) ─────────────────────────────

## Empujón de cámara suelto (aterrizajes, parry...): `world_dir` proyectado a pantalla, `amount` como el "shake".
static func kick(world_dir: Vector3, amount: float) -> void:
	if not enabled():
		return
	var inst := _instance()
	if inst:
		inst._kick(world_dir, amount)

## FOV punch suelto (grados que se cierra la cámara un instante; negativo = se abre).
static func fov_punch(deg: float) -> void:
	if not enabled():
		return
	var inst := _instance()
	if inst:
		inst._fov_punch(deg)

## Squash & stretch de un modelo: se aplasta `amount` (proporción) y recupera con un estirón en `recover` s.
## Guarda la escala base en metadatos (golpes seguidos no la desplazan). Tiempo real.
static func squash(node: Node3D, amount: float, recover: float = 0.22) -> void:
	if not enabled() or not is_instance_valid(node):
		return
	if not node.has_meta(&"_hf_sq_base"):
		node.set_meta(&"_hf_sq_base", node.scale)
	var base: Vector3 = node.get_meta(&"_hf_sq_base")
	var old = node.get_meta(&"_hf_sq_tw") if node.has_meta(&"_hf_sq_tw") else null
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	node.scale = base * Vector3(1.0 + amount * 0.5, 1.0 - amount, 1.0 + amount * 0.5)
	var tw := node.create_tween().set_ignore_time_scale(true)
	node.set_meta(&"_hf_sq_tw", tw)
	tw.tween_property(node, "scale", base, recover).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(_squash_done.bind(node, base))

static func _squash_done(node: Node3D, base: Vector3) -> void:
	if is_instance_valid(node):
		node.scale = base
		node.remove_meta(&"_hf_sq_base")
		node.remove_meta(&"_hf_sq_tw")

const PERFECT_COLOR := Color(0.35, 0.75, 1.0)
const PERFECT_SLOWMO := 0.35      ## s (tiempo real) de cámara lenta
const PERFECT_SCALE := 0.25

## Esquiva perfecta: cámara lenta (no en red), destello azul, fantasmas y un "zas" agudo.
static func perfect_dodge(player: Node3D) -> void:
	if not enabled():
		return
	var inst := _instance()
	if inst == null:
		return
	if not Net.is_online():
		slowmo(PERFECT_SLOWMO, PERFECT_SCALE)
	inst._screen_pulse(0.7, PERFECT_COLOR)
	AudioManager.duck(6.0, 0.3)
	inst._fov_punch(-4.0)   # se abre un poco: "todo va más lento"
	AudioManager.play("orb_cast", -4.0, 1.5)
	AudioManager.play("dodge", -2.0, 0.65)

# ── Fantasmas (afterimages) ──

const GHOST_SHADER := preload("res://assets/shaders/afterimage.gdshader")
const GHOST_MAX_VERTS := 60000    ## tope de vértices horneados por fantasma (móviles)

var _ghost_mats: Dictionary = {}  # Color.to_html() -> ShaderMaterial

## Pendiente de usar: será la habilidad de una armadura (de momento ninguna voltereta deja fantasmas).
## Deja `count` siluetas congeladas de `root` (una cada `interval` s) que se desvanecen en `life` s.
## Hornea la pose actual de las mallas con esqueleto. En calidad baja, solo una.
static func afterimages(root: Node3D, count: int, interval: float, color: Color, life: float = 0.3) -> void:
	if not enabled() or not is_instance_valid(root):
		return
	var inst := _instance()
	if inst == null:
		return
	if Quality.level() == Quality.Level.LOW:
		count = mini(count, 1)
	for i in count:
		if i == 0:
			inst._ghost(root, color, life)
		else:
			inst.get_tree().create_timer(interval * i, true, false, true).timeout.connect(inst._ghost.bind(root, color, life))

func _ghost(root: Node3D, color: Color, life: float) -> void:
	if not is_instance_valid(root) or not root.is_inside_tree():
		return
	var key := color.to_html()
	var mat: ShaderMaterial = _ghost_mats.get(key)
	if mat == null:
		mat = ShaderMaterial.new()
		mat.shader = GHOST_SHADER
		mat.set_shader_parameter("tint", color)
		_ghost_mats[key] = mat
	var holder := Node3D.new()
	holder.top_level = true
	add_child(holder)
	var verts := 0
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var m: Mesh = mi.mesh
		if mi.skin != null:
			m = mi.bake_mesh_from_current_skeleton_pose()
			if m == null:
				continue
		if m is ArrayMesh:
			for si in m.get_surface_count():
				verts += (m as ArrayMesh).surface_get_array_len(si)
		if verts > GHOST_MAX_VERTS:
			break
		var g := MeshInstance3D.new()
		g.mesh = m
		g.material_override = mat
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(g)
		g.global_transform = mi.global_transform
	var tw := holder.create_tween()
	tw.tween_method(_ghost_fade.bind(holder), 1.0, 0.0, life)
	tw.tween_callback(holder.queue_free)

func _ghost_fade(f: float, holder: Node3D) -> void:
	for g in holder.get_children():
		(g as GeometryInstance3D).set_instance_shader_parameter("fade", f)

# ── Líneas de velocidad ──

const SPEED_LINES_SHADER_CODE := """
shader_type canvas_item;
uniform float strength = 0.0;
float h(float x) { return fract(sin(x * 91.17) * 43758.5453); }
void fragment() {
	vec2 c = UV - 0.5;
	c.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float r = length(c);
	float a = atan(c.y, c.x) / 6.28318 + 0.5;
	float ray = floor(a * 90.0);
	float slot = floor(TIME * 9.0 + h(ray) * 7.0);
	float on = step(0.78, h(ray * 1.31 + slot * 0.71));
	float thin = 1.0 - abs(fract(a * 90.0) - 0.5) * 2.0;
	float mask = smoothstep(0.3, 0.62, r);
	COLOR = vec4(1.0, 1.0, 1.0, on * thin * mask * strength * 0.2);
}
"""

var _lines: ColorRect

## Intensidad (0..1) de las líneas de velocidad en los bordes de la pantalla (la fija la cámara al esprintar).
static func speed_lines(strength: float) -> void:
	if not enabled():
		return
	var inst := _instance()
	if inst:
		inst._set_lines(strength)

func _set_lines(strength: float) -> void:
	if Quality.level() == Quality.Level.LOW:
		strength = 0.0
	if strength <= 0.001 and not is_instance_valid(_lines):
		return
	if not is_instance_valid(_lines):
		var layer := CanvasLayer.new()
		layer.layer = 48
		add_child(layer)
		_lines = ColorRect.new()
		_lines.set_anchors_preset(Control.PRESET_FULL_RECT)
		_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sh := Shader.new()
		sh.code = SPEED_LINES_SHADER_CODE
		var m := ShaderMaterial.new()
		m.shader = sh
		_lines.material = m
		layer.add_child(_lines)
	_lines.visible = strength > 0.001
	if _lines.visible:
		(_lines.material as ShaderMaterial).set_shader_parameter("strength", strength)

# ───────────────────────────── Perfil "light" (supervivencia, fase 5) ─────────────────────────────

const LIGHT_FX_PER_FRAME := 2      ## golpes por frame con destello + partículas (el resto solo suma)
const LIGHT_SFX_GAP_MS := 70       ## entre sonidos de impacto
const LIGHT_SHAKE_MULT := 0.3      ## temblor de los golpes respecto a la mazmorra
const LIGHT_TRAUMA_MAX := 0.35     ## tope del temblor por golpes (lo que ya haya por encima no se recorta)
const BATCH_BIG := 5               ## bajas en un mismo frame para el estallido grande
const ELITE_STOP := 0.06           ## hitstop al matar un élite o el minijefe

var _fx_frame := -1
var _fx_count := 0
var _batch_n := 0
var _batch_pts: Array[Vector3] = []   ## hasta BATCH_POINTS bajas de muestra (repartidas) para los estallidos
var _batch_col := Color.WHITE
const BATCH_POINTS := 3

## Pura: ¿este enemigo de las hordas es un élite o el minijefe? (RunEvents.make_elite les sube la XP)
static func is_elite(enemy) -> bool:
	var xp = enemy.get("xp_reward") if enemy != null else null
	return xp != null and float(xp) >= float(XpCurve.XP_ELITE)

## Pura: cuántas bajas hacen falta para el estallido grande, y qué tamaño de estallido toca a `n`.
static func batch_burst_count(n: int) -> int:
	return 0 if n < BATCH_BIG else mini(18 + n * 3, 60)

func _hit_light(enemy, amount: float, kb_dir: Vector3, killed: bool) -> void:
	var p: Dictionary = PROFILES.get(weapon_tag, DEFAULT)
	var col: Color = p["color"]
	var pos: Vector3 = enemy.global_position + Vector3(0, 0.9 * enemy.scale.y, 0)
	var dir := kb_dir
	dir.y = 0.0
	dir = dir.normalized() if dir.length_squared() > 0.0001 else Vector3.FORWARD
	var power := clampf(amount / 40.0, 0.25, 1.0)
	# Presupuesto: solo los primeros golpes de cada frame dibujan destello y partículas
	var frame := Engine.get_process_frames()
	if frame != _fx_frame:
		_fx_frame = frame
		_fx_count = 0
	if _fx_count < LIGHT_FX_PER_FRAME:
		_fx_count += 1
		_flash(pos, col, 0.6 + 0.4 * power)
		_burst(p, pos, dir, maxi(int(float(p["count"]) * 0.5), 3))
	var now := Time.get_ticks_msec()
	if now - _last_sfx_ms >= LIGHT_SFX_GAP_MS:
		_chain = _chain + 1 if now - _last_sfx_ms <= CHAIN_WINDOW_MS else 0
		_last_sfx_ms = now
		AudioManager.play_at(p["sfx"], pos, -6.0, chain_pitch(_chain) * randf_range(0.97, 1.03))
	if enemy.has_method("apply_knockback"):
		enemy.apply_knockback(dir * 2.0 * float(p["kb"]) * power)
	_trauma = minf(_trauma + float(p["shake"]) * LIGHT_SHAKE_MULT * power, maxf(_trauma, LIGHT_TRAUMA_MAX))
	if not killed:
		return
	last_kill_color = col
	if is_elite(enemy):
		# Élite / minijefe: este sí congela y se nota
		_freeze(ELITE_STOP)
		AudioManager.duck(5.0, 0.2)
		_trauma = minf(_trauma + 0.45, 1.0)
		_kick(dir, 0.6)
		_screen_pulse(0.5)
		_burst(PROFILES.get(W.MACE, DEFAULT).merged({"color": col}, true), pos, dir, 40)
		AudioManager.play_at("slam_boom", pos, -4.0, 0.8)
		return
	# Bajas normales: se juntan y se resuelven una vez por frame (_flush_kills)
	_batch_n += 1
	_batch_col = col
	# Muestreo uniforme (reservoir): si mueren en anillo a tu alrededor, el estallido no cae en el centro
	if _batch_pts.size() < BATCH_POINTS:
		_batch_pts.append(pos)
	else:
		var k := randi() % _batch_n
		if k < BATCH_POINTS:
			_batch_pts[k] = pos

## Una vez por frame: si murieron muchos a la vez, un solo estallido grande y un sonido gordo en vez de N.
func _flush_kills() -> void:
	if _batch_n == 0:
		return
	var n := _batch_n
	var pts := _batch_pts.duplicate()
	_batch_n = 0
	_batch_pts.clear()
	var big := batch_burst_count(n)
	if big > 0:
		var prof: Dictionary = PROFILES.get(W.SPORE_BAZOOKA, DEFAULT).merged({"color": _batch_col, "speed": 9.0}, true)
		for pt in pts:
			_burst(prof, pt, Vector3.UP, maxi(big / pts.size(), 8))
			_flash(pt, _batch_col, 1.6)
		_trauma = minf(_trauma + 0.12 + 0.02 * n, maxf(_trauma, 0.5))
		AudioManager.duck(3.0, 0.05)
		AudioManager.play_at("kill_burst", pts[0], -1.0, 0.72)
		AudioManager.play_at("slam_boom", pts[0], -10.0, 1.1)
	else:
		AudioManager.play_at("kill_burst", pts[0], -9.0, randf_range(0.95, 1.1) + 0.04 * n)
