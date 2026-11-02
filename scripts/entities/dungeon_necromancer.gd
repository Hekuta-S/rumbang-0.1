class_name DungeonNecromancer
extends DungeonGoblin

## Jefe necromántico de la mazmorra (el de supervivencia, necromancer_boss.gd, no cambia).
## Comparte la máquina de estados de DungeonGoblin; añade fases, barra de jefe, erupciones
## múltiples e invocación de zombis.
##
##  - scythe (tajo): de cerca; cuña ancha → alejarse o esquivar.
##  - volley (andanada de almas): de lejos; cinco orbes en abanico → meterse entre ellos.
##  - eruption (erupciones): varios círculos en el suelo alrededor del jugador, cada uno con su
##    aviso, que estallan escalonados → salir de los círculos.
##  - summon (invocación): levanta zombis a su alrededor (no se reaniman; mueren con él).
##  - roar (rugido): solo al cambiar de fase; es inmune mientras ruge y la onda empuja.
## Fases al bajar del 66 % y del 33 %: anticipaciones más cortas, menos pausa entre ataques, más
## erupciones y más zombis. Armadura total: solo se aturde al acumular mucho daño seguido.

signal phase_changed(phase: int)

const BOSS_DIR := MODEL_DIR + "bosses/necromancer/"
const NECRO_DIR := MODEL_DIR + "dungeon/necro/"
const NECRO_CLIPS := {
	"walk": BOSS_DIR + "caminar_necro_boss.fbx",
	"erupt": BOSS_DIR + "invocar_erupciones.fbx",
	"summon": BOSS_DIR + "invocar_zombies_necro.fbx",
	"scythe_windup": NECRO_DIR + "necro_scythe_windup.fbx",
	"scythe": NECRO_DIR + "necro_scythe.fbx",
	"cast_windup": NECRO_DIR + "necro_cast_windup.fbx",
	"cast": NECRO_DIR + "necro_cast.fbx",
	"roar": NECRO_DIR + "necro_roar.fbx",
	"recover": NECRO_DIR + "necro_recover.fbx",
	"hurt": NECRO_DIR + "necro_hurt.fbx",
	"death": NECRO_DIR + "necro_death.fbx",
}
## Mismo formato que DungeonGoblin.ATTACKS (y DungeonMage), más:
##  eruption / summon: lo hace _on_impact · "attack_clip": "" sigue con el clip de la anticipación
##  range [-1, -1]: nunca se elige por distancia (el rugido lo fuerza el cambio de fase)
const NECRO_ATTACKS := {
	"scythe": {"range": [0.0, 3.4], "weight": 3, "cooldown": 0.0, "shape": "cone", "reach": 3.8, "half_angle": 70.0,
		"windup_clip": "scythe_windup", "attack_clip": "scythe", "windup": 0.8, "track": 0.55,
		"attack_time": 0.6, "window": Vector2(0.1, 0.3), "lunge": 5.0, "dash": 0.0,
		"damage": 4.0, "recover": 0.9},
	"volley": {"range": [4.0, 16.0], "weight": 3, "cooldown": 2.5, "shape": "cone", "reach": 12.0, "half_angle": 18.0,
		"needs_sight": true, "ranged": true, "orbs": 5, "spread": 9.0, "orb_speed": 8.5,
		"windup_clip": "cast_windup", "attack_clip": "cast", "windup": 1.0, "track": 0.75,
		"attack_time": 0.5, "window": Vector2(0.12, 0.14), "lunge": 0.0, "dash": 0.0,
		"damage": 2.0, "recover": 0.7},
	"eruption": {"range": [3.0, 20.0], "weight": 2, "cooldown": 6.0, "shape": "none", "ranged": true, "eruption": true,
		"windup_clip": "erupt", "attack_clip": "", "windup": 0.9, "track": 0.9,
		"attack_time": 1.2, "window": Vector2(0.05, 0.06), "lunge": 0.0, "dash": 0.0,
		"damage": 3.0, "recover": 0.6},
	"summon": {"range": [0.0, 30.0], "weight": 2, "cooldown": 14.0, "shape": "none", "ranged": true, "summon": true,
		"windup_clip": "summon", "attack_clip": "", "windup": 1.2, "track": 0.0,
		"attack_time": 0.9, "window": Vector2(0.1, 0.11), "lunge": 0.0, "dash": 0.0,
		"damage": 0.0, "recover": 0.5},
	"roar": {"range": [-1.0, -1.0], "weight": 0, "cooldown": 0.0, "shape": "circle", "radius": 5.0, "center": 0.0,
		"windup_clip": "roar", "attack_clip": "", "windup": 0.6, "track": 0.0,
		"attack_time": 0.7, "window": Vector2(0.0, 0.12), "lunge": 0.0, "dash": 0.0,
		"damage": 2.0, "recover": 0.4, "shake": 0.7},
}
const COLOR := Color(0.3, 1.0, 0.6)
const PHASE_HP := [0.66, 0.33]
const PHASE_WINDUP := [1.0, 0.85, 0.7]
const PHASE_REST := [1.1, 0.75, 0.45]
const PHASE_ERUPTIONS := [3, 5, 7]
const PHASE_ZOMBIES := [2, 3, 4]
const MAX_ZOMBIES := 5
const ERUPTION_RADIUS := 1.6
const ERUPTION_SPREAD := 4.0          ## alrededor del jugador (m)
const BOSS_NAME := "NIGROMANTE"

## Nombre de la barra (DungeonRatKing lo cambia); el color de la barra y de sus efectos es telegraph_color
var boss_name := BOSS_NAME
var phase := 0
var _phase_pending := false
var _summons: Array[DungeonZombie] = []
var _bar_layer: CanvasLayer
var _bar: ProgressBar
var _bar_trail: ProgressBar

func _init() -> void:
	attacks = NECRO_ATTACKS
	clips = NECRO_CLIPS
	idle_model = BOSS_DIR + "ataque_idle_necroboss.fbx"
	texture = "res://assets/textures/enemigos/textura_necro_boss.png"
	model_height = 3.0
	enemy_type = EnemyData.EnemyType.NORMAL_GOBLIN
	hp_mult = 15.0                # 40 × 15 = 600
	speed_mult = 0.5              # 2,25 m/s
	hit_radius = 0.9
	hit_height = 3.0
	stagger_damage = 9999.0       # nunca se aturde de un golpe...
	stagger_knock = 9999.0
	armor = 9999.0                # ...ni se inmuta con los normales...
	armor_break = 140.0           # ...pero 140 de daño seguido lo aturden
	stagger_time = 2.0
	windup_poise = 9999.0
	knock_scale = 0.1
	telegraph_color = COLOR
	sfx_pitch = 0.6
	attack_rest = PHASE_REST[0]
	face_player_dist = 20.0

func _ready() -> void:
	super()
	add_to_group("boss")
	_build_boss_bar()

func is_immune() -> bool:
	return _atk_name == "roar" and (state == State.WINDUP or state == State.ATTACK)

func take_damage(amount: float, knockback_dir: Vector3 = Vector3.ZERO) -> void:
	if puppet:
		super(amount, knockback_dir)
		return
	if state == State.DEAD:
		return
	if is_immune():
		_flash_color = telegraph_color
		_flash = 0.6
		AudioManager.play_at("impact_magic", global_position, -6.0, 1.6)
		return
	super(amount, knockback_dir)
	if state == State.DEAD:
		return
	var want := 0
	for t in PHASE_HP:
		if hp <= max_hp * float(t):
			want += 1
	if want > phase:
		phase = want
		_phase_pending = true

func _physics_process(delta: float) -> void:
	if _phase_pending and state != State.WINDUP and state != State.ATTACK and state != State.DEAD:
		_phase_pending = false
		windup_scale = PHASE_WINDUP[phase]
		attack_rest = PHASE_REST[phase]
		_start_attack("roar")
		phase_changed.emit(phase)
	super(delta)
	_update_boss_bar(delta)

func _on_impact() -> void:
	super()
	if _atk.get("eruption", false):
		_erupt()
	elif _atk.get("summon", false):
		_summon()
	elif int(_atk.get("orbs", 0)) > 0:
		var root := get_tree().current_scene
		if root == null:
			return
		var from := global_position + Vector3(0, 1.8, 0) + _facing * 1.0
		var n := int(_atk["orbs"])
		for i in n:
			var d := _facing.rotated(Vector3.UP, deg_to_rad((i - (n - 1) * 0.5) * float(_atk["spread"])))
			MageOrb.spawn(root, from, d, float(_atk["orb_speed"]), float(_atk["damage"]), telegraph_color, get_rid())

## Erupciones: la primera donde está el jugador; el resto alrededor, escalonadas.
func _erupt() -> void:
	if not is_instance_valid(player):
		return
	var parent := get_parent()
	var p := player.global_position
	var n: int = PHASE_ERUPTIONS[phase]
	for i in n:
		var at := p
		if i > 0:
			var ang := randf() * TAU
			at = p + Vector3(cos(ang), 0.0, sin(ang)) * randf_range(1.5, ERUPTION_SPREAD)
			if map:
				var cell := map.world_to_cell(at)
				if not map._cells.has(cell) or map._walls.has(cell):
					continue
		GroundBlast.spawn(parent, Vector3(at.x, global_position.y, at.z), ERUPTION_RADIUS, 0.75 + i * 0.16, float(_atk["damage"]), telegraph_color)

func _summon() -> void:
	_summons = _summons.filter(func(z): return is_instance_valid(z) and not z.is_dead())
	var n := mini(PHASE_ZOMBIES[phase], MAX_ZOMBIES - _summons.size())
	for i in n:
		var pos := global_position
		for t in 8:
			var ang := randf() * TAU
			var cand := global_position + Vector3(cos(ang), 0.0, sin(ang)) * randf_range(2.5, 4.0)
			if map == null:
				pos = cand
				break
			var cell := map.world_to_cell(cand)
			if map._cells.has(cell) and not map._walls.has(cell) and not map._blocked.has(cell):
				pos = cand
				break
		var z := DungeonZombie.new()
		z.can_revive = false
		z.map = map
		get_parent().add_child(z)
		z.global_position = Vector3(pos.x, global_position.y + 0.1, pos.z)
		SpawnDissolve.play(z.get_model(), z, 0.8, telegraph_color, 1.2)
		_summons.append(z)
	AudioManager.play_at("goblin_die", global_position, 0.0, 0.5)

func _die() -> void:
	super()
	# Sus zombis caen con él
	for z in _summons:
		if is_instance_valid(z) and not z.is_dead():
			z.take_damage(9999.0, Vector3.ZERO)
	_summons.clear()
	if _bar_layer:
		var tw := _bar_layer.create_tween()
		tw.tween_interval(1.2)
		tw.tween_callback(_bar_layer.queue_free)

## Parry al jefe: no se aturde, pero cuenta como daño contra su armadura.
func _on_parried() -> void:
	_flash_color = PlayerParryController.COLOR
	_flash = 1.0
	_armor_dmg += PlayerParryController.BOSS_ARMOR
	if _armor_dmg >= armor_break:
		_armor_dmg = 0.0
		_set_state(State.STAGGER)

func summon_count() -> int:
	return _summons.filter(func(z): return is_instance_valid(z) and not z.is_dead()).size()

# ───────────────────────────── Barra de jefe ─────────────────────────────

func _build_boss_bar() -> void:
	_bar_layer = CanvasLayer.new()
	_bar_layer.layer = 20
	add_child(_bar_layer)
	var title := Label.new()
	title.text = boss_name
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", telegraph_color.lightened(0.4))
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 6)
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.offset_left = -150.0
	title.offset_right = 150.0
	title.offset_top = 62.0          # debajo del cronómetro
	title.offset_bottom = 88.0
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bar_layer.add_child(title)
	# Debajo, una barra blanca que va por detrás de la vida y se vacía despacio (daño reciente)
	_bar_trail = _make_bar(Color(1.0, 1.0, 1.0, 0.85), Color(0.04, 0.02, 0.06, 0.85))
	_bar_layer.add_child(_bar_trail)
	_bar = _make_bar(telegraph_color.darkened(0.15), Color(0, 0, 0, 0))
	_bar_layer.add_child(_bar)
	for ratio in PHASE_HP:
		var mark := ColorRect.new()
		mark.color = Color(1, 1, 1, 0.9)
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mark.anchor_left = ratio
		mark.anchor_right = ratio
		mark.anchor_bottom = 1.0
		mark.offset_right = 2.0
		_bar.add_child(mark)

func _make_bar(fill_color: Color, back_color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = 1.0
	bar.step = 0.0
	bar.value = 1.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	bar.offset_left = -300.0
	bar.offset_right = 300.0
	bar.offset_top = 90.0
	bar.offset_bottom = 110.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.set_corner_radius_all(3)
	var back := StyleBoxFlat.new()
	back.bg_color = back_color
	back.set_corner_radius_all(3)
	if back_color.a > 0.0:
		back.set_border_width_all(2)
		back.border_color = telegraph_color.lightened(0.3)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", back)
	return bar

func _update_boss_bar(delta: float) -> void:
	if _bar == null:
		return
	var v := clampf(hp / max_hp, 0.0, 1.0)
	_bar.value = v
	_bar_trail.value = move_toward(_bar_trail.value, v, delta * 0.35) if _bar_trail.value > v else v
	# Inmune al rugir: la barra parpadea
	_bar.modulate = Color(1, 1, 1, 0.55 + 0.45 * sin(_clock * 20.0)) if is_immune() else Color.WHITE
