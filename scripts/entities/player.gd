extends CharacterBody3D

signal stats_changed(hp, max_hp, shield, max_shield, energy, max_energy)
signal experience_gained(amount, current_xp, required_xp)
signal leveled_up(new_level)
signal weapon_changed(weapon_index, weapon_name, energy_cost)
signal weapon_attacked(weapon_type)
signal reload_state_changed(weapon_type, ammo, max_ammo, is_reloading, progress)
signal player_died

var health_comp: Node
var energy_comp: Node
var experience_comp: Node

@export var max_hp: float:
	get: return health_comp.max_hp if health_comp else 10.0
	set(v): if health_comp: health_comp.max_hp = v

@export var max_shield: float:
	get: return health_comp.max_shield if health_comp else 5.0
	set(v): if health_comp: health_comp.max_shield = v

@export var max_energy: float:
	get: return energy_comp.max_energy if energy_comp else 200.0
	set(v): if energy_comp: energy_comp.max_energy = v

var hp: float:
	get: return health_comp.hp if health_comp else 10.0
	set(v): if health_comp: health_comp.hp = v

var shield: float:
	get: return health_comp.shield if health_comp else 5.0
	set(v): if health_comp: health_comp.shield = v

var energy: float:
	get: return energy_comp.energy if energy_comp else 200.0
	set(v): if energy_comp: energy_comp.energy = v

@export var move_speed: float = 8.5
@export var roll_speed: float = 18.0
@export var mouse_sensitivity: float = 0.003

var camera_controller: Node
var input_controller: Node
var combat_controller: Node
var inventory: Node

var is_berserk: bool = false
var berserk_timer: float = 0.0
var is_riva_fast: bool = false ## Riva en modo ráfaga (Pies Humeantes): animación súper carrera + estela de humo
 ## Índice actual del elemento para el ataque de Saimon
var skill_cd_timer: float = 0.0
@export var skill_cooldown: float = 10.0

var time_since_damage: float:
	get: return health_comp.time_since_damage if health_comp else 0.0
	set(v): if health_comp: health_comp.time_since_damage = v

var shield_regen_delay: float:
	get: return health_comp.shield_regen_delay if health_comp else 4.0
	set(v): if health_comp: health_comp.shield_regen_delay = v


## Mikeura's signature weapon: a spear-lance with a melee thrust AND a ranged throw.



## 4-weapon loadout: slot 0 is filled by the character's starting weapon,
## the rest are filled when the player picks up weapons in the map.







const PlayerMovementController = preload("res://scripts/components/player_movement_controller.gd")
const PlayerAnimationController = preload("res://scripts/components/player_animation_controller.gd")

var movement_controller: PlayerMovementController
var animation_controller: PlayerAnimationController








# --- Auto Combat Variables ---



# -----------------------------

## ---------------------------------------------------------------------------
## Datos de armas centralizados en WeaponData (refactor neutro). Estas tres
## funciones-fachada conservan las firmas originales; delegan en el módulo de
## datos canónico para que los attack_* no cambien.
## ---------------------------------------------------------------------------
func get_weapon_data(weapon_type: int) -> WeaponData:
	return WeaponData.get_weapon_data(weapon_type)

var weapon_levels: Dictionary = {}

func get_weapon_level(w_id: int) -> int:
	return weapon_levels.get(w_id, 1)

func upgrade_weapon(w_id: int) -> void:
	weapon_levels[w_id] = get_weapon_level(w_id) + 1

func get_weapon_modifiers(w_id: int) -> Dictionary:
	var lvl = get_weapon_level(w_id)
	var data = get_weapon_data(w_id)
	var cat = data.category # "melee", "ranged", "special"
	
	var mods = {
		"damage": 1.0,
		"size": 1.0,
		"cooldown": 1.0, # attack speed / cooldown multiplier
		"quantity_bonus": 0,
		"pierce_bonus": 0,
		"duration": 1.0
	}
	
	if lvl >= 2: mods.damage += 0.15
	if lvl >= 3:
		if cat == "melee" or cat == "special": mods.size += 0.10
		elif cat == "ranged": mods.quantity_bonus += 1
	if lvl >= 4:
		mods.cooldown *= 0.85 # -15% cooldown / +15% attack speed (approximated)
	if lvl >= 5: mods.damage += 0.15
	if lvl >= 6:
		if cat == "ranged": mods.pierce_bonus += 1
		else: mods.quantity_bonus += 1
	if lvl >= 7:
		mods.size += 0.15
		
	return mods

func _weapon_damage(weapon_type: int) -> float:
	var base_dmg = WeaponData.weapon_damage(weapon_type, is_berserk)
	var mods = get_weapon_modifiers(weapon_type)
	return base_dmg * mods.damage

func _weapon_heavy_damage(weapon_type: int) -> float:
	var base_dmg = WeaponData.weapon_heavy_damage(weapon_type, is_berserk)
	var mods = get_weapon_modifiers(weapon_type)
	return base_dmg * mods.damage

 ## 0: Purple (AoE), 1: Brown (Speed Boost), 2: Green (Healing Cloud)


## Nombre / coste / icono por arma. Re-exportados desde WeaponData (módulo
## canónico) para no tocar a los consumidores (HUD, señales, UI).
var weapon_names: Dictionary = WeaponData.weapon_names
var weapon_energy_costs: Dictionary = WeaponData.weapon_energy_costs
var weapon_icons: Dictionary = WeaponData.weapon_icons

@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var camera: Camera3D = $SpringArm3D/Camera3D
@onready var mesh: Node3D = $KnightMesh
@onready var muzzle: Marker3D = $KnightMesh/Muzzle
@onready var melee_area: Area3D = $KnightMesh/MeleeArea

# Weapon 3D Model references
var weapon_models: Dictionary = {}
var weapon_visuals: Node = null








## Weapons with a magazine use ammo instead of energy (empty = needs reload).
## Key: WeaponType -> rounds per magazine. Weapons not listed are infinite.


## Seconds it takes to reload a magazine weapon after it runs dry.


## Current ammo per weapon type (only relevant for weapons with a magazine).






## Spore bonuses set by PassiveBronch (defaults are the un-buffed values).



## Assign a PassiveData resource in the Inspector to give this character unique passives.
@export var passive: PassiveData = null

func _ready() -> void:
	add_to_group("player")
	
	combat_controller = load("res://scripts/components/player_combat_controller.gd").new()
	combat_controller.name = "PlayerCombatController"
	add_child(combat_controller)

	inventory = load("res://scripts/components/inventory_component.gd").new()
	inventory.name = "InventoryComponent"
	add_child(inventory)

	health_comp = load("res://scripts/components/health_component.gd").new()
	health_comp.name = "HealthComponent"
	add_child(health_comp)
	
	energy_comp = load("res://scripts/components/energy_component.gd").new()
	energy_comp.name = "EnergyComponent"
	add_child(energy_comp)
	
	experience_comp = load("res://scripts/components/experience_component.gd").new()
	experience_comp.name = "ExperienceComponent"
	add_child(experience_comp)

	health_comp.health_changed.connect(func(h, mh, s, ms): emit_signal("stats_changed", h, mh, s, ms, energy_comp.energy, energy_comp.max_energy))
	energy_comp.energy_changed.connect(func(e, me): emit_signal("stats_changed", health_comp.hp, health_comp.max_hp, health_comp.shield, health_comp.max_shield, e, me))
	health_comp.entity_died.connect(func(): emit_signal("player_died"))
	experience_comp.experience_gained.connect(func(amount, current_xp, required_xp): emit_signal("experience_gained", amount, current_xp, required_xp))
	experience_comp.leveled_up.connect(func(new_level): emit_signal("leveled_up", new_level))

	health_comp.damage_taking.connect(func(data):
		if passive and passive.has_method("on_take_damage"):
			data["amount"] = passive.on_take_damage(self, data["amount"])
	)
	health_comp.check_shield_regen.connect(func(results):
		if passive and passive.has_method("allow_shield_regen"):
			results.append(passive.allow_shield_regen(self))
	)
	health_comp.shield_recharged.connect(func():
		if passive and passive.has_method("on_shield_recharged"):
			passive.on_shield_recharged()
	)
	
	if combat_controller.is_auto_combat_enabled:
		var auto_combat_script = load("res://scripts/components/auto_combat_controller.gd")
		var auto_combat_node = auto_combat_script.new()
		auto_combat_node.name = "AutoCombatController"
		add_child(auto_combat_node)
	
	input_controller = load("res://scripts/components/player_input_controller.gd").new()
	input_controller.name = "PlayerInputController"
	add_child(input_controller)
	
	input_controller.weapon_cycle.connect(cycle_slots)
	input_controller.weapon_select.connect(select_slot)
	input_controller.skill_pressed.connect(activate_skill)
	input_controller.alt_attack_pressed.connect(_on_alt_attack_pressed)
	input_controller.reload_pressed.connect(start_reload)
	input_controller.toggle_mouse_capture.connect(_on_toggle_mouse_capture)
	input_controller.spawn_debug_enemy.connect(_on_spawn_debug_enemy)

	hp = max_hp
	shield = max_shield
	energy = max_energy
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	# Apply passive overrides BEFORE emitting stats (passive may change shield/hp).
	if passive:
		passive.apply_to_player(self)
	
	# Setup 3rd Person Camera System
	camera_controller = $CameraController
	
	setup_weapon_models()
	
	movement_controller = PlayerMovementController.new()
	movement_controller.name = "PlayerMovementController"
	add_child(movement_controller)
	
	animation_controller = PlayerAnimationController.new()
	animation_controller.name = "PlayerAnimationController"
	add_child(animation_controller)
	
	combat_controller.weapon_slots.clear()
	# Each character starts with their signature weapon.
	var selected_char: Dictionary = GameData.get_selected()
	var initial_weapons: Array = selected_char.get("initial_weapons", [WeaponData.WeaponType.SPEAR_LANCE])
	for w in initial_weapons:
		combat_controller.weapon_slots.append(w)
		
	combat_controller.current_slot = 0
	select_slot(0)
	
	emit_signal("stats_changed", hp, max_hp, shield, max_shield, energy, max_energy)

# Per-frame combat + movement + camera + animation hook.
func _physics_process(delta: float) -> void:
	time_since_damage += delta
	
	
		
			
	if skill_cd_timer > 0: skill_cd_timer -= delta

	# Magazine weapon reload: progresses even while another weapon is out.
	
		
		
			
			
			
		

	if is_berserk:
		berserk_timer -= delta
		if berserk_timer <= 0: is_berserk = false

	
		

	movement_controller.handle_movement(delta)
	

## Attack / skill / secondary-fire input. Lives in the physics timestep so
## hold-to-fire weapons, cooldowns and the Kaionz charge mechanic are stable.

func select_slot(slot_idx: int) -> void:
	if not combat_controller: return
	if slot_idx < 0 or slot_idx >= combat_controller.weapon_slots.size():
		return
	combat_controller.current_slot = slot_idx
	var wt: int = combat_controller.weapon_slots[slot_idx]
	update_weapon_visuals()
	if weapon_names.has(wt):
		emit_signal("weapon_changed", slot_idx, weapon_names[wt], weapon_energy_costs.get(wt, 0))
	

func cycle_slots(delta_idx: int) -> void:
	if not combat_controller or combat_controller.weapon_slots.is_empty():
		return
	select_slot((combat_controller.current_slot + delta_idx) % combat_controller.weapon_slots.size())

func _input(event) -> void:
	if camera_controller:
		camera_controller.handle_input(event)

	if event is InputEventKey and event.pressed and event.keycode == KEY_U:
		if experience_comp and experience_comp.has_method("gain_experience"):
			experience_comp.gain_experience(experience_comp.experience_required - experience_comp.experience)


	# ── Cursor release / recapture ─────────────────────────────────────────
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED



# ══════════════════════════════════════════════════════════════════════════
# Weapon 3D models — built procedurally, attached to KnightMesh.
# ══════════════════════════════════════════════════════════════════════════
## Builds the weapon info list shown in the HUD weapon slots.
## Each entry matches what hud.update_weapons() expects (icon/name/cost, and
## max_ammo/ammo for magazine weapons).

	
var weapon_slots: Array:
	get: return combat_controller.weapon_slots if combat_controller else []
	set(v): if combat_controller: combat_controller.weapon_slots = v

var current_slot: int:
	get: return combat_controller.current_slot if combat_controller else 0
	set(v): if combat_controller: combat_controller.current_slot = v

var is_spear_thrown: bool:
	get: return combat_controller.is_spear_thrown if combat_controller else false
	set(v): if combat_controller: combat_controller.is_spear_thrown = v

var reloading_weapon: int:
	get: return combat_controller.reloading_weapon if combat_controller else -1
	set(v): if combat_controller: combat_controller.reloading_weapon = v

var auto_combat_target: Node3D:
	get:
		if is_instance_valid(combat_controller) and "auto_combat_target" in combat_controller:
			var target = combat_controller.get("auto_combat_target")
			if is_instance_valid(target):
				return target as Node3D
		return null
	set(v):
		if is_instance_valid(combat_controller) and "auto_combat_target" in combat_controller:
			combat_controller.set("auto_combat_target", v)

var dust_speed_boost_timer: float:
	get: return combat_controller.dust_speed_boost_timer if combat_controller else 0.0
	set(v): if combat_controller: combat_controller.dust_speed_boost_timer = v

var spore_damage_mult: float:
	get: return combat_controller.spore_damage_mult if combat_controller else 1.0
	set(v): if combat_controller: combat_controller.spore_damage_mult = v

var spore_cloud_duration: float:
	get: return combat_controller.spore_cloud_duration if combat_controller else 3.0
	set(v): if combat_controller: combat_controller.spore_cloud_duration = v

func get_weapons_list() -> Array:
	var list: Array = []
	if not combat_controller: return list
	for wt in combat_controller.weapon_slots:
		var info: Dictionary = {
			"icon": weapon_icons.get(wt, "⚔️"),
			"name": weapon_names.get(wt, "Arma"),
			"cost": weapon_energy_costs.get(wt, 0),
		}
		var mag: int = combat_controller.weapon_mag_size.get(wt, 0)
		if mag > 0:
			info["max_ammo"] = mag
			info["ammo"] = combat_controller.weapon_ammo.get(wt, mag)
		list.append(info)
	return list

func setup_weapon_models() -> void:
	# Construye las mallas 3D de las armas en un componente dedicado
	# (player_weapon_visuals.gd) y comparte su diccionario de modelos.
	weapon_visuals = load("res://scripts/entities/player_weapon_visuals.gd").new()
	add_child(weapon_visuals)
	weapon_visuals.setup_weapon_models(mesh)
	weapon_models = weapon_visuals.weapon_models

# end of setup_weapon_models() — everything below is gameplay helpers.

# ══════════════════════════════════════════════════════════════════════════
# MOVEMENT & CAMERA
# ══════════════════════════════════════════════════════════════════════════
const GRAVITY := 22.0

## WASD -> direction vector. Checks both the logical and physical key states so
## it works with real keyboards and synthetic/test key events alike.

## Shows only the model of the currently selected weapon slot. The spear stays
## hidden while it is flying through the air.
func update_weapon_visuals() -> void:
	if not combat_controller or combat_controller.weapon_slots.is_empty():
		return
	var active: int = combat_controller.weapon_slots[combat_controller.current_slot]
	for wt in weapon_models:
		var m: Node3D = weapon_models[wt]
		if m != null and is_instance_valid(m):
			# Por defecto, ocultamos todas las armas (el jugador pidió que solo aparezcan al atacar)
			m.visible = false

func show_weapon_temporarily(duration: float = 0.5) -> void:
	var active = current_weapon()
	if weapon_models.has(active):
		var m = weapon_models[active]
		m.visible = true
		var timer = get_tree().create_timer(duration)
		timer.timeout.connect(func(): m.visible = false)

func current_weapon() -> int:
	if not combat_controller or combat_controller.weapon_slots.is_empty():
		return WeaponData.WeaponType.SPEAR_LANCE
	var slot = clamp(combat_controller.current_slot, 0, combat_controller.weapon_slots.size() - 1)
	return combat_controller.weapon_slots[slot]

func on_spear_returned() -> void:
	if combat_controller and combat_controller.has_method("on_spear_returned"):
		combat_controller.on_spear_returned()

## Add a weapon to the next free slot. Returns false if the loadout is full.
func add_weapon(w_type: int) -> bool:
	if not combat_controller: return false
	if combat_controller.weapon_slots.size() >= combat_controller.MAX_WEAPON_SLOTS:
		return false
	combat_controller.weapon_slots.append(w_type)
	update_weapon_visuals()
	emit_signal("weapon_changed", combat_controller.current_slot, weapon_names[current_weapon()], weapon_energy_costs[current_weapon()])
	
	return true

## Current ammo for a weapon (-1 means the weapon has no magazine / infinite).


func _emit_reload_state() -> void:
	if not combat_controller: return
	var w: int = combat_controller.reloading_weapon if combat_controller.reloading_weapon >= 0 else current_weapon()
	var progress: float = 0.0
	if combat_controller.reloading_weapon >= 0:
		progress = clamp(combat_controller.reload_timer / combat_controller.total_reload_time, 0.0, 1.0)
	emit_signal("reload_state_changed", w, combat_controller.get_weapon_ammo(w), combat_controller.weapon_mag_size.get(w, 0), combat_controller.reloading_weapon >= 0, progress)

# ══════════════════════════════════════════════════════════════════════════
# COMBAT
# ══════════════════════════════════════════════════════════════════════════

## Per-character special ability (E key). Kaionz slams both fists; everyone
## else enters Berserk mode.
func activate_skill() -> void:
	if skill_cd_timer > 0: return
	skill_cd_timer = skill_cooldown
	var char_id: String = GameData.get_selected().get("id", "")
	match char_id:
		"kaionz":
			skill_kaionz()
		_:
			# Default skill: Berserk mode (all other characters)
			is_berserk = true
			berserk_timer = 6.0

## Raycasts from the camera center out through the crosshair point.
func get_camera_aim_point() -> Vector3:
	if is_instance_valid(combat_controller) and "weapon_slots" in combat_controller and not combat_controller.weapon_slots.is_empty():
		if "auto_combat_target" in combat_controller and is_instance_valid(combat_controller.get("auto_combat_target")):
			return combat_controller.get("auto_combat_target").global_position + Vector3(0, 1.0, 0)
			
	var viewport_rect = get_viewport().get_visible_rect()
	var screen_center = viewport_rect.size * 0.5

	var ray_origin = camera.project_ray_origin(screen_center)
	var ray_normal = camera.project_ray_normal(screen_center)
	var max_range = 100.0
	var ray_target = ray_origin + ray_normal * max_range

	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_target)
	query.exclude = [get_rid()]
	query.collision_mask = 1 # Only hit terrain and enemies, ignore projectiles (Layer 4)

	var result = space_state.intersect_ray(query)
	if not result.is_empty():
		return result.position
	return ray_target

## Calculates a flattened horizontal forward vector toward the current aim point.
func get_attack_forward_dir() -> Vector3:
	var aim = get_camera_aim_point()
	var dir = aim - global_position
	dir.y = 0
	if dir.length_squared() < 0.001:
		return -mesh.global_transform.basis.z
	return dir.normalized()

func orient_player_to_aim(_aim_point: Vector3) -> void:
	# The model no longer rotates to face the aim target when attacking;
	# the attack effect plays in place without turning the character.
	pass

func apply_camera_recoil(pitch_amount: float, yaw_amount: float, kick_z: float = 0.08) -> void:
	pass

func create_muzzle_flash(flash_color: Color, scale_multiplier: float = 1.0) -> void:
	if not is_inside_tree(): return
	var parent = get_parent()
	if not parent or not is_instance_valid(parent) or not parent.is_inside_tree(): return
	var flash_node = Node3D.new()
	parent.add_child(flash_node)
	flash_node.global_position = muzzle.global_position

	var light = OmniLight3D.new()
	light.light_color = flash_color
	light.light_energy = 7.0 * scale_multiplier
	light.omni_range = 5.0 * scale_multiplier
	flash_node.add_child(light)

	var flash_mesh = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.2 * scale_multiplier
	sphere.height = 0.4 * scale_multiplier
	flash_mesh.mesh = sphere

	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color.WHITE.lerp(flash_color, 0.4)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = flash_color
	mat.emission_energy_multiplier = 5.0
	flash_mesh.material_override = mat

	flash_node.add_child(flash_mesh)

	# --- Dynamic Muzzle Sparks Burst ---
	var particles = CPUParticles3D.new()
	particles.amount = int(18 * scale_multiplier)
	particles.lifetime = 0.18 * scale_multiplier
	particles.explosiveness = 1.0
	particles.one_shot = true
	particles.spread = 35.0
	particles.initial_velocity_min = 7.0 * scale_multiplier
	particles.initial_velocity_max = 16.0 * scale_multiplier
	
	# Point particles in the direction the player is looking
	if spring_arm:
		particles.direction = -spring_arm.global_transform.basis.z
	else:
		particles.direction = Vector3.FORWARD

	var p_mesh = BoxMesh.new()
	p_mesh.size = Vector3(0.06, 0.06, 0.22) * scale_multiplier
	particles.mesh = p_mesh
	
	var p_mat = StandardMaterial3D.new()
	p_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	p_mat.albedo_color = Color.WHITE.lerp(flash_color, 0.3)
	p_mat.emission_enabled = true
	p_mat.emission = flash_color
	p_mat.emission_energy_multiplier = 5.0
	particles.material_override = p_mat
	
	flash_node.add_child(particles)
	particles.emitting = true

	var tween = flash_node.create_tween().set_parallel(true)
	tween.tween_property(light, "light_energy", 0.0, 0.12)
	tween.tween_property(flash_mesh, "scale", Vector3(2.4, 2.4, 2.4) * scale_multiplier, 0.1)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.12)
	tween.chain().tween_callback(flash_node.queue_free)






























func take_damage(amount: float, _direction: Vector3 = Vector3.ZERO) -> void:

	if health_comp and health_comp.has_method("take_damage"):
		health_comp.take_damage(amount)

func heal(amount: float) -> void:
	if health_comp and health_comp.has_method("heal"):
		health_comp.heal(amount)

func restore_energy(amount: float) -> void:
	if energy_comp and energy_comp.has_method("restore_energy"):
		energy_comp.restore_energy(amount)

# ══════════════════════════════════════════════════════════════════════════
# KAIONZ — AIR FISTS COMBAT SYSTEM
# ══════════════════════════════════════════════════════════════════════════

## Normal attack: alternating left/right air-punch combo.
## Each hit sends a compressed-air shockwave in front of the player.


func skill_kaionz() -> void:
	var player_pos := global_position
	var radius     := 9.0

	# Clap animation: bring both fists to centre, then snap back
	if weapon_models.has(WeaponData.WeaponType.AIR_FISTS) and is_instance_valid(weapon_models[WeaponData.WeaponType.AIR_FISTS]):
		var fists_root : Node3D = weapon_models[WeaponData.WeaponType.AIR_FISTS]
		if fists_root.get_child_count() >= 2:
			var left_fist  : Node3D = fists_root.get_child(0)
			var right_fist : Node3D = fists_root.get_child(1)
			var orig_l := left_fist.position
			var orig_r := right_fist.position
			var clap_tween := create_tween().set_parallel(true)
			clap_tween.tween_property(left_fist,  "position", Vector3(0.0, orig_l.y, orig_l.z - 0.08), 0.12)
			clap_tween.tween_property(right_fist, "position", Vector3(0.0, orig_r.y, orig_r.z - 0.08), 0.12)
			clap_tween.chain().tween_interval(0.05)
			clap_tween.chain().set_parallel(true)
			clap_tween.tween_property(left_fist,  "position", orig_l, 0.18)
			clap_tween.tween_property(right_fist, "position", orig_r, 0.18)

	# Apply slow to all enemies in radius
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy): continue
		var dist: float = (enemy as Node3D).global_position.distance_to(player_pos)
		if dist <= radius and enemy.has_method("apply_slow"):
			enemy.apply_slow(4.0, 0.45)

	create_air_shockwave_visual(player_pos, radius)
	apply_camera_recoil(0.03, 0.0, 0.1)

## Procedural single-fist punch animation: snaps one fist forward then returns.


func create_air_shockwave_visual(center: Vector3, max_radius: float) -> void:
	# Primary shockwave ring
	var ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius  = 0.15
	ring_mesh.outer_radius  = 0.45
	ring_mesh.rings         = 22
	ring_mesh.ring_segments = 14
	ring.mesh = ring_mesh

	var mat := StandardMaterial3D.new()
	mat.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color  = Color(0.65, 0.95, 1.0, 1.0)
	mat.transparency  = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission      = Color(0.5, 0.90, 1.0)
	mat.emission_energy_multiplier = 4.5
	ring.material_override = mat

	get_parent().add_child(ring)
	ring.global_position = center + Vector3(0, 0.12, 0)

	var tw := create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(max_radius, 1.0, max_radius), 0.55).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat,  "albedo_color:a", 0.0, 0.65)
	tw.chain().tween_callback(ring.queue_free)

	# Secondary inner pulse ring (slightly delayed)
	var ring2 := MeshInstance3D.new()
	var ring2_mesh := TorusMesh.new()
	ring2_mesh.inner_radius  = 0.08
	ring2_mesh.outer_radius  = 0.28
	ring2_mesh.rings         = 18
	ring2_mesh.ring_segments = 10
	ring2.mesh = ring2_mesh
	var mat2 := mat.duplicate() as StandardMaterial3D
	mat2.albedo_color = Color(0.85, 0.98, 1.0, 0.85)
	ring2.material_override = mat2

	get_parent().add_child(ring2)
	ring2.global_position = center + Vector3(0, 0.3, 0)

	var tw2 := create_tween().set_parallel(true)
	tw2.tween_interval(0.08)
	tw2.tween_property(ring2, "scale", Vector3(max_radius * 0.65, 1.0, max_radius * 0.65), 0.42).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw2.tween_property(mat2,  "albedo_color:a", 0.0, 0.50)
	tw2.chain().tween_callback(ring2.queue_free)

	# Ambient light burst
	var swave_light := OmniLight3D.new()
	swave_light.light_color  = Color(0.55, 0.88, 1.0)
	swave_light.light_energy = 8.0
	swave_light.omni_range   = max_radius * 1.5
	get_parent().add_child(swave_light)
	swave_light.global_position = center + Vector3(0, 1.0, 0)
	var ltw := create_tween()
	ltw.tween_property(swave_light, "light_energy", 0.0, 0.7)
	ltw.tween_callback(swave_light.queue_free)

	# CPUParticles burst of wind wisps around player
	var wisp := CPUParticles3D.new()
	wisp.amount              = 28
	wisp.lifetime            = 0.5
	wisp.one_shot            = true
	wisp.explosiveness       = 0.95
	wisp.direction           = Vector3.UP
	wisp.spread              = 90.0
	wisp.initial_velocity_min = 3.5
	wisp.initial_velocity_max = 9.0
	wisp.gravity             = Vector3(0, -1.5, 0)
	wisp.scale_amount_min    = 0.10
	wisp.scale_amount_max    = 0.28
	wisp.emission_shape      = CPUParticles3D.EMISSION_SHAPE_SPHERE
	wisp.emission_sphere_radius = 0.6
	var wisp_mesh := SphereMesh.new()
	wisp_mesh.radius = 0.08
	wisp_mesh.height = 0.16
	wisp.mesh = wisp_mesh
	var wisp_mat := StandardMaterial3D.new()
	wisp_mat.shading_mode    = BaseMaterial3D.SHADING_MODE_UNSHADED
	wisp_mat.albedo_color    = Color(0.7, 0.95, 1.0, 0.8)
	wisp_mat.transparency    = BaseMaterial3D.TRANSPARENCY_ALPHA
	wisp_mat.emission_enabled = true
	wisp_mat.emission        = Color(0.5, 0.88, 1.0)
	wisp_mat.emission_energy_multiplier = 3.0
	wisp.material_override   = wisp_mat
	get_parent().add_child(wisp)
	wisp.global_position = center + Vector3(0, 0.8, 0)
	wisp.emitting = true
	var wc := create_tween()
	wc.tween_interval(1.2)
	wc.tween_callback(wisp.queue_free)

# ══════════════════════════════════════════════════════════════════════════
# TATAN — ALCHEMY DUSTS (copy-only weapon; the original had no dusts attack)
# ══════════════════════════════════════════════════════════════════════════

## Primary attack: lobs a pouch of the selected powder toward the aim point.
## Mode 1 (brown speed dust) is a self-buff and is NOT thrown.





func get_weapon_ammo(w_type: int) -> int:
	return combat_controller.get_weapon_ammo(w_type)

func start_reload() -> void:
	combat_controller.start_reload()

func auto_attack(target: Node3D) -> void:
	combat_controller.auto_attack(target)

func attack() -> void:
	combat_controller.attack()
	
func throw_spear() -> void:
	combat_controller.throw_spear()

func _on_alt_attack_pressed() -> void:
	if current_weapon() == WeaponData.WeaponType.DUAL_DAGGERS:
		combat_controller.attack_dual_daggers_heavy(0.5 if is_berserk else 1.0)
	elif current_weapon() == WeaponData.WeaponType.DUSTS:
		combat_controller.cycle_dust_mode()
	else:
		throw_spear()

func _on_toggle_mouse_capture() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_spawn_debug_enemy() -> void:
	var enemy_scene = load("res://scenes/entities/enemy.tscn")
	var enemy = enemy_scene.instantiate()
	get_parent().add_child(enemy)
	var forward_dir = -global_transform.basis.z
	enemy.global_position = global_position + forward_dir * 10.0 + Vector3(0, 1, 0)
