class_name WeaponStrategy
extends RefCounted

const SLASH_VFX = preload("res://scripts/objects/slash_vfx.gd")
const SPEAR_SLASH_SHADER: Shader = preload("res://assets/shaders/spear_slash.gdshader")
const DUST_VFX = preload("res://scripts/objects/dust_vfx.gd")
const CLOUD_SHADER: Shader = preload("res://assets/shaders/alchemical_clouds.gdshader")

var c: PlayerCombatController

func _init(controller: PlayerCombatController) -> void:
	c = controller

func attack(cd_mult: float) -> void:
	pass

## Tamaño de ataques cuerpo a cuerpo / proyectiles según objetos (PlayerStatBlock).
func _melee_size() -> float:
	return c.player.stat_block.melee_size() if c.player.stat_block else 1.0

func _ranged_size() -> float:
	return c.player.stat_block.ranged_size() if c.player.stat_block else 1.0

func _scale_melee(node: Node3D) -> void:
	node.scale = node.scale * _melee_size()

func _scale_ranged(node: Node3D) -> void:
	node.scale = Vector3.ONE * _ranged_size()

func animate_weapon_swing(weapon_type: int, side: float) -> void:
	var weapon: Node3D = c.player.weapon_models.get(weapon_type)
	if not weapon or not is_instance_valid(weapon):
		return
	var base_transform: Transform3D = weapon.transform
	var base_rot: Vector3 = base_transform.basis.get_euler()
	var start_rot: Vector3 = base_rot + Vector3(0.0, deg_to_rad(52.0 * side), deg_to_rad(-18.0))
	var end_rot: Vector3 = base_rot + Vector3(0.0, deg_to_rad(-52.0 * side), deg_to_rad(22.0))
	weapon.rotation = start_rot
	var tween = c.player.create_tween()
	tween.tween_property(weapon, "rotation", end_rot, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func() -> void:
		if is_instance_valid(weapon) and weapon.is_inside_tree():
			weapon.transform = base_transform
	)

class EnergySwordStrategy extends WeaponStrategy:

	func attack(cd_mult: float) -> void:
		c.attack_cooldown = c.player.get_weapon_data(WeaponData.WeaponType.ENERGY_SWORD).base_cooldown * cd_mult
		c.player.orient_player_to_aim(c.player.get_camera_aim_point())
		var forward_dir = c.player.get_attack_forward_dir()
		var player_pos = c.player.global_position
		var dmg = c.player._weapon_damage(WeaponData.WeaponType.ENERGY_SWORD)
	
		var slash_side = c._melee_swing_side
		c._melee_swing_side = -c._melee_swing_side
	
		AudioManager.play("ataque-espalanza", -10.0, 1.05)
	
		# Hitbox is now handled by the instantiated weapon scene
		var sword_scene = preload("res://scenes/objects/energy_sword.tscn").instantiate()
		c.player.get_parent().add_child(sword_scene)
		sword_scene.global_position = player_pos + forward_dir * 1.5
		sword_scene.look_at(sword_scene.global_position + forward_dir, Vector3.UP)
		_scale_melee(sword_scene)
		sword_scene.setup(dmg, 0.2, 15.0, forward_dir)
	
		var weapon_model: Node3D = c.player.weapon_models.get(WeaponData.WeaponType.ENERGY_SWORD)
		if is_instance_valid(weapon_model):
			weapon_model.visible = false

		create_sword_slash_visual(player_pos, forward_dir)

	func create_sword_slash_visual(pos: Vector3, facing_dir: Vector3) -> void:
		SLASH_VFX.spawn(c.player, c.player.get_parent(), pos, facing_dir, 3.6 * _melee_size(), 1.5, c._melee_swing_side < 0, {
			"slash_color": Color(0.2, 0.7, 1.0, 1.0),
			"core_color": Color(0.9, 0.98, 1.0, 1.0),
			"zoom": 0.75,
			"emission_strength": 4.0,
		})


class TriShotgunStrategy extends WeaponStrategy:

	const BASE_PELLETS := 5
	const MAX_PELLETS := 10
	const BASE_RANGE := 6.0
	const BASE_HALF_ANGLE := 14.0
	const BASE_PUSH := 3.0
	## Ancho de impacto de cada perdigón alrededor de su trayectoria (radio del enemigo ≈ 0.45)
	const PELLET_WIDTH := 0.8
	const SMOKE_COLOR := Color(0.42, 0.44, 0.5)
	const SmokeTrailZoneRef = preload("res://scripts/objects/smoke_trail_zone.gd")

	static func pellet_count(mods: Dictionary) -> int:
		return clampi(BASE_PELLETS + int(mods.get("quantity_bonus", 0)), 1, MAX_PELLETS)

	func attack(cd_mult: float) -> void:
		var W := WeaponData.WeaponType.TRI_SHOTGUN
		c.attack_cooldown = c.player.get_weapon_data(W).base_cooldown * cd_mult
		var aim_point = c.player.get_camera_aim_point()
		var start_pos: Vector3 = c.player.muzzle.global_position
		var base_dir: Vector3 = (aim_point - start_pos).normalized()
		if (aim_point - start_pos).length_squared() < 0.04:
			base_dir = -c.player.spring_arm.global_transform.basis.z
		base_dir.y = 0.0   # el cono es horizontal, como el resto de ataques de área
		if base_dir.length_squared() < 0.0001:
			base_dir = -c.player.mesh.global_transform.basis.z
			base_dir.y = 0.0
		base_dir = base_dir.normalized()

		c.player.orient_player_to_aim(aim_point)
		AudioManager.play("disparo-escopeta", -10.0)

		var mods: Dictionary = c.player.get_weapon_modifiers(W)
		var dmg: float = c.player._weapon_damage(W)
		# Tamaño: alcanza más lejos y abre más el cono
		var size: float = maxf(float(mods.get("size", 1.0)), 0.3) * _ranged_size()
		var reach: float = BASE_RANGE * size
		var half_angle: float = BASE_HALF_ANGLE * sqrt(size)
		var push: float = BASE_PUSH * (1.0 + float(mods.get("knockback", 0.0)))
		var n := pellet_count(mods)

		var enemies: Array = EnemyRegistry.all()
		var space_state = c.player.get_world_3d().direct_space_state
		for i in range(n):
			var t: float = 0.5 if n == 1 else float(i) / float(n - 1)
			var deg: float = lerpf(-half_angle, half_angle, t) + randf_range(-1.5, 1.5)
			var pellet_dir: Vector3 = base_dir.rotated(Vector3.UP, deg_to_rad(deg))

			# Paredes del mapa (capa 1) cortan el perdigón
			var max_dist: float = reach
			var wall_q = PhysicsRayQueryParameters3D.create(start_pos, start_pos + pellet_dir * reach)
			wall_q.exclude = [c.player.get_rid()]
			wall_q.collision_mask = 1
			var wall = space_state.intersect_ray(wall_q)
			if not wall.is_empty():
				max_dist = start_pos.distance_to(wall.position)

			# Impacto por geometría (más fiable que rayos físicos): el enemigo más cercano
			# a lo largo de la trayectoria cuya distancia lateral sea menor al ancho del perdigón.
			var best = null
			var best_t: float = max_dist + 1.0
			for e in enemies:
				if not is_instance_valid(e) or not e.has_method("take_damage"):
					continue
				var rel: Vector3 = e.global_position - start_pos
				if absf(rel.y) > 3.5:
					continue
				var along: float = rel.x * pellet_dir.x + rel.z * pellet_dir.z
				if along < -0.3 or along > max_dist:
					continue
				var side: float = absf(rel.x * pellet_dir.z - rel.z * pellet_dir.x)
				if side <= PELLET_WIDTH and along < best_t:
					best_t = along
					best = e
			if best != null:
				# Vector con módulo > 1 = velocidad de empuje (ver Enemy.take_damage)
				best.take_damage(dmg, pellet_dir * push)

		_create_blast(start_pos, base_dir, size, half_angle, reach)

	## Disparo: fogonazo corto + nube de humo gris que se abre en cono y se disipa.
	func _create_blast(pos: Vector3, dir: Vector3, size: float, half_angle: float, reach: float) -> void:
		var parent: Node = c.player.get_parent()

		# Fogonazo cálido muy breve
		var flash := MeshInstance3D.new()
		var fm := SphereMesh.new()
		fm.radius = 0.22 * size
		fm.height = 0.44 * size
		fm.radial_segments = 8
		fm.rings = 4
		flash.mesh = fm
		var fmat := StandardMaterial3D.new()
		fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		fmat.albedo_color = Color(1.0, 0.75, 0.35, 0.9)
		flash.material_override = fmat
		flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(flash)
		flash.global_position = pos + dir * 0.3
		var ftw := flash.create_tween().set_parallel(true)
		ftw.tween_property(flash, "scale", Vector3.ONE * 1.8, 0.09)
		ftw.tween_property(fmat, "albedo_color:a", 0.0, 0.09)
		ftw.chain().tween_callback(flash.queue_free)

		# Nube de humo: bocanadas grandes y suaves que viajan por el cono y se frenan
		var smoke := CPUParticles3D.new()
		parent.add_child(smoke)
		smoke.global_position = pos + dir * 0.4
		smoke.amount = Quality.count(34)
		smoke.lifetime = 1.5
		smoke.one_shot = true
		smoke.explosiveness = 0.9
		smoke.direction = dir
		smoke.spread = clampf(half_angle, 12.0, 40.0)
		smoke.damping_min = 3.0
		smoke.damping_max = 3.6
		smoke.initial_velocity_min = reach * 1.6
		smoke.initial_velocity_max = reach * 3.2
		smoke.gravity = Vector3(0, 0.25, 0)
		smoke.angle_max = 360.0
		var quad := QuadMesh.new()
		quad.size = Vector2(1.3, 1.3)
		smoke.mesh = quad
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		mat.billboard_keep_scale = true
		mat.vertex_color_use_as_albedo = true
		mat.albedo_texture = SmokeTrailZoneRef._soft_puff_texture()
		smoke.material_override = mat
		var ramp := Gradient.new()
		ramp.set_color(0, Color(SMOKE_COLOR.r, SMOKE_COLOR.g, SMOKE_COLOR.b, 0.95))
		ramp.add_point(0.55, Color(SMOKE_COLOR.r, SMOKE_COLOR.g, SMOKE_COLOR.b, 0.8))   # se mantiene densa
		ramp.set_color(ramp.get_point_count() - 1, Color(SMOKE_COLOR.r, SMOKE_COLOR.g, SMOKE_COLOR.b, 0.0))
		smoke.color_ramp = ramp
		var grow := Curve.new()
		grow.add_point(Vector2(0.0, 0.6))
		grow.add_point(Vector2(1.0, 1.8))
		smoke.scale_amount_curve = grow
		smoke.emitting = true
		smoke.get_tree().create_timer(1.8).timeout.connect(smoke.queue_free)

	## Serpientes de Joel: 3 serpientes de esmeralda en cono (una al centro, dos en
	## los bordes desviadas ±half_angle del arma).


class RailgunStrategy extends WeaponStrategy:

	func attack(cd_mult: float) -> void:
		c.attack_cooldown = c.player.get_weapon_data(WeaponData.WeaponType.RAILGUN).base_cooldown * cd_mult
		var aim_point = c.player.get_camera_aim_point()
		var start_pos = c.player.muzzle.global_position
		var aim_dir = (aim_point - start_pos).normalized()
		if (aim_point - start_pos).length_squared() < 0.04:
			aim_dir = -c.player.spring_arm.global_transform.basis.z
	
		c.player.orient_player_to_aim(aim_point)
	
		var max_range = c.player.get_weapon_data(WeaponData.WeaponType.RAILGUN).weapon_range
		var end_pos = start_pos + aim_dir * max_range
		var dmg = c.player._weapon_damage(WeaponData.WeaponType.RAILGUN)
	
		# Raycast check for wall/environment collision
		var space_state = c.player.get_world_3d().direct_space_state
		var ray_query = PhysicsRayQueryParameters3D.create(start_pos, end_pos)
		ray_query.exclude = [c.player.get_rid()]
		ray_query.collision_mask = 1 # Wall / World layer
		var ray_res = space_state.intersect_ray(ray_query)
		if not ray_res.is_empty():
			end_pos = ray_res.position
	
		# Piercing Laser Beam: Pierces ALL enemies along beam line
		var beam_radius = c.player.get_weapon_data(WeaponData.WeaponType.RAILGUN).beam_radius * _ranged_size()
		for enemy in EnemyRegistry.all():
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
		c.player.apply_camera_recoil(0.065, randf_range(-0.015, 0.015), 0.18)
		c.player.create_muzzle_flash(railgun_color, 1.8)

	func spawn_railgun_hit_sparks(pos: Vector3, normal: Vector3) -> void:
		var BulletScript = load("res://scripts/objects/bullet.gd")
		if BulletScript and BulletScript.has_method("spawn_impact_sparks"):
			BulletScript.spawn_impact_sparks(c.player.get_parent(), pos, normal, Color(0.95, 0.2, 1.0))

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
	
		c.player.get_parent().add_child(beam)
		beam.global_position = (start_pos + end_pos) * 0.5
	
		var dir = (end_pos - start_pos).normalized()
		if dir.cross(Vector3.UP).length() > 0.001:
			beam.look_at(end_pos, Vector3.UP)
			beam.rotate_object_local(Vector3.RIGHT, deg_to_rad(90))
	
		var tween = c.player.create_tween()
		tween.tween_property(mat, "albedo_color:a", 0.0, 0.25)
		tween.tween_callback(beam.queue_free)


class SpearLanceStrategy extends WeaponStrategy:
	const ENABLE_SPEAR_THROW: bool = false

	## Hasta 8 cortes. Orden de aparición (grados respecto al frente, positivo = derecha):
	## frente, atrás, derecha, izquierda y luego las 4 diagonales.
	const BLADE_ANGLES: Array[float] = [0.0, 180.0, 90.0, -90.0, 45.0, -45.0, 135.0, -135.0]
	const MAX_BLADES: int = 8

	## Cantidad de cortes según las mejoras ("Hoja extra" suma a la hoja base).
	static func blade_count(mods: Dictionary) -> int:
		return clampi(1 + int(mods.get("quantity_bonus", 0)), 1, MAX_BLADES)

	func attack(cd_mult: float) -> void:
		# Make it slower (e.g. 1.4x base cooldown)
		c.attack_cooldown = c.player.get_weapon_data(WeaponData.WeaponType.SPEAR_LANCE).base_cooldown * cd_mult * 1.4
		
		# El tajo debe ser estrictamente hacia donde mira el modelo del personaje (frente físico), no hacia la cámara (crosshair)
		var forward_dir = -c.player.mesh.global_transform.basis.z.normalized()
		var player_pos = c.player.global_position
		var dmg = c.player._weapon_damage(WeaponData.WeaponType.SPEAR_LANCE)
		# Mejoras propias de la Espalanza (tamaño del corte, velocidad, daño...)
		var mods: Dictionary = c.player.get_weapon_modifiers(WeaponData.WeaponType.SPEAR_LANCE)
	
		var slash_side = c._melee_swing_side
		c._melee_swing_side = -c._melee_swing_side
		
		# Slower, deeper sound for a larger sweep
		AudioManager.play("ataque-espalanza", -10.0, 0.85)
	
		# Un hitbox + un tajo por hoja. Comparten la lista de enemigos golpeados:
		# cada enemigo recibe daño una sola vez por ataque (más hojas = más cobertura).
		var weapon_model: Node3D = c.player.weapon_models.get(WeaponData.WeaponType.SPEAR_LANCE)
		if is_instance_valid(weapon_model):
			weapon_model.visible = false

		# Cada hoja golpea con su PROPIO timing: la primera al instante y las demás repartidas
		# por igual dentro del ciclo de ataque (ciclo / nº de hojas), no todas a la vez.
		var blades := blade_count(mods)
		var step: float = c.attack_cooldown / float(blades)
		for i in range(blades):
			if i == 0:
				_strike_blade(0, slash_side, false)
			else:
				c.player.get_tree().create_timer(step * float(i)).timeout.connect(_strike_blade.bind(i, slash_side, true))

		# Launch code is preserved but disabled while the weapon is slash-only.
		if ENABLE_SPEAR_THROW:
			var combo_tween = c.player.create_tween()
			combo_tween.tween_interval(0.35)
			combo_tween.tween_callback(func():
				if not is_instance_valid(c.player) or c.player.current_weapon() != WeaponData.WeaponType.SPEAR_LANCE:
					return

				var enemies = EnemyRegistry.all()
				var closest = null
				var min_dist = 45.0

				for e in enemies:
					if not is_instance_valid(e): continue
					var d = e.global_position.distance_to(c.player.global_position)
					if d < min_dist:
						min_dist = d
						closest = e

				var start_pos = c.player.muzzle.global_position
				var aim_dir = c.player.get_attack_forward_dir()

				if closest:
					var target_pos = closest.global_position + Vector3(0, 1.0, 0)
					aim_dir = (target_pos - start_pos).normalized()
					c.player.orient_player_to_aim(target_pos)

				# Do not hide the spear from hand; these are spectral summons!

				var proj = c.spear_projectile_scene.instantiate()
				c.player.get_parent().add_child(proj)
				proj.global_position = start_pos
				_scale_ranged(proj)
				proj.setup(aim_dir, 35.0 * (c.player.stat_block.damage_mult() if c.player.stat_block else 1.0), 48.0, c.player.get_rid())
				AudioManager.play("ataque-espalanza", -6.0, 1.3)
			)
	
	## Throws the spear-lance (right mouse). The spear is
	## gone from the c.player's hand until it returns.

	func animate_weapon_swing(weapon_type: int, side: float) -> void:
		var weapon: Node3D = c.player.weapon_models.get(weapon_type)
		if not weapon or not is_instance_valid(weapon):
			return
		var base_transform: Transform3D = weapon.transform
		var base_rot: Vector3 = base_transform.basis.get_euler()

		# Tajo horizontal apretado solo al frente del personaje
		var start_rot: Vector3 = base_rot + Vector3(0.0, deg_to_rad(20.0 * side), deg_to_rad(-5.0))
		var end_rot: Vector3 = base_rot + Vector3(0.0, deg_to_rad(-20.0 * side), deg_to_rad(10.0))
		weapon.rotation = start_rot

		var tween = c.player.create_tween()
		tween.tween_property(weapon, "rotation", end_rot, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_callback(func() -> void:
			if is_instance_valid(weapon) and weapon.is_inside_tree():
				weapon.transform = base_transform
		)

	## Un golpe de la hoja `index`: calcula dirección, daño y mejoras en ESTE instante
	## (el jugador puede haberse movido/girado desde el inicio del ciclo).
	func _strike_blade(index: int, slash_side: float, delayed: bool) -> void:
		if not is_instance_valid(c.player) or not c.player.is_inside_tree():
			return
		if delayed and c.player.current_weapon() != WeaponData.WeaponType.SPEAR_LANCE and not c.player.weapon_slots.has(WeaponData.WeaponType.SPEAR_LANCE):
			return
		var mods: Dictionary = c.player.get_weapon_modifiers(WeaponData.WeaponType.SPEAR_LANCE)
		var dmg = c.player._weapon_damage(WeaponData.WeaponType.SPEAR_LANCE)
		var forward_dir: Vector3 = -c.player.mesh.global_transform.basis.z.normalized()
		var player_pos: Vector3 = c.player.global_position
		var blade_dir: Vector3 = forward_dir.rotated(Vector3.UP, deg_to_rad(BLADE_ANGLES[index]))
		if index > 0:
			AudioManager.play("ataque-espalanza", -13.0, 0.9 + 0.04 * float(index))
		_spawn_blade_hitbox(player_pos, blade_dir, dmg, mods)
		create_spear_slash_visual(player_pos, blade_dir, slash_side, mods)

	func _spawn_blade_hitbox(player_pos: Vector3, dir: Vector3, dmg: float, mods: Dictionary) -> void:
		var spear_scene = preload("res://scenes/objects/spear_lance_hitbox.tscn").instantiate()
		c.player.get_parent().add_child(spear_scene)
		# El hitbox nace en el jugador (su forma ya se extiende hacia delante):
		# así también golpea a los enemigos pegados al cuerpo.
		spear_scene.global_position = player_pos
		spear_scene.look_at(spear_scene.global_position + dir, Vector3.UP)
		# Pasillo estrecho: exige apuntar; el tamaño de la mejora lo ensancha/alarga
		spear_scene.scale = Vector3(0.7, 1.0, 1.3) * float(mods["size"])
		_scale_melee(spear_scene)
		spear_scene.source_weapon = WeaponData.WeaponType.SPEAR_LANCE
		spear_scene.source_player = c.player
		spear_scene.setup(dmg, 0.35, 16.0, dir)

	## El tajo refleja las mejoras: tamaño (quad y distancia), velocidad (duración
	## más corta) y daño (más brillo y núcleo más blanco).
	func create_spear_slash_visual(pos: Vector3, facing_dir: Vector3, side: float, mods: Dictionary = {}) -> void:
		var size_mult: float = float(mods.get("size", 1.0)) * _melee_size()
		var speed_factor: float = clampf(float(mods.get("cooldown", 1.0)), 0.5, 1.0)
		var dmg_bonus: float = clampf(float(mods.get("damage", 1.0)) - 1.0, 0.0, 1.0)
		var base_core := Color(0.85, 1.0, 0.9, 1.0)
		SLASH_VFX.spawn(c.player, c.player.get_parent(), pos, facing_dir, 4.6 * size_mult, 1.7 * size_mult, side < 0, {
			"slash_color": Color(0.2, 1.0, 0.45, 1.0).lerp(Color(0.55, 1.0, 0.65, 1.0), dmg_bonus),
			"core_color": base_core.lerp(Color.WHITE, dmg_bonus),
			"emission_strength": 4.8 + 2.4 * dmg_bonus,
			"thickness": 0.34,
			"trail_length": 1.15,
			"curve": 0.32,
		}, SLASH_VFX.DURATION * speed_factor, SPEAR_SLASH_SHADER)

	## Flamethrower fire effect: a hot white-yellow inner core plus an outer
	## cone of orange flames streaming out of the nozzle, lit by a flickering
	## point light. Everything self-destructs shortly after firing.

	func throw_spear() -> void:
		if c.player.current_weapon() != WeaponData.WeaponType.SPEAR_LANCE: return
		if not ENABLE_SPEAR_THROW: return
		if c.attack_cooldown > 0: return
	
		c.attack_cooldown = c.SPEAR_THROW_CD
	
		var aim_point = c.player.get_camera_aim_point()
		var start_pos = c.player.muzzle.global_position
		var aim_dir = (aim_point - start_pos).normalized()
		if (aim_point - start_pos).length_squared() < 0.04:
			aim_dir = -c.player.spring_arm.global_transform.basis.z
	
		c.player.orient_player_to_aim(aim_point)
		c.player.emit_signal("weapon_attacked", WeaponData.WeaponType.SPEAR_LANCE)
	
		# Spectral spears don't hide the c.player's weapon.
	
		var proj = c.spear_projectile_scene.instantiate()
		c.player.get_parent().add_child(proj)
		proj.global_position = start_pos
		_scale_ranged(proj)
		proj.setup(aim_dir, 30.0 * (c.player.stat_block.damage_mult() if c.player.stat_block else 1.0), 48.0, c.player.get_rid())
	
		c.player.apply_camera_recoil(0.01, randf_range(-0.004, 0.004), 0.06)
	
	## Called by the thrown spear when it lands / returns to the c.player.

	func on_spear_returned() -> void:
		c.is_spear_thrown = false
		c.player.update_weapon_visuals()


class FlameThrowerStrategy extends WeaponStrategy:
	const FLAME_STREAM = preload("res://scripts/objects/flame_stream.gd")
	var _stream: Node3D = null

	## Empuje de cada tick. Era 14 (el valor por defecto de MeleeHitbox) y, al ser daño
	## continuo, desplazaba a los enemigos sin parar; ahora apenas los roza.
	const FLAME_KNOCKBACK := 1.6

	## Ráfaga: el fuego se mantiene BURST_BASE_S segundos de disparo continuo y luego se
	## recalienta y descansa REST_S. Si se deja de disparar > IDLE_RESET_S la ráfaga se renueva.
	const BURST_BASE_S := 3.0
	const REST_S := 1.2
	const IDLE_RESET_S := 0.6
	var _burst_used: float = 0.0
	var _last_fire_t: float = -100.0
	var _rest_until: float = -1.0

	func is_overheated() -> bool:
		return Time.get_ticks_msec() / 1000.0 < _rest_until

	## Dirección del fuego: hacia el objetivo del combate automático (cualquier dirección,
	## también a la espalda o a los lados) o, sin objetivo, hacia donde apunta la cámara.
	func _flame_direction() -> Vector3:
		var target = c.player.auto_combat_target
		if target != null and is_instance_valid(target):
			var d: Vector3 = target.global_position - c.player.global_position
			d.y = 0.0
			if d.length_squared() > 0.01:
				return d.normalized()
		return c.player.get_attack_forward_dir()

	func attack(cd_mult: float) -> void:
		c.attack_cooldown = c.player.get_weapon_data(WeaponData.WeaponType.FLAME_THROWER).base_cooldown * cd_mult
		var now := Time.get_ticks_msec() / 1000.0

		# Recalentado: no dispara hasta que termina el descanso (sigue intentándolo cada 0.1 s)
		if now < _rest_until:
			c.attack_cooldown = 0.1
			return

		var mods: Dictionary = c.player.get_weapon_modifiers(WeaponData.WeaponType.FLAME_THROWER)
		var burst_len: float = BURST_BASE_S * float(mods.get("burst_time", 1.0))
		if now - _last_fire_t > IDLE_RESET_S:
			_burst_used = 0.0
		else:
			_burst_used += now - _last_fire_t
		_last_fire_t = now
		if _burst_used >= burst_len:
			_rest_until = now + REST_S
			_burst_used = 0.0
			if _stream != null and is_instance_valid(_stream):
				_stream.extinguish()
			c.attack_cooldown = 0.1
			return

		var forward_dir: Vector3 = _flame_direction()
		var player_pos = c.player.global_position
		var dmg = c.player._weapon_damage(WeaponData.WeaponType.FLAME_THROWER)
		var size_mult: float = float(mods["size"]) * _melee_size()

		# Hitbox is now handled by the instantiated weapon scene
		var flame_scene = preload("res://scenes/objects/flame_thrower.tscn").instantiate()
		c.player.get_parent().add_child(flame_scene)
		flame_scene.global_position = player_pos
		flame_scene.look_at(flame_scene.global_position + forward_dir, Vector3.UP)
		flame_scene.scale = Vector3.ONE * size_mult
		flame_scene.setup(dmg, 0.2, FLAME_KNOCKBACK)
		flame_scene.source_weapon = WeaponData.WeaponType.FLAME_THROWER
		flame_scene.source_player = c.player

		update_continuous_flame(forward_dir, size_mult)

	## Chorro de fuego procedural (FlameStream): una sola instancia reutilizada,
	## apunta a la dirección de ataque y se apaga sola al dejar de disparar.
	func update_continuous_flame(dir: Vector3, size_mult: float = 1.0) -> void:
		if _stream == null or not is_instance_valid(_stream):
			_stream = FLAME_STREAM.new()
			c.player.get_parent().add_child(_stream)
			_stream.set_anchor(c.player.muzzle)
		_stream.aim(dir)
		_stream.apply_size(size_mult)
		_stream.keep_alive()

	## Procedural melee swing: sweeps the held weapon across a horizontal arc,
	## alternating sides each attack, then restores the idle pose.


class SporeBazookaStrategy extends WeaponStrategy:

	## Hasta 5 proyectiles en abanico (grados respecto al apuntado).
	const SHOT_ANGLES: Array[float] = [0.0, 9.0, -9.0, 18.0, -18.0]
	const MAX_SHOTS: int = 5
	## Separación máxima entre disparos de una misma salva (el ciclo del bazuca es muy largo)
	const MAX_STAGGER_S := 0.45

	static func shot_count(mods: Dictionary) -> int:
		return clampi(1 + int(mods.get("quantity_bonus", 0)), 1, MAX_SHOTS)

	func attack(cd_mult: float) -> void:
		c.attack_cooldown = c.player.get_weapon_data(WeaponData.WeaponType.SPORE_BAZOOKA).base_cooldown * cd_mult
		c.player.orient_player_to_aim(c.player.get_camera_aim_point())

		var mods: Dictionary = c.player.get_weapon_modifiers(WeaponData.WeaponType.SPORE_BAZOOKA)
		var shots := shot_count(mods)
		# Cada proyectil sale con su propio timing (el primero al instante)
		var step: float = minf(c.attack_cooldown / float(shots), MAX_STAGGER_S)
		for i in range(shots):
			if i == 0:
				_fire_spore(0)
			else:
				c.player.get_tree().create_timer(step * float(i)).timeout.connect(_fire_spore.bind(i))

	## Dispara el proyectil `index` con los datos de ESTE instante (apuntado, daño, mejoras).
	func _fire_spore(index: int) -> void:
		if not is_instance_valid(c.player) or not c.player.is_inside_tree():
			return
		var mods: Dictionary = c.player.get_weapon_modifiers(WeaponData.WeaponType.SPORE_BAZOOKA)
		var aim_point = c.player.get_camera_aim_point()
		var start_pos = c.player.muzzle.global_position
		var aim_dir: Vector3 = (aim_point - start_pos).normalized()
		if (aim_point - start_pos).length_squared() < 0.04:
			aim_dir = -c.player.spring_arm.global_transform.basis.z
		aim_dir = aim_dir.rotated(Vector3.UP, deg_to_rad(SHOT_ANGLES[index]))

		var b_stream = AudioManager.get_stream("tiro_bazuca")
		var b_start_time = b_stream.get_length() * 0.10 if b_stream else 0.0
		AudioManager.play("tiro_bazuca", -10.0 if index == 0 else -14.0, 1.0 + 0.05 * float(index), b_start_time)

		var data: WeaponData = c.player.get_weapon_data(WeaponData.WeaponType.SPORE_BAZOOKA)
		var dmg = c.player._weapon_damage(WeaponData.WeaponType.SPORE_BAZOOKA) * c.spore_damage_mult
		var cloud_dps = 5.0 * c.spore_damage_mult * float(mods["damage"])
		var size_mult: float = float(mods["size"]) * _ranged_size()
		var spore_color = Color(0.8, 0.95, 0.3)

		var proj = c.spore_projectile_scene.instantiate()
		c.player.get_parent().add_child(proj)
		proj.global_position = start_pos
		proj.scale = Vector3.ONE * size_mult
		proj.setup(aim_dir, dmg, data.projectile_speed, cloud_dps, c.spore_cloud_duration, data.weapon_range * size_mult)
		proj.source_weapon = WeaponData.WeaponType.SPORE_BAZOOKA
		proj.source_player = c.player

		c.player.apply_camera_recoil(0.05 if index == 0 else 0.02, randf_range(-0.008, 0.008), 0.14 if index == 0 else 0.06)
		c.player.create_muzzle_flash(spore_color, 1.6)

	## Twin Daggers: rapid short-range cuts. Alternates red and blue slash visuals.


class DustsStrategy extends WeaponStrategy:

	const DustProjectileRef = preload("res://scripts/objects/dust_projectile.gd")
	## Hasta 4 polvazos por lanzamiento (grados de giro respecto al apuntado).
	const THROW_ANGLES: Array[float] = [0.0, 11.0, -11.0, 22.0]
	const MAX_THROWS: int = 4
	const THROW_STAGGER_S := 0.12
	const BASE_DAMAGE := 38.0

	static func dust_count(mods: Dictionary) -> int:
		return clampi(1 + int(mods.get("quantity_bonus", 0)), 1, MAX_THROWS)

	func attack(cd_mult: float) -> void:
		c.attack_cooldown = c.player.get_weapon_data(WeaponData.WeaponType.DUSTS).base_cooldown * cd_mult
		var aim_point = c.player.get_camera_aim_point()
		c.player.orient_player_to_aim(aim_point)
		
		AudioManager.play("ataque-espalanza", -2.0, 1.8)
	
		if c.current_dust_mode == 1:
			# Brown dust: burst of speed instead of a throw.
			c.dust_speed_boost_timer = 4.0
			create_dust_puff_visual(c.player.muzzle.global_position, Color(1.0, 0.93, 0.74))
			return
	
		var mods: Dictionary = c.player.get_weapon_modifiers(WeaponData.WeaponType.DUSTS)
		# El polvo sanador es una sola nube; el arcano lanza hasta MAX_THROWS polvazos
		var throws := dust_count(mods) if c.current_dust_mode == 0 else 1
		var start_pos: Vector3 = c.player.muzzle.global_position
		for i in range(throws):
			if i == 0:
				_throw_dust(start_pos, aim_point, 0, mods)
			else:
				c.player.get_tree().create_timer(THROW_STAGGER_S * float(i)).timeout.connect(
					_throw_dust.bind(start_pos, aim_point, i, mods))

		var dust_color = Color(0.9, 0.84, 1.0) if c.current_dust_mode == 0 else Color(0.85, 1.0, 0.93)
		c.player.apply_camera_recoil(0.02, randf_range(-0.004, 0.004), 0.08)
		c.player.create_muzzle_flash(dust_color, 1.1)

	## Lanza el polvazo `index`: se abre en abanico girando el punto de impacto alrededor del jugador.
	func _throw_dust(start_pos: Vector3, aim_point: Vector3, index: int, mods: Dictionary) -> void:
		if not is_instance_valid(c.player) or not c.player.is_inside_tree():
			return
		var offset: Vector3 = aim_point - start_pos
		offset = offset.rotated(Vector3.UP, deg_to_rad(THROW_ANGLES[index]))
		var dmg: float = BASE_DAMAGE * float(mods["damage"]) * (c.player.stat_block.damage_mult() if c.player.stat_block else 1.0)
		var radius: float = DustProjectileRef.BASE_RADIUS * float(mods["size"]) * _ranged_size()
		var proj = c.dust_projectile_scene.instantiate()
		c.player.get_parent().add_child(proj)
		_scale_ranged(proj)
		proj.setup(start_pos, start_pos + offset, c.current_dust_mode, c.player, dmg, radius, float(mods.get("slow", 0.0)))
		if index > 0:
			AudioManager.play("ataque-espalanza", -8.0, 1.8 + 0.05 * float(index))

	## Right-click with dusts out: cycle the powder (0 AoE → 1 speed → 2 heal).

	func cycle_dust_mode() -> void:
		c.current_dust_mode = (c.current_dust_mode + 1) % 3
	
	## Small puff of dust used by the brown speed-dust self-buff.

	func create_dust_puff_visual(pos: Vector3, color: Color) -> void:
		var container := Node3D.new()
		c.player.get_parent().add_child(container)
		container.global_position = pos

		var light := Quality.new_light()
		light.light_color = color
		light.light_energy = 3.5
		light.omni_range = 4.0
		container.add_child(light)

		# Bocanada de polvo con el shader de polvo (blanco con un toque cálido)
		var cloud_mesh := MeshInstance3D.new()
		var s_mesh := SphereMesh.new()
		s_mesh.radius = 0.5
		s_mesh.height = 1.0
		s_mesh.radial_segments = 16
		s_mesh.rings = 10
		cloud_mesh.mesh = s_mesh
		var mat := ShaderMaterial.new()
		mat.shader = CLOUD_SHADER
		mat.set_shader_parameter("clouds_color", Vector3(color.r, color.g, color.b))
		mat.set_shader_parameter("rim_color", Vector3(1.0, 1.0, 1.0))
		mat.set_shader_parameter("clouds_speed", 6.0)
		mat.set_shader_parameter("clouds_scale", 1.8)
		mat.set_shader_parameter("compression_squish", 1.0)
		mat.set_shader_parameter("explosion_progress", 0.0)
		cloud_mesh.material_override = mat
		cloud_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		container.add_child(cloud_mesh)

		var grains: CPUParticles3D = DUST_VFX.grains(50, 0.7, 0.3, 0.05, 0.1, color, 3.0)
		grains.one_shot = true
		grains.explosiveness = 0.95
		container.add_child(grains)
		grains.emitting = true
		var stars: CPUParticles3D = DUST_VFX.sparkles(8, 0.6, 0.3, 0.15, 0.25, color)
		stars.one_shot = true
		stars.explosiveness = 0.9
		container.add_child(stars)
		stars.emitting = true

		var tween = container.create_tween().set_parallel(true)
		tween.tween_property(cloud_mesh, "scale", Vector3(2.6, 2.6, 2.6), 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(mat, "shader_parameter/explosion_progress", 1.0, 0.6)
		tween.tween_property(light, "light_energy", 0.0, 0.5)
		tween.chain().tween_interval(0.8)
		tween.chain().tween_callback(container.queue_free)


class SerpentsStrategy extends WeaponStrategy:

	## Espíritus de Joel (druida): invoca animales espirituales que atacan por él.
	## Fase 1: Dragón de Komodo (melee, azota con la cola y deja sangrado).
	const SEARCH_RANGE := 14.0
	const SUMMON_DISTANCE := 2.4

	## Dirección horizontal hacia el enemigo más cercano (o el frente del jugador).
	func _target_dir() -> Vector3:
		var best = null
		var best_d := SEARCH_RANGE
		for e in EnemyRegistry.all():
			if not is_instance_valid(e):
				continue
			var d: float = e.global_position.distance_to(c.player.global_position)
			if d < best_d:
				best_d = d
				best = e
		var dir: Vector3
		if best != null:
			dir = best.global_position - c.player.global_position
		else:
			dir = -c.player.mesh.global_transform.basis.z
		dir.y = 0.0
		if dir.length_squared() < 0.0001:
			dir = Vector3.FORWARD
		return dir.normalized()

	## Rotación de animales: se alternan; si el más cercano está lejos, ataca el búho (a distancia).
	var _next_animal: int = 0
	const MELEE_RANGE := 8.0

	func _nearest_enemy():
		var best = null
		var best_d := SEARCH_RANGE
		for e in EnemyRegistry.all():
			if not is_instance_valid(e):
				continue
			var d: float = e.global_position.distance_to(c.player.global_position)
			if d < best_d:
				best_d = d
				best = e
		return best

	## Animales: 0 Komodo (equilibrado), 1 Búho (rápido, golpea suave), 2 Hipopótamo (lento, golpea fuerte).
	## base: multiplicadores de partida. Por cada nivel de mejora del animal: daño (+), tamaño (+) y
	## recarga (×): el tiempo hasta la siguiente invocación se acorta.
	const SPIRIT_BASE := {0: {"dmg": 1.0, "cd": 1.0}, 1: {"dmg": 0.8, "cd": 0.7}, 2: {"dmg": 1.7, "cd": 1.6}}
	const SPIRIT_PER_LEVEL := {
		0: {"dmg": 0.12, "size": 0.08, "cd": 0.94},
		1: {"dmg": 0.08, "size": 0.06, "cd": 0.90},
		2: {"dmg": 0.20, "size": 0.10, "cd": 0.96},
	}

	func attack(cd_mult: float) -> void:
		var W := WeaponData.WeaponType.SERPENTS
		var mods: Dictionary = c.player.get_weapon_modifiers(W)
		var owned: Array = c.player.weapon_inventory.get_owned_spirits()
		var enemy = _nearest_enemy()
		var dir := _target_dir()
		# Rotación entre los animales que Joel tiene. El Komodo cede su turno al Búho si el enemigo está lejos.
		var kind: int = owned[_next_animal % owned.size()]
		_next_animal += 1
		if enemy == null:
			if not owned.has(0):
				c.attack_cooldown = 0.2   # sin enemigos, Búho/Hipopótamo no tienen a quién invocar
				return
			kind = 0
		elif kind == 0 and owned.has(1) and enemy.global_position.distance_to(c.player.global_position) > MELEE_RANGE:
			kind = 1
		c.player.orient_player_to_aim(c.player.global_position + dir * 5.0)

		var lvl := int(mods.get(["komodo_lvl", "owl_lvl", "hippo_lvl"][kind], 0))
		var base: Dictionary = SPIRIT_BASE[kind]
		var per: Dictionary = SPIRIT_PER_LEVEL[kind]
		c.attack_cooldown = c.player.get_weapon_data(W).base_cooldown * cd_mult * float(base["cd"]) * pow(float(per["cd"]), lvl)
		var size: float = maxf(float(mods.get("size", 1.0)), 0.3) * (1.0 + float(per["size"]) * lvl)
		var dmg: float = c.player._weapon_damage(W) * float(base["dmg"]) * (1.0 + float(per["dmg"]) * lvl)
		match kind:
			1:
				SpiritOwl.summon(c.player.get_parent(), c.player, enemy, dmg, size, W)
			2:
				var tgt = SpiritHippo.pick_target(c.player.get_tree(), c.player.global_position, SEARCH_RANGE)
				SpiritHippo.summon(c.player.get_parent(), c.player, tgt if tgt else enemy, dmg, size, W,
					SpiritHippo.BASE_CAPACITY + int(mods.get("quantity_bonus", 0)))
			_:
				var at: Vector3 = c.player.global_position + dir * SUMMON_DISTANCE * size
				SpiritKomodo.summon(c.player.get_parent(), c.player, at, dir, dmg, size, W)
		c.player.create_muzzle_flash(Color(0.4, 1.0, 0.85), 1.0)


class SpinningAxeStrategy extends WeaponStrategy:

	## Hasta 5 hachas en abanico (grados respecto a la dirección de tiro).
	const AXE_ANGLES: Array[float] = [0.0, 14.0, -14.0, 28.0, -28.0]
	const MAX_AXES: int = 5

	static func axe_count(mods: Dictionary) -> int:
		return clampi(1 + int(mods.get("quantity_bonus", 0)), 1, MAX_AXES)

	func attack(cd_mult: float) -> void:
		var W := WeaponData.WeaponType.SPINNING_AXE
		var data = c.player.get_weapon_data(W)
		c.attack_cooldown = data.base_cooldown * cd_mult
		var aim_point = c.player.get_camera_aim_point()
		c.player.orient_player_to_aim(aim_point)
		var start_pos = c.player.muzzle.global_position
		var aim_dir = (aim_point - start_pos).normalized()
		if (aim_point - start_pos).length_squared() < 0.04:
			aim_dir = -c.player.spring_arm.global_transform.basis.z

		var mods: Dictionary = c.player.get_weapon_modifiers(W)
		var dmg = c.player._weapon_damage(W)
		var size_mult: float = float(mods["size"])
		var spin_time: float = 2.0 * float(mods["duration"])
		for i in range(axe_count(mods)):
			var proj = preload("res://scenes/objects/spinning_axe_projectile.tscn").instantiate()
			c.player.get_parent().add_child(proj)
			proj.global_position = start_pos
			_scale_ranged(proj)
			proj.scale *= size_mult
			var dir: Vector3 = aim_dir.rotated(Vector3.UP, deg_to_rad(AXE_ANGLES[i]))
			proj.setup(dir, dmg, data.projectile_speed, data.weapon_range)
			proj.spin_duration = spin_time

		c.player.apply_camera_recoil(0.02, 0.0, 0.1)
		c.player.create_muzzle_flash(Color(0.2, 0.9, 0.3), 1.2)


class ElementsCycleStrategy extends WeaponStrategy:

	func attack(cd_mult: float) -> void:
		c.attack_cooldown = c.player.get_weapon_data(WeaponData.WeaponType.ELEMENTS_CYCLE).base_cooldown * cd_mult

		# El daño lo hacen las esferas al orbitar y tocar enemigos (ver
		# elemental_orbs.gd, _tick_contact_damage); el ataque solo hace
		# destellar el ciclo elemental.
		var orbs_node: ElementalOrbs = c.elemental_orbs
		if not orbs_node or orbs_node.orbs.is_empty():
			return
		orbs_node.flash_cycle()


class ZombieArmStrategy extends WeaponStrategy:

	## Hasta 5 brazos en abanico (grados respecto a la dirección de tiro).
	const ARM_ANGLES: Array[float] = [0.0, 16.0, -16.0, 32.0, -32.0]
	const MAX_ARMS: int = 5

	static func arm_count(mods: Dictionary) -> int:
		return clampi(1 + int(mods.get("quantity_bonus", 0)), 1, MAX_ARMS)

	## Lanza el brazo `index` con los datos de ESTE instante (apuntado, daño, mejoras).
	func _throw_arm(index: int) -> void:
		if not is_instance_valid(c.player) or not c.player.is_inside_tree():
			return
		var mods: Dictionary = c.player.get_weapon_modifiers(WeaponData.WeaponType.ZOMBIE_ARM)
		var aim_point = c.player.get_camera_aim_point()
		# Vuelo a ras del cañón: el aim_point suele estar en el suelo y un brazo con
		# componente vertical se hundía bajo tierra sin tocar a los enemigos.
		var base_dir: Vector3 = aim_point - c.player.muzzle.global_position
		base_dir.y = 0.0
		if base_dir.length_squared() < 0.0001:
			base_dir = c.player.get_attack_forward_dir()
		base_dir = base_dir.normalized()
		var dmg = c.player._weapon_damage(WeaponData.WeaponType.ZOMBIE_ARM)
		var size_mult: float = float(mods["size"]) * _ranged_size()
		var range_mult: float = float(mods["range"])
		var proj = load("res://scripts/objects/zombie_arm_projectile.tscn").instantiate()
		c.player.get_parent().add_child(proj)
		proj.global_position = c.player.muzzle.global_position
		var dir: Vector3 = base_dir.rotated(Vector3.UP, deg_to_rad(ARM_ANGLES[index]))
		proj.setup(dir, dmg, c.player)
		proj.apply_upgrades(size_mult, range_mult)
		proj.source_weapon = WeaponData.WeaponType.ZOMBIE_ARM
		proj.source_player = c.player
		if index > 0:
			AudioManager.play("ataque-espalanza", -15.0, 0.8)

	func attack(cd_mult: float) -> void:
		c.attack_cooldown = c.player.get_weapon_data(WeaponData.WeaponType.ZOMBIE_ARM).base_cooldown * cd_mult
		var aim_point = c.player.get_camera_aim_point()
		c.player.orient_player_to_aim(aim_point)

		var mods: Dictionary = c.player.get_weapon_modifiers(WeaponData.WeaponType.ZOMBIE_ARM)
		var proj_scene = load("res://scripts/objects/zombie_arm_projectile.tscn")
		# Vuelo a ras del cañón: el aim_point suele estar en el suelo y un brazo con
		# componente vertical se hundía bajo tierra sin tocar a los enemigos.
		var base_dir: Vector3 = aim_point - c.player.muzzle.global_position
		base_dir.y = 0.0
		if base_dir.length_squared() < 0.0001:
			base_dir = c.player.get_attack_forward_dir()
		base_dir = base_dir.normalized()
		var dmg = c.player._weapon_damage(WeaponData.WeaponType.ZOMBIE_ARM)
		var size_mult: float = float(mods["size"]) * _ranged_size()
		var range_mult: float = float(mods["range"])

		# Cada brazo sale con su propio timing: el primero al instante y los demás repartidos
		# dentro del ciclo de ataque (ciclo / nº de brazos). Cada uno golpea por su cuenta.
		var arms := arm_count(mods)
		var step: float = c.attack_cooldown / float(arms)
		for i in range(arms):
			if i == 0:
				_throw_arm(0)
			else:
				c.player.get_tree().create_timer(step * float(i)).timeout.connect(_throw_arm.bind(i))

		AudioManager.play("ataque-espalanza", -12.0, 0.8)
		
		c.player.apply_camera_recoil(0.015, randf_range(-0.005, 0.005), 0.05)
