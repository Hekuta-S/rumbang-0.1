extends Control

# Crosshair / Reticle settings
@export var base_gap: float = 7.0
@export var line_length: float = 10.0
@export var line_width: float = 2.0
@export var dot_radius: float = 2.0

@export var reticle_color: Color = Color(0.2, 0.92, 1.0, 0.95) # Cyan neon color
@export var outline_color: Color = Color(0.0, 0.0, 0.0, 0.75) # High contrast dark outline
@export var flash_color: Color = Color(1.0, 0.95, 0.4, 1.0) # Bright gold/white flash on kickback

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

func trigger_kickback(weapon_type: int = -1, strength_mult: float = 1.0) -> void:
	var impulse = 12.0
	
	# Weapon specific kickback pulse intensity
	match weapon_type:
		0: # ENERGY_SWORD (Melee swing)
			impulse = 11.0
		1: # FLAME_AXE (Heavy Melee AOE swing)
			impulse = 18.0
		2: # PLASMA_RIFLE (Rapid Fire shot)
			impulse = 8.5
		3: # TRI_SHOTGUN (Spread Shotgun shot)
			impulse = 20.0
		4: # RAILGUN (Heavy Beam shot)
			impulse = 24.0
		6: # FLAME_THROWER (sustained flame, light recoil)
			impulse = 7.0
		7: # SPORE_BAZOOKA (heavy canister launch)
			impulse = 26.0
		8: # DUAL_DAGGERS (rapid short melee cuts)
			impulse = 9.0
		_:
			impulse = 12.0 * strength_mult

	current_kickback = min(max_kickback, current_kickback + impulse)
	flash_intensity = 1.0
	queue_redraw()

func _draw() -> void:
	var gap = base_gap + current_kickback
	var active_color = reticle_color.lerp(flash_color, flash_intensity)
	
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
