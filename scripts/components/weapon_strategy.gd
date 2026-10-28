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

## ── Apuntado en la mazmorra ──
## El punto lo da el crosshair (rayo desde el centro de la pantalla, o el objetivo fijado):
## PlayerCameraAndAimController.get_dungeon_aim().
func _dungeon_aim_point() -> Vector3:
	return c.player.camera_aim_controller.get_dungeon_aim()["point"]

## Dirección horizontal desde el jugador hacia el punto del crosshair.
func _dungeon_aim() -> Vector3:
	var d: Vector3 = _dungeon_aim_point() - c.player.global_position
	d.y = 0.0
	if d.length_squared() < 0.25:
		d = -c.player.spring_arm.global_transform.basis.z
		d.y = 0.0
	return d.normalized() if d.length_squared() > 0.0001 else Vector3.FORWARD

## Dirección 3D desde `from` (la boca del arma) hacia el punto del crosshair. Si el punto queda
## demasiado cerca o detrás, recto al frente.
func _dungeon_shot_dir(from: Vector3) -> Vector3:
	var flat := _dungeon_aim()
	var d: Vector3 = _dungeon_aim_point() - from
	if d.length() < 1.5 or Vector3(d.x, 0.0, d.z).normalized().dot(flat) < 0.5:
		return flat
	return d.normalized()

## Dónde queda la boca del arma tras girar al personaje (el esqueleto aún no se ha actualizado).
func _muzzle_after_turn(old_yaw: float) -> Vector3:
	var pp: Vector3 = c.player.global_position
	var rel: Vector3 = c.player.muzzle.global_position - pp
	return pp + rel.rotated(Vector3.UP, angle_difference(old_yaw, c.player.mesh.rotation.y))

## Gira al personaje hacia `dir` y bloquea unos instantes el giro hacia donde camina.
func _face(dir: Vector3, hold_s: float) -> void:
	c.player.mesh.rotation.y = atan2(-dir.x, -dir.z)
	var mc = c.player.movement_controller
	if mc:
		mc.face_lock_until = Time.get_ticks_msec() / 1000.0 + hold_s

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
		sword_scene.source_weapon = WeaponData.WeaponType.ENERGY_SWORD
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
		_fire_shot(1.0, 1.0)

	## ── Ráfaga de escopetazos (click derecho, mazmorra) ──
	## Cuatro disparos seguidos muy rápidos (la animación de disparo va acelerada); cada uno algo
	## más flojo que el normal y el retroceso va empujando a Riva hacia atrás.
	const BURST_SHOTS := 4
	const BURST_INTERVAL := 0.13
	const BURST_DAMAGE := 0.75       ## × daño de un disparo normal, por disparo
	const BURST_ANIM_SPEED := 3.2
	const BURST_COOLDOWN := 3.0
	const BURST_RECOIL := 4.5        ## empuje de Riva hacia atrás por disparo (m/s)
	var _burst_ready_at: float = 0.0

	func burst_cooldown_left() -> float:
		return maxf(_burst_ready_at - Time.get_ticks_msec() / 1000.0, 0.0)

	func shotgun_burst() -> bool:
		var now := Time.get_ticks_msec() / 1000.0
		if now < _burst_ready_at:
			return false
		_burst_ready_at = now + BURST_COOLDOWN
		# Sin disparo normal mientras dura la ráfaga
		c.attack_cooldown = maxf(c.attack_cooldown, BURST_INTERVAL * BURST_SHOTS + 0.15)
		for i in BURST_SHOTS:
			if i == 0:
				_burst_shot(i)
			else:
				c.player.get_tree().create_timer(BURST_INTERVAL * i).timeout.connect(_burst_shot.bind(i))
		return true

	func _burst_shot(index: int) -> void:
		if not is_instance_valid(c.player) or not c.player.is_inside_tree():
			return
		var dir := _fire_shot(BURST_DAMAGE, BURST_ANIM_SPEED)
		var mc = c.player.movement_controller
		if mc and mc.has_method("add_dash"):
			mc.add_dash(-dir * BURST_RECOIL)
		var last := index == BURST_SHOTS - 1
		HitFeedback.shake(0.16 if not last else 0.32)
		c.player.apply_camera_recoil(0.03, randf_range(-0.012, 0.012), 0.12 if not last else 0.22)

	## Un escopetazo. Devuelve la dirección (horizontal) del disparo.
	func _fire_shot(dmg_mult: float, anim_speed: float) -> Vector3:
		var W := WeaponData.WeaponType.TRI_SHOTGUN
		var aim_point = c.player.get_camera_aim_point()
		var start_pos: Vector3 = c.player.muzzle.global_position
		if GameData.game_mode == "dungeon":
			# Riva se gira hacia el crosshair y dispara desde la boca de la escopeta
			var old_yaw: float = c.player.mesh.rotation.y
			_face(_dungeon_aim(), 0.4)
			start_pos = _muzzle_after_turn(old_yaw)
			aim_point = _dungeon_aim_point()
			if c.player.animation_controller:
				c.player.animation_controller.play_held_shot(anim_speed)
			HitFeedback.shake(0.18)
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
		var dmg: float = c.player._weapon_damage(W) * dmg_mult
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
				HitFeedback.weapon_tag = WeaponData.WeaponType.TRI_SHOTGUN
				best.take_damage(dmg, pellet_dir * push)

		_create_blast(start_pos, base_dir, size, half_angle, reach)
		return base_dir

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
					HitFeedback.weapon_tag = WeaponData.WeaponType.RAILGUN
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

	var _active_hitbox: Node3D = null
	var _anim_connected: bool = false

	func _connect_animation_signals() -> void:
		if _anim_connected: return
		var ac = c.player.animation_controller if (c.player and is_instance_valid(c.player)) else null
		if ac and ac.has_signal("hit_window_opened"):
			ac.hit_window_opened.connect(_on_dungeon_hit_opened)
			ac.hit_window_closed.connect(_on_dungeon_hit_closed)
			_anim_connected = true

	func _on_dungeon_hit_opened(attack_id: int, anim_name: String) -> void:
		if not is_instance_valid(c.player) or not c.player.is_inside_tree():
			return
		if c.player.current_weapon() != WeaponData.WeaponType.SPEAR_LANCE:
			return
		if is_instance_valid(_active_hitbox):
			_active_hitbox.queue_free()
			_active_hitbox = null

		var mods: Dictionary = c.player.get_weapon_modifiers(WeaponData.WeaponType.SPEAR_LANCE)
		var base_dmg = c.player._weapon_damage(WeaponData.WeaponType.SPEAR_LANCE)
		var dmg = base_dmg
		var kb = 6.0
		var box_size = Vector3(1.0, 1.0, 1.8) * float(mods.get("size", 1.0))
		var offset = Vector3(0, 0.8, -1.3)

		if anim_name == "attack1":
			dmg = base_dmg
			kb = 6.0
			box_size = Vector3(1.0, 1.0, 1.8) * float(mods.get("size", 1.0))
			offset = Vector3(0, 0.8, -1.3)
		elif anim_name == "attack2":
			dmg = base_dmg * 0.95
			kb = 5.0
			box_size = Vector3(2.6, 1.0, 2.6) * float(mods.get("size", 1.0))
			offset = Vector3(0, 0.8, 0.0)
		elif anim_name == "attack3":
			dmg = base_dmg * 1.5
			kb = 10.0
			box_size = Vector3(1.8, 1.4, 2.0) * float(mods.get("size", 1.0))
			offset = Vector3(0, 0.8, -1.6)

		var spear_scene = preload("res://scenes/objects/spear_lance_hitbox.tscn").instantiate()
		c.player.mesh.add_child(spear_scene)
		spear_scene.position = offset
		spear_scene.rotation = Vector3.ZERO
		spear_scene.scale = box_size
		_scale_melee(spear_scene)
		spear_scene.source_weapon = WeaponData.WeaponType.SPEAR_LANCE
		spear_scene.source_player = c.player
		spear_scene.setup(dmg, 0.35, kb, -c.player.mesh.global_transform.basis.z.normalized())
		_active_hitbox = spear_scene

		var trail: BladeTrail = c.player.weapon_visuals.spear_trail if c.player.weapon_visuals else null
		if is_instance_valid(trail) and trail.is_visible_in_tree():
			trail.emit(0.4)

	func _on_dungeon_hit_closed(_attack_id: int) -> void:
		if is_instance_valid(_active_hitbox):
			_active_hitbox.queue_free()
			_active_hitbox = null

	## Cantidad de cortes según las mejoras ("Hoja extra" suma a la hoja base).
	static func blade_count(mods: Dictionary) -> int:
		return clampi(1 + int(mods.get("quantity_bonus", 0)), 1, MAX_BLADES)

	func attack(cd_mult: float) -> void:
		_connect_animation_signals()
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
	
		var weapon_model: Node3D = c.player.weapon_models.get(WeaponData.WeaponType.SPEAR_LANCE)
		if is_instance_valid(weapon_model) and not weapon_model.has_meta("in_hand"):
			weapon_model.visible = false

		if GameData.game_mode == "dungeon":
			# En mazmorra, el golpe lo genera _on_dungeon_hit_opened cuando la animacion llega a su ventana
			return

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
		# Golpe principal con la espalanza en la mano: la estela sigue la hoja animada.
		# Las hojas extra (mejoras, otros ángulos) mantienen el tajo de energía.
		var trail: BladeTrail = c.player.weapon_visuals.spear_trail if c.player.weapon_visuals else null
		# En supervivencia no hay animación de ataque que mueva la hoja: se usa el tajo de energía de siempre
		if index == 0 and GameData.game_mode == "dungeon" and is_instance_valid(trail) and trail.is_visible_in_tree():
			trail.emit(0.5)
		else:
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
	
	## Lanzamiento cargado (click derecho mantenido). power 0..1: más daño,
	## velocidad, tamaño y empuje; con carga completa atraviesa enemigos.
	func throw_spear_charged(power: float) -> void:
		if c.player.current_weapon() != WeaponData.WeaponType.SPEAR_LANCE: return
		c.attack_cooldown = c.SPEAR_THROW_CD * 0.6
		var forward: Vector3 = -c.player.mesh.global_transform.basis.z
		forward.y = 0.0
		var aim_dir := forward.normalized()
		var target = c.player.get("auto_combat_target")
		var start_pos: Vector3 = c.player.global_position + Vector3(0, 1.3, 0) + aim_dir * 0.6
		if is_instance_valid(target):
			aim_dir = ((target.global_position + Vector3(0, 0.9, 0)) - start_pos).normalized()
		var dmg_mult: float = c.player.stat_block.damage_mult() if c.player.stat_block else 1.0
		var proj = c.spear_projectile_scene.instantiate()
		c.player.get_parent().add_child(proj)
		proj.global_position = start_pos
		_scale_ranged(proj)
		proj.setup(aim_dir, lerpf(34.0, 70.0, power), lerpf(25.0, 90.0, power) * dmg_mult, c.player.get_rid())
		if proj.has_method("make_espalanza"):
			proj.make_espalanza(power)
		if c.player.animation_controller:
			c.player.animation_controller.play_throw()
		c.player.emit_signal("weapon_attacked", WeaponData.WeaponType.SPEAR_LANCE)
		AudioManager.play("spear_throw", -4.0, lerpf(1.1, 0.8, power))
		if power >= 1.0:
			AudioManager.play("kill_burst", -8.0, 1.3)
		c.player.apply_camera_recoil(0.01 + 0.02 * power, 0.0, 0.08 + 0.12 * power)

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
		if GameData.game_mode == "dungeon":
			return _dungeon_aim()
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

		# Recalentado (o en plena explosión): no dispara hasta que termina (sigue intentándolo cada 0.1 s)
		if now < _rest_until or now < _blast_ready_at - BLAST_COOLDOWN + BLAST_LOCK_S:
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
		if GameData.game_mode == "dungeon":
			_face(forward_dir, 0.35)
			if c.player.animation_controller:
				c.player.animation_controller.held_fire_until = now + 0.25
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

	## ── Explosión de fuego (click derecho, mazmorra) ──
	## Estalla delante de la boquilla: daña y lanza a los enemigos y rompe props alrededor;
	## el retroceso empuja a Vangry hacia atrás.
	const BLAST_COOLDOWN := 3.5
	const BLAST_DISTANCE := 1.8      ## m por delante del jugador
	const BLAST_RADIUS := 4.2
	const BLAST_DAMAGE := 18.0
	const BLAST_KNOCK := 20.0        ## empuje máximo a los enemigos (m/s)
	const BLAST_RECOIL := 17.0       ## empuje del jugador hacia atrás (m/s)
	const BLAST_HOP := 3.5
	const BLAST_LOCK_S := 0.6        ## sin chorro mientras dura la animación de la explosión
	var _blast_ready_at: float = 0.0

	func blast_cooldown_left() -> float:
		return maxf(_blast_ready_at - Time.get_ticks_msec() / 1000.0, 0.0)

	func flame_blast() -> bool:
		var now := Time.get_ticks_msec() / 1000.0
		if now < _blast_ready_at:
			return false
		_blast_ready_at = now + BLAST_COOLDOWN
		var dir := _dungeon_aim()
		_face(dir, 0.6)
		if _stream != null and is_instance_valid(_stream):
			_stream.extinguish()
		if c.player.animation_controller:
			c.player.animation_controller.play_held_blast()
		# El estallido sale cuando la animación termina de agacharse y apuntar (fotograma 5 ≈ 0.13 s)
		c.player.get_tree().create_timer(0.13).timeout.connect(_detonate.bind(dir))
		return true

	func _detonate(dir: Vector3) -> void:
		if not is_instance_valid(c.player) or not c.player.is_inside_tree():
			return
		var mods: Dictionary = c.player.get_weapon_modifiers(WeaponData.WeaponType.FLAME_THROWER)
		var radius: float = BLAST_RADIUS * float(mods.get("size", 1.0))
		var center: Vector3 = c.player.global_position + dir * BLAST_DISTANCE
		var dmg: float = BLAST_DAMAGE * float(mods.get("damage", 1.0))
		for e in EnemyRegistry.query_radius(center, radius + 0.6):
			if not is_instance_valid(e) or not e.has_method("take_damage"):
				continue
			if e.has_method("is_dead") and e.is_dead():
				continue
			var away: Vector3 = e.global_position - center
			away.y = 0.0
			var dist := away.length()
			if dist > radius + 0.6:
				continue
			away = away / dist if dist > 0.05 else dir
			var falloff := clampf(1.0 - dist / (radius + 0.6), 0.35, 1.0)
			e.take_damage(dmg * falloff, away * BLAST_KNOCK * falloff)
		# Props rompibles dentro de la explosión
		for prop in c.player.get_tree().get_nodes_in_group("destructibles"):
			if is_instance_valid(prop) and prop is Node3D and prop.global_position.distance_to(center) <= radius and prop.has_method("take_damage"):
				prop.take_damage(999.0, (prop.global_position - center).normalized())
		# Retroceso de Vangry
		var mc = c.player.movement_controller
		if mc and mc.has_method("add_dash"):
			mc.add_dash(-dir * BLAST_RECOIL)
		c.player.velocity.y = maxf(c.player.velocity.y, BLAST_HOP)
		FlameBlast.spawn(c.player.get_parent(), center + Vector3(0, 0.9, 0), radius)
		AudioManager.play_at("explosion", center, -2.0, randf_range(0.9, 1.05))
		AudioManager.play_at("impact_fire", center, -4.0, 0.8)
		HitFeedback.shake(0.75)
		c.player.apply_camera_recoil(0.06, 0.0, 0.25)

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
		if GameData.game_mode == "dungeon":
			# Bronch se gira hacia el crosshair y el proyectil sale de la boca hacia ese punto
			var old_yaw: float = c.player.mesh.rotation.y
			_face(_dungeon_aim(), 0.45)
			start_pos = _muzzle_after_turn(old_yaw)
			aim_dir = _dungeon_shot_dir(start_pos)
			if c.player.animation_controller:
				c.player.animation_controller.play_held_shot()
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

	## ── Perdigonazo (click derecho, mazmorra) ──
	## Como una escopeta: un abanico de perdigones de esporas de corto alcance que hace mucho
	## daño a bocajarro y empuja; el retroceso echa a Bronch un poco hacia atrás.
	const SHOTGUN_COOLDOWN := 1.4
	const SHOTGUN_PELLETS := 9
	const SHOTGUN_SPREAD_DEG := 18.0     ## semiángulo horizontal del abanico
	const SHOTGUN_RANGE := 9.0
	const SHOTGUN_SPEED := 34.0
	const SHOTGUN_PELLET_DAMAGE := 5.0
	const SHOTGUN_KNOCK := 1.0           ## empuje que suma cada perdigón que acierta (m/s)
	const SHOTGUN_RECOIL := 13.0          ## empuje de Bronch hacia atrás (m/s)
	const SHOTGUN_DELAY := 0.12          ## sale cuando la animación termina de apuntar
	const SHOTGUN_LOCK_S := 0.55         ## sin disparo normal mientras dura la animación
	var _shotgun_ready_at: float = 0.0

	func shotgun_cooldown_left() -> float:
		return maxf(_shotgun_ready_at - Time.get_ticks_msec() / 1000.0, 0.0)

	func spore_shotgun() -> bool:
		var now := Time.get_ticks_msec() / 1000.0
		if now < _shotgun_ready_at:
			return false
		_shotgun_ready_at = now + SHOTGUN_COOLDOWN
		c.attack_cooldown = maxf(c.attack_cooldown, SHOTGUN_LOCK_S)
		var dir := _dungeon_aim()
		_face(dir, 0.6)
		if c.player.animation_controller:
			c.player.animation_controller.play_held_blast()
		c.player.get_tree().create_timer(SHOTGUN_DELAY).timeout.connect(_fire_pellets.bind(dir))
		return true

	func _fire_pellets(dir: Vector3) -> void:
		if not is_instance_valid(c.player) or not c.player.is_inside_tree():
			return
		var mods: Dictionary = c.player.get_weapon_modifiers(WeaponData.WeaponType.SPORE_BAZOOKA)
		var dmg: float = SHOTGUN_PELLET_DAMAGE * float(mods.get("damage", 1.0)) * c.spore_damage_mult
		var rng: float = SHOTGUN_RANGE * float(mods.get("size", 1.0)) * _ranged_size()
		var from: Vector3 = c.player.muzzle.global_position
		# Si la boca queda dentro de una pared, salir desde el pecho
		var q := PhysicsRayQueryParameters3D.create(c.player.global_position + Vector3(0, 1.2, 0), from, 1)
		q.exclude = [c.player.get_rid()]
		if not c.player.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			from = c.player.global_position + Vector3(0, 1.2, 0)
		var parent: Node = c.player.get_parent()
		# El centro del abanico va al punto del crosshair (con su inclinación)
		var center := _dungeon_shot_dir(from)
		for i in SHOTGUN_PELLETS:
			# Reparto uniforme del abanico con un poco de azar, y algo de dispersión vertical
			var t := (float(i) / float(SHOTGUN_PELLETS - 1)) * 2.0 - 1.0
			var yaw := deg_to_rad(t * SHOTGUN_SPREAD_DEG + randf_range(-3.0, 3.0))
			var d := center.rotated(Vector3.UP, yaw)
			d.y += randf_range(-0.05, 0.06)
			SporePellet.fire(parent, from, d, dmg, SHOTGUN_KNOCK, SHOTGUN_SPEED * randf_range(0.92, 1.08), rng * randf_range(0.85, 1.0), c.player)
		var mc = c.player.movement_controller
		if mc and mc.has_method("add_dash"):
			mc.add_dash(-dir * SHOTGUN_RECOIL)
		c.player.create_muzzle_flash(Color(0.7, 1.0, 0.25), 2.4)
		var puff := SporeVFX.gas(Quality.count(10), 0.6, 0.15, 0.4, 0.9, 0.3)
		puff.one_shot = true
		puff.explosiveness = 0.95
		puff.direction = dir
		puff.spread = SHOTGUN_SPREAD_DEG
		puff.initial_velocity_min = 4.0
		puff.initial_velocity_max = 8.0
		parent.add_child(puff)
		puff.global_position = from
		puff.emitting = true
		puff.get_tree().create_timer(1.0).timeout.connect(puff.queue_free)
		AudioManager.play("tiro_bazuca", -6.0, 1.45)
		AudioManager.play_at("explosion_bits", from, -4.0, 1.3)
		HitFeedback.shake(0.35)
		c.player.apply_camera_recoil(0.05, randf_range(-0.01, 0.01), 0.2)

	## Twin Daggers: rapid short-range cuts. Alternates red and blue slash visuals.


class DustsStrategy extends WeaponStrategy:

	const DustProjectileRef = preload("res://scripts/objects/dust_projectile.gd")
	const FLOATING_DAMAGE = preload("res://scripts/objects/floating_damage.gd")
	## Hasta 4 polvazos por lanzamiento (grados de giro respecto al apuntado).
	const THROW_ANGLES: Array[float] = [0.0, 11.0, -11.0, 22.0]
	const MAX_THROWS: int = 4
	const THROW_STAGGER_S := 0.12
	const BASE_DAMAGE := 38.0

	static func dust_count(mods: Dictionary) -> int:
		return clampi(1 + int(mods.get("quantity_bonus", 0)), 1, MAX_THROWS)

	## Mazmorra: el lanzamiento lo marca la animación (Tatan se mueve despacio mientras lanza).
	const THROW_SLOW := 0.3

	func attack(cd_mult: float) -> void:
		c.attack_cooldown = c.player.get_weapon_data(WeaponData.WeaponType.DUSTS).base_cooldown * cd_mult
		if GameData.game_mode == "dungeon" and _dungeon_throw():
			return
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

	## Lanzamiento con animación (Tatan en la mazmorra). Devuelve false si no hay animaciones.
	func _dungeon_throw() -> bool:
		var ac = c.player.animation_controller
		if ac == null or not ac.has_method("play_dust_throw"):
			return false
		# En la mazmorra el click izquierdo siempre lanza polvo arcano (el derecho es el polvo a la cara)
		var mode := 0
		var info: Dictionary = ac.play_dust_throw(mode)
		if info.is_empty():
			return false
		var length: float = info["length"]
		var release: float = info["release"]
		# No se encadena otro lanzamiento hasta casi terminar la animación
		c.attack_cooldown = maxf(c.attack_cooldown, length * 0.8)
		_face(_dungeon_aim(), release + 0.1)
		var mc = c.player.movement_controller
		if mc:
			mc.slow_until = Time.get_ticks_msec() / 1000.0 + length * 0.75
			mc.slow_mult = THROW_SLOW
		AudioManager.play("ataque-espalanza", -6.0, 1.5)
		c.player.get_tree().create_timer(release).timeout.connect(_dungeon_release.bind(mode))
		return true

	## El polvo sale de la mano derecha hacia el punto del crosshair en el instante de soltarlo.
	func _dungeon_release(mode: int) -> void:
		if not is_instance_valid(c.player) or not c.player.is_inside_tree():
			return
		var hand: Vector3 = c.player.animation_controller.bone_global_position("mixamorig_RightHand")
		var dust_color = Color(0.9, 0.84, 1.0) if mode == 0 else (Color(1.0, 0.93, 0.74) if mode == 1 else Color(0.85, 1.0, 0.93))
		AudioManager.play("ataque-espalanza", -2.0, 1.8)
		HitFeedback.shake(0.12)
		if mode == 1:
			c.dust_speed_boost_timer = 4.0
			create_dust_puff_visual(hand, dust_color)
			return
		var mods: Dictionary = c.player.get_weapon_modifiers(WeaponData.WeaponType.DUSTS)
		var aim_point: Vector3 = _dungeon_aim_point()
		var throws := dust_count(mods) if mode == 0 else 1
		for i in range(throws):
			if i == 0:
				_throw_dust(hand, aim_point, 0, mods)
			else:
				c.player.get_tree().create_timer(THROW_STAGGER_S * float(i)).timeout.connect(
					_throw_dust.bind(hand, aim_point, i, mods))
		create_dust_puff_visual(hand, dust_color)

	## ── Polvo a la cara (click derecho, mazmorra) ──
	## Tatan se estampa un puñado de polvo en la cara: corre más rápido un rato y se cura un poco.
	const FACE_COOLDOWN := 6.0
	const FACE_SPEED_S := 4.0        ## duración del extra de velocidad (el del polvo marrón: ×1.35)
	const FACE_HEAL_FRACTION := 0.1  ## vida curada (fracción de la vida máxima)
	var _face_ready_at: float = 0.0

	func face_cooldown_left() -> float:
		return maxf(_face_ready_at - Time.get_ticks_msec() / 1000.0, 0.0)

	func dust_face() -> bool:
		var now := Time.get_ticks_msec() / 1000.0
		if now < _face_ready_at:
			return false
		var ac = c.player.animation_controller
		var info: Dictionary = ac.play_dust_throw(3) if ac and ac.has_method("play_dust_throw") else {}
		if info.is_empty():
			return false
		_face_ready_at = now + FACE_COOLDOWN
		var length: float = info["length"]
		c.attack_cooldown = maxf(c.attack_cooldown, length * 0.8)
		var mc = c.player.movement_controller
		if mc:
			mc.slow_until = now + float(info["release"]) + 0.35
			mc.slow_mult = THROW_SLOW
		AudioManager.play("ataque-espalanza", -8.0, 1.3)
		c.player.get_tree().create_timer(info["release"]).timeout.connect(_face_slap)
		return true

	func _face_slap() -> void:
		if not is_instance_valid(c.player) or not c.player.is_inside_tree():
			return
		var face: Vector3 = c.player.animation_controller.bone_global_position("mixamorig_Head") + Vector3(0, 0.12, 0)
		c.dust_speed_boost_timer = FACE_SPEED_S
		var amount: float = maxf(c.player.max_hp * FACE_HEAL_FRACTION, 1.0)
		var healed: float = minf(amount, c.player.max_hp - c.player.hp)
		c.player.heal(amount)
		if healed > 0.0:
			FLOATING_DAMAGE.spawn(c.player.get_parent(), face + Vector3(0, 0.5, 0), healed, Color(0.4, 1.0, 0.45), false, "+%d" % ceili(healed))
		create_dust_puff_visual(face, Color(1.0, 0.85, 0.45))
		if c.player.has_method("_play_heal_fx"):
			c.player._play_heal_fx()
		AudioManager.play("ataque-espalanza", -2.0, 0.8)
		AudioManager.play("dodge", -4.0, 1.4)
		HitFeedback.shake(0.18)
		c.player.apply_camera_recoil(-0.03, 0.0, 0.12)

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
		if GameData.game_mode == "dungeon":
			return _dungeon_aim()
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

	## Mazmorra: el Komodo es el "Stand" de Joel. Joel adopta una pose (Jotaro, Giorno o Dio, una por
	## animación del Komodo), el espíritu brota de su pecho, ataca y vuelve a meterse en él.
	const KOMODO_DELAY := 0.1
	const GESTURE_SLOW := 0.2
	func _dungeon_komodo(dir: Vector3, size: float, dmg: float, weapon: int) -> void:
		var idx := SpiritKomodo.pick_variant()
		var ac = c.player.animation_controller
		var length: float = ac.play_gesture(idx) if ac and ac.has_method("play_gesture") else 0.0
		var mc = c.player.movement_controller
		if mc and length > 0.0:
			mc.slow_until = Time.get_ticks_msec() / 1000.0 + length * 0.7
			mc.slow_mult = GESTURE_SLOW
		var at: Vector3 = c.player.global_position + dir * SUMMON_DISTANCE * size
		c.player.get_tree().create_timer(KOMODO_DELAY).timeout.connect(func():
			if is_instance_valid(c.player) and c.player.is_inside_tree():
				var k := SpiritKomodo.summon(c.player.get_parent(), c.player, at, dir, dmg, size, weapon, idx)
				StandAura.spawn(c.player, k.stand_time()))

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
		if GameData.game_mode == "dungeon":
			_face(dir, 0.5)
		else:
			c.player.orient_player_to_aim(c.player.global_position + dir * 5.0)

		var lvl := int(mods.get(["komodo_lvl", "owl_lvl", "hippo_lvl"][kind], 0))
		var base: Dictionary = SPIRIT_BASE[kind]
		var per: Dictionary = SPIRIT_PER_LEVEL[kind]
		c.attack_cooldown = c.player.get_weapon_data(W).base_cooldown * cd_mult * float(base["cd"]) * pow(float(per["cd"]), lvl)
		var size: float = maxf(float(mods.get("size", 1.0)), 0.3) * (1.0 + float(per["size"]) * lvl)
		var dmg: float = c.player._weapon_damage(W) * float(base["dmg"]) * (1.0 + float(per["dmg"]) * lvl)
		if kind == 0 and GameData.game_mode == "dungeon":
			_dungeon_komodo(dir, size, dmg, W)
			c.player.create_muzzle_flash(Color(0.4, 1.0, 0.85), 1.0)
			return
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
