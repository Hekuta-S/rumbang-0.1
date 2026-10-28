extends Control

# Crosshair / Reticle settings
@export var base_gap: float = 7.0
@export var line_length: float = 10.0
@export var line_width: float = 2.0
@export var dot_radius: float = 2.0

@export var reticle_color: Color = Color(0.2, 0.92, 1.0, 0.95) # Cyan neon color
@export var outline_color: Color = Color(0.0, 0.0, 0.0, 0.75) # High contrast dark outline
@export var flash_color: Color = Color(1.0, 0.95, 0.4, 1.0) # Bright gold/white flash on kickback

## Mazmorra: se pone rojo y se cierra sobre un enemigo, y marca los impactos con una X.
@export var enemy_color: Color = Color(1.0, 0.25, 0.2, 1.0)
@export var hit_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var kill_color: Color = Color(1.0, 0.3, 0.2, 1.0)
var _dungeon := false
var _player: Node = null
var _on_enemy := 0.0
var _hit_marker := 0.0
var _hit_kill := false
var _last_hit_seen := -1

var current_kickback: float = 0.0
var flash_intensity: float = 0.0
var max_kickback: float = 32.0

func _ready() -> void:
	# Ensure node is centered regardless of window size
	set_anchors_preset(PRESET_CENTER)
	grow_horizontal = GROW_DIRECTION_BOTH
	grow_vertical = GROW_DIRECTION_BOTH

func _process(delta: float) -> void:
	var needs_redraw = false
	if _dungeon_update(delta):
		needs_redraw = true
	if current_kickback > 0.001:
		current_kickback = lerp(current_kickback, 0.0, delta * 16.0)
		if current_kickback < 0.001:
			current_kickback = 0.0
		needs_redraw = true

	if flash_intensity > 0.001:
		flash_intensity = lerp(flash_intensity, 0.0, delta * 14.0)
		if flash_intensity < 0.001:
			flash_intensity = 0.0
		needs_redraw = true

	if needs_redraw:
		queue_redraw()

func _dungeon_update(delta: float) -> bool:
	if not _dungeon:
		_dungeon = GameData.game_mode == "dungeon"
		if not _dungeon:
			return false
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if _player == null:
			return false
	var target := 0.0
	var aim_ctrl = _player.get("camera_aim_controller")
	if aim_ctrl and aim_ctrl.has_method("get_dungeon_aim"):
		target = 1.0 if aim_ctrl.get_dungeon_aim().get("enemy") != null else 0.0
	var before := _on_enemy
	_on_enemy = move_toward(_on_enemy, target, delta * 8.0)
	if HitFeedback.last_hit_ms != _last_hit_seen:
		if _last_hit_seen != -1 or HitFeedback.last_hit_ms > 0:
			_hit_marker = 1.0
			_hit_kill = HitFeedback.last_hit_killed
		_last_hit_seen = HitFeedback.last_hit_ms
	if _hit_marker > 0.0:
		_hit_marker = maxf(_hit_marker - delta * (2.5 if _hit_kill else 4.0), 0.0)
		return true
	return before != _on_enemy

func trigger_kickback(weapon_type: int = -1, strength_mult: float = 1.0) -> void:
	var impulse = 12.0
	
	# Weapon specific kickback pulse intensity
	match weapon_type:
		0: # ENERGY_SWORD (Melee swing)
			impulse = 11.0
		3: # TRI_SHOTGUN (Spread Shotgun shot)
			impulse = 20.0
		4: # RAILGUN (Heavy Beam shot)
			impulse = 24.0
		6: # FLAME_THROWER (sustained flame, light recoil)
			impulse = 7.0
		7: # SPORE_BAZOOKA (heavy canister launch)
			impulse = 26.0
		_:
			impulse = 12.0 * strength_mult

	current_kickback = min(max_kickback, current_kickback + impulse)
	flash_intensity = 1.0
	queue_redraw()

func _draw() -> void:
	var gap = base_gap + current_kickback - 2.5 * _on_enemy
	var active_color = reticle_color.lerp(enemy_color, _on_enemy).lerp(flash_color, flash_intensity)
	
	# Outline line width (slightly thicker than inner line for high contrast visibility)
	var outline_width = line_width + 2.0
	
	# 1. CENTER DOT (reticle center dot with dark outline)
	draw_circle(Vector2.ZERO, dot_radius + 1.0, outline_color)
	draw_circle(Vector2.ZERO, dot_radius, active_color)

	# 2. 4 RETICLE LINES (Top, Bottom, Left, Right)
	var dirs = [
		Vector2(0, -1), # Top line
		Vector2(0, 1),  # Bottom line
		Vector2(-1, 0), # Left line
		Vector2(1, 0)   # Right line
	]

	for dir in dirs:
		var start_pt = dir * gap
		var end_pt = dir * (gap + line_length)

		# Dark outline line for contrast against all terrain
		draw_line(start_pt, end_pt, outline_color, outline_width, true)
		# Inner bright reticle line
		draw_line(start_pt, end_pt, active_color, line_width, true)

	# 3. Marca de impacto: X diagonal que se abre y se desvanece (más grande y roja si mata)
	if _hit_marker > 0.0:
		var hm_col: Color = kill_color if _hit_kill else hit_color
		hm_col.a = _hit_marker
		var hm_out := outline_color
		hm_out.a *= _hit_marker
		var r0 := 9.0 + (1.0 - _hit_marker) * 4.0
		var r1 := r0 + (9.0 if _hit_kill else 6.0)
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var n: Vector2 = d.normalized()
			draw_line(n * r0, n * r1, hm_out, line_width + 2.0, true)
			draw_line(n * r0, n * r1, hm_col, line_width, true)
