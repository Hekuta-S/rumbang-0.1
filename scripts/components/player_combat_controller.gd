extends Node
class_name PlayerCombatController

var player: CharacterBody3D

var auto_combat_target: Node3D = null
var attack_cooldowns: Dictionary = {}
var is_auto_combat_enabled: bool = true

var attack_cooldown: float = 0.0

var weapon_slots: Array = []
var current_slot: int = 0
var is_spear_thrown: bool = false
var _melee_swing_side: float = 1.0

var _punch_combo_step: int = 0
var _punch_dash_timer: float = 0.0
const PUNCH_DASH_DURATION: float = 0.18
var _punch_dash_dir: Vector3 = Vector3.ZERO

var current_dust_mode: int = 0
var dust_speed_boost_timer: float = 0.0
const SPEAR_THROW_COST: float = 2.0
const SPEAR_THROW_CD: float = 0.9
const MAX_WEAPON_SLOTS: int = 4

var weapon_ammo: Dictionary = {}
var reloading_weapon: int = -1
var reload_timer: float = 0.0
var total_reload_time: float = 1.0

var spore_damage_mult: float = 1.0
var spore_cloud_duration: float = 3.5

var saimon_element_index: int = 0

var weapon_mag_size: Dictionary = {
	WeaponData.WeaponType.SPORE_BAZOOKA: 1,
}

var weapon_reload_time: Dictionary = {
	WeaponData.WeaponType.SPORE_BAZOOKA: 2.4,
}

var bullet_scene = preload("res://scenes/objects/bullet.tscn")
var spear_projectile_scene = preload("res://scenes/objects/spear_projectile.tscn")
var spore_projectile_scene = preload("res://scenes/objects/spore_projectile.tscn")
var dust_projectile_scene = preload("res://scenes/objects/dust_projectile.tscn")
var serpent_projectile_scene = preload("res://scenes/objects/serpent_projectile.tscn")

func _ready() -> void:
	player = get_parent() as CharacterBody3D

func _process(delta: float) -> void:
	if attack_cooldown > 0: attack_cooldown -= delta
	for w in attack_cooldowns.keys():
		if attack_cooldowns[w] > 0:
			attack_cooldowns[w] -= delta

	if dust_speed_boost_timer > 0:
		dust_speed_boost_timer -= delta

	if reloading_weapon >= 0:
		reload_timer += delta
		if reload_timer >= total_reload_time:
			weapon_ammo[reloading_weapon] = weapon_mag_size[reloading_weapon]
			reloading_weapon = -1
			reload_timer = 0.0
		player._emit_reload_state()

func auto_attack(target: Node3D) -> void:

	
	var cd_mult = 0.5 if player.is_berserk else 1.0
	
	for i in range(weapon_slots.size()):
		var w = weapon_slots[i]
		if w == null: continue
		
		var w_cd = attack_cooldowns.get(w, 0.0)
		if w_cd > 0: continue
		
		# The spear is in the air; melee is unavailable until it returns.
		if w == WeaponData.WeaponType.SPEAR_LANCE and is_spear_thrown: continue
		# Cannot fire a weapon while it is being reloaded.
		if reloading_weapon == w: continue
		
		var mag: int = weapon_mag_size.get(w, 0)
		if mag > 0 and get_weapon_ammo(w) <= 0:
			if current_slot == i:
				start_reload()
			continue
			
		var cost = player.weapon_energy_costs[w]
		if player.energy < cost: continue
		
		if cost > 0:
			player.energy -= cost
			player.emit_signal("stats_changed", player.hp, player.max_hp, player.shield, player.max_shield, player.energy, player.max_energy)
			
		player.emit_signal("weapon_attacked", w)
		if player.has_method("show_weapon_temporarily"):
			player.show_weapon_temporarily(0.4)

		# Auto-fire logic per weapon type main variable for the attack function logic to read,
		# and also update our dictionary
		var current_old = current_slot
		current_slot = i
		cd_mult = 0.5 if player.is_berserk else 1.0
		if player.has_method("get_weapon_modifiers"):
			cd_mult *= player.get_weapon_modifiers(w).cooldown
		
		match w:
			WeaponData.WeaponType.ENERGY_SWORD: attack_energy_sword(cd_mult)
			WeaponData.WeaponType.FLAME_AXE: attack_flame_axe(cd_mult)
			WeaponData.WeaponType.PLASMA_RIFLE: attack_plasma_rifle(cd_mult)
			WeaponData.WeaponType.TRI_SHOTGUN: attack_tri_shotgun(cd_mult)
			WeaponData.WeaponType.RAILGUN: attack_railgun(cd_mult)
			WeaponData.WeaponType.SPEAR_LANCE: attack_spear_lance(cd_mult)
			WeaponData.WeaponType.FLAME_THROWER: attack_flame_thrower(cd_mult)
			WeaponData.WeaponType.SPORE_BAZOOKA: attack_spore_bazooka(cd_mult)
			WeaponData.WeaponType.DUAL_DAGGERS: attack_dual_daggers(cd_mult)
			WeaponData.WeaponType.AIR_FISTS: attack_air_fists(cd_mult)
			WeaponData.WeaponType.DUSTS: attack_dusts(cd_mult)
			WeaponData.WeaponType.SERPENTS: attack_serpents(cd_mult)
			WeaponData.WeaponType.SPINNING_AXE: attack_spinning_axe(cd_mult)
			WeaponData.WeaponType.ELEMENTS_CYCLE: attack_elements_cycle(cd_mult)
			WeaponData.WeaponType.ZOMBIE_ARM: attack_zombie_arm(cd_mult)
			
		attack_cooldowns[w] = attack_cooldown
		current_slot = current_old
		
		if mag > 0:
			weapon_ammo[w] = max(0, get_weapon_ammo(w) - 1)
			if weapon_ammo[w] <= 0:
				if current_slot == i:
					start_reload()
			else:
				if current_slot == i:
					player._emit_reload_state()

## Primary attack dispatcher. Fires the correct attack for the equipped weapon,
## gates on cooldown / roll / spear-in-flight / reload / player.energy, then consumes
## ammo for magazine weapons.

func attack() -> void:
	if attack_cooldown > 0: return
	# The spear is in the air; melee is unavailable until it returns.
	if player.current_weapon() == WeaponData.WeaponType.SPEAR_LANCE and is_spear_thrown: return
	# Cannot fire a weapon while it is being reloaded.
	if reloading_weapon == player.current_weapon(): return

	var cd_mult = 0.5 if player.is_berserk else 1.0
	if player.has_method("get_weapon_modifiers"):
		cd_mult *= player.get_weapon_modifiers(player.current_weapon()).cooldown

	# Magazine weapons need a round chambered; otherwise start reloading.
	var mag: int = weapon_mag_size.get(player.current_weapon(), 0)
	if mag > 0 and get_weapon_ammo(player.current_weapon()) <= 0:
		start_reload()
		return

	var cost = player.weapon_energy_costs[player.current_weapon()]
	if player.energy < cost: return

	if cost > 0:
		player.energy -= cost
		player.emit_signal("stats_changed", player.hp, player.max_hp, player.shield, player.max_shield, player.energy, player.max_energy)

	player.emit_signal("weapon_attacked", player.current_weapon())
	if player.has_method("show_weapon_temporarily"):
		player.show_weapon_temporarily(0.4)

	match player.current_weapon():
		WeaponData.WeaponType.ENERGY_SWORD:
			attack_energy_sword(cd_mult)
		WeaponData.WeaponType.FLAME_AXE:
			attack_flame_axe(cd_mult)
		WeaponData.WeaponType.PLASMA_RIFLE:
			attack_plasma_rifle(cd_mult)
		WeaponData.WeaponType.TRI_SHOTGUN:
			attack_tri_shotgun(cd_mult)
		WeaponData.WeaponType.RAILGUN:
			attack_railgun(cd_mult)
		WeaponData.WeaponType.SPEAR_LANCE:
			attack_spear_lance(cd_mult)
		WeaponData.WeaponType.FLAME_THROWER:
			attack_flame_thrower(cd_mult)
		WeaponData.WeaponType.SPORE_BAZOOKA:
			attack_spore_bazooka(cd_mult)
		WeaponData.WeaponType.DUAL_DAGGERS:
			attack_dual_daggers(cd_mult)
		WeaponData.WeaponType.AIR_FISTS:
			attack_air_fists(cd_mult)
		WeaponData.WeaponType.DUSTS:
			attack_dusts(cd_mult)
		WeaponData.WeaponType.SERPENTS:
			attack_serpents(cd_mult)
		WeaponData.WeaponType.SPINNING_AXE:
			attack_spinning_axe(cd_mult)
		WeaponData.WeaponType.ELEMENTS_CYCLE:
			attack_elements_cycle(cd_mult)
		WeaponData.WeaponType.ZOMBIE_ARM:
			attack_zombie_arm(cd_mult)

	# Consume ammo after firing; empty magazine starts the slow reload.
	if mag > 0:
		weapon_ammo[player.current_weapon()] = max(0, get_weapon_ammo(player.current_weapon()) - 1)
		if weapon_ammo[player.current_weapon()] <= 0:
			start_reload()
		else:
			player._emit_reload_state()


func attack_zombie_arm(cd_mult: float) -> void:
	attack_cooldown = player.get_weapon_data(WeaponData.WeaponType.ZOMBIE_ARM).base_cooldown * cd_mult
	var aim_point = player.get_camera_aim_point()
	player.orient_player_to_aim(aim_point)

	var proj_scene = load("res://scripts/objects/zombie_arm_projectile.tscn")
	var proj = proj_scene.instantiate()
	player.get_parent().add_child(proj)
	
	var dir = (aim_point - player.muzzle.global_position).normalized()
	proj.global_position = player.muzzle.global_position
	var dmg = WeaponData.weapon_damage(WeaponData.WeaponType.ZOMBIE_ARM, player.is_berserk)
	proj.setup(dir, dmg, player)
	
	AudioManager.play("ataque-espalanza", -12.0, 0.8)
	
	player.apply_camera_recoil(0.015, randf_range(-0.005, 0.005), 0.05)

func attack_flame_thrower(cd_mult: float) -> void:
	attack_cooldown = player.get_weapon_data(WeaponData.WeaponType.FLAME_THROWER).base_cooldown * cd_mult
	player.orient_player_to_aim(player.get_camera_aim_point())
	var forward_dir = player.get_attack_forward_dir()
	var player_pos = player.global_position

	var dmg = player._weapon_damage(WeaponData.WeaponType.FLAME_THROWER)
	
	# Hitbox is now handled by the instantiated weapon scene
	var flame_scene = preload("res://scenes/objects/flame_thrower.tscn").instantiate()
	player.get_parent().add_child(flame_scene)
	flame_scene.global_position = player_pos
	flame_scene.look_at(flame_scene.global_position + forward_dir, Vector3.UP)
	flame_scene.setup(dmg, 0.2)

	create_flame_burst_visual(player_pos, forward_dir)

## Spore Bazooka: lobs a canister that bursts into a corrosive cloud.
## Fires from the muzzle toward the camera aim point.

func attack_spore_bazooka(cd_mult: float) -> void:
	attack_cooldown = player.get_weapon_data(WeaponData.WeaponType.SPORE_BAZOOKA).base_cooldown * cd_mult
	var aim_point = player.get_camera_aim_point()
	var start_pos = player.muzzle.global_position
	var aim_dir = (aim_point - start_pos).normalized()
	if (aim_point - start_pos).length_squared() < 0.04:
		aim_dir = -player.spring_arm.global_transform.basis.z

	player.orient_player_to_aim(aim_point)

	var b_stream = AudioManager.get_stream("tiro_bazuca")
	var b_start_time = b_stream.get_length() * 0.10 if b_stream else 0.0
	AudioManager.play("tiro_bazuca", -10.0, 1.0, b_start_time)

	var dmg = player._weapon_damage(WeaponData.WeaponType.SPORE_BAZOOKA) * spore_damage_mult
	var cloud_dps = 4.0 * spore_damage_mult
	var spore_color = Color(0.8, 0.95, 0.3)

	var proj = spore_projectile_scene.instantiate()
	player.get_parent().add_child(proj)
	proj.global_position = start_pos
	proj.setup(aim_dir, dmg, player.get_weapon_data(WeaponData.WeaponType.SPORE_BAZOOKA).projectile_speed,
		cloud_dps, spore_cloud_duration, player.get_weapon_data(WeaponData.WeaponType.SPORE_BAZOOKA).range)

	player.apply_camera_recoil(0.05, randf_range(-0.008, 0.008), 0.14)
	player.create_muzzle_flash(spore_color, 1.6)

## Twin Daggers: rapid short-range cuts. Alternates red and blue slash visuals.

func attack_dual_daggers(cd_mult: float) -> void:
	attack_cooldown = player.get_weapon_data(WeaponData.WeaponType.DUAL_DAGGERS).base_cooldown * cd_mult
	player.orient_player_to_aim(player.get_camera_aim_point())
	var forward_dir = player.get_attack_forward_dir()
	var player_pos = player.global_position
	var dmg = player._weapon_damage(WeaponData.WeaponType.DUAL_DAGGERS)

	var slash_side = _melee_swing_side
	_melee_swing_side = -_melee_swing_side

	var slash_color = Color(1.0, 0.25, 0.25) if slash_side > 0 else Color(0.25, 0.55, 1.0)

	# Hitbox is now handled by the instantiated weapon scene
	var daggers_scene = preload("res://scenes/objects/dual_daggers.tscn").instantiate()
	player.get_parent().add_child(daggers_scene)
	daggers_scene.global_position = player_pos + forward_dir * 1.25
	daggers_scene.look_at(daggers_scene.global_position + forward_dir, Vector3.UP)
	daggers_scene.setup(dmg, 0.15, 12.0, forward_dir)

	animate_weapon_swing(WeaponData.WeaponType.DUAL_DAGGERS, slash_side)
	create_dual_slash_visual(player_pos, forward_dir, slash_side, slash_color)

## Twin Daggers (Right Click): strikes with BOTH daggers in one wide cross,
## dealing much more damage than the fast single cuts.

func attack_dual_daggers_heavy(cd_mult: float) -> void:
	attack_cooldown = player.get_weapon_data(WeaponData.WeaponType.DUAL_DAGGERS).heavy_cooldown * cd_mult
	player.orient_player_to_aim(player.get_camera_aim_point())
	var forward_dir = player.get_attack_forward_dir()
	var player_pos = player.global_position
	var dmg = player._weapon_heavy_damage(WeaponData.WeaponType.DUAL_DAGGERS)

	player.emit_signal("weapon_attacked", WeaponData.WeaponType.DUAL_DAGGERS)

	# Hitbox is now handled by the instantiated weapon scene
	var daggers_scene = preload("res://scenes/objects/dual_daggers.tscn").instantiate()
	player.get_parent().add_child(daggers_scene)
	# Heavy attack gets a larger hitbox scale
	daggers_scene.scale = Vector3(1.5, 1.0, 1.5)
	daggers_scene.global_position = player_pos + forward_dir * 1.5
	daggers_scene.look_at(daggers_scene.global_position + forward_dir, Vector3.UP)
	daggers_scene.setup(dmg, 0.25, 18.0, forward_dir)

	# Cross slash: both daggers sweep toward the center.
	create_dual_slash_visual(player_pos, forward_dir, 1.0, Color(1.0, 0.25, 0.25))
	create_dual_slash_visual(player_pos, forward_dir, -1.0, Color(0.25, 0.55, 1.0))
	player.apply_camera_recoil(0.02, randf_range(-0.005, 0.005), 0.05)

## Short, colored slash arc for the twin daggers (red for main hand,
## blue for off hand). Sweeps across the front, alternating with `side`.

func create_dual_slash_visual(pos: Vector3, facing_dir: Vector3, side: float, slash_color: Color) -> void:
	var arc = MeshInstance3D.new()
	var mesh_inst = PrismMesh.new()
	mesh_inst.size = Vector3(2.2, 0.08, 1.3)
	arc.mesh = mesh_inst

	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(slash_color.r, slash_color.g, slash_color.b, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = slash_color
	mat.emission_energy_multiplier = 2.0
	arc.material_override = mat

	player.get_parent().add_child(arc)
	arc.global_position = pos + facing_dir * 1.1 + Vector3(0, 1.0, 0)
	if facing_dir.cross(Vector3.UP).length() > 0.001:
		arc.look_at(arc.global_position + facing_dir, Vector3.UP)

	arc.rotation.y = deg_to_rad(-35.0 * side)

	# --- Cutting Slash Sparks ---
	var sparks := CPUParticles3D.new()
	sparks.amount = 14
	sparks.lifetime = 0.2
	sparks.explosiveness = 0.9
	sparks.one_shot = true
	sparks.direction = facing_dir + Vector3(side * 0.5, 0.2, 0).normalized()
	sparks.spread = 30.0
	sparks.initial_velocity_min = 6.0
	sparks.initial_velocity_max = 12.0
	sparks.scale_amount_min = 0.4
	sparks.scale_amount_max = 0.8

	var p_mesh := BoxMesh.new()
	p_mesh.size = Vector3(0.04, 0.04, 0.2)
	sparks.mesh = p_mesh

	var sp_mat := StandardMaterial3D.new()
	sp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sp_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sp_mat.albedo_color = Color(slash_color.r, slash_color.g, slash_color.b, 0.5)
	sp_mat.emission_enabled = true
	sp_mat.emission = slash_color
	sp_mat.emission_energy_multiplier = 2.5
	sparks.material_override = sp_mat

	player.get_parent().add_child(sparks)
	sparks.global_position = arc.global_position
	sparks.emitting = true

	var tween = player.create_tween().set_parallel(true)
	tween.tween_property(arc, "rotation:y", deg_to_rad(35.0 * side), 0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(arc, "scale", Vector3(1.3, 1.3, 1.3), 0.12)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.18)
	tween.chain().tween_callback(arc.queue_free)
	
	var cleanup = player.create_tween()
	cleanup.tween_interval(0.3)
	cleanup.tween_callback(sparks.queue_free)

## Mikeura's spear-lance: broad horizontal slash in front of the player.

func attack_spear_lance(cd_mult: float) -> void:
	# Make it slower (e.g. 1.4x base cooldown)
	attack_cooldown = player.get_weapon_data(WeaponData.WeaponType.SPEAR_LANCE).base_cooldown * cd_mult * 1.4
	player.orient_player_to_aim(player.get_camera_aim_point())
	var forward_dir = player.get_attack_forward_dir()
	var player_pos = player.global_position
	var dmg = player._weapon_damage(WeaponData.WeaponType.SPEAR_LANCE)

	var slash_side = _melee_swing_side
	_melee_swing_side = -_melee_swing_side
	
	# Slower, deeper sound for a larger sweep
	AudioManager.play("ataque-espalanza", -10.0, 0.85)

	# Hitbox is now handled by the instantiated weapon scene
	var spear_scene = preload("res://scenes/objects/spear_lance_hitbox.tscn").instantiate()
	player.get_parent().add_child(spear_scene)
	spear_scene.global_position = player_pos + forward_dir * 1.8
	spear_scene.look_at(spear_scene.global_position + forward_dir, Vector3.UP)
	
	# Half sweep size (scale) and slightly longer active duration (0.35s)
	spear_scene.scale = Vector3(1.25, 1.0, 1.25) 
	spear_scene.setup(dmg, 0.35, 16.0, forward_dir)

	animate_weapon_swing(WeaponData.WeaponType.SPEAR_LANCE, slash_side)
	create_spear_slash_visual(player_pos, forward_dir, slash_side)
	
	# Delay then automatically throw the spear towards the closest enemy
	var combo_tween = player.create_tween()
	combo_tween.tween_interval(0.35)
	combo_tween.tween_callback(func():
		if not is_instance_valid(player) or player.current_weapon() != WeaponData.WeaponType.SPEAR_LANCE:
			return
			
		var enemies = player.get_tree().get_nodes_in_group("enemies")
		var closest: Node3D = null
		var min_dist = 45.0
		
		for e in enemies:
			if not is_instance_valid(e): continue
			var d = e.global_position.distance_to(player.global_position)
			if d < min_dist:
				min_dist = d
				closest = e
				
		var start_pos = player.muzzle.global_position
		var aim_dir = player.get_attack_forward_dir()
		
		if closest:
			var target_pos = closest.global_position + Vector3(0, 1.0, 0)
			aim_dir = (target_pos - start_pos).normalized()
			player.orient_player_to_aim(target_pos)
			
		# Do not hide the spear from hand; these are spectral summons!
		
		var proj = spear_projectile_scene.instantiate()
		player.get_parent().add_child(proj)
		proj.global_position = start_pos
		proj.setup(aim_dir, 35.0, 48.0, player.get_rid())
		AudioManager.play("ataque-espalanza", -6.0, 1.3)
	)

## Throws the spear-lance (right mouse). Costs a little player.energy; the spear is
## gone from the player's hand until it returns.

func throw_spear() -> void:
	if player.current_weapon() != WeaponData.WeaponType.SPEAR_LANCE: return
	if attack_cooldown > 0: return

	var cost = SPEAR_THROW_COST
	if player.energy < cost: return

	player.energy -= cost
	player.emit_signal("stats_changed", player.hp, player.max_hp, player.shield, player.max_shield, player.energy, player.max_energy)
	attack_cooldown = SPEAR_THROW_CD

	var aim_point = player.get_camera_aim_point()
	var start_pos = player.muzzle.global_position
	var aim_dir = (aim_point - start_pos).normalized()
	if (aim_point - start_pos).length_squared() < 0.04:
		aim_dir = -player.spring_arm.global_transform.basis.z

	player.orient_player_to_aim(aim_point)
	player.emit_signal("weapon_attacked", WeaponData.WeaponType.SPEAR_LANCE)

	# Spectral spears don't hide the player's weapon.

	var proj = spear_projectile_scene.instantiate()
	player.get_parent().add_child(proj)
	proj.global_position = start_pos
	proj.setup(aim_dir, 30.0, 48.0, player.get_rid())

	player.apply_camera_recoil(0.01, randf_range(-0.004, 0.004), 0.06)

## Called by the thrown spear when it lands / returns to the player.

func on_spear_returned() -> void:
	is_spear_thrown = false
	player.update_weapon_visuals()


func attack_energy_sword(cd_mult: float) -> void:
	attack_cooldown = player.get_weapon_data(WeaponData.WeaponType.ENERGY_SWORD).base_cooldown * cd_mult
	player.orient_player_to_aim(player.get_camera_aim_point())
	var forward_dir = player.get_attack_forward_dir()
	var player_pos = player.global_position
	var dmg = player._weapon_damage(WeaponData.WeaponType.ENERGY_SWORD)

	var slash_side = _melee_swing_side
	_melee_swing_side = -_melee_swing_side

	AudioManager.play("ataque-espalanza", -10.0, 1.05)

	# Hitbox is now handled by the instantiated weapon scene
	var sword_scene = preload("res://scenes/objects/energy_sword.tscn").instantiate()
	player.get_parent().add_child(sword_scene)
	sword_scene.global_position = player_pos + forward_dir * 1.5
	sword_scene.look_at(sword_scene.global_position + forward_dir, Vector3.UP)
	sword_scene.setup(dmg, 0.2, 15.0, forward_dir)

	animate_weapon_swing(WeaponData.WeaponType.ENERGY_SWORD, slash_side)
	create_sword_slash_visual(player_pos, forward_dir)


func attack_flame_axe(cd_mult: float) -> void:
	attack_cooldown = player.get_weapon_data(WeaponData.WeaponType.FLAME_AXE).base_cooldown * cd_mult
	var player_pos = player.global_position
	var dmg = player._weapon_damage(WeaponData.WeaponType.FLAME_AXE)
	var aoe_radius = player.get_weapon_data(WeaponData.WeaponType.FLAME_AXE).range

	# Hitbox is now handled by the instantiated weapon scene
	var axe_scene = preload("res://scenes/objects/flame_axe.tscn").instantiate()
	player.get_parent().add_child(axe_scene)
	axe_scene.global_position = player_pos
	axe_scene.setup(dmg, 0.2, 18.0, Vector3.ZERO)

	create_flame_shockwave_visual(player_pos, aoe_radius)


func attack_plasma_rifle(cd_mult: float) -> void:
	attack_cooldown = player.get_weapon_data(WeaponData.WeaponType.PLASMA_RIFLE).base_cooldown * cd_mult
	var aim_point = player.get_camera_aim_point()
	var start_pos = player.muzzle.global_position
	var aim_dir = (aim_point - start_pos).normalized()
	if (aim_point - start_pos).length_squared() < 0.04:
		aim_dir = -player.spring_arm.global_transform.basis.z

	player.orient_player_to_aim(aim_point)

	var dmg = player._weapon_damage(WeaponData.WeaponType.PLASMA_RIFLE)
	var bullet_color = Color(0.0, 0.9, 1.0)

	var bullet = bullet_scene.instantiate()
	player.get_parent().add_child(bullet)
	bullet.global_position = start_pos
	bullet.setup(aim_dir, dmg, player.get_weapon_data(WeaponData.WeaponType.PLASMA_RIFLE).projectile_speed, false, bullet_color, player.get_rid())

	player.apply_camera_recoil(0.012, randf_range(-0.003, 0.003), 0.05)
	player.create_muzzle_flash(bullet_color, 1.0)


func attack_tri_shotgun(cd_mult: float) -> void:
	attack_cooldown = player.get_weapon_data(WeaponData.WeaponType.TRI_SHOTGUN).base_cooldown * cd_mult
	var aim_point = player.get_camera_aim_point()
	var start_pos = player.muzzle.global_position
	var base_dir = (aim_point - start_pos).normalized()
	if (aim_point - start_pos).length_squared() < 0.04:
		base_dir = -player.spring_arm.global_transform.basis.z

	player.orient_player_to_aim(aim_point)

	AudioManager.play("disparo-escopeta", -10.0)

	var dmg = player._weapon_damage(WeaponData.WeaponType.TRI_SHOTGUN)
	# Smoke shotgun: disparos gris humo
	var pellet_color = Color(0.65, 0.65, 0.7)

	var angles = [-12.0, -6.0, 0.0, 6.0, 12.0]
	for deg in angles:
		var spread_rot = Transform3D().rotated(Vector3.UP, deg_to_rad(deg + randf_range(-1.5, 1.5)))
		var pellet_dir = (spread_rot.basis * base_dir).normalized()

		var bullet = bullet_scene.instantiate()
		player.get_parent().add_child(bullet)
		bullet.global_position = start_pos
		bullet.setup(pellet_dir, dmg, player.get_weapon_data(WeaponData.WeaponType.TRI_SHOTGUN).projectile_speed, false, pellet_color, player.get_rid())

	player.apply_camera_recoil(0.038, randf_range(-0.01, 0.01), 0.12)
	player.create_muzzle_flash(pellet_color, 1.4)

## Serpientes de Joel: 3 serpientes de esmeralda en cono (una al centro, dos en
## los bordes desviadas ±half_angle del arma).

func attack_serpents(cd_mult: float) -> void:
	attack_cooldown = player.get_weapon_data(WeaponData.WeaponType.SERPENTS).base_cooldown * cd_mult
	var aim_point = player.get_camera_aim_point()
	var start_pos = player.muzzle.global_position
	var base_dir = (aim_point - start_pos).normalized()
	if (aim_point - start_pos).length_squared() < 0.04:
		base_dir = -player.spring_arm.global_transform.basis.z

	player.orient_player_to_aim(aim_point)

	var s_stream = AudioManager.get_stream("disparo-serpiente")
	var s_start_time = s_stream.get_length() * 0.35 if s_stream else 0.0
	AudioManager.play("disparo-serpiente", -10.0, 1.05, s_start_time)

	var dmg = player._weapon_damage(WeaponData.WeaponType.SERPENTS)
	var half_angle = player.get_weapon_data(WeaponData.WeaponType.SERPENTS).half_angle
	var snake_speed = player.get_weapon_data(WeaponData.WeaponType.SERPENTS).projectile_speed
	var serpent_color = Color(0.3, 0.9, 0.4)

	var angles = [0.0, -half_angle, half_angle]
	for deg in angles:
		var spread_rot = Transform3D().rotated(Vector3.UP, deg_to_rad(deg + randf_range(-1.5, 1.5)))
		var snake_dir: Vector3 = (spread_rot.basis * base_dir).normalized()

		var snake = serpent_projectile_scene.instantiate()
		player.get_parent().add_child(snake)
		snake.global_position = start_pos
		snake.setup(snake_dir, dmg, snake_speed, player.get_rid())

	player.apply_camera_recoil(0.012, 0.0, 0.15)
	player.create_muzzle_flash(serpent_color, 1.2)

## Hacha Giratoria (Garri): lanza un hacha que vuela hasta max_range o hasta chocar

func attack_spinning_axe(cd_mult: float) -> void:
	attack_cooldown = player.get_weapon_data(WeaponData.WeaponType.SPINNING_AXE).base_cooldown * cd_mult
	var aim_point = player.get_camera_aim_point()
	player.orient_player_to_aim(aim_point)
	var start_pos = player.muzzle.global_position
	var aim_dir = (aim_point - start_pos).normalized()
	if (aim_point - start_pos).length_squared() < 0.04:
		aim_dir = -player.spring_arm.global_transform.basis.z

	var dmg = player._weapon_damage(WeaponData.WeaponType.SPINNING_AXE)
	var proj = preload("res://scenes/objects/spinning_axe_projectile.tscn").instantiate()
	player.get_parent().add_child(proj)
	proj.global_position = start_pos
	proj.setup(aim_dir, dmg, player.get_weapon_data(WeaponData.WeaponType.SPINNING_AXE).projectile_speed, player.get_weapon_data(WeaponData.WeaponType.SPINNING_AXE).range)

	player.apply_camera_recoil(0.02, 0.0, 0.1)
	player.create_muzzle_flash(Color(0.2, 0.9, 0.3), 1.2)

## Ciclo Elemental (Saimon): Fuego -> Hielo -> Viento -> Agua -> Planta

func attack_elements_cycle(cd_mult: float) -> void:
	attack_cooldown = player.get_weapon_data(WeaponData.WeaponType.ELEMENTS_CYCLE).base_cooldown * cd_mult
	var aim_point = player.get_camera_aim_point()
	player.orient_player_to_aim(aim_point)
	var start_pos = player.muzzle.global_position
	var aim_dir = (aim_point - start_pos).normalized()
	if (aim_point - start_pos).length_squared() < 0.04:
		aim_dir = -player.spring_arm.global_transform.basis.z

	var colors = [
		Color(1.0, 0.3, 0.1), # Fuego
		Color(0.2, 0.8, 1.0), # Hielo
		Color(0.8, 0.8, 0.8), # Viento
		Color(0.1, 0.4, 1.0), # Agua
		Color(0.3, 0.9, 0.2)  # Planta
	]
	
	var elements = ["fuego", "hielo", "viento", "agua", "planta"]
	var current_element = elements[saimon_element_index]
	var pellet_color = colors[saimon_element_index]
	
	saimon_element_index = (saimon_element_index + 1) % 5

	var dmg = player._weapon_damage(WeaponData.WeaponType.ELEMENTS_CYCLE)
	
	var bullet = bullet_scene.instantiate()
	player.get_parent().add_child(bullet)
	bullet.global_position = start_pos
	bullet.setup(aim_dir, dmg, player.get_weapon_data(WeaponData.WeaponType.ELEMENTS_CYCLE).projectile_speed, false, pellet_color, player.get_rid())
	
	# Add a small meta tag to let the bullet know it's elemental if we want to add effects later
	bullet.set_meta("element", current_element)

	player.apply_camera_recoil(0.015, randf_range(-0.005, 0.005), 0.1)
	player.create_muzzle_flash(pellet_color, 1.3)




func attack_railgun(cd_mult: float) -> void:
	attack_cooldown = player.get_weapon_data(WeaponData.WeaponType.RAILGUN).base_cooldown * cd_mult
	var aim_point = player.get_camera_aim_point()
	var start_pos = player.muzzle.global_position
	var aim_dir = (aim_point - start_pos).normalized()
	if (aim_point - start_pos).length_squared() < 0.04:
		aim_dir = -player.spring_arm.global_transform.basis.z

	player.orient_player_to_aim(aim_point)

	var max_range = player.get_weapon_data(WeaponData.WeaponType.RAILGUN).range
	var end_pos = start_pos + aim_dir * max_range
	var dmg = player._weapon_damage(WeaponData.WeaponType.RAILGUN)

	# Raycast check for wall/environment collision
	var space_state = player.get_world_3d().direct_space_state
	var ray_query = PhysicsRayQueryParameters3D.create(start_pos, end_pos)
	ray_query.exclude = [player.get_rid()]
	ray_query.collision_mask = 1 # Wall / World layer
	var ray_res = space_state.intersect_ray(ray_query)
	if not ray_res.is_empty():
		end_pos = ray_res.position

	# Piercing Laser Beam: Pierces ALL enemies along beam line
	var beam_radius = player.get_weapon_data(WeaponData.WeaponType.RAILGUN).beam_radius
	for enemy in player.get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy): continue
		var enemy_center = enemy.global_position + Vector3(0, 0.8, 0)
		var closest_pt = Geometry3D.get_closest_point_to_segment(enemy_center, start_pos, end_pos)
		var dist = (enemy_center - closest_pt).length()
		if dist <= beam_radius:
			if enemy.has_method("take_damage"):
				enemy.take_damage(dmg, aim_dir)
				spawn_railgun_hit_sparks(closest_pt, aim_dir)

	if not ray_res.is_empty():
		spawn_railgun_hit_sparks(end_pos, ray_res.normal)

	var railgun_color = Color(0.95, 0.2, 1.0)
	create_railgun_visual(start_pos, end_pos)
	player.apply_camera_recoil(0.065, randf_range(-0.015, 0.015), 0.18)
	player.create_muzzle_flash(railgun_color, 1.8)


func spawn_railgun_hit_sparks(pos: Vector3, normal: Vector3) -> void:
	var BulletScript = load("res://scripts/objects/bullet.gd")
	if BulletScript and BulletScript.has_method("spawn_impact_sparks"):
		BulletScript.spawn_impact_sparks(player.get_parent(), pos, normal, Color(0.95, 0.2, 1.0))


func create_spear_slash_visual(pos: Vector3, facing_dir: Vector3, side: float) -> void:
	var pivot = Node3D.new()
	player.get_parent().add_child(pivot)
	pivot.global_position = pos + facing_dir * 1.8 + Vector3(0, 1.0, 0)
	if facing_dir.cross(Vector3.UP).length() > 0.001:
		pivot.look_at(pivot.global_position + facing_dir, Vector3.UP)

	var arc = MeshInstance3D.new()
	var mesh_inst = PrismMesh.new()
	mesh_inst.size = Vector3(3.6, 0.4, 1.8)
	arc.mesh = mesh_inst
	pivot.add_child(arc)

	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.4, 1.0, 0.55, 0.45)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.3, 1.0, 0.5)
	mat.emission_energy_multiplier = 2.0
	arc.material_override = mat

	# --- Emerald Slash Energy Wisps ---
	var energy_particles := CPUParticles3D.new()
	energy_particles.amount = 16
	energy_particles.lifetime = 0.25
	energy_particles.one_shot = true
	energy_particles.explosiveness = 0.85
	energy_particles.direction = facing_dir + Vector3(side * 0.4, 0.0, 0).normalized()
	energy_particles.spread = 45.0
	energy_particles.initial_velocity_min = 7.0
	energy_particles.initial_velocity_max = 15.0
	energy_particles.scale_amount_min = 0.4
	energy_particles.scale_amount_max = 0.9

	var ep_mesh := SphereMesh.new()
	ep_mesh.radius = 0.08
	ep_mesh.height = 0.16
	energy_particles.mesh = ep_mesh

	var ep_mat := StandardMaterial3D.new()
	ep_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ep_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ep_mat.albedo_color = Color(0.5, 1.0, 0.6, 0.5)
	ep_mat.emission_enabled = true
	ep_mat.emission = Color(0.3, 1.0, 0.5)
	ep_mat.emission_energy_multiplier = 2.0
	energy_particles.material_override = ep_mat

	pivot.add_child(energy_particles)
	energy_particles.emitting = true

	# Sweep the arc horizontally across the front, opposite to the weapon swing.
	pivot.rotation.y = deg_to_rad(-45.0 * side)
	var tween = player.create_tween().set_parallel(true)
	tween.tween_property(pivot, "rotation:y", deg_to_rad(45.0 * side), 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(arc, "scale", Vector3(1.6, 1.0, 1.6), 0.16)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.22)
	tween.chain().tween_callback(pivot.queue_free)

## Flamethrower fire effect: a hot white-yellow inner core plus an outer
## cone of orange flames streaming out of the nozzle, lit by a flickering
## point light. Everything self-destructs shortly after firing.

func create_flame_burst_visual(origin: Vector3, dir: Vector3) -> void:
	var flat_dir = Vector3(dir.x, 0.0, dir.z)
	if flat_dir.length() < 0.01:
		flat_dir = Vector3.FORWARD
	flat_dir = flat_dir.normalized()

	# Create a temporary anchor attached to the rotating player.mesh
	# so the emitter follows the player's position and rotation
	var anchor = Node3D.new()
	player.mesh.add_child(anchor)
	anchor.global_position = origin + flat_dir * 0.8 + Vector3.UP * 1.05
	anchor.look_at(anchor.global_position + flat_dir, Vector3.UP)

	# -- Inner core: intense hot white-yellow core streamer
	var core = _build_flame_cone(Vector3.FORWARD)
	core.local_coords = false # Trails realistically in the world
	core.amount = 45
	core.lifetime = 0.25
	core.spread = 10.0
	core.initial_velocity_min = 12.0
	core.initial_velocity_max = 18.0
	core.scale_amount_min = 0.25
	core.scale_amount_max = 0.55
	core.mesh = _flame_mesh(0.12)
	core.material_override = _flame_material(Color(1.0, 0.95, 0.7), 6.0)
	core.color_ramp = _make_flame_ramp([
		[Color(1.0, 1.0, 0.9, 1.0), 0.0],
		[Color(1.0, 0.8, 0.2, 0.9), 0.4],
		[Color(1.0, 0.4, 0.0, 0.0), 1.0],
	])
	anchor.add_child(core)
	core.emitting = true

	# -- Outer cone: wide intense fiery plume expanding forward
	var flame = _build_flame_cone(Vector3.FORWARD)
	flame.local_coords = false
	flame.amount = 80
	flame.lifetime = 0.45
	flame.spread = 22.0
	flame.initial_velocity_min = 10.0
	flame.initial_velocity_max = 22.0
	flame.scale_amount_min = 0.4
	flame.scale_amount_max = 1.3
	flame.mesh = _flame_mesh(0.2)
	flame.material_override = _flame_material(Color(1.0, 0.45, 0.05), 4.5)
	flame.color_ramp = _make_flame_ramp([
		[Color(1.0, 0.7, 0.1, 1.0), 0.0],
		[Color(1.0, 0.35, 0.02, 0.95), 0.3],
		[Color(0.85, 0.15, 0.0, 0.6), 0.75],
		[Color(0.2, 0.05, 0.0, 0.0), 1.0],
	])
	anchor.add_child(flame)
	flame.emitting = true

	# -- High speed bright orange/yellow ember sparks bursting from nozzle
	var sparks = _build_flame_cone(Vector3.FORWARD)
	sparks.local_coords = false
	sparks.amount = 35
	sparks.lifetime = 0.40
	sparks.spread = 35.0
	sparks.initial_velocity_min = 16.0
	sparks.initial_velocity_max = 28.0
	sparks.scale_amount_min = 0.08
	sparks.scale_amount_max = 0.18
	sparks.gravity = Vector3(0, -3.0, 0)
	sparks.mesh = _flame_mesh(0.04)
	sparks.material_override = _flame_material(Color(1.0, 0.9, 0.3), 8.0)
	sparks.color_ramp = _make_flame_ramp([
		[Color(1.0, 0.95, 0.5, 1.0), 0.0],
		[Color(1.0, 0.5, 0.0, 0.8), 0.6],
		[Color(1.0, 0.2, 0.0, 0.0), 1.0],
	])
	anchor.add_child(sparks)
	sparks.emitting = true

	# -- Powerful dynamic light flashing along the nozzle path
	var light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.15)
	light.light_energy = 8.0
	light.omni_range = 10.0
	anchor.add_child(light)
	# Position the light slightly forward relative to the anchor
	light.position = Vector3(0, 0, -1.5)
	
	var flicker = player.create_tween()
	for i in 6:
		flicker.tween_property(light, "light_energy", randf_range(5.0, 10.0), 0.04)
	flicker.tween_property(light, "light_energy", 0.0, 0.12)
	flicker.tween_callback(light.queue_free)

	# Cleanup anchor (which holds all particles) after emission completes
	var cleanup = player.create_tween()
	cleanup.tween_interval(0.7)
	cleanup.tween_callback(anchor.queue_free)

## Builds a base forward-shooting fire cone emitter (one shot, additive).

func _build_flame_cone(dir: Vector3) -> CPUParticles3D:
	var p = CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.direction = dir
	p.gravity = Vector3(0, 1.5, 0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINT
	return p

## A low-poly blurred sphere player.mesh used for each flame puff.

func _flame_mesh(radius: float) -> SphereMesh:
	var m = SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = 6
	m.rings = 4
	return m

## Additive, unshaded glowing material for the flame puffs.

func _flame_material(color: Color, emission: float) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Additive blending glows and fades out (RGB ramps to dark at the tail).
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = emission
	return mat

## Builds a Gradient ramp from ordered [color, offset] pairs.

func _make_flame_ramp(points: Array) -> Gradient:
	var g = Gradient.new()
	var offsets = PackedFloat32Array()
	var colors = PackedColorArray()
	for p in points:
		offsets.append(p[1])
		colors.append(p[0])
	g.offsets = offsets
	g.colors = colors
	return g

## Procedural melee swing: sweeps the held weapon across a horizontal arc,
## alternating sides each attack, then restores the idle pose.

func animate_weapon_swing(weapon_type: int, side: float) -> void:
	var weapon: Node3D = player.weapon_models.get(weapon_type)
	if not weapon or not is_instance_valid(weapon):
		return
	var base_transform: Transform3D = weapon.transform
	var base_rot: Vector3 = base_transform.basis.get_euler()
	var start_rot: Vector3 = base_rot + Vector3(0.0, deg_to_rad(52.0 * side), deg_to_rad(-18.0))
	var end_rot: Vector3 = base_rot + Vector3(0.0, deg_to_rad(-52.0 * side), deg_to_rad(22.0))
	weapon.rotation = start_rot
	var tween = player.create_tween()
	tween.tween_property(weapon, "rotation", end_rot, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func() -> void:
		if is_instance_valid(weapon) and weapon.is_inside_tree():
			weapon.transform = base_transform
	)


func create_sword_slash_visual(pos: Vector3, facing_dir: Vector3) -> void:
	var arc = MeshInstance3D.new()
	var mesh_inst = PrismMesh.new()
	mesh_inst.size = Vector3(2.8, 0.12, 1.6)
	arc.mesh = mesh_inst

	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.0, 0.95, 1.0, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.0, 0.85, 1.0)
	mat.emission_energy_multiplier = 2.5
	arc.material_override = mat

	player.get_parent().add_child(arc)
	arc.global_position = pos + facing_dir * 1.4 + Vector3(0, 1.0, 0)
	if facing_dir.cross(Vector3.UP).length() > 0.001:
		arc.look_at(arc.global_position + facing_dir, Vector3.UP)

	# --- Plasma Sparks along edge ---
	var sparks := CPUParticles3D.new()
	sparks.amount = 14
	sparks.lifetime = 0.22
	sparks.one_shot = true
	sparks.explosiveness = 0.85
	sparks.direction = facing_dir
	sparks.spread = 40.0
	sparks.initial_velocity_min = 6.0
	sparks.initial_velocity_max = 14.0
	sparks.scale_amount_min = 0.4
	sparks.scale_amount_max = 0.9

	var p_mesh := BoxMesh.new()
	p_mesh.size = Vector3(0.05, 0.05, 0.2)
	sparks.mesh = p_mesh

	var sp_mat := StandardMaterial3D.new()
	sp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sp_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sp_mat.albedo_color = Color(0.6, 0.95, 1.0, 0.5)
	sp_mat.emission_enabled = true
	sp_mat.emission = Color(0.0, 0.85, 1.0)
	sp_mat.emission_energy_multiplier = 2.5
	sparks.material_override = sp_mat

	player.get_parent().add_child(sparks)
	sparks.global_position = arc.global_position
	sparks.emitting = true

	var tween = player.create_tween().set_parallel(true)
	tween.tween_property(arc, "scale", Vector3(1.4, 1.4, 1.4), 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.2)
	tween.chain().tween_callback(arc.queue_free)

	var cleanup = player.create_tween()
	cleanup.tween_interval(0.3)
	cleanup.tween_callback(sparks.queue_free)


func create_flame_shockwave_visual(pos: Vector3, max_radius: float) -> void:
	var container = Node3D.new()
	player.get_parent().add_child(container)
	container.global_position = pos + Vector3(0, 0.1, 0)

	var ring = MeshInstance3D.new()
	var mesh_inst = TorusMesh.new()
	mesh_inst.inner_radius = 0.2
	mesh_inst.outer_radius = 0.6
	mesh_inst.rings = 20
	mesh_inst.ring_segments = 16
	ring.mesh = mesh_inst

	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.4, 0.05, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.35, 0.0)
	mat.emission_energy_multiplier = 2.5
	ring.material_override = mat
	container.add_child(ring)

	var light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.5, 0.1)
	light.light_energy = 5.0
	light.omni_range = max_radius * 1.4
	container.add_child(light)

	# --- Fiery Embers & Sparks Burst ---
	var embers := CPUParticles3D.new()
	embers.amount = 26
	embers.lifetime = 0.45
	embers.one_shot = true
	embers.explosiveness = 0.9
	embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	embers.emission_sphere_radius = 0.8
	embers.direction = Vector3.UP
	embers.spread = 75.0
	embers.initial_velocity_min = 3.5
	embers.initial_velocity_max = 8.0
	embers.gravity = Vector3(0, 2.0, 0)
	embers.scale_amount_min = 0.3
	embers.scale_amount_max = 0.8

	var p_mesh := BoxMesh.new()
	p_mesh.size = Vector3(0.08, 0.08, 0.16)
	embers.mesh = p_mesh

	var eb_mat := StandardMaterial3D.new()
	eb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	eb_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	eb_mat.albedo_color = Color(1.0, 0.8, 0.2, 0.6)
	eb_mat.emission_enabled = true
	eb_mat.emission = Color(1.0, 0.5, 0.1)
	eb_mat.emission_energy_multiplier = 3.0
	embers.material_override = eb_mat

	container.add_child(embers)
	embers.emitting = true

	var tween = player.create_tween().set_parallel(true)
	tween.tween_property(ring, "scale", Vector3(max_radius, 1.0, max_radius), 0.3).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.35)
	tween.tween_property(light, "light_energy", 0.0, 0.4)
	tween.chain().tween_callback(container.queue_free)


func create_railgun_visual(start_pos: Vector3, end_pos: Vector3) -> void:
	var beam = MeshInstance3D.new()
	var mesh_inst = CylinderMesh.new()
	mesh_inst.top_radius = 0.2
	mesh_inst.bottom_radius = 0.2
	mesh_inst.height = (end_pos - start_pos).length()
	beam.mesh = mesh_inst

	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.95, 0.2, 1.0, 1.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam.material_override = mat

	player.get_parent().add_child(beam)
	beam.global_position = (start_pos + end_pos) * 0.5

	var dir = (end_pos - start_pos).normalized()
	if dir.cross(Vector3.UP).length() > 0.001:
		beam.look_at(end_pos, Vector3.UP)
		beam.rotate_object_local(Vector3.RIGHT, deg_to_rad(90))

	var tween = player.create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.25)
	tween.tween_callback(beam.queue_free)


func attack_air_fists(cd_mult: float) -> void:
	attack_cooldown = player.get_weapon_data(WeaponData.WeaponType.AIR_FISTS).base_cooldown * cd_mult
	player.orient_player_to_aim(player.get_camera_aim_point())
	var forward_dir = player.get_attack_forward_dir()
	var player_pos = player.global_position
	var dmg = player._weapon_damage(WeaponData.WeaponType.AIR_FISTS)

	# Alternate combo step: 0 = left punch, 1 = right punch
	var punch_side = 1.0 if _punch_combo_step == 0 else -1.0
	_punch_combo_step = (_punch_combo_step + 1) % 2

	# Hitbox is now handled by the instantiated weapon scene
	var fists_scene = preload("res://scenes/objects/air_fists.tscn").instantiate()
	player.get_parent().add_child(fists_scene)
	fists_scene.global_position = player_pos + forward_dir * 1.5
	fists_scene.look_at(fists_scene.global_position + forward_dir, Vector3.UP)
	fists_scene.setup(dmg, 0.15, 14.0, forward_dir)

	# Animate: snap the punching fist forward then spring back
	_animate_air_fist_punch(punch_side)
	create_air_punch_visual(player_pos, forward_dir, punch_side, false)

## Charged attack (hold LMB ≥ 0.55 s then release):
## Kaionz dashes forward then slams with a massive two-handed air blast.

func attack_air_fists_charged(cd_mult: float) -> void:
	attack_cooldown = player.get_weapon_data(WeaponData.WeaponType.AIR_FISTS).heavy_cooldown * cd_mult
	player.orient_player_to_aim(player.get_camera_aim_point())
	var forward_dir = player.get_attack_forward_dir()
	var player_pos = player.global_position

	# Start the dash
	_punch_dash_dir   = forward_dir
	_punch_dash_timer = PUNCH_DASH_DURATION

	# Slightly delayed hit (fires at dash midpoint)
	var dmg = player._weapon_heavy_damage(WeaponData.WeaponType.AIR_FISTS)
	var hit_timer = player.create_tween()
	hit_timer.tween_interval(PUNCH_DASH_DURATION * 0.6)
	hit_timer.tween_callback(func() -> void:
		if not player.is_inside_tree(): return
		var hit_pos = player.global_position
		var hit_dir = -player.mesh.global_transform.basis.z
		var fists_scene = preload("res://scenes/objects/air_fists.tscn").instantiate()
		player.get_parent().add_child(fists_scene)
		fists_scene.scale = Vector3(2.0, 1.0, 2.0)
		fists_scene.global_position = hit_pos + hit_dir * 1.5
		fists_scene.look_at(fists_scene.global_position + hit_dir, Vector3.UP)
		fists_scene.setup(dmg, 0.25, 22.0, hit_dir)
		create_air_punch_visual(hit_pos, hit_dir, 0.0, true)
		player.apply_camera_recoil(0.04, randf_range(-0.01, 0.01), 0.12)
	)

	player.emit_signal("weapon_attacked", WeaponData.WeaponType.AIR_FISTS)
	player.apply_camera_recoil(0.025, randf_range(-0.005, 0.005), 0.07)

## Skill — Choque de Puños (E key):
## Kaionz slams both fists together, generating an air shockwave that
## radiates outward 9 m and slows all enemies caught in it by 55% for 4 s.

func _animate_air_fist_punch(side: float) -> void:
	var fists_root : Node3D = player.weapon_models.get(WeaponData.WeaponType.AIR_FISTS)
	if not fists_root or not is_instance_valid(fists_root): return
	# side > 0 → left fist (child 0), side < 0 → right fist (child 1)
	var child_idx = 0 if side > 0 else 1
	if fists_root.get_child_count() <= child_idx: return
	var fist : Node3D = fists_root.get_child(child_idx)
	var orig = fist.position
	var punched = orig + Vector3(0, 0, -0.22)   # local -Z = forward
	var tw = player.create_tween()
	tw.tween_property(fist, "position", punched, 0.07).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(fist, "position", orig,    0.14).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)

## Short-lived compressed-air impact visual: an expanding flat ring + light burst.
## `is_charged` makes a larger, two-ring version for the dash punch.

func create_air_punch_visual(pos: Vector3, facing_dir: Vector3, side: float, is_charged: bool) -> void:
	var ring_count = 2 if is_charged else 1
	var base_scale = 2.2 if is_charged else 1.4
	var duration = 0.22 if is_charged else 0.16

	for i in range(ring_count):
		var ring = MeshInstance3D.new()
		var ring_mesh = TorusMesh.new()
		ring_mesh.inner_radius  = 0.05
		ring_mesh.outer_radius  = 0.18
		ring_mesh.rings         = 14
		ring_mesh.ring_segments = 10
		ring.mesh = ring_mesh

		var mat = StandardMaterial3D.new()
		mat.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color  = Color(0.6, 0.93, 1.0, 0.45)
		mat.transparency  = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.emission_enabled = true
		mat.emission      = Color(0.4, 0.85, 1.0)
		mat.emission_energy_multiplier = 2.0
		ring.material_override = mat

		player.get_parent().add_child(ring)
		ring.global_position = pos + facing_dir * (1.0 + i * 0.3) + Vector3(0, 0.9, 0)
		if facing_dir.cross(Vector3.UP).length() > 0.001:
			ring.look_at(ring.global_position + facing_dir, Vector3.UP)
		ring.rotate_object_local(Vector3.RIGHT, deg_to_rad(90))

		var target_scale = Vector3(base_scale + i * 0.5, base_scale + i * 0.5, base_scale + i * 0.5)
		var tw = player.create_tween().set_parallel(true)
		tw.tween_property(ring, "scale", target_scale, duration).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		tw.tween_property(mat,  "albedo_color:a", 0.0,   duration * 1.3)
		tw.chain().tween_callback(ring.queue_free)

	# --- Wind Shockwave Stream ---
	var wind := CPUParticles3D.new()
	wind.amount = 18 if is_charged else 12
	wind.lifetime = 0.25
	wind.explosiveness = 0.9
	wind.one_shot = true
	wind.direction = facing_dir
	wind.spread = 25.0
	wind.initial_velocity_min = 9.0 if is_charged else 6.0
	wind.initial_velocity_max = 18.0 if is_charged else 12.0
	wind.scale_amount_min = 0.4
	wind.scale_amount_max = 0.9

	var wp_mesh := SphereMesh.new()
	wp_mesh.radius = 0.07
	wp_mesh.height = 0.2
	wind.mesh = wp_mesh

	var wp_mat := StandardMaterial3D.new()
	wp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wp_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wp_mat.albedo_color = Color(0.75, 0.95, 1.0, 0.45)
	wp_mat.emission_enabled = true
	wp_mat.emission = Color(0.5, 0.9, 1.0)
	wp_mat.emission_energy_multiplier = 1.8
	wind.material_override = wp_mat

	var w_ramp := Gradient.new()
	w_ramp.set_color(0, Color(0.75, 0.95, 1.0, 0.5))
	w_ramp.add_point(1.0, Color(0.5, 0.85, 1.0, 0.0))
	wind.color_ramp = w_ramp

	player.get_parent().add_child(wind)
	wind.global_position = pos + facing_dir * 1.0 + Vector3(0, 0.9, 0)
	wind.emitting = true

	var w_clean = player.create_tween()
	w_clean.tween_interval(0.35)
	w_clean.tween_callback(wind.queue_free)

	# Impact light
	var light = OmniLight3D.new()
	light.light_color  = Color(0.55, 0.90, 1.0)
	light.light_energy = 5.5 if is_charged else 3.5
	light.omni_range   = 5.5 if is_charged else 3.5
	player.get_parent().add_child(light)
	light.global_position = pos + facing_dir * 1.2 + Vector3(0, 0.9, 0)
	var ltw = player.create_tween()
	ltw.tween_property(light, "light_energy", 0.0, 0.18)
	ltw.tween_callback(light.queue_free)

## Expanding air shockwave for the skill: large torus ring + secondary pulse ring
## + a soft point light that fades out over the full animation.

func attack_dusts(cd_mult: float) -> void:
	attack_cooldown = player.get_weapon_data(WeaponData.WeaponType.DUSTS).base_cooldown * cd_mult
	var aim_point = player.get_camera_aim_point()
	player.orient_player_to_aim(aim_point)
	
	AudioManager.play("ataque-espalanza", -2.0, 1.8)

	if current_dust_mode == 1:
		# Brown dust: burst of speed instead of a throw.
		dust_speed_boost_timer = 4.0
		create_dust_puff_visual(player.muzzle.global_position, Color(0.55, 0.38, 0.18))
		return

	var proj = dust_projectile_scene.instantiate()
	player.get_parent().add_child(proj)
	proj.setup(player.muzzle.global_position, aim_point, current_dust_mode, player)

	var dust_color = Color(0.73, 0.25, 0.9) if current_dust_mode == 0 else Color(0.2, 0.95, 0.45)
	player.apply_camera_recoil(0.02, randf_range(-0.004, 0.004), 0.08)
	player.create_muzzle_flash(dust_color, 1.1)

## Right-click with dusts out: cycle the powder (0 AoE → 1 speed → 2 heal).

func cycle_dust_mode() -> void:
	current_dust_mode = (current_dust_mode + 1) % 3

## Small puff of dust used by the brown speed-dust self-buff.

func create_dust_puff_visual(pos: Vector3, color: Color) -> void:
	var container := Node3D.new()
	player.get_parent().add_child(container)
	container.global_position = pos

	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 5.0
	light.omni_range = 4.0
	container.add_child(light)

	var puff := CPUParticles3D.new()
	puff.amount              = 28
	puff.lifetime            = 0.5
	puff.one_shot            = true
	puff.explosiveness       = 0.95
	puff.direction           = Vector3.UP
	puff.spread              = 90.0
	puff.initial_velocity_min = 2.0
	puff.initial_velocity_max = 5.5
	puff.gravity             = Vector3(0, 0.5, 0)
	puff.scale_amount_min    = 0.15
	puff.scale_amount_max    = 0.4
	puff.emission_shape      = CPUParticles3D.EMISSION_SHAPE_SPHERE
	puff.emission_sphere_radius = 0.35

	var p_mesh := SphereMesh.new()
	p_mesh.radius = 0.04
	p_mesh.height = 0.08
	puff.mesh = p_mesh

	var p_mat := StandardMaterial3D.new()
	p_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	p_mat.albedo_color = Color(color, 0.9)
	p_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	p_mat.emission_enabled = true
	p_mat.emission = color
	p_mat.emission_energy_multiplier = 3.5
	puff.material_override = p_mat

	var color_ramp := Gradient.new()
	color_ramp.set_color(0, Color(color.r, color.g, color.b, 0.9))
	color_ramp.add_point(1.0, Color(color.r, color.g, color.b, 0.0))
	puff.color_ramp = color_ramp

	container.add_child(puff)
	puff.emitting = true

	var tween = container.create_tween().set_parallel(true)
	tween.tween_property(light, "light_energy", 0.0, 0.4)
	tween.chain().tween_callback(container.queue_free)

func get_weapon_ammo(w_type: int) -> int:
	if weapon_mag_size.get(w_type, 0) > 0:
		return weapon_ammo.get(w_type, weapon_mag_size[w_type])
	return -1

## Starts reloading the current magazine weapon. Ignored if it has no magazine
## or is already reloading.

func start_reload() -> void:
	var w = player.current_weapon()
	if weapon_mag_size.get(w, 0) <= 0:
		return
	if reloading_weapon == w:
		return
	reloading_weapon = w
	total_reload_time = weapon_reload_time.get(w, 2.0)
	reload_timer = 0.0
	player._emit_reload_state()
