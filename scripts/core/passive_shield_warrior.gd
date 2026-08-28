## PassiveShieldWarrior.gd
## Passive for the Shield Warrior character.
##
## Mechanics:
##  - Shield absorbs [damage_mitigation]% of incoming damage; the rest bleeds through to HP.
##  - Shield does NOT auto-regen while it still has charges (only regens from 0).
##  - When shield is fully depleted, a shockwave burst pushes all nearby enemies away.
class_name PassiveShieldWarrior
extends PassiveData

## Fraction of incoming damage absorbed by the shield (0.0 – 1.0).
@export_range(0.0, 1.0, 0.05) var damage_mitigation: float = 0.55

## Radius of the shockwave burst when shield depletes.
@export var burst_radius: float = 6.0

## Knockback force applied to enemies in the burst.
@export var burst_force: float = 18.0

## Visual color of the burst ring.
@export var burst_color: Color = Color(0.4, 0.8, 1.0, 0.9)

# Internal flag: shield was above 0 last frame (prevents burst firing repeatedly).
var _shield_was_active: bool = true


func apply_to_player(player: CharacterBody3D) -> void:
	# Shield Warrior always starts with full shield.
	player.shield = player.max_shield
	_shield_was_active = player.shield > 0


## Override damage to apply mitigation: shield absorbs [mitigation]% of the hit,
## rest bleeds through. Returns the bleed-through hp damage.
func on_take_damage(player: CharacterBody3D, amount: float) -> float:
	if player.shield <= 0:
		# No shield — full damage to HP.
		return amount

	var shield_absorbed := amount * damage_mitigation
	var bleed_through  := amount * (1.0 - damage_mitigation)

	# Drain shield by the absorbed portion.
	player.shield = max(0.0, player.shield - shield_absorbed)

	# Trigger burst if shield just hit zero.
	if player.shield <= 0.0 and _shield_was_active:
		_shield_was_active = false
		on_shield_depleted(player)

	return bleed_through  # This damage is applied to HP by player.gd.


## Shield Warrior's shield only regens when it is at 0 (fully depleted).
func allow_shield_regen(player: CharacterBody3D) -> bool:
	return player.shield <= 0.0


## Fires the shockwave burst and resets the depletion flag so the next
## recharge cycle can trigger a new burst.
func on_shield_depleted(player: CharacterBody3D) -> void:
	_push_nearby_enemies(player)
	_spawn_burst_vfx(player)
	# After the burst, allow regen — flag will re-arm once shield > 0 again.
	# (The player.gd regen loop will fill the shield back up from 0.)
	# Re-arm the depletion flag when shield is full again (handled in player.gd via
	# _on_shield_recharged hook, or we just re-arm when regen starts).
	_shield_was_active = false  # Will be set true again once shield > 0 by player.gd.


## Pushes every enemy inside [burst_radius] away from the player.
func _push_nearby_enemies(player: CharacterBody3D) -> void:
	var enemies := player.get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if not is_instance_valid(enemy): continue
		if not enemy is Node3D: continue
		var dist: float = player.global_position.distance_to(enemy.global_position)
		if dist > burst_radius: continue

		var dir: Vector3 = (enemy.global_position - player.global_position).normalized()
		# Apply knockback if the enemy supports it.
		if enemy.has_method("apply_knockback"):
			enemy.apply_knockback(dir * burst_force)
		elif enemy is CharacterBody3D:
			# Fallback: directly set velocity for one frame.
			enemy.velocity += dir * burst_force


## Spawns a quick expanding ring + flash light at the player's position.
func _spawn_burst_vfx(player: CharacterBody3D) -> void:
	var parent := player.get_parent()
	if not parent or not is_instance_valid(parent) or not parent.is_inside_tree(): return

	# --- Flash light ---
	var light := OmniLight3D.new()
	light.light_color   = burst_color
	light.light_energy  = 8.0
	light.omni_range    = burst_radius * 1.5
	parent.add_child(light)
	light.global_position = player.global_position

	# --- Expanding ring particles ---
	var particles := CPUParticles3D.new()
	particles.amount             = 40
	particles.lifetime           = 0.4
	particles.one_shot           = true
	particles.explosiveness      = 1.0
	particles.direction          = Vector3.ZERO
	particles.spread             = 180.0
	particles.flatness           = 1.0   # spread in a ring on XZ plane
	particles.initial_velocity_min = burst_radius * 1.8
	particles.initial_velocity_max = burst_radius * 2.2
	particles.gravity            = Vector3.ZERO
	particles.scale_amount_min   = 0.3
	particles.scale_amount_max   = 0.7

	var p_mesh := SphereMesh.new()
	p_mesh.radius = 0.08
	p_mesh.height = 0.16
	particles.mesh = p_mesh

	var mat := StandardMaterial3D.new()
	mat.shading_mode             = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color             = burst_color
	mat.emission_enabled         = true
	mat.emission                 = burst_color
	mat.emission_energy_multiplier = 5.0
	mat.transparency             = BaseMaterial3D.TRANSPARENCY_ALPHA
	particles.material_override  = mat

	parent.add_child(particles)
	particles.global_position = player.global_position
	particles.emitting = true

	# Tween: fade light and auto-free everything.
	var tween := player.get_tree().create_tween().set_parallel(true)
	tween.tween_property(light, "light_energy", 0.0, 0.35)
	tween.chain().tween_callback(light.queue_free)
	tween.chain().tween_callback(particles.queue_free)


## Called by player.gd when shield finishes recharging to re-arm the burst trigger.
func on_shield_recharged() -> void:
	_shield_was_active = true
