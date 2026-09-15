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

var _strategies: Dictionary = {}

func _ready() -> void:
	player = get_parent() as CharacterBody3D
	
	_strategies[WeaponData.WeaponType.ENERGY_SWORD] = WeaponStrategy.EnergySwordStrategy.new(self)
	_strategies[WeaponData.WeaponType.FLAME_AXE] = WeaponStrategy.FlameAxeStrategy.new(self)
	_strategies[WeaponData.WeaponType.PLASMA_RIFLE] = WeaponStrategy.PlasmaRifleStrategy.new(self)
	_strategies[WeaponData.WeaponType.TRI_SHOTGUN] = WeaponStrategy.TriShotgunStrategy.new(self)
	_strategies[WeaponData.WeaponType.RAILGUN] = WeaponStrategy.RailgunStrategy.new(self)
	_strategies[WeaponData.WeaponType.SPEAR_LANCE] = WeaponStrategy.SpearLanceStrategy.new(self)
	_strategies[WeaponData.WeaponType.FLAME_THROWER] = WeaponStrategy.FlameThrowerStrategy.new(self)
	_strategies[WeaponData.WeaponType.SPORE_BAZOOKA] = WeaponStrategy.SporeBazookaStrategy.new(self)
	_strategies[WeaponData.WeaponType.DUAL_DAGGERS] = WeaponStrategy.DualDaggersStrategy.new(self)
	_strategies[WeaponData.WeaponType.AIR_FISTS] = WeaponStrategy.AirFistsStrategy.new(self)
	_strategies[WeaponData.WeaponType.DUSTS] = WeaponStrategy.DustsStrategy.new(self)
	_strategies[WeaponData.WeaponType.SERPENTS] = WeaponStrategy.SerpentsStrategy.new(self)
	_strategies[WeaponData.WeaponType.SPINNING_AXE] = WeaponStrategy.SpinningAxeStrategy.new(self)
	_strategies[WeaponData.WeaponType.ELEMENTS_CYCLE] = WeaponStrategy.ElementsCycleStrategy.new(self)
	_strategies[WeaponData.WeaponType.ZOMBIE_ARM] = WeaponStrategy.ZombieArmStrategy.new(self)


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
		
		if _strategies.has(w):
			_strategies[w].attack(cd_mult)
		
			
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

	var cw = player.current_weapon()
	if _strategies.has(cw):
		_strategies[cw].attack(cd_mult)

	

	# Consume ammo after firing; empty magazine starts the slow reload.
	if mag > 0:
		weapon_ammo[player.current_weapon()] = max(0, get_weapon_ammo(player.current_weapon()) - 1)
		if weapon_ammo[player.current_weapon()] <= 0:
			start_reload()
		else:
			player._emit_reload_state()


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
